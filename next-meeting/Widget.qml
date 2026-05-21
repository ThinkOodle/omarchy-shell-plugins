import QtQuick
import Quickshell
import qs.Commons

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "next-meeting"
  property var settings: ({})

  implicitWidth: pill.implicitWidth
  implicitHeight: bar ? bar.barSize : 26

  Main {
    id: main
    settings: root.settings
  }

  Rectangle {
    id: pill
    anchors.fill: parent
    implicitWidth: label.implicitWidth + 12
    radius: 6
    color: "transparent"

    Text {
      id: label
      anchors.centerIn: parent
      text: main.text
      color: main.stateClass === "off" ? Qt.darker(bar ? bar.foreground : Color.foreground, 1.35) : (bar ? bar.foreground : Color.foreground)
      font.family: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"
      font.pixelSize: 12
      elide: Text.ElideRight
      width: Math.min(420, implicitWidth)
      visible: text !== ""
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: main.isLoading ? Qt.BusyCursor : (main.hasMeeting ? Qt.PointingHandCursor : Qt.ArrowCursor)
      enabled: main.text !== ""

      function syncTooltip() {
        if (!root.bar) return
        if (containsMouse && main.tooltipText !== "") root.bar.showTooltip(pill, main.tooltipText)
        else root.bar.hideTooltip(pill)
      }

      onEntered: syncTooltip()
      onExited: if (root.bar) root.bar.hideTooltip(pill)

      onClicked: function(mouse) {
        if (root.bar) root.bar.hideTooltip(pill)
        if (main.isLoading) return
        // Right click on widget to manually fetch new events
        if (mouse.button === Qt.RightButton) {
          main.refresh(true)
          return
        }
        if (!main.hasMeeting) return
        main.openNextEvent()
      }

      Connections {
        target: main
        function onTooltipTextChanged() { mouseArea.syncTooltip() }
      }
    }
  }
}
