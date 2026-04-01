# Terminal Performance Benchmark

This gives Blink a repeatable way to measure terminal scrolling and resize churn instead of relying on feel.

## Enable Signposts

For `Blink Dev`:

```bash
defaults write com.blink.app.dev blink.perf.signposts -bool YES
```

For the production app:

```bash
defaults write com.blink.app blink.perf.signposts -bool YES
```

The terminal surface emits these signposts from [TerminalSurfaceView.swift](/Users/bradley/Code/blink/Blink/Terminal/TerminalSurfaceView.swift):

- `SurfaceResizeSync`
- `SurfaceResizeDeferred`
- `SurfaceScaleChanged`
- `SurfacePixelSizeChanged`
- `SurfaceScrollWheel`

## Repro Scenario

In a Blink shell tab, run:

```bash
bash scripts/terminal-scroll-benchmark.sh --lines 250000 --width 240 | cat
```

Then:

1. Wait for the command to finish so the scrollback buffer is full.
2. Scroll rapidly through the buffer for 10-15 seconds with a trackpad or wheel.
3. Resize the pane repeatedly while still scrolling.

For a slower streaming case, use:

```bash
bash scripts/terminal-scroll-benchmark.sh --lines 50000 --width 240 --delay 0.001 | cat
```

## Instruments Setup

Use these Instruments templates:

1. `Points of Interest`
2. `Time Profiler`

Recommended capture flow:

1. Launch `Blink Dev`.
2. Start recording in Instruments.
3. Run the benchmark command above.
4. Perform the manual scroll and resize actions.
5. Stop recording.

## What To Compare

Focus on:

- Count and duration of `SurfaceResizeSync`
- How often `SurfaceResizeDeferred` fires during pane drag/resize
- CPU cost under `Time Profiler` inside the Ghostty embed path
- Whether `SurfacePixelSizeChanged` is firing when the pane size is visually stable

## A/B Process

When comparing two implementations:

1. Use the same build configuration.
2. Use the same benchmark command.
3. Use the same manual interaction pattern.
4. Compare signpost counts and `Time Profiler` samples, not just feel.
