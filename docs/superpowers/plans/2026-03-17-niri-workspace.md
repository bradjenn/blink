# Niri Workspace — Follow-Up Note

> Captures the current state of Blink's Niri-inspired workspace rewrite and the remaining work before the feature feels complete.

**Branch:** `feature/niri-workspace`

**Goal:** Push Blink from a flat tab strip toward a Niri-style spatial workspace model with live window columns, keyboard/gesture navigation, and stronger motion.

---

## Built Now

- Visible tab strip removed in favor of horizontal workspace columns.
- Active project renders as a row of live terminal/tool windows.
- Focused window gets distinct styling and centered scroll behavior.
- Window insert/remove/focus motion is in place for the basic column model.
- Sidebar now owns window creation instead of a top toolbar.
- `Cmd + two-finger horizontal swipe` switches windows.
- `Cmd+W` closes the active workspace window instead of the app window.
- State/tests were cleaned up so window lifecycle behavior is deterministic.

---

## Still Left

### 1. Floating Tool Layer

Tool windows such as:
- `lazygit`
- `Claude Code`
- `Codex`
- `Open Code`

still open as normal columns. They should move into a separate floating layer so the main shell workspace remains stable.

### 2. Overview Mode

Add a zoomed-out overview for:
- selecting windows
- reordering windows
- moving windows between columns
- understanding the current project workspace at a glance

### 3. True Column Composition

The current model is effectively one surface per column. Still needed:
- multiple windows inside a column
- tabbed/stacked column behavior
- moving a window into an existing column
- extracting a window from a column

### 4. Window Management Actions

Add first-class actions for:
- move window left/right
- merge into column
- extract from column
- maximize/focus current column

### 5. Stronger Keyboard Model

Current shortcuts work, but the app still lacks a deliberate Niri-style action model for:
- focus navigation
- moving windows
- reorganizing columns
- invoking overview

### 6. Layout Persistence

Projects/settings already persist, but the spatial workspace itself does not. Need to persist:
- column order
- focused window
- floating tool windows
- future stacked/tabbed column structure

### 7. Motion Pass

Basic column motion exists, but a fuller motion system is still pending:
- overview zoom transitions
- floating window transitions
- better layout reflow polish
- optional reduced-motion tuning

---

## Recommended Next Order

1. Floating tool layer
2. Overview mode
3. True multi-window columns
4. Layout persistence
5. Motion polish

