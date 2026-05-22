import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "model-usage"

  property bool popupOpen: false
  property int selectedTabIndex: 0
  property bool refreshFlash: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color border: Color.popups.border
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.085)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.24)
  readonly property string fontFamily: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property var providers: usageMain.enabledProviders
  readonly property var selectedProvider: providers.length > 0 ? providers[Math.min(selectedTabIndex, providers.length - 1)] : null

  function close() { popupOpen = false }

  function triggerRefresh() {
    refreshFlash = true
    refreshFlashTimer.restart()
    usageMain.refreshAll(true)
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function iconSourceForProvider(provider) {
    if (!provider) return ""
    if (provider.providerId === "claude") return Qt.resolvedUrl("assets/claude.svg")
    if (provider.providerId === "codex") return Qt.resolvedUrl("assets/codex.svg")
    return ""
  }

  function usagePercent(provider) {
    if (!provider) return -1
    var values = []
    if (provider.rateLimitPercent >= 0) values.push(provider.rateLimitPercent)
    if (provider.secondaryRateLimitPercent >= 0) values.push(provider.secondaryRateLimitPercent)
    if (values.length === 0) return -1
    return Math.max.apply(Math, values)
  }

  function formatUsagePercent(provider) {
    var pct = usagePercent(provider)
    return pct < 0 ? "—" : Math.round(pct * 100) + "%"
  }

  function weeklyUsage(provider) {
    if (!provider) return ({ percent: -1, resetAt: "", label: "" })
    if (String(provider.rateLimitLabel || "").toLowerCase().indexOf("week") >= 0)
      return { percent: provider.rateLimitPercent, resetAt: provider.rateLimitResetAt, label: provider.rateLimitLabel }
    if (String(provider.secondaryRateLimitLabel || "").toLowerCase().indexOf("week") >= 0)
      return { percent: provider.secondaryRateLimitPercent, resetAt: provider.secondaryRateLimitResetAt, label: provider.secondaryRateLimitLabel }
    return ({ percent: -1, resetAt: "", label: "" })
  }

  function paceInfo(provider) {
    var weekly = weeklyUsage(provider)
    if (weekly.percent < 0 || !weekly.resetAt) return ({ text: "", detail: "", deficit: false })
    var reset = new Date(weekly.resetAt).getTime()
    var now = Date.now()
    var period = 7 * 24 * 60 * 60 * 1000
    var remaining = reset - now
    if (remaining <= 0 || remaining > period) return ({ text: "", detail: "", deficit: false })
    var elapsed = period - remaining
    var expected = root.clamp(elapsed / period, 0, 1)
    var used = root.clamp(weekly.percent, 0, 1)
    var diff = used - expected
    var abs = Math.abs(diff)
    var label = abs <= 0.02 ? "On pace" : (diff > 0 ? Math.round(abs * 100) + "% in deficit" : Math.round(abs * 100) + "% in reserve")
    var projection = "Lasts until reset"
    if (used > 0 && elapsed > 0) {
      var eta = elapsed / used * (1 - used)
      if (eta < remaining) projection = "Runs out in " + provider.formatResetTime(new Date(now + eta).toISOString())
    }
    return ({ text: label, detail: "Expected " + Math.round(expected * 100) + "% used · " + projection, deficit: diff > 0 && abs > 0.02 })
  }

  function tooltipText() {
    if (providers.length === 0) return "Model Usage"
    var lines = ["Model Usage"]
    for (var i = 0; i < providers.length; i++) {
      var provider = providers[i]
      var line = provider.providerName + ": " + formatUsagePercent(provider) + " used"
      var pace = paceInfo(provider)
      if (pace.text !== "") line += " · " + pace.text
      if (provider.syncEnabled && provider.syncDeviceCount > 1) line += " · " + provider.syncDeviceCount + " devices"
      lines.push(line)
    }
    return lines.join("\n")
  }

  function syncSummary(provider) {
    if (usageMain.syncStatusText !== "") return usageMain.syncStatusText
    if (!provider || !provider.syncEnabled) return ""
    var count = Number(provider.syncDeviceCount || 0)
    if (count <= 0) return "Synced usage"
    return "Synced from " + count + " device" + (count === 1 ? "" : "s")
  }

  function selectTab(index) {
    if (providers.length === 0) {
      selectedTabIndex = 0
      return
    }
    selectedTabIndex = ((index % providers.length) + providers.length) % providers.length
  }

  function handleChipPress(index, button, target) {
    if (root.bar && target) root.bar.hideTooltip(target)
    if (button === Qt.RightButton) {
      root.triggerRefresh()
      return
    }

    var wasOpen = root.popupOpen
    var wasSelected = root.selectedTabIndex === index
    root.selectTab(index)
    if (wasOpen && wasSelected) root.popupOpen = false
    else {
      root.popupOpen = true
      root.triggerRefresh()
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onPopupOpenChanged: {
    if (popupOpen) {
      usageMain.refreshAll()
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  onProvidersChanged: if (selectedTabIndex >= providers.length) selectTab(0)

  Main {
    id: usageMain
    settings: root.settings
  }

  Timer {
    id: refreshFlashTimer
    interval: 900
    repeat: false
    onTriggered: root.refreshFlash = false
  }

  IpcHandler {
    target: "model-usage"
    function open(): string { root.popupOpen = true; return "ok" }
    function close(): string { root.popupOpen = false; return "ok" }
    function toggle(): string { root.popupOpen = !root.popupOpen; return "ok" }
    function refresh(): string { root.triggerRefresh(); return "ok" }
  }

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: barRow.implicitWidth + 10
    implicitHeight: root.bar ? root.bar.barSize : 26

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: 8

      Repeater {
        model: providers

        Item {
          id: chip
          required property var modelData
          required property int index
          readonly property real pct: root.usagePercent(modelData)
          readonly property bool tooltipHovered: mouseArea.containsMouse

          width: chipRow.implicitWidth
          height: root.bar ? root.bar.barSize : 26

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 4

            Image {
              id: chipIcon
              source: root.iconSourceForProvider(chip.modelData)
              width: 13
              height: 13
              sourceSize.width: 13
              sourceSize.height: 13
              fillMode: Image.PreserveAspectFit
              anchors.verticalCenter: parent.verticalCenter
              opacity: chip.pct >= 0.9 ? 0.75 : 1
            }

            Text {
              text: root.formatUsagePercent(chip.modelData)
              color: chip.pct >= 0.9 ? urgent : foreground
              font.family: fontFamily
              font.pixelSize: 10
              font.bold: chip.pct >= 0.9
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          property var registeredBar: null

          function triggerPress(button) {
            root.handleChipPress(chip.index, button, chip)
          }

          function syncClickRegistration() {
            if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)
            registeredBar = root.bar
            if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(chip)
          }

          Component.onCompleted: syncClickRegistration()
          Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)

          Connections {
            target: root
            function onBarChanged() { chip.syncClickRegistration() }
          }

          MouseArea {
            id: mouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: if (root.bar) root.bar.showTooltip(chip, root.tooltipText())
            onExited: if (root.bar) root.bar.hideTooltip(chip)
            onClicked: function(mouse) { root.handleChipPress(chip.index, mouse.button, chip) }
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.selectTab(root.selectedTabIndex + dx)
        if (dy !== 0) flick.contentY = root.clamp(flick.contentY + dy * 56, 0, Math.max(0, flick.contentHeight - flick.height))
      }
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.triggerRefresh()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Header { provider: root.selectedProvider }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        Item {
          visible: providers.length > 1
          Layout.fillWidth: true
          Layout.preferredHeight: 30

          Row {
            anchors.fill: parent
            spacing: 6

            Repeater {
              model: providers

              Button {
                required property var modelData
                required property int index
                width: (parent.width - parent.spacing * Math.max(0, providers.length - 1)) / Math.max(1, providers.length)
                height: parent.height
                text: modelData.providerName
                foreground: root.foreground
                tooltipBackground: root.background
                tooltipForeground: root.foreground
                fontFamily: root.fontFamily
                fontSize: 11
                horizontalPadding: 8
                verticalPadding: 5
                active: index === root.selectedTabIndex
                hasCursor: index === root.selectedTabIndex
                onClicked: {
                  root.selectTab(index)
                  keyCatcher.forceActiveFocus()
                }
              }
            }
          }
        }

        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          ColumnLayout {
            id: contentColumn
            width: flick.width
            spacing: 10

            Text {
              visible: !root.selectedProvider
              Layout.fillWidth: true
              Layout.topMargin: 24
              text: "No providers enabled. Enable Claude or Codex in shell.json."
              color: dim
              font.family: fontFamily
              font.pixelSize: 11
              horizontalAlignment: Text.AlignHCenter
            }

            StatusCard { provider: root.selectedProvider }
            RateLimitCard { provider: root.selectedProvider }
            TodayCard { provider: root.selectedProvider }
            WeekCard { provider: root.selectedProvider }
            AllTimeCard { provider: root.selectedProvider }

            Text {
              Layout.fillWidth: true
              text: {
                var sync = root.syncSummary(root.selectedProvider)
                return (sync !== "" ? sync + " · " : "") + "←/→ switch tabs · j/k scroll · r refresh · esc close"
              }
              color: dim
              font.family: fontFamily
              font.pixelSize: 10
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }

  component Header: RowLayout {
    property var provider: null
    visible: !!provider
    Layout.fillWidth: true
    spacing: 8

    Image {
      source: root.iconSourceForProvider(provider)
      Layout.preferredWidth: 16
      Layout.preferredHeight: 16
      sourceSize.width: 16
      sourceSize.height: 16
      fillMode: Image.PreserveAspectFit
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      text: provider ? provider.providerName + " Usage" : ""
      color: foreground
      font.family: fontFamily
      font.pixelSize: 15
      font.bold: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      visible: provider && String(provider.tierLabel || "") !== ""
      text: provider ? provider.tierLabel : ""
      foreground: root.foreground
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 6
      verticalPadding: 3
      active: true
      enabled: false
    }

    Button {
      text: (root.refreshFlash || usageMain.refreshing) ? "Refreshing…" : "Refresh"
      foreground: root.foreground
      tooltipText: (root.refreshFlash || usageMain.refreshing) ? "Refreshing usage…" : "Refresh usage"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      active: root.refreshFlash || usageMain.refreshing
      onClicked: {
        root.triggerRefresh()
        keyCatcher.forceActiveFocus()
      }
    }
  }

  component StatusCard: SectionCard {
    property var provider: null
    visible: !!provider && String(provider.usageStatusText || "") !== ""
    titleColor: urgent
    title: provider ? provider.usageStatusText : ""
    subtitle: provider ? provider.authHelpText : ""
  }

  component RateLimitCard: SectionCard {
    id: rateLimitCard
    property var provider: null
    visible: !!provider && ((provider.rateLimitPercent >= 0) || (provider.secondaryRateLimitPercent >= 0))
    title: "Rate Limit Usage"

    ColumnLayout {
      width: parent.width
      spacing: 10
      ProgressRow {
        visible: provider && provider.rateLimitPercent >= 0
        label: provider ? provider.rateLimitLabel : ""
        value: provider ? provider.rateLimitPercent : -1
        resetText: provider && provider.rateLimitResetAt ? "Resets in " + provider.formatResetTime(provider.rateLimitResetAt) : ""
      }
      ProgressRow {
        visible: provider && provider.secondaryRateLimitPercent >= 0
        label: provider ? provider.secondaryRateLimitLabel : ""
        value: provider ? provider.secondaryRateLimitPercent : -1
        resetText: provider && provider.secondaryRateLimitResetAt ? "Resets in " + provider.formatResetTime(provider.secondaryRateLimitResetAt) : ""
      }
      PaceRow { provider: rateLimitCard.provider }
    }
  }

  component TodayCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.ready && provider.hasLocalStats
    title: "Today"

    ColumnLayout {
      width: parent.width
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        spacing: 20
        StatBlock { value: provider ? String(provider.todayPrompts || 0) : "0"; label: "prompts" }
        StatBlock { value: provider ? String(provider.todaySessions || 0) : "0"; label: "sessions" }
      }
      Repeater {
        model: {
          var toks = provider ? (provider.todayTokensByModel || {}) : {}
          var out = []
          for (var k in toks) out.push({ modelId: k, count: toks[k] })
          return out
        }
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          Text { text: usageMain.friendlyModelName(modelData.modelId); color: dim; font.family: fontFamily; font.pixelSize: 11 }
          Item { Layout.fillWidth: true }
          Text { text: usageMain.formatTokenCount(modelData.count) + " tokens"; color: foreground; font.family: fontFamily; font.pixelSize: 11; font.bold: true }
        }
      }
    }
  }

  component WeekCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.recentDays && provider.recentDays.length > 0
    title: "Last 7 Days"

    ColumnLayout {
      width: parent.width
      spacing: 6
      Repeater {
        model: provider ? provider.recentDays : []
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 8
          readonly property real count: modelData ? Number(modelData.messageCount || 0) : 0
          readonly property real maxCount: {
            var days = provider ? (provider.recentDays || []) : []
            var max = 1
            for (var i = 0; i < days.length; i++) if (Number(days[i].messageCount || 0) > max) max = Number(days[i].messageCount || 0)
            return max
          }
          Text {
            text: {
              var d = modelData.date
              if (!d) return ""
              var dt = new Date(d + "T00:00:00")
              var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
              return names[dt.getDay()] + " " + String(dt.getMonth() + 1).padStart(2, "0") + "/" + String(dt.getDate()).padStart(2, "0")
            }
            color: dim
            font.family: fontFamily
            font.pixelSize: 10
            Layout.preferredWidth: 48
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 10
            color: track
            radius: Math.max(1, Style.cornerRadius / 3)
            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * (count / maxCount)
              color: root.alpha(foreground, 0.78)
              radius: Math.max(1, Style.cornerRadius / 3)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
          Text {
            text: usageMain.formatTokenCount(count)
            color: foreground
            font.family: fontFamily
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 48
          }
        }
      }
    }
  }

  component AllTimeCard: SectionCard {
    property var provider: null
    visible: {
      var usage = provider ? (provider.modelUsage || {}) : {}
      return Object.keys(usage).length > 0
    }
    title: "All-Time"

    ColumnLayout {
      width: parent.width
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        spacing: 20
        StatBlock { value: provider ? usageMain.formatTokenCount(provider.totalPrompts || 0) : "0"; label: "messages" }
        StatBlock { value: provider ? String(provider.totalSessions || 0) : "0"; label: "sessions" }
      }
      PanelSeparator { Layout.fillWidth: true; foreground: root.foreground; strength: 0.18 }
      Repeater {
        model: {
          var usage = provider ? (provider.modelUsage || {}) : {}
          var out = []
          for (var k in usage) out.push({ modelId: k, data: usage[k] })
          return out
        }
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 4
          Text { text: usageMain.friendlyModelName(modelData.modelId); color: foreground; font.family: fontFamily; font.pixelSize: 11; font.bold: true }
          GridLayout {
            Layout.leftMargin: 10
            columns: 2
            columnSpacing: 18
            rowSpacing: 2
            DetailPair { name: "Input"; value: usageMain.formatTokenCount(modelData.data.inputTokens || 0) }
            DetailPair { name: "Output"; value: usageMain.formatTokenCount(modelData.data.outputTokens || 0) }
            DetailPair { name: "Cache Read"; value: usageMain.formatTokenCount(modelData.data.cacheReadInputTokens || 0) }
            DetailPair { name: "Cache Write"; value: usageMain.formatTokenCount(modelData.data.cacheCreationInputTokens || 0) }
          }
        }
      }
    }
  }

  component SectionCard: Rectangle {
    id: section
    property string title: ""
    property string subtitle: ""
    property color titleColor: foreground
    default property alias content: body.data

    Layout.fillWidth: true
    color: card
    border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
    border.width: 1
    radius: Style.cornerRadius
    implicitHeight: body.implicitHeight + 22

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      spacing: 8

      PanelSectionHeader {
        visible: section.title !== ""
        Layout.fillWidth: true
        text: section.title
        foreground: section.titleColor
        fontFamily: root.fontFamily
        fontSize: 11
      }
      Text {
        visible: section.subtitle !== ""
        Layout.fillWidth: true
        text: section.subtitle
        color: dim
        font.family: fontFamily
        font.pixelSize: 10
        wrapMode: Text.WordWrap
      }
    }
  }

  component PaceRow: ColumnLayout {
    property var provider: null
    readonly property var pace: root.paceInfo(provider)

    visible: pace.text !== ""
    spacing: 2
    Layout.fillWidth: true

    RowLayout {
      Layout.fillWidth: true
      Text {
        text: "Pace"
        color: dim
        font.family: fontFamily
        font.pixelSize: 10
      }
      Item { Layout.fillWidth: true }
      Text {
        text: pace.text
        color: pace.deficit ? urgent : foreground
        font.family: fontFamily
        font.pixelSize: 10
        font.bold: true
      }
    }

    Text {
      Layout.fillWidth: true
      text: pace.detail
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignRight
    }
  }

  component ProgressRow: ColumnLayout {
    property string label: ""
    property real value: -1
    property string resetText: ""
    spacing: 5
    Layout.fillWidth: true

    RowLayout {
      Layout.fillWidth: true
      Text { text: label; color: dim; font.family: fontFamily; font.pixelSize: 11 }
      Item { Layout.fillWidth: true }
      Text {
        text: value < 0 ? "—" : Math.round(value * 100) + "%"
        color: value >= 0.9 ? urgent : foreground
        font.family: fontFamily
        font.pixelSize: 11
        font.bold: true
      }
    }
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 8
      color: track
      radius: Math.max(1, Style.cornerRadius / 3)
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * root.clamp(value, 0, 1)
        color: value >= 0.9 ? root.alpha(urgent, 0.72) : root.alpha(foreground, 0.78)
        radius: Math.max(1, Style.cornerRadius / 3)
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
    }
    Text { visible: resetText !== ""; text: resetText; color: dim; font.family: fontFamily; font.pixelSize: 10 }
  }

  component StatBlock: ColumnLayout {
    property string value: "0"
    property string label: ""
    spacing: 2
    Text { text: value; color: foreground; font.family: fontFamily; font.pixelSize: 18; font.bold: true }
    Text { text: label; color: dim; font.family: fontFamily; font.pixelSize: 10 }
  }

  component DetailPair: RowLayout {
    property string name: ""
    property string value: ""
    Text { text: name; color: dim; font.family: fontFamily; font.pixelSize: 10; Layout.preferredWidth: 76 }
    Text { text: value; color: foreground; font.family: fontFamily; font.pixelSize: 10; font.bold: true }
  }
}
