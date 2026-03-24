#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/agent-debate.sh [options] "task"

Runs Claude Code and Codex in a bounded debate loop on the same task.

Options:
  --rounds N        Total rounds per agent. 1 = independent answers only. Default: 2
  --output-dir DIR  Directory for prompts, responses, and transcript
  --help            Show this help text

If no task argument is provided, the script reads the task from stdin.
Artifacts are written to .agents/debates/<timestamp>/ by default.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

append_transcript() {
  local title="$1"
  local file="$2"

  {
    printf '## %s\n\n' "$title"
    cat "$file"
    printf '\n\n'
  } >> "$TRANSCRIPT"
}

build_initial_prompt() {
  local agent_name="$1"
  local prompt_file="$2"

  {
    printf 'You are %s in a two-agent debate with a peer model.\n\n' "$agent_name"
    printf 'Task:\n%s\n\n' "$TASK"
    cat <<'EOF'
Rules:
- Work only from the task and your own reasoning.
- Do not use tools, edit files, or run commands.
- Be concise and specific.
- Treat the other model as a capable peer, not a subordinate.

Respond in Markdown with these headings:
## Position
## Assumptions
## Risks
## Question for Peer
EOF
  } > "$prompt_file"
}

build_followup_prompt() {
  local agent_name="$1"
  local own_prev="$2"
  local peer_prev="$3"
  local round="$4"
  local prompt_file="$5"

  {
    printf 'You are %s in round %s of a two-agent debate.\n\n' "$agent_name" "$round"
    printf 'Original task:\n%s\n\n' "$TASK"
    cat <<'EOF'
Instructions:
- Critique the peer's reasoning directly.
- Keep what still holds, and change your view if the peer surfaced a real flaw.
- Do not use tools, edit files, or run commands.
- Be concise and specific.

Your previous response:
<<<YOUR_PREVIOUS_RESPONSE
EOF
    cat "$own_prev"
    cat <<'EOF'
YOUR_PREVIOUS_RESPONSE
>>>

Peer response:
<<<PEER_RESPONSE
EOF
    cat "$peer_prev"
    cat <<'EOF'
PEER_RESPONSE
>>>

Respond in Markdown with these headings:
## Strongest Point from Peer
## Weakest Point from Peer
## Updated Position
## Question for Peer
EOF
  } > "$prompt_file"
}

run_claude() {
  local prompt_file="$1"
  local output_file="$2"
  local prompt_text

  prompt_text="$(cat "$prompt_file")"
  claude \
    -p \
    --output-format text \
    --permission-mode dontAsk \
    --tools "" \
    -- \
    "$prompt_text" > "$output_file"
}

run_codex() {
  local prompt_file="$1"
  local output_file="$2"
  local log_file="${output_file%.md}.log"

  if ! codex exec \
    --sandbox read-only \
    --color never \
    -o "$output_file" \
    - < "$prompt_file" >"$log_file" 2>&1; then
    tail -n 40 "$log_file" >&2 || true
    return 1
  fi
}

ROUNDS=2
OUTPUT_DIR=""
TASK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rounds)
      ROUNDS="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$TASK" ]]; then
        TASK+=" "
      fi
      TASK+="$1"
      shift
      ;;
  esac
done

if [[ ! "$ROUNDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "--rounds must be a positive integer" >&2
  exit 1
fi

if [[ -z "$TASK" ]]; then
  TASK="$(cat)"
fi

if [[ -z "${TASK// }" ]]; then
  echo "Task is required" >&2
  usage >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$ROOT/.agents/debates/$(date +%Y%m%d-%H%M%S)"
fi

TRANSCRIPT="$OUTPUT_DIR/transcript.md"

require_cmd claude
require_cmd codex

mkdir -p "$OUTPUT_DIR/prompts" "$OUTPUT_DIR/responses"

trap 'status=$?; if [[ $status -ne 0 ]]; then echo "Debate failed. Inspect $OUTPUT_DIR for partial logs." >&2; fi' EXIT

printf '%s\n' "$TASK" > "$OUTPUT_DIR/task.txt"

{
  printf '# Agent Debate\n\n'
  printf -- '- Task: %s\n' "$TASK"
  printf -- '- Rounds per agent: %s\n' "$ROUNDS"
  printf -- '- Claude CLI: %s\n' "$(claude --version)"
  printf -- '- Codex CLI: %s\n\n' "$(codex --version)"
} > "$TRANSCRIPT"

CLAUDE_PROMPT="$OUTPUT_DIR/prompts/claude-round-1.txt"
CODEX_PROMPT="$OUTPUT_DIR/prompts/codex-round-1.txt"
CLAUDE_RESPONSE="$OUTPUT_DIR/responses/claude-round-1.md"
CODEX_RESPONSE="$OUTPUT_DIR/responses/codex-round-1.md"

build_initial_prompt "Claude" "$CLAUDE_PROMPT"
build_initial_prompt "Codex" "$CODEX_PROMPT"

echo "==> Round 1: Claude"
run_claude "$CLAUDE_PROMPT" "$CLAUDE_RESPONSE"
append_transcript "Round 1 - Claude" "$CLAUDE_RESPONSE"

echo "==> Round 1: Codex"
run_codex "$CODEX_PROMPT" "$CODEX_RESPONSE"
append_transcript "Round 1 - Codex" "$CODEX_RESPONSE"

if (( ROUNDS >= 2 )); then
  for ((round = 2; round <= ROUNDS; round++)); do
    NEXT_CLAUDE_PROMPT="$OUTPUT_DIR/prompts/claude-round-$round.txt"
    NEXT_CODEX_PROMPT="$OUTPUT_DIR/prompts/codex-round-$round.txt"
    NEXT_CLAUDE_RESPONSE="$OUTPUT_DIR/responses/claude-round-$round.md"
    NEXT_CODEX_RESPONSE="$OUTPUT_DIR/responses/codex-round-$round.md"

    build_followup_prompt "Claude" "$CLAUDE_RESPONSE" "$CODEX_RESPONSE" "$round" "$NEXT_CLAUDE_PROMPT"
    build_followup_prompt "Codex" "$CODEX_RESPONSE" "$CLAUDE_RESPONSE" "$round" "$NEXT_CODEX_PROMPT"

    echo "==> Round $round: Claude"
    run_claude "$NEXT_CLAUDE_PROMPT" "$NEXT_CLAUDE_RESPONSE"
    append_transcript "Round $round - Claude" "$NEXT_CLAUDE_RESPONSE"

    echo "==> Round $round: Codex"
    run_codex "$NEXT_CODEX_PROMPT" "$NEXT_CODEX_RESPONSE"
    append_transcript "Round $round - Codex" "$NEXT_CODEX_RESPONSE"

    CLAUDE_RESPONSE="$NEXT_CLAUDE_RESPONSE"
    CODEX_RESPONSE="$NEXT_CODEX_RESPONSE"
  done
fi

cat <<EOF
Debate complete.
Task: $TASK
Transcript: $TRANSCRIPT
Claude final: $CLAUDE_RESPONSE
Codex final: $CODEX_RESPONSE
EOF
