# Bar

The bar is a single transparent surface per monitor that can occupy **multiple screen edges** at
once. Everything is configured in **Settings → Bar**.

## Modes

| Mode | Behaviour |
| --- | --- |
| **dock** | Flush against one edge, reserves space |
| **float** | One edge with a gap from the screen border, rounded, still reserves space |
| **frame** | The signature look: a multi-edge frame (e.g. top + left) with rounded inner corners; edges without modules shrink to half thickness |

Each mode keeps its **own module arrangement** — switching modes never disturbs the others.

## Edges & groups

Every active edge has three groups: **start**, **center**, **end**. Modules are added per
edge/group (Settings → Bar → Modules → Add). On vertical edges the modules rotate to read along
the bar.

Menus that grow out of the bar (settings menu, calendar, volume/mpris flyouts, notification
centre) dock into the bar with concave fillet transitions; a module in start/end merges its menu
into the corner, a center module grows a free tab. The transition style (fillet / straight) is
configurable in Settings → Style → Transition.

## Sizing & style

- Thickness, float gap, inner radius, module margin/spacing
- Module background: none / per group / per module (radius + opacity)
- Icon size and font size — globally, overridable per module via its gear
- Bar opacity (Settings → Bar → Style)

## Per-monitor configuration

Enable **per-monitor** in Settings → Bar to override any bar setting for a specific monitor
(stored under `bar_monitors.<name>` in settings.json). The settings page edits the monitor picked
in its header. Each monitor can have a completely different bar (mode, edges, modules).

When a window is fullscreen the bar hides and bar-docked menus grow from the bare screen edge
instead.

## Exclusive zones

Space is reserved per screen × edge, only where the bar actually occupies that edge. The taskbar
can additionally reserve space ("like bar", Settings → Taskbar).
