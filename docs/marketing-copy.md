# Blink Marketing Copy

This doc keeps Blink's public copy consistent across GitHub, the website, and launch posts.

## Positioning

**Primary pitch**

Blink is a native macOS workspace for developers who live in tmux, Neovim, and AI CLIs.

**Expanded pitch**

Blink gives each project a persistent workspace with terminal panes, managed tool tabs, AI CLI sessions, and a built-in browser for localhost, docs, and auth flows. Instead of rebuilding your setup every time you switch context, you reopen the workspace and keep going.

**Who it is for**

- macOS developers working across multiple repos every day
- people who already use `tmux`, `nvim`, `lazygit`, Codex, Claude Code, or similar CLI-first tools
- developers who want a project browser without turning their terminal app into a full personal browser

**What Blink is not**

- not a general-purpose web browser
- not a generic "AI terminal"
- not trying to replace `tmux`; it makes `tmux`-based project workflows easier to reopen and manage on macOS

## GitHub Copy

**About**

Native macOS workspace for tmux, Neovim, and AI CLI workflows.

**Short description alternatives**

- Native macOS project workspace with persistent terminals, AI CLI panes, and a built-in dev browser.
- A macOS workspace for terminal-first development with tmux restore, column layout, and AI CLI sessions.
- Native macOS workspace for developers who juggle terminals, editors, localhost previews, and AI CLIs.

**Topics**

`macos`, `swift`, `swiftui`, `terminal`, `tmux`, `neovim`, `developer-tools`, `ai`, `productivity`, `libghostty`

## Homepage Copy

**Hero title**

Blink is a native macOS workspace for tmux, Neovim, and AI CLI workflows.

**Hero subtitle**

Open a project and get your terminals, editors, AI sessions, and browser panes back in one persistent workspace. Built for localhost previews, docs, auth flows, and fast context switching.

**CTA options**

- Download for macOS
- Install with Homebrew
- Watch the workflow demo

**Three supporting bullets**

- Reopen a project and restore the layout you were already using.
- Keep Codex, Claude Code, terminals, and browser panes side by side.
- Use a built-in project browser for localhost, docs, downloads, and auth redirects.

**Feature section framing**

### One workspace per project

Blink keeps terminal panes, managed tools, browser tabs, and layout state scoped to the current workspace.

### Built for terminal-first developers

Use `tmux`, `nvim`, `lazygit`, Yazi, Codex, Claude Code, and other CLI tools without bouncing between separate macOS apps.

### A browser for project work, not everything

Open localhost previews, docs, login flows, and project links inside the workspace while keeping storage isolated per project.

## Launch Angles

Pick one angle per launch. Do not lead with every feature at once.

**Angle 1: Persistent project workspace**

I built a native macOS workspace that restores my terminals, editor sessions, and tool panes per project instead of making me rebuild everything after every context switch.

**Angle 2: AI CLI workflows**

I wanted Codex and Claude Code to live beside my terminal and editor, not in a separate app or browser tab, so I built a macOS workspace around that flow.

**Angle 3: Project browser**

I wanted localhost, docs, auth redirects, and downloads inside the same project workspace as my shell without turning my terminal app into a full browser.

## Launch Post Drafts

### Show HN title options

- Show HN: Blink, a native macOS workspace for tmux, Neovim, and AI CLI workflows
- Show HN: Blink, a macOS project workspace with persistent terminals and built-in AI CLI panes
- Show HN: Blink, a terminal-first macOS workspace with tmux restore and a project browser

### Show HN body

Blink is a native macOS workspace I built for the way I actually work: one repo at a time, with terminals, Neovim, git tools, AI CLIs, and a few project web pages all open together.

The core idea is simple: each project gets its own persistent workspace. When I come back later, Blink restores the layout and reconnects the shell/editor flow instead of making me rebuild it from scratch.

The app is focused on a narrow workflow:

- terminal-first development with `tmux`
- managed tabs for tools like `nvim`, `lazygit`, Codex, and Claude Code
- a built-in browser for localhost previews, docs, auth redirects, and downloads
- column-based layout instead of a pile of overlapping windows

It is not trying to be a full browser or a replacement for `tmux`. The goal is to make project context easier to reopen and manage on macOS.

Repo:
https://github.com/bradjenn/blink

### X / Bluesky

I built Blink: a native macOS workspace for tmux, Neovim, and AI CLI workflows.

It keeps terminals, Codex/Claude panes, and project browser tabs in one persistent per-project layout, so reopening a repo feels like resuming work instead of rebuilding context.

https://github.com/bradjenn/blink

### Reddit

I built a native macOS workspace for terminal-first development.

Blink is designed around per-project persistence: terminals, editor/tool panes, AI CLI sessions, and a built-in browser for localhost/docs/auth flows all stay scoped to the current workspace.

It is aimed at people who already use tools like `tmux`, `nvim`, `lazygit`, Codex, or Claude Code and want that workflow to feel more native on macOS.

Repo:
https://github.com/bradjenn/blink

## Demo Script

Use a short video and show the workflow, not the settings UI.

1. Open a repo workspace.
2. Show restored terminal/editor/AI panes.
3. Open localhost in the workspace browser.
4. Trigger an auth/docs flow.
5. Switch to another workspace.
6. Return and show the first workspace still intact.

## Before Promoting

- notarize the app so direct download does not trigger manual quarantine workarounds
- make the GitHub About line match the README and website hero
- use "Blink for macOS" or "Blink Workspace" in posts to reduce name ambiguity
- attach a short demo clip to every launch post
