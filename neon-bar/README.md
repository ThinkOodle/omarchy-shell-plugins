# Neon Demo Bar

`demo.neon-bar` is a full Omarchy bar replacement demo. It intentionally looks
unlike the built-in bar with a floating translucent pill/rail. It still renders the configured Omarchy bar widgets
from `~/.config/omarchy/shell.json`, so existing widget configuration remains
useful while the bar chrome is completely replaced.

## Install

Add this repository as a trusted Omarchy plugin source once:

```bash
omarchy plugin source add https://github.com/thinkoodle/omarchy-shell-plugins
```

Then add and enable Neon Demo Bar. Because it is a full bar option, enabling it
makes it the active bar:

```bash
omarchy plugin add demo.neon-bar --enable
```

If it does not appear immediately, reload the shell:

```bash
omarchy restart shell
```

Return to the built-in bar:

```bash
omarchy config shell bar reset
# or explicitly:
omarchy config shell bar use omarchy.bar
omarchy restart shell
```

List available full-bar options:

```bash
omarchy config shell bar options
# or via the plugin command:
omarchy plugin bar options
```

## Development contract for replacement bars

A replacement bar is a normal Omarchy plugin with `kind: "bar"` and an
`entryPoints.bar` QML file:

```json
{
  "schemaVersion": 1,
  "id": "your.namespace.bar",
  "name": "Your Bar",
  "version": "1.0.0",
  "author": "You",
  "description": "A full Omarchy bar replacement",
  "kinds": ["bar"],
  "entryPoints": { "bar": "Bar.qml" }
}
```

The bar entry point should be an `Item`, not a `ShellRoot`. Omarchy injects
properties after loading, so keep them optional rather than `required`:

```qml
Item {
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property var barConfig: ({})
}
```

For compatibility with existing widgets, panels, notifications, and debug tools,
your bar should expose these properties/functions:

- `position`, `vertical`, `barSize`, `barHidden`
- `fontFamily`, `foreground`, `barForeground`, `background`, `urgent`
- `foregroundAnimationEnabled`
- `activePopout`, `requestPopout(owner)`, `releasePopout(owner)`
- `run(command)` for widget click actions
- `showTooltip(target, text)` and `hideTooltip(target)` (no-op is acceptable)
- `registerClickTarget(target)` and `unregisterClickTarget(target)` (no-op is acceptable if you do not implement drag/reorder overlays)
- `openConfigPanel()` returning `true` or `false`
- `debugBarGeometry()` returning an array of rendered widget slots

To stay compatible with existing bar widgets, load components from
`barWidgetRegistry.widgets`, then inject the same per-slot properties the built-in
bar injects:

```qml
if ("bar" in target) target.bar = root
if ("moduleName" in target) target.moduleName = moduleName
if ("settings" in target) target.settings = moduleSettings
```

This demo implements the core compatible path: it renders registered widgets,
respects `bar.position`, watches the `bar-off` toggle used by
`omarchy toggle bar`, supports drag-to-reorder using the shared `shell.json`
layout, provides popout coordination, and exposes debug geometry. It deliberately
keeps tooltip handling minimal; custom bars can add their own tooltip bubble
system if desired.
