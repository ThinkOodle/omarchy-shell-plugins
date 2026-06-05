import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by omarchy-shell. Keep these optional (not required) so the
  // loader can create the plugin and then wire the properties in.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property var barConfig: ({})

  property string home: Quickshell.env("HOME")
  property string position: normalizePosition(barConfig && barConfig.position)
  property bool vertical: position === "left" || position === "right"
  property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  property int outerInset: Style.space(5)
  property int visualExtra: Style.space(2)
  property int windowSize: barSize + outerInset + visualExtra
  property bool barHidden: false
  property string fontFamily: Style.font.family
  property color background: Color.bar.background
  property color foreground: Color.bar.text
  property color barForeground: Color.bar.text
  property color urgent: Color.bar.active
  property bool foregroundAnimationEnabled: false
  property var activePopout: null
  property var debugModuleSlots: []
  property var clickTargets: []
  property var barDragSource: null
  property var barDragTarget: null
  property bool barDragAfter: false
  property var barDragWindow: null

  function normalizePosition(value) {
    var next = String(value || "").trim()
    return /^(top|bottom|left|right)$/.test(next) ? next : "top"
  }

  function entryId(entry) {
    if (typeof entry === "string") return entry
    if (entry && typeof entry === "object" && !Array.isArray(entry)) {
      var id = entry.id
      if (id !== undefined && id !== null && String(id) !== "") return String(id)
    }
    return ""
  }

  function entrySettings(entry) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return ({})
    var copy = ({})
    for (var key in entry) {
      if (key !== "id") copy[key] = entry[key]
    }
    return copy
  }

  function layoutEntries(region) {
    var layout = barConfig && barConfig.layout ? barConfig.layout : null
    var entries = layout ? layout[region] : null
    return Array.isArray(entries) ? entries : []
  }

  function run(command) {
    if (!command) return
    launcher.command = Util.hyprExecCommand(command)
    launcher.startDetached()
  }

  function showTooltip(target, text) {}
  function hideTooltip(target) {}

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  function openConfigPanel() {
    return false
  }

  function registerDebugModuleSlot(slot) {
    if (!slot || debugModuleSlots.indexOf(slot) !== -1) return
    var next = debugModuleSlots.slice()
    next.push(slot)
    debugModuleSlots = next
  }

  function unregisterDebugModuleSlot(slot) {
    var next = debugModuleSlots.filter(function(item) { return item !== slot })
    debugModuleSlots = next
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function clearBarDrag() {
    barDragSource = null
    barDragTarget = null
    barDragAfter = false
    barDragWindow = null
  }

  function rawLayoutSection(config, region) {
    if (!config.bar || typeof config.bar !== "object" || Array.isArray(config.bar)) config.bar = {}
    if (!config.bar.layout || typeof config.bar.layout !== "object" || Array.isArray(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []
    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }
    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < debugModuleSlots.length; i++) {
      var slot = debugModuleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try { slotPoint = slot.mapToItem(null, 0, 0) } catch (e) {}

      if (scenePoint.x >= slotPoint.x && scenePoint.x <= slotPoint.x + slot.width &&
          scenePoint.y >= slotPoint.y && scenePoint.y <= slotPoint.y + slot.height) {
        return {
          slot: slot,
          after: root.vertical ? scenePoint.y > slotPoint.y + slot.height / 2 : scenePoint.x > slotPoint.x + slot.width / 2
        }
      }
    }
    return null
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < debugModuleSlots.length; i++) {
      var slot = debugModuleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }
    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }
      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }
    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false
    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try { targetPoint = slot.mapToItem(target, localX, localY) } catch (e) { continue }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false
    target.triggerPress(button)
    return true
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < debugModuleSlots.length; i++) {
      var slot = debugModuleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try { point = slot.mapToItem(null, 0, 0) } catch (e) {}
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  Process { id: launcher }

  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-lc", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }

  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: barWindow
        required property var modelData

        screen: modelData
        visible: !root.barHidden
        color: "transparent"
        implicitWidth: root.vertical ? root.windowSize : 0
        implicitHeight: root.vertical ? 0 : root.windowSize
        WlrLayershell.namespace: "demo-neon-bar"
        WlrLayershell.layer: WlrLayer.Top

        anchors {
          top: root.position === "top" || root.vertical
          bottom: root.position === "bottom" || root.vertical
          left: root.position === "left" || !root.vertical
          right: root.position === "right" || !root.vertical
        }

        Loader {
          anchors.fill: parent
          sourceComponent: root.vertical ? verticalSurface : horizontalSurface
        }

        Component {
          id: horizontalSurface

          Item {
            anchors.fill: parent

            Rectangle {
              id: pill
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              anchors.topMargin: root.position === "bottom" ? 0 : root.outerInset
              anchors.bottomMargin: root.position === "top" ? 0 : root.outerInset
              radius: height / 2
              color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)
              border.color: Color.accent
              border.width: 1
              clip: true

            }

            ModuleRow {
              entries: root.layoutEntries("left")
              region: "left"
              anchors.left: pill.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: pill.verticalCenter
            }

            ModuleRow {
              entries: root.layoutEntries("center")
              region: "center"
              anchors.centerIn: pill
            }

            ModuleRow {
              entries: root.layoutEntries("right")
              region: "right"
              anchors.right: pill.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: pill.verticalCenter
            }
          }
        }

        Component {
          id: verticalSurface

          Item {
            anchors.fill: parent

            Rectangle {
              id: rail
              anchors.fill: parent
              anchors.topMargin: Style.space(12)
              anchors.bottomMargin: Style.space(12)
              anchors.leftMargin: root.position === "right" ? 0 : root.outerInset
              anchors.rightMargin: root.position === "left" ? 0 : root.outerInset
              radius: width / 2
              color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.78)
              border.color: Color.accent
              border.width: 1
              clip: true

            }

            ModuleColumn {
              entries: root.layoutEntries("left")
              region: "left"
              anchors.top: rail.top
              anchors.topMargin: Style.space(14)
              anchors.horizontalCenter: rail.horizontalCenter
            }

            ModuleColumn {
              entries: root.layoutEntries("center")
              region: "center"
              anchors.centerIn: rail
            }

            ModuleColumn {
              entries: root.layoutEntries("right")
              region: "right"
              anchors.bottom: rail.bottom
              anchors.bottomMargin: Style.space(14)
              anchors.horizontalCenter: rail.horizontalCenter
            }
          }
        }
      }
    }
  }

  component ModuleRow: Row {
    property var entries: []
    property string region: ""
    spacing: Style.space(1)

    Repeater {
      model: entries
      ModuleSlot {
        required property var modelData
        entry: modelData
        region: parent.region
      }
    }
  }

  component ModuleColumn: Column {
    property var entries: []
    property string region: ""
    spacing: Style.space(1)

    Repeater {
      model: entries
      ModuleSlot {
        required property var modelData
        entry: modelData
        region: parent.region
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property var registryComponent: {
      var widgets = root.barWidgetRegistry ? root.barWidgetRegistry.widgets : ({})
      var key = Util.canonicalWidgetId(moduleName)
      return widgets[key] ? widgets[key].component : null
    }
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: registryLoader.item
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool dropTarget: root.barDragTarget === slot

    visible: registered && activeItem !== null
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? (root.vertical ? activeItem.implicitHeight : root.barSize) : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerDebugModuleSlot(slot)
    Component.onDestruction: root.unregisterDebugModuleSlot(slot)
    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.35 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      visible: slot.dragSource
      anchors.fill: parent
      color: "transparent"
      border.color: Color.accent
      border.width: 1
      radius: Math.min(width, height) / 2
      opacity: 0.75
    }

    Rectangle {
      visible: !root.vertical && slot.dropTarget && !root.barDragAfter
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 2
      color: Color.accent
      opacity: 0.95
    }

    Rectangle {
      visible: !root.vertical && slot.dropTarget && root.barDragAfter
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 2
      color: Color.accent
      opacity: 0.95
    }

    Rectangle {
      visible: root.vertical && slot.dropTarget && !root.barDragAfter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 2
      color: Color.accent
      opacity: 0.95
    }

    Rectangle {
      visible: root.vertical && slot.dropTarget && root.barDragAfter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 2
      color: Color.accent
      opacity: 0.95
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragSource = slot
          }
          dragging = true
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true
        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }
  }
}
