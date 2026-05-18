import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Fullscreen transparent overlay that lets the user drag a measurement
// line and read off pixel distance. ESC closes; click-drag draws a new
// measurement; click "pin" to leave it on screen and start another.
// Mounted as a singleton by Overlay.qml.
Item {
  id: root

  signal closeRequested()

  // Eight rotating colors for pinned lines so multiple measurements stay
  // visually distinguishable.
  readonly property var palette: [
    "#A78BFA", "#34D399", "#F87171", "#FBBF24",
    "#60A5FA", "#F472B6", "#A3E635", "#FB923C"
  ]
  function colorForIndex(i) { return palette[i % palette.length] }

  // Bookkeeping for the currently-rubber-banded line and the pinned list.
  // `current` is the finished line waiting for an action (copy, pin,
  // discard); the rubber-band live during the drag lives in x1/y1/x2/y2.
  property bool measuring: false
  property var current: null
  property var pinned: []

  property real x1: 0
  property real y1: 0
  property real x2: 0
  property real y2: 0

  readonly property real curW: current ? Math.abs(current.x2 - current.x1) : 0
  readonly property real curH: current ? Math.abs(current.y2 - current.y1) : 0
  readonly property real curDist: Math.round(Math.sqrt(curW * curW + curH * curH))

  function doPin() {
    if (!current) return
    var arr = pinned.slice()
    arr.push({
      x1: current.x1, y1: current.y1,
      x2: current.x2, y2: current.y2,
      color: colorForIndex(arr.length)
    })
    pinned = arr
    current = null
  }

  function removePinned(i) {
    var arr = pinned.slice()
    arr.splice(i, 1)
    // Renumber colors so they stay contiguous; otherwise the palette
    // rotation looks accidental.
    for (var j = 0; j < arr.length; j++)
      arr[j] = { x1: arr[j].x1, y1: arr[j].y1, x2: arr[j].x2, y2: arr[j].y2, color: colorForIndex(j) }
    pinned = arr
  }

  function clearAll() { pinned = [] }

  function copyResult(text) {
    copyProc.command = ["bash", "-lc", "printf %s " + shellQuote(text) + " | wl-copy"]
    copyProc.startDetached()
  }
  function shellQuote(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'" }

  Process { id: copyProc }

  onMeasuringChanged: canvas.requestPaint()
  onCurrentChanged:   canvas.requestPaint()
  onPinnedChanged:    canvas.requestPaint()

  PanelWindow {
    id: win
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    screen: Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    visible: true

    WlrLayershell.namespace: "omarchy-screen-toolkit-measure"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive keyboard focus so ESC reliably routes here instead of
    // whatever app was focused beforehand.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.closeRequested()
          event.accepted = true
        }
      }
      Component.onCompleted: Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)

      // First-use hint, hidden once the user has done anything.
      Column {
        anchors.centerIn: parent
        spacing: 8
        visible: !root.measuring && !root.current && root.pinned.length === 0

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          color: "white"
          font.pixelSize: 36
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Click and drag to measure"
          color: "white"
          font.bold: true
          font.pixelSize: 18
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Hold Alt to constrain · Esc to dismiss"
          color: Qt.rgba(1, 1, 1, 0.5)
          font.pixelSize: 11
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        hoverEnabled: true
        onPositionChanged: function(mouse) {
          if (!root.measuring) return
          if (mouse.modifiers & Qt.AltModifier) {
            // Snap to horizontal or vertical, whichever has the larger
            // delta. Matches the constraint behavior most measure tools
            // ship with.
            var dx = Math.abs(mouse.x - root.x1)
            var dy = Math.abs(mouse.y - root.y1)
            if (dx > dy) { root.x2 = mouse.x; root.y2 = root.y1 }
            else         { root.x2 = root.x1; root.y2 = mouse.y }
          } else {
            root.x2 = mouse.x; root.y2 = mouse.y
          }
          canvas.requestPaint()
        }
        onPressed: function(mouse) {
          root.measuring = true
          root.current = null
          root.x1 = mouse.x; root.y1 = mouse.y
          root.x2 = mouse.x; root.y2 = mouse.y
        }
        onReleased: function(mouse) {
          if (mouse.modifiers & Qt.AltModifier) {
            var dx = Math.abs(mouse.x - root.x1)
            var dy = Math.abs(mouse.y - root.y1)
            if (dx > dy) { root.x2 = mouse.x; root.y2 = root.y1 }
            else         { root.x2 = root.x1; root.y2 = mouse.y }
          } else {
            root.x2 = mouse.x; root.y2 = mouse.y
          }
          root.measuring = false
          var dist = Math.sqrt(
            Math.pow(root.x2 - root.x1, 2) +
            Math.pow(root.y2 - root.y1, 2))
          // 4px floor — anything smaller is probably an accidental click.
          if (dist > 4)
            root.current = { x1: root.x1, y1: root.y1, x2: root.x2, y2: root.y2 }
          else
            root.current = null
        }
      }
    }

    Canvas {
      id: canvas
      anchors.fill: parent

      function drawLine(ctx, m, color) {
        var x1 = m.x1, y1 = m.y1, x2 = m.x2, y2 = m.y2
        var w = Math.abs(x2 - x1), h = Math.abs(y2 - y1)

        // Dashed bounding box first — gives the measurement context for
        // its width/height components.
        ctx.save()
        ctx.strokeStyle = "rgba(255,255,255,0.2)"
        ctx.lineWidth = 1
        ctx.setLineDash([4, 4])
        ctx.strokeRect(Math.min(x1, x2), Math.min(y1, y2), w, h)
        ctx.restore()

        // Corner ticks of the bounding box.
        ctx.fillStyle = color
        ;[[x1, y1], [x2, y2], [x1, y2], [x2, y1]].forEach(function(pt) {
          ctx.beginPath(); ctx.arc(pt[0], pt[1], 3, 0, Math.PI * 2); ctx.fill()
        })

        // The actual measurement line + larger endpoint dots.
        ctx.save()
        ctx.strokeStyle = color
        ctx.lineWidth = 2
        ctx.setLineDash([])
        ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
        ctx.restore()
        ctx.fillStyle = color
        ;[[x1, y1], [x2, y2]].forEach(function(pt) {
          ctx.beginPath(); ctx.arc(pt[0], pt[1], 5, 0, Math.PI * 2); ctx.fill()
        })

        if (w > 20) {
          var midX = (Math.min(x1, x2) + Math.max(x1, x2)) / 2
          var ty = Math.min(y1, y2) - 12
          ctx.save()
          ctx.strokeStyle = "rgba(255,255,255,0.5)"
          ctx.lineWidth = 1
          ctx.setLineDash([])
          ctx.beginPath()
          ctx.moveTo(Math.min(x1, x2), ty); ctx.lineTo(Math.max(x1, x2), ty)
          ctx.stroke()
          ctx.restore()
          ctx.fillStyle = "white"
          ctx.font = "bold 11px sans-serif"
          ctx.textAlign = "center"
          ctx.fillText(Math.round(w) + "px", midX, ty - 4)
        }
        if (h > 20) {
          var midY = (Math.min(y1, y2) + Math.max(y1, y2)) / 2
          var tx = Math.min(x1, x2) - 12
          ctx.save()
          ctx.strokeStyle = "rgba(255,255,255,0.5)"
          ctx.lineWidth = 1
          ctx.setLineDash([])
          ctx.beginPath()
          ctx.moveTo(tx, Math.min(y1, y2)); ctx.lineTo(tx, Math.max(y1, y2))
          ctx.stroke()
          ctx.restore()
          ctx.fillStyle = "white"
          ctx.font = "bold 11px sans-serif"
          ctx.textAlign = "center"
          ctx.save()
          ctx.translate(tx - 4, midY); ctx.rotate(-Math.PI / 2)
          ctx.fillText(Math.round(h) + "px", 0, 0)
          ctx.restore()
        }
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        for (var i = 0; i < root.pinned.length; i++)
          drawLine(ctx, root.pinned[i], root.pinned[i].color)
        if (root.measuring)
          drawLine(ctx, { x1: root.x1, y1: root.y1, x2: root.x2, y2: root.y2 }, "#ffffff")
        if (root.current)
          drawLine(ctx, root.current, "#ffffff")
      }
    }

    // Action card for the in-progress measurement.
    Rectangle {
      id: activeCard
      visible: root.current !== null && !root.measuring
      readonly property real ex: root.current ? root.current.x2 : 0
      readonly property real ey: root.current ? root.current.y2 : 0
      readonly property real rawX: ex + 16
      readonly property real rawY: ey + 16
      x: {
        var rx = rawX
        if (rx + width + 8 > win.width) rx = ex - width - 16
        return Math.max(8, rx)
      }
      y: {
        var ry = rawY
        if (ry + height + 8 > win.height) ry = ey - height - 16
        return Math.max(8, ry)
      }
      width: activeRow.implicitWidth + 28
      height: activeRow.implicitHeight + 16
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 10
      color: Color.popups.background
      border.color: "white"
      border.width: 2

      Row {
        id: activeRow
        anchors.centerIn: parent
        spacing: 10

        Column {
          spacing: 2
          anchors.verticalCenter: parent.verticalCenter
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.curDist + " px"
            color: Color.foreground
            font.bold: true
            font.pixelSize: 13
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.curW) + " × " + Math.round(root.curH)
            color: Qt.darker(Color.foreground, 1.4)
            font.pixelSize: 10
          }
        }

        ActionBtn {
          glyph: ""
          onTriggered: root.copyResult(
            root.curDist + "px (" + Math.round(root.curW) + "×" + Math.round(root.curH) + ")")
        }
        ActionBtn { glyph: ""; onTriggered: root.doPin() }
        ActionBtn {
          glyph: ""
          danger: true
          onTriggered: {
            root.current = null
            if (root.pinned.length === 0) root.closeRequested()
          }
        }
      }
    }

    // Cards for each pinned measurement.
    Repeater {
      model: root.pinned
      delegate: Rectangle {
        required property var modelData
        required property int index
        readonly property real mw: Math.abs(modelData.x2 - modelData.x1)
        readonly property real mh: Math.abs(modelData.y2 - modelData.y1)
        readonly property real mdist: Math.round(Math.sqrt(mw * mw + mh * mh))

        x: {
          var rx = modelData.x2 + 16
          if (rx + width + 8 > win.width) rx = modelData.x2 - width - 16
          return Math.max(8, rx)
        }
        y: {
          var ry = modelData.y2 + 16
          if (ry + height + 8 > win.height) ry = modelData.y2 - height - 16
          return Math.max(8, ry)
        }
        width: pinnedRow.implicitWidth + 28
        height: pinnedRow.implicitHeight + 14
        radius: Style.cornerRadius > 0 ? Style.cornerRadius : 10
        color: Color.popups.background
        border.color: modelData.color
        border.width: 2

        Row {
          id: pinnedRow
          anchors.centerIn: parent
          spacing: 8

          Rectangle {
            width: 10; height: 10; radius: 5
            color: modelData.color
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: mdist + " px"
              color: Color.foreground
              font.bold: true
              font.pixelSize: 13
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: Math.round(mw) + " × " + Math.round(mh)
              color: Qt.darker(Color.foreground, 1.4)
              font.pixelSize: 10
            }
          }

          ActionBtn {
            glyph: ""
            small: true
            onTriggered: root.copyResult(
              mdist + "px (" + Math.round(mw) + "×" + Math.round(mh) + ")")
          }
          ActionBtn {
            glyph: ""
            small: true
            danger: true
            onTriggered: root.removePinned(index)
          }
        }
      }
    }

    // Floating "clear all" button — only shows once there's something
    // pinned worth clearing.
    Rectangle {
      visible: root.pinned.length >= 1
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottomMargin: 32
      width: clearRow.implicitWidth + 28
      height: 36
      radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
      color: clearMA.containsMouse ? Qt.rgba(0.9, 0.3, 0.3, 0.15) : Color.popups.background
      border.color: "#a55555"
      border.width: 1

      Row {
        id: clearRow
        anchors.centerIn: parent
        spacing: 6
        Text { text: ""; color: "#a55555"; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Text { text: "Clear all"; color: "#a55555"; font.bold: true; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
      }
      MouseArea {
        id: clearMA
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clearAll()
      }
    }
  }

  // Small icon button used in the action cards. Inline-defined so the
  // measure overlay stays self-contained — no shared component file.
  component ActionBtn: Rectangle {
    id: btn
    property string glyph: ""
    property bool danger: false
    property bool small: false
    signal triggered()

    width: small ? 26 : 28
    height: small ? 26 : 28
    radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    color: btnMA.containsMouse
      ? (danger ? Qt.rgba(0.9, 0.3, 0.3, 0.18) : Color.accent)
      : Qt.rgba(0.5, 0.5, 0.5, 0.18)

    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: btn.danger && btnMA.containsMouse
        ? "#ff6b6b"
        : (btnMA.containsMouse ? Color.popups.background : Color.foreground)
      font.pixelSize: small ? 11 : 12
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
