import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "next-meeting"

  Main {
    id: main
    settings: root.settings
  }

  visible: main.text !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: main.text
    tooltipText: main.tooltipText
    pressable: !main.isLoading
    dimmed: main.isLoading

    onPressed: function(b) {
      if (main.isLoading) return
      if (b === Qt.RightButton) {
        main.refresh(true)
        return
      }
      if (b === Qt.LeftButton && main.hasMeeting) main.openNextEvent()
    }
  }
}
