import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Webcam mirror — a small floating "selfie" window with a flip toggle
// and an aspect toggle (square / 16:9). Mounted as a singleton by
// Overlay.qml. Closing it asks Overlay.qml to drop the slot.
//
// We intentionally keep this UI minimal compared to Noctalia's version:
// no countdown screenshot/record from inside the mirror (the bar widget
// already has a Record tool), no resize handles. The mirror is just a
// mirror.
Item {
  id: root

  signal closeRequested()

  property bool isFlipped: true
  property bool isSquare: true
  property int cameraIndex: 0

  // Floating frame geometry. Defaults to a small square parked in the
  // lower-right; the user can grab and drag.
  property int curW: 280
  property int curH: 280
  property int curX: -1
  property int curY: -1

  property bool dragging: false

  function applyAspect() {
    curH = isSquare ? curW : Math.max(120, Math.round(curW * 9 / 16))
    var sw = win.screen ? win.screen.width : 1920
    var sh = win.screen ? win.screen.height : 1080
    curX = Math.max(0, Math.min(sw - curW, curX))
    curY = Math.max(0, Math.min(sh - curH, curY))
  }

  PanelWindow {
    id: win
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    screen: Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: true

    WlrLayershell.namespace: "omarchy-screen-toolkit-mirror"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Only the camera card receives input; clicks elsewhere fall through
    // to whatever app is below. The mask grows during a drag so quick
    // mouse moves don't lose the press.
    mask: Region { item: root.dragging ? maskAll : cameraCard }
    Item { id: maskAll; anchors.fill: parent }

    Component.onCompleted: {
      if (root.curX < 0 && win.screen) {
        root.curX = Math.max(0, win.screen.width - root.curW - 24)
        root.curY = Math.max(0, Math.round((win.screen.height - root.curH) / 2))
      }
    }

    MediaDevices { id: mediaDevices }

    Rectangle {
      id: cameraCard
      x: root.curX
      y: root.curY
      width: root.curW
      height: root.curH
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 10
      color: "black"
      clip: true
      border.color: cardHover.containsMouse ? Color.accent : Qt.rgba(1, 1, 1, 0.18)
      border.width: 1

      Behavior on border.color { ColorAnimation { duration: 140 } }

      // Wrap the QtMultimedia bits in a Loader so we can decisively
      // tear down the Camera when the user closes the overlay —
      // otherwise the device handle lingers and a quick re-open can
      // collide with the still-active session.
      Loader {
        id: cameraLoader
        anchors.fill: parent
        active: true
        sourceComponent: Component {
          Item {
            anchors.fill: parent
            CaptureSession {
              camera: Camera {
                active: true
                cameraDevice: {
                  var inputs = mediaDevices.videoInputs
                  if (inputs.length === 0) return mediaDevices.defaultVideoInput
                  return inputs[root.cameraIndex % Math.max(1, inputs.length)]
                }
              }
              videoOutput: videoOut
            }
            VideoOutput {
              id: videoOut
              anchors.fill: parent
              fillMode: VideoOutput.PreserveAspectCrop
              // Mirror horizontally by default — selfie-style cameras
              // read more naturally that way.
              transform: Scale {
                origin.x: videoOut.width / 2
                xScale: root.isFlipped ? -1 : 1
              }
            }
          }
        }
      }

      // Empty-state fallback if no camera is attached. Keeps the
      // overlay clearly visible (rather than presenting a black frame
      // that looks like a hung process).
      Column {
        anchors.centerIn: parent
        spacing: 8
        visible: mediaDevices.videoInputs.length === 0
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          color: "white"
          font.pixelSize: 24
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "No camera detected"
          color: "white"
          font.pixelSize: 11
        }
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
          var sw = win.screen ? win.screen.width : 9999
          var sh = win.screen ? win.screen.height : 9999
          root.curX = Math.max(0, Math.min(sw - root.curW, startX + (p.x - startPt.x)))
          root.curY = Math.max(0, Math.min(sh - root.curH, startY + (p.y - startPt.y)))
        }
        onReleased: root.dragging = false
      }

      Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 10
        width: ctrlRow.implicitWidth + 16
        height: 30
        radius: 15
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: cardHover.containsMouse ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        z: 3

        Row {
          id: ctrlRow
          anchors.centerIn: parent
          spacing: 4

          MirrorBtn {
            glyph: root.isSquare ? "" : ""
            onTriggered: { root.isSquare = !root.isSquare; root.applyAspect() }
          }
          MirrorBtn {
            glyph: ""
            active: root.isFlipped
            onTriggered: root.isFlipped = !root.isFlipped
          }
          MirrorBtn {
            glyph: ""
            visible: mediaDevices.videoInputs.length > 1
            onTriggered: root.cameraIndex = (root.cameraIndex + 1) % mediaDevices.videoInputs.length
          }
          MirrorBtn {
            glyph: ""
            danger: true
            onTriggered: root.closeRequested()
          }
        }
      }

      // Bottom-right resize handle — same pattern as Pin.qml. Keeps the
      // aspect ratio (square vs 16:9) the user selected via the toggle.
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

        onPressed: function(mouse) {
          root.dragging = true
          startPt = mapToItem(null, mouse.x, mouse.y)
          startW = root.curW
        }
        onPositionChanged: function(mouse) {
          if (!pressed) return
          var p = mapToItem(null, mouse.x, mouse.y)
          var nw = Math.max(140, startW + (p.x - startPt.x))
          root.curW = nw
          root.curH = root.isSquare ? nw : Math.max(100, Math.round(nw * 9 / 16))
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

  component MirrorBtn: Rectangle {
    id: btn
    property string glyph: ""
    property bool active: false
    property bool danger: false
    signal triggered()

    width: 26
    height: 26
    radius: 13
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: btn.active
      ? Qt.rgba(1, 1, 1, 0.25)
      : (btnMA.containsMouse
          ? (btn.danger ? Qt.rgba(1, 0.2, 0.2, 0.45) : Qt.rgba(1, 1, 1, 0.18))
          : "transparent")

    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: "white"
      font.pixelSize: 12
    }

    MouseArea {
      id: btnMA
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.triggered()
    }
  }
}
