import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// A single floating, draggable, resizable image pinned on top of the
// screen. Mounted by Overlay.qml per slot; closing the pin removes the
// slot, which in turn unmounts this component. Multiple pin slots stack
// so the user can pile several images on screen at once.
Item {
  id: root

  // payload from Overlay's slot: { tool: "pin", path: "/tmp/...png", w, h }
  property var payload: ({})
  signal closeRequested()

  readonly property string imgPath: payload && payload.path ? String(payload.path) : ""
  readonly property int srcW: payload && payload.w ? Math.max(80, parseInt(payload.w) || 600) : 600
  readonly property int srcH: payload && payload.h ? Math.max(60, parseInt(payload.h) || 400) : 400

  // The captured pixel buffer can be much bigger than the display (think
  // 4K capture on a 1080p secondary). Cap initial pin size at 60% of the
  // host screen so it's manageable; the user can still grow it.
  function clampSize(w, h, screenW, screenH) {
    var maxW = Math.max(160, Math.round(screenW * 0.6))
    var maxH = Math.max(120, Math.round(screenH * 0.6))
    var s = Math.min(1.0, Math.min(maxW / w, maxH / h))
    return { w: Math.round(w * s), h: Math.round(h * s) }
  }

  property int curW: 0
  property int curH: 0
  property int curX: 0
  property int curY: 0
  property bool placed: false

  // Successive pins offset slightly so they don't sit exactly on top of
  // each other. Overlay.qml passes this so each new pin knows where in
  // the stack it landed.
  readonly property int stackIndex: payload && payload.stackIndex ? parseInt(payload.stackIndex) || 0 : 0

  function initPlacement(screenW, screenH) {
    var s = clampSize(srcW, srcH, screenW, screenH)
    curW = s.w
    curH = s.h
    var offset = (stackIndex % 8) * 28
    curX = Math.max(0, Math.round((screenW - curW) / 2) + offset)
    curY = Math.max(0, Math.round((screenH - curH) / 2) + offset)
    placed = true
  }

  // Loader.onLoaded sets `payload` AFTER Component.onCompleted fires, so
  // both the panel-mount and a payload arrival might race to be "the one
  // that knows enough to place the window". Gate placement on both being
  // ready and let whichever fires last actually run it.
  function tryPlace() {
    if (placed) return
    if (!imgPath) return
    var sw = (typeof win !== "undefined" && win && win.screen) ? win.screen.width  : 0
    var sh = (typeof win !== "undefined" && win && win.screen) ? win.screen.height : 0
    if (sw <= 0 || sh <= 0) return
    initPlacement(sw, sh)
  }

  onPayloadChanged: tryPlace()

  // True during drag/resize so the input region expands to the full
  // window — otherwise quick mouse movement off the card cancels the
  // gesture.
  property bool dragging: false

  function shellQuote(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'" }

  Process { id: copyProc }
  function copyImage() {
    if (!root.imgPath) return
    copyProc.command = ["bash", "-lc",
      "wl-copy --type image/png < " + shellQuote(root.imgPath)]
    copyProc.startDetached()
  }

  PanelWindow {
    id: win
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    screen: Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: true

    WlrLayershell.namespace: "omarchy-screen-toolkit-pin"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    mask: Region { item: root.dragging ? maskAll : pinCard }
    Item { id: maskAll; anchors.fill: parent }

    Component.onCompleted: root.tryPlace()

    Rectangle {
      id: pinCard
      x: root.curX
      y: root.curY
      width: root.curW
      height: root.curH
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
      color: "black"
      border.color: cardHover.containsMouse ? Color.accent : Qt.rgba(1, 1, 1, 0.18)
      border.width: 1
      clip: true

      Behavior on border.color { ColorAnimation { duration: 140 } }

      Image {
        anchors.fill: parent
        source: root.imgPath ? "file://" + root.imgPath : ""
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: true
      }

      MouseArea {
        id: cardHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property point startPt: Qt.point(0, 0)
        property int startX: 0
        property int startY: 0

        onPressed: function(mouse) {
          root.dragging = true
          startPt = mapToItem(null, mouse.x, mouse.y)
          startX = root.curX
          startY = root.curY
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var p = mapToItem(null, mouse.x, mouse.y)
          var dx = p.x - startPt.x
          var dy = p.y - startPt.y
          var sw = win.screen ? win.screen.width : 9999
          var sh = win.screen ? win.screen.height : 9999
          root.curX = Math.max(-(root.curW - 60), Math.min(sw - 60, startX + dx))
          root.curY = Math.max(0, Math.min(sh - 40, startY + dy))
        }
        onReleased: root.dragging = false
      }

      // Hover-only control strip: copy + close. Anything more
      // sophisticated (fill mode swap, opacity slider) is left for a
      // later pass.
      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10
        width: stripRow.implicitWidth + 16
        height: 30
        radius: 15
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: cardHover.containsMouse ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        z: 3

        Row {
          id: stripRow
          anchors.centerIn: parent
          spacing: 6

          Rectangle {
            width: 24; height: 24; radius: 12
            anchors.verticalCenter: parent.verticalCenter
            color: copyHover.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent"
            Text {
              anchors.centerIn: parent
              text: ""
              color: "white"
              font.pixelSize: 12
            }
            MouseArea {
              id: copyHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyImage()
            }
          }

          Rectangle {
            width: 24; height: 24; radius: 12
            anchors.verticalCenter: parent.verticalCenter
            color: closeHover.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.45) : "transparent"
            Text {
              anchors.centerIn: parent
              text: ""
              color: "white"
              font.pixelSize: 12
            }
            MouseArea {
              id: closeHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.closeRequested()
            }
          }
        }
      }

      // Single bottom-right resize handle. A single handle keeps the
      // drag/resize hit-test simple — the rest of the card stays a pure
      // drag target.
      MouseArea {
        width: 22; height: 22
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeFDiagCursor
        z: 10

        property point startPt: Qt.point(0, 0)
        property int startW: 0
        property int startH: 0

        onPressed: function(mouse) {
          root.dragging = true
          startPt = mapToItem(null, mouse.x, mouse.y)
          startW = root.curW
          startH = root.curH
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var p = mapToItem(null, mouse.x, mouse.y)
          root.curW = Math.max(120, startW + (p.x - startPt.x))
          root.curH = Math.max(80, startH + (p.y - startPt.y))
        }
        onReleased: root.dragging = false

        Rectangle {
          anchors.centerIn: parent
          width: 8; height: 8; radius: 2
          color: Qt.rgba(1, 1, 1, 0.7)
          opacity: parent.containsMouse || parent.pressed ? 1.0 : 0.35
          Behavior on opacity { NumberAnimation { duration: 140 } }
        }
      }
    }
  }
}
