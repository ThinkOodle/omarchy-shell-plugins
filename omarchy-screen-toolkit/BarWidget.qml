import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "omarchy-screen-toolkit"
  property var settings: ({})

  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property string pluginId: "omarchy-screen-toolkit"

  property bool popupOpen: false
  property bool resultOpen: false
  property bool settingsView: false

  // PopupCard calls this on outside-click via HyprlandFocusGrab. We close
  // whichever popup the user dismissed without flipping the other on. This
  // is the "user dismissed" path — we flush any pending history persist here
  // so the bar widget rebuild (triggered by updateEntryInline) only happens
  // after the popup is already gone.
  function closePopout() {
    popupOpen = false; resultOpen = false; settingsView = false
    persistHistoryIfDirty()
  }

  // Programmatic close used right before launching a tool. Doesn't persist:
  // the persist would write to ~/.config/omarchy/shell.json, causing the bar
  // layout's Repeater to rebuild its delegates (since shellConfig becomes a
  // fresh deep clone). That rebuild destroys this BarWidget instance, so the
  // result popup we're about to open from the picked color would be torn
  // down mid-flight. History stays in-memory across the tool run and gets
  // flushed when the user dismisses the result popup.
  function closeForTool() { popupOpen = false; resultOpen = false; settingsView = false }

  function openMainPopup() { resultOpen = false; popupOpen = true }
  function openResultPopup() { popupOpen = false; resultOpen = true }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------- settings -----------------------------------------------
  // The widget receives `settings` via ModuleSlot.injectProps — that's the
  // inline part of the bar layout entry. We mirror it into history arrays
  // and persist patches back through shell.updateEntryInline.
  property var colorHistory: []
  property var paletteHistory: []

  function isPlainObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

  // Qt sometimes hands us arrays via `var` property bindings that fail
  // Array.isArray() across QML contexts, even though Object.keys + length all
  // behave correctly. Copy by length probe so we always end up with a real
  // JS array on the widget side.
  function asArrayCopy(value) {
    if (Array.isArray(value)) return value.slice()
    if (value && typeof value === "object" && typeof value.length === "number") {
      var out = []
      for (var i = 0; i < value.length; i++) out.push(value[i])
      return out
    }
    return []
  }

  function refreshFromSettings() {
    var s = isPlainObject(settings) ? settings : ({})
    colorHistory = asArrayCopy(s.colorHistory)
    paletteHistory = asArrayCopy(s.paletteHistory)
  }

  // True after ModuleSlot.injectProps has handed us real settings (separate
  // from the QML initial-default {}). Used to gate addColor/addPalette so
  // an early sentinel fire doesn't clobber persisted history with `[hex]`.
  property bool settingsInjected: false

  onSettingsChanged: {
    settingsInjected = true
    refreshFromSettings()
  }

  function setting(key, fallback) {
    var s = isPlainObject(settings) ? settings : ({})
    var v = s[key]
    return (v === undefined || v === null) ? fallback : v
  }

  // True when in-memory colorHistory/paletteHistory has new entries we haven't
  // yet written back through updateEntryInline. We defer those writes until
  // the user dismisses the popup — see closePopout for the rationale.
  property bool historyDirty: false

  function persist(patch) {
    if (!root.hostShell || typeof root.hostShell.updateEntryInline !== "function") return
    var next = ({ id: pluginId })
    var s = isPlainObject(settings) ? settings : ({})
    for (var k in s) if (k !== "id") next[k] = s[k]
    for (var pk in patch) if (pk !== "id") next[pk] = patch[pk]
    // Always carry the current in-memory history so a settings edit (which
    // pulls `next` from `s`, the last-persisted snapshot) doesn't roll back
    // recent picks the user made since the last persist.
    next.colorHistory = colorHistory.slice()
    next.paletteHistory = paletteHistory.slice()
    historyDirty = false
    root.hostShell.updateEntryInline(pluginId, next)
  }

  function persistHistoryIfDirty() { if (historyDirty) persist({}) }

  // ---------------- own source dir for bundled scripts ---------------------
  readonly property string sourceDir: {
    var url = String(Qt.resolvedUrl("."))
    var prefix = "file://"
    if (url.indexOf(prefix) === 0) url = url.substring(prefix.length)
    if (url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return url
  }
  readonly property string binDir: sourceDir + "/bin"

  // ---------------- tool actions -------------------------------------------
  Process { id: launcherProc }

  function runShell(command) {
    launcherProc.command = ["bash", "-lc", command]
    launcherProc.startDetached()
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function summonOverlay(tool, extra) {
    if (!root.hostShell) return
    var payload = { tool: tool }
    if (extra) for (var k in extra) payload[k] = extra[k]
    root.hostShell.summon(pluginId, JSON.stringify(payload))
  }

  function invokeTool(tool) {
    // Close both popups before running so layer-shell overlays from the tool
    // (slurp, hyprpicker freeze) don't fight with our PopupCard's focus grab.
    // Use closeForTool so we don't trigger a persist (and thus a bar widget
    // rebuild) before the script writes its result.
    closeForTool()
    switch (tool) {
    case "color":     runShell(shellQuote(binDir + "/ost-color-pick")); break
    case "annotate":  runShell("omarchy-capture-screenshot region slurp"); break
    case "measure":   summonOverlay("measure", null); break
    case "pin":       runShell(shellQuote(binDir + "/ost-pin-region")); break
    case "palette":   runShell(shellQuote(binDir + "/ost-palette")); break
    case "ocr":       runShell("omarchy-capture-text-extraction"); break
    case "qr":        runShell(shellQuote(binDir + "/ost-qr")); break
    case "lens":      runShell(shellQuote(binDir + "/ost-lens")); break
    case "record":
      if (String(root.setting("recordFormat", "mp4")) === "gif")
        runShell(shellQuote(binDir + "/ost-record-gif"))
      else
        runShell("omarchy-capture-screenrecording")
      break
    case "mirror":    summonOverlay("mirror", null); break
    default: console.warn("unknown tool:", tool)
    }
  }

  function deleteColor(value) {
    var next = []
    for (var i = 0; i < colorHistory.length; i++)
      if (colorHistory[i] !== value) next.push(colorHistory[i])
    colorHistory = next
    historyDirty = true
  }

  function clearColorHistory() { colorHistory = []; historyDirty = true }
  function clearPaletteHistory() { paletteHistory = []; historyDirty = true }

  function addColor(hex) {
    // Skip writes before injection — local colorHistory is the QML default []
    // at that point, so we'd clobber whatever's on disk with a single-entry
    // list when the popup is later dismissed. The watcher will re-trigger
    // after injection lands.
    if (!settingsInjected) return
    var value = String(hex || "").trim()
    if (!value) return
    var next = [value]
    for (var i = 0; i < colorHistory.length && next.length < 20; i++)
      if (colorHistory[i] !== value) next.push(colorHistory[i])
    colorHistory = next
    historyDirty = true
  }

  // ---------------- color format helpers -----------------------------------
  // Parse "#rrggbb" into [r, g, b] 0..255. Returns null if malformed.
  function parseHex(value) {
    var m = String(value || "").match(/^#?([0-9a-fA-F]{6})$/)
    if (!m) return null
    var n = parseInt(m[1], 16)
    return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]
  }

  function rgbStr(value) {
    var rgb = parseHex(value)
    return rgb ? ("rgb(" + rgb[0] + ", " + rgb[1] + ", " + rgb[2] + ")") : ""
  }

  function hsvStr(value) {
    var rgb = parseHex(value)
    if (!rgb) return ""
    var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
    var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
    var h = 0, s = max === 0 ? 0 : d / max, v = max
    if (d !== 0) {
      if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
      else if (max === g) h = (b - r) / d + 2
      else h = (r - g) / d + 4
      h *= 60
    }
    return "hsv(" + Math.round(h) + ", " + Math.round(s * 100) + "%, " + Math.round(v * 100) + "%)"
  }

  function hslStr(value) {
    var rgb = parseHex(value)
    if (!rgb) return ""
    var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
    var max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min
    var l = (max + min) / 2
    var h = 0, s = 0
    if (d !== 0) {
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
      if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
      else if (max === g) h = (b - r) / d + 2
      else h = (r - g) / d + 4
      h *= 60
    }
    return "hsl(" + Math.round(h) + ", " + Math.round(s * 100) + "%, " + Math.round(l * 100) + "%)"
  }

  // The chip the user has expanded into the detail strip. Set automatically
  // after a fresh pick, but the user can swap by clicking any chip.
  property string selectedColor: ""

  function addPalette(colors) {
    if (!settingsInjected) return
    if (!Array.isArray(colors) || colors.length === 0) return
    var entry = colors.slice()
    var next = [entry]
    for (var i = 0; i < paletteHistory.length && next.length < 10; i++)
      next.push(paletteHistory[i])
    paletteHistory = next
    historyDirty = true
  }

  // ---------------- runtime sentinels --------------------------------------
  // Tools live in bin/<script>. They write their last result to a file in
  // $XDG_RUNTIME_DIR/omarchy-screen-toolkit/<kind>.last and we mirror that
  // into colorHistory / paletteHistory. The watchers attach to the inode at
  // startup, so we touch the sentinels first to give inotify something to
  // hold onto — otherwise the first write after script run isn't observed.
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-screen-toolkit"

  Process {
    id: ensureRuntime
    running: true
    command: ["bash", "-lc",
      "mkdir -p \"$0\"; : >>\"$0/color.last\"; : >>\"$0/palette.last\"",
      root.runtimeDir]
    onExited: {
      colorSentinel.reload()
      paletteSentinel.reload()
    }
  }

  // Track the previous content so re-reading an unchanged file (after a
  // touch-only event) doesn't re-add the same color twice.
  property string lastColorSeen: ""
  property string lastPaletteSeen: ""

  // Settling gate: the bar host injects `settings` (and therefore colorHistory)
  // after Component.onCompleted runs, so any sentinel load that arrives during
  // that race sees empty history and looks like a "fresh pick". Hold popup-
  // opening until injection has had time to land.
  property bool sentinelArmed: false
  Timer {
    id: armSentinelTimer
    interval: 800
    repeat: false
    onTriggered: root.sentinelArmed = true
  }
  Component.onCompleted: {
    refreshFromSettings()
    armSentinelTimer.start()
  }

  FileView {
    id: colorSentinel
    path: root.runtimeDir + "/color.last"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = String(text() || "").trim()
      if (!t || t === root.lastColorSeen) return
      root.lastColorSeen = t
      var headBefore = root.colorHistory.length > 0 ? root.colorHistory[0] : ""
      var isFreshPick = headBefore !== t
      root.addColor(t)
      if (root.sentinelArmed && isFreshPick) {
        root.selectedColor = t
        root.settingsView = false
        root.openResultPopup()
      }
    }
  }

  FileView {
    id: paletteSentinel
    path: root.runtimeDir + "/palette.last"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var raw = String(text() || "").trim()
      if (!raw || raw === root.lastPaletteSeen) return
      root.lastPaletteSeen = raw
      var lines = raw.split(/\s+/)
      var clean = []
      for (var i = 0; i < lines.length; i++)
        if (lines[i].length > 0) clean.push(lines[i])
      root.addPalette(clean)
    }
  }

  // ---------------- tool catalog -------------------------------------------
  readonly property var toolCatalog: [
    { id: "color",    icon: "󰸉", label: "Color" },
    { id: "annotate", icon: "󰏬", label: "Annotate" },
    { id: "measure",  icon: "󰢈", label: "Measure" },
    { id: "pin",      icon: "󰐃", label: "Pin" },
    { id: "palette",  icon: "󰸌", label: "Palette" },
    { id: "ocr",      icon: "󰦨", label: "OCR" },
    { id: "qr",       icon: "󰡯", label: "QR" },
    { id: "lens",     icon: "󰍉", label: "Lens" },
    { id: "record",   icon: "󰕧", label: "Record" },
    { id: "mirror",   icon: "󰖠", label: "Mirror" }
  ]

  // ---------------- theme tokens used by the popup --------------------------
  property color foreground: Color.foreground
  property color dim: Qt.darker(Color.foreground, 1.5)
  property color popupBackground: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent

  Behavior on foreground { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on popupBackground { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on popupBorder { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on accent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }

  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: bar ? bar.fontFamily : "monospace"

  // ---------------- bar button ---------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄄"
    tooltipText: "Screen toolkit"

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.bar && typeof root.bar.run === "function")
          root.bar.run("omarchy-capture-screenshot")
        return
      }
      if (root.popupOpen || root.resultOpen) root.closePopout()
      else root.openMainPopup()
    }
  }

  // ---------------- IPC --------------------------------------------------
  // Lets keybinds toggle the popup without going through the panel-summon
  // path. `omarchy-shell screen-toolkit toggle` opens/closes it.
  IpcHandler {
    target: "screen-toolkit"
    function toggle(): void {
      if (root.popupOpen || root.resultOpen) root.closePopout()
      else root.openMainPopup()
    }
    function open(): void { root.openMainPopup() }
    function close(): void { root.closePopout() }
  }

  // ---------------- popup --------------------------------------------------
  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: 480
    contentHeight: contentColumn.implicitHeight + 2 * popup.padding

    FocusScope {
      anchors.fill: parent
      focus: root.popupOpen
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.closePopout()
          event.accepted = true
        }
      }
    }

    ColumnLayout {
      id: contentColumn
      width: popup.contentWidth - 2 * popup.padding
      spacing: 12

      // header
      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: root.settingsView ? "Settings" : "Screen Toolkit"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 13
          font.bold: true
          Layout.fillWidth: true
        }

        HeaderButton {
          glyph: root.settingsView ? "" : ""
          onClicked: root.settingsView = !root.settingsView
        }
      }

      // body
      Loader {
        Layout.fillWidth: true
        sourceComponent: root.settingsView ? settingsBody : toolsBody
      }
    }
  }

  // Result overlay — opens automatically after a fresh color pick. Built as
  // a fullscreen layer-shell window with exclusive keyboard focus so ESC
  // reliably closes it. The card itself is centered on screen.
  PanelWindow {
    id: resultOverlay
    visible: root.resultOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // The bar that hosts this widget is per-screen; pin the overlay to the
    // same screen so it shows on the same output (and so the per-screen
    // duplicate widget instances don't fight over the default screen).
    screen: root.QsWindow && root.QsWindow.window ? root.QsWindow.window.screen : null

    WlrLayershell.namespace: "omarchy-screen-toolkit-result"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    onVisibleChanged: {
      if (visible && resultKeyCatcher) Qt.callLater(function() {
        if (resultKeyCatcher) resultKeyCatcher.forceActiveFocus()
      })
    }

    // Backdrop swallows clicks outside the card and dismisses the overlay.
    MouseArea {
      anchors.fill: parent
      onClicked: root.closePopout()
    }

    Rectangle {
      id: resultCard
      anchors.centerIn: parent
      width: 380
      implicitHeight: resultColumn.implicitHeight + 24
      height: implicitHeight
      color: root.popupBackground
      border.color: root.popupBorder
      border.width: 2
      radius: root.cornerRadius > 0 ? root.cornerRadius : 10

      // Swallow clicks on the card so the backdrop doesn't see them.
      MouseArea { anchors.fill: parent }

      Item {
        id: resultKeyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.closePopout()
            event.accepted = true
          }
        }
      }

      ColumnLayout {
        id: resultColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        spacing: 12

        // result panel
        Loader {
          Layout.fillWidth: true
          active: root.selectedColor !== ""
          sourceComponent: colorResult
        }

        // history
        RowLayout {
          Layout.fillWidth: true
          spacing: 8
          visible: root.colorHistory.length > 0

          Text {
            text: "History"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }

          Item { Layout.fillWidth: true }

          Text {
            text: ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: 11
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.clearColorHistory()
            }
          }
        }

        Flow {
          Layout.fillWidth: true
          spacing: 8
          visible: root.colorHistory.length > 0

          Repeater {
            model: root.colorHistory
            delegate: ColorSwatch {
              required property var modelData
              value: String(modelData)
              selected: value === root.selectedColor
              onTriggered: {
                root.selectedColor = (root.selectedColor === value) ? "" : value
              }
              onDeleteRequested: root.deleteColor(value)
            }
          }
        }
      }
    }
  }

  // -------------- bodies ---------------------------------------------------
  Component {
    id: toolsBody

    ColumnLayout {
      spacing: 12

      GridLayout {
        Layout.fillWidth: true
        columns: 5
        rowSpacing: 8
        columnSpacing: 8

        Repeater {
          model: root.toolCatalog
          delegate: ToolTile {
            required property var modelData
            iconText: modelData.icon
            label: modelData.label
            Layout.fillWidth: true
            onActivated: root.invokeTool(modelData.id)
          }
        }
      }


      SectionHeader {
        text: "Recent palettes"
        visible: root.paletteHistory.length > 0
        onClear: root.clearPaletteHistory()
      }
      Column {
        Layout.fillWidth: true
        spacing: 6
        visible: root.paletteHistory.length > 0

        Repeater {
          model: root.paletteHistory
          delegate: Row {
            id: paletteRow
            spacing: 4
            required property var modelData
            readonly property var colors: Array.isArray(modelData) ? modelData : (modelData && modelData.colors) || []

            Repeater {
              model: paletteRow.colors
              delegate: ColorChip {
                required property var modelData
                value: String(modelData)
                deletable: false
                onTriggered: root.runShell("printf %s " + root.shellQuote(value) + " | wl-copy")
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: settingsBody

    ColumnLayout {
      spacing: 10

      SettingsRow {
        label: "Screenshot path"
        placeholder: "$XDG_PICTURES_DIR"
        value: String(root.setting("screenshotPath", ""))
        onCommitted: root.persist({ screenshotPath: text })
      }

      SettingsRow {
        label: "Video path"
        placeholder: "$XDG_VIDEOS_DIR"
        value: String(root.setting("videoPath", ""))
        onCommitted: root.persist({ videoPath: text })
      }

      SettingsRow {
        label: "OCR language"
        placeholder: "eng"
        value: String(root.setting("ocrLang", "eng"))
        onCommitted: root.persist({ ocrLang: text })
      }

      SettingsRow {
        label: "Record format"
        placeholder: "mp4 | gif"
        value: String(root.setting("recordFormat", "mp4"))
        onCommitted: {
          var v = String(text || "").trim().toLowerCase()
          if (v === "mp4" || v === "gif") root.persist({ recordFormat: v })
        }
      }

      SettingsRow {
        label: "GIF max seconds"
        placeholder: "30"
        value: String(root.setting("gifMaxSeconds", 30))
        onCommitted: {
          var n = parseInt(text, 10)
          if (isFinite(n) && n > 0) root.persist({ gifMaxSeconds: n })
        }
      }

      SettingsRow {
        label: "Search engine URL"
        placeholder: "https://www.google.com/searchbyimage?image_url="
        value: String(root.setting("searchEngineUrl", ""))
        onCommitted: root.persist({ searchEngineUrl: text })
      }

      SettingsToggle {
        label: "Copy recording to clipboard"
        checked: root.setting("copyRecordingToClipboard", false) === true
        onToggled: root.persist({ copyRecordingToClipboard: value })
      }

      SettingsToggle {
        label: "Skip recording confirmation"
        checked: root.setting("skipRecordingConfirmation", false) === true
        onToggled: root.persist({ skipRecordingConfirmation: value })
      }
    }
  }

  // -------------- reusable bits --------------------------------------------
  component HeaderButton: Rectangle {
    id: hb
    property string glyph: ""
    signal clicked()

    implicitWidth: 24
    implicitHeight: 24
    radius: root.cornerRadius > 0 ? root.cornerRadius : 4
    color: hbHover.containsMouse ? Style.hotFill : "transparent"

    Text {
      anchors.centerIn: parent
      text: hb.glyph
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 12
    }

    MouseArea {
      id: hbHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: hb.clicked()
    }
  }

  component ToolTile: Item {
    id: tile
    property string iconText: ""
    property string label: ""
    signal activated()

    implicitHeight: 64

    Rectangle {
      anchors.fill: parent
      color: tileHover.containsMouse ? Style.hotFill : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
      border.color: tileHover.containsMouse ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      border.width: 1
      radius: root.cornerRadius > 0 ? root.cornerRadius : 6

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 3

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: tile.iconText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 18
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: tile.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }

      Behavior on border.color { ColorAnimation { duration: 140 } }
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    MouseArea {
      id: tileHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.activated()
    }
  }

  component SectionHeader: RowLayout {
    id: sh
    property string text: ""
    signal clear()

    Layout.fillWidth: true
    spacing: 6

    Text {
      Layout.fillWidth: true
      text: sh.text
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 10
      font.bold: true
    }

    Text {
      text: "clear"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 10
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sh.clear()
      }
    }
  }

  component ColorChip: Item {
    id: chip
    property string value: ""
    property bool deletable: true
    property bool selected: false
    signal triggered()
    signal deleteRequested()

    implicitWidth: chipLabel.implicitWidth + 30
    implicitHeight: 20

    Rectangle {
      anchors.fill: parent
      radius: root.cornerRadius > 0 ? root.cornerRadius : 4
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      border.color: chip.selected ? root.accent : (chipHover.containsMouse ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18))
      border.width: chip.selected ? 2 : 1
    }

    Rectangle {
      width: 12; height: 12; radius: 2
      anchors.left: parent.left
      anchors.leftMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      color: chip.value
      border.color: Qt.rgba(0, 0, 0, 0.4)
      border.width: 1
    }

    Text {
      id: chipLabel
      anchors.left: parent.left
      anchors.leftMargin: 22
      anchors.verticalCenter: parent.verticalCenter
      text: chip.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 10
    }

    MouseArea {
      id: chipHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton && chip.deletable) chip.deleteRequested()
        else chip.triggered()
      }
    }
  }

  // Result panel rendered when `selectedColor` is set. Mirrors a familiar
  // color-tool layout: a "pick again" affordance, a big swatch + hex, then
  // labelled format rows with individual copy buttons, and footer actions.
  Component {
    id: colorResult

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: resultColumn.implicitHeight + 18
      radius: root.cornerRadius > 0 ? root.cornerRadius : 8
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
      border.width: 1

      ColumnLayout {
        id: resultColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 10

        // -------- pick again
        Item {
          Layout.fillWidth: true
          implicitHeight: pickAgain.implicitHeight

          Row {
            id: pickAgain
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Text {
              text: ""
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 11
              anchors.verticalCenter: parent.verticalCenter
            }
            Text {
              text: "Pick again"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: 11
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.runShell(root.shellQuote(root.binDir + "/ost-color-pick"))
          }
        }

        // -------- swatch + hex label
        Item {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          implicitWidth: bigSwatch.width
          implicitHeight: bigSwatch.height + swatchLabel.height + 6

          Rectangle {
            id: bigSwatch
            width: 130
            height: 84
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            radius: root.cornerRadius > 0 ? root.cornerRadius : 10
            color: root.selectedColor
            border.color: Qt.rgba(0, 0, 0, 0.4)
            border.width: 1
          }

          Text {
            id: swatchLabel
            anchors.top: bigSwatch.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.selectedColor.toUpperCase()
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
          }
        }

        // -------- format rows
        FormatRow { label: "HEX"; value: root.selectedColor }
        FormatRow { label: "RGB"; value: root.rgbStr(root.selectedColor) }
        FormatRow { label: "HSL"; value: root.hslStr(root.selectedColor) }
        FormatRow { label: "HSV"; value: root.hsvStr(root.selectedColor) }

        // -------- actions
        RowLayout {
          Layout.fillWidth: true
          Layout.topMargin: 4
          spacing: 8

          Item { Layout.fillWidth: true }

          ActionPill {
            glyph: ""
            label: "Copy All"
            onTriggered: {
              var lines = root.selectedColor + "\n" +
                root.rgbStr(root.selectedColor) + "\n" +
                root.hslStr(root.selectedColor) + "\n" +
                root.hsvStr(root.selectedColor)
              root.runShell("printf %s " + root.shellQuote(lines) + " | wl-copy")
            }
          }

          ActionPill {
            glyph: ""
            label: "Clear result"
            onTriggered: root.selectedColor = ""
          }

          Item { Layout.fillWidth: true }
        }
      }
    }
  }

  component FormatRow: RowLayout {
    id: fr
    property string label: ""
    property string value: ""
    property bool justCopied: false

    Layout.fillWidth: true
    spacing: 10

    Text {
      text: fr.label
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: 11
      font.bold: true
      Layout.preferredWidth: 36
    }

    Text {
      text: fr.justCopied ? "copied" : fr.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 11
      Layout.fillWidth: true
      elide: Text.ElideRight
    }

    Rectangle {
      Layout.preferredWidth: 22
      Layout.preferredHeight: 22
      radius: root.cornerRadius > 0 ? root.cornerRadius : 4
      color: copyBtnHover.containsMouse ? Style.hotFill : "transparent"
      border.color: fr.justCopied ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      MouseArea {
        id: copyBtnHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          if (!fr.value) return
          root.runShell("printf %s " + root.shellQuote(fr.value) + " | wl-copy")
          fr.justCopied = true
          copiedReset.restart()
        }
      }

      Timer {
        id: copiedReset
        interval: 900
        repeat: false
        onTriggered: fr.justCopied = false
      }

      Behavior on border.color { ColorAnimation { duration: 140 } }
    }
  }

  component ActionPill: Rectangle {
    id: ap
    property string glyph: ""
    property string label: ""
    signal triggered()

    implicitWidth: apContent.implicitWidth + 18
    implicitHeight: 24
    radius: root.cornerRadius > 0 ? root.cornerRadius : 4
    color: apHover.containsMouse ? Style.hotFill : "transparent"
    border.color: apHover.containsMouse ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
    border.width: 1

    Row {
      id: apContent
      anchors.centerIn: parent
      spacing: 6

      Text {
        text: ap.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        text: ap.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: apHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ap.triggered()
    }

    Behavior on border.color { ColorAnimation { duration: 140 } }
  }

  component ColorSwatch: Item {
    id: sw
    property string value: ""
    property bool selected: false
    signal triggered()
    signal deleteRequested()

    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: sw.value
      border.color: sw.selected ? root.accent : (swHover.containsMouse ? root.accent : Qt.rgba(0, 0, 0, 0.4))
      border.width: sw.selected ? 2 : 1
    }

    MouseArea {
      id: swHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onEntered: if (root.bar) root.bar.showTooltip(sw, sw.value)
      onExited: if (root.bar) root.bar.hideTooltip(sw)
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) sw.deleteRequested()
        else sw.triggered()
      }
    }
  }

  component SettingsRow: ColumnLayout {
    id: sr
    property string label: ""
    property string placeholder: ""
    property string value: ""
    signal committed(string text)

    Layout.fillWidth: true
    spacing: 3

    Text {
      text: sr.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: 10
      font.bold: true
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 26
      radius: root.cornerRadius > 0 ? root.cornerRadius : 4
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      border.color: rowField.activeFocus ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      border.width: 1

      TextInput {
        id: rowField
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: TextInput.AlignVCenter
        text: sr.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 11
        clip: true
        selectByMouse: true
        onEditingFinished: sr.committed(text)
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: sr.placeholder
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
        font.family: root.fontFamily
        font.pixelSize: 11
        visible: rowField.text.length === 0
      }
    }
  }

  component SettingsToggle: RowLayout {
    id: st
    property string label: ""
    property bool checked: false
    signal toggled(bool value)

    Layout.fillWidth: true
    spacing: 10

    Text {
      Layout.fillWidth: true
      text: st.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 11
    }

    Rectangle {
      id: track
      implicitWidth: 32
      implicitHeight: 16
      radius: 8
      color: st.checked ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
      border.width: 1

      Rectangle {
        width: 12; height: 12; radius: 6
        anchors.verticalCenter: parent.verticalCenter
        x: st.checked ? track.width - width - 2 : 2
        color: root.popupBackground
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.InOutCubic } }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: st.toggled(!st.checked)
      }
    }
  }
}
