import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "next-meeting"

  property bool popupOpen: false
  property bool settingsMode: false
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property bool refreshFlash: false
  property int selectedEventIndex: 0
  property int selectedDayOffset: 0
  property var availableCalendars: []
  property bool calendarsLoading: false
  property string calendarsStatusText: ""
  property var now: new Date()

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color border: Color.popups.border
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.085)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property string fontFamily: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"
  readonly property int maxDayOffset: Math.max(0, main.lookaheadDays - 1)
  readonly property string selectedDateString: dateStringForOffset(main.today, selectedDayOffset)
  readonly property string selectedDateLabel: labelForDate(selectedDateString, selectedDayOffset)
  readonly property var dayEvents: eventsForDate(selectedDateString)
  readonly property string currentDateString: dateString(now)
  readonly property int currentTimeMinutes: minutesForDate(now)
  readonly property string currentTimeLabel: clockLabel(now)
  readonly property bool selectedDayIsToday: selectedDateString === currentDateString
  readonly property int nowMarkerIndex: computeNowMarkerIndex()
  readonly property var calendarOptions: calendarOptionsWithSelected(availableCalendars, draftValue("calendars", []))
  readonly property string listCalendarsScriptPath: pathFromUrl(Qt.resolvedUrl("scripts/list-calendars.sh"))

  function close() {
    popupOpen = false
    settingsMode = false
  }

  function showAgenda() {
    settingsMode = false
    settingsStatusText = ""
    popupOpen = true
    ensureSelection()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function toggleAgenda() {
    if (popupOpen && !settingsMode) close()
    else showAgenda()
  }

  function triggerRefresh() {
    refreshFlash = true
    refreshFlashTimer.restart()
    main.refresh(true)
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function pathFromUrl(url) {
    var value = String(url)
    if (value.indexOf("file://") === 0) return decodeURIComponent(value.substring(7))
    return value
  }

  function parseIsoDate(value) {
    var parts = String(value || "").split("-")
    if (parts.length >= 3) {
      var y = Number(parts[0])
      var m = Number(parts[1])
      var d = Number(parts[2])
      if (isFinite(y) && isFinite(m) && isFinite(d)) return new Date(y, m - 1, d)
    }
    return new Date()
  }

  function dateString(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" + String(date.getDate()).padStart(2, "0")
  }

  function dateStringForOffset(today, offset) {
    var date = parseIsoDate(today)
    date.setDate(date.getDate() + Number(offset || 0))
    return dateString(date)
  }

  function minutesForDate(date) {
    if (!date) return 0
    return date.getHours() * 60 + date.getMinutes()
  }

  function timeToMinutes(value) {
    var parts = String(value || "").split(":")
    if (parts.length < 2) return -1
    var hours = Number(parts[0])
    var minutes = Number(parts[1])
    if (!isFinite(hours) || !isFinite(minutes)) return -1
    return hours * 60 + minutes
  }

  function clockLabel(date) {
    var hours24 = date.getHours()
    var minutes = String(date.getMinutes()).padStart(2, "0")
    var suffix = hours24 >= 12 ? "pm" : "am"
    var hours = hours24 % 12
    if (hours === 0) hours = 12
    return hours + ":" + minutes + suffix
  }

  function computeNowMarkerIndex() {
    if (!selectedDayIsToday) return -1
    var events = dayEvents || []
    for (var i = 0; i < events.length; i++) {
      var event = events[i] || ({})
      if (event.allDay === true || !event.startTime) continue
      var start = timeToMinutes(event.startTime)
      if (start < 0) continue
      var end = timeToMinutes(event.endTime)
      if (end < 0) end = start
      if (String(event.endDate || event.date || "") !== String(event.date || "")) end = 24 * 60
      if (end >= currentTimeMinutes || start >= currentTimeMinutes) return i
    }
    return events.length
  }

  function labelForDate(dateString, offset) {
    if (offset === 0 && main.todayLabel !== "") return main.todayLabel
    var date = parseIsoDate(dateString)
    if (offset === 0) return Qt.formatDate(date, "dddd, MMMM d")
    if (offset === 1) return "Tomorrow, " + Qt.formatDate(date, "MMMM d")
    return Qt.formatDate(date, "dddd, MMMM d")
  }

  function eventsForDate(dateString) {
    var events = main.events || []
    var out = []
    for (var i = 0; i < events.length; i++) {
      if (String(events[i].date || "") === dateString) out.push(events[i])
    }
    return out
  }

  function cloneObject(value, fallback) {
    if (value === undefined || value === null) return fallback
    try {
      return JSON.parse(JSON.stringify(value))
    } catch (e) {
      return fallback
    }
  }

  function defaultSettings() {
    return {
      refreshIntervalSec: 1800,
      scheduleClearText: "No more meetings today ✅",
      lookaheadDays: 7,
      maxDisplayChars: 42,
      meetOpenMode: "system-browser",
      meetOpenCommand: "",
      calendars: []
    }
  }

  function normalizeCalendars(value) {
    var out = []
    if (value && typeof value.length === "number" && typeof value !== "string") {
      for (var i = 0; i < value.length; i++) {
        var s = String(value[i]).trim()
        if (s !== "") out.push(s)
      }
      return out
    }
    if (typeof value === "string" && value.trim() !== "") {
      var parts = value.split(",")
      for (var j = 0; j < parts.length; j++) {
        var p = parts[j].trim()
        if (p !== "") out.push(p)
      }
    }
    return out
  }

  function calendarsText(value) {
    if (value && typeof value.length === "number" && typeof value !== "string") return value.join(", ")
    return String(value || "")
  }

  function calendarOptionsWithSelected(options, selectedValue) {
    var out = []
    var seen = ({})

    function add(option, fallbackDescription) {
      var value = ""
      var label = ""
      var description = fallbackDescription || ""
      if (typeof option === "string") {
        value = option
        label = option
      } else if (option) {
        value = String(option.value || option.label || "")
        label = String(option.label || option.value || "")
        description = String(option.description || description || "")
      }
      value = String(value || "").trim()
      if (value === "") return
      if (label === "") label = value
      var key = "$" + value
      if (seen[key] === true) return
      seen[key] = true
      out.push({ value: value, label: label, description: description })
    }

    var source = options || []
    for (var i = 0; i < source.length; i++) add(source[i], "")

    var selected = normalizeCalendars(selectedValue)
    for (var j = 0; j < selected.length; j++) add(selected[j], "Configured")
    return out
  }

  function selectedCalendarCount() {
    return normalizeCalendars(draftValue("calendars", [])).length
  }

  function selectedCalendarSummary() {
    var selected = normalizeCalendars(draftValue("calendars", []))
    if (selected.length === 0) return "All calendars"
    if (selected.length === 1) return selected[0]
    return selected.length + " calendars selected"
  }

  function calendarSelected(value) {
    return normalizeCalendars(draftValue("calendars", [])).indexOf(String(value || "")) >= 0
  }

  function toggleDraftCalendar(value) {
    var calendar = String(value || "").trim()
    if (calendar === "") return
    var selected = normalizeCalendars(draftValue("calendars", []))
    var index = selected.indexOf(calendar)
    if (index >= 0) selected.splice(index, 1)
    else selected.push(calendar)
    setDraftValue("calendars", selected)
  }

  function clearDraftCalendars() {
    setDraftValue("calendars", [])
  }

  function applyCalendarOptions(raw) {
    calendarsLoading = false
    var text = String(raw || "").trim()
    if (text === "") {
      availableCalendars = []
      calendarsStatusText = ""
      return
    }

    try {
      var parsed = JSON.parse(text)
      if (!Array.isArray(parsed)) parsed = []
      availableCalendars = calendarOptionsWithSelected(parsed, [])
      calendarsStatusText = ""
    } catch (e) {
      availableCalendars = []
      calendarsStatusText = "Could not read calendar list"
    }
  }

  function loadCalendarOptions(force) {
    if (calendarOptionsProcess.running) return
    if (force !== true && availableCalendars.length > 0) return
    calendarsLoading = true
    calendarsStatusText = ""
    calendarOptionsProcess.command = [listCalendarsScriptPath]
    calendarOptionsProcess.running = true
  }

  function normalizedSettings(source) {
    var defaults = defaultSettings()
    var next = cloneObject(source, {}) || {}

    var refresh = Number(next.refreshIntervalSec === undefined || next.refreshIntervalSec === null ? defaults.refreshIntervalSec : next.refreshIntervalSec)
    next.refreshIntervalSec = Math.round(clamp(isFinite(refresh) ? refresh : defaults.refreshIntervalSec, 60, 86400))

    var lookahead = Number(next.lookaheadDays === undefined || next.lookaheadDays === null ? defaults.lookaheadDays : next.lookaheadDays)
    next.lookaheadDays = Math.round(clamp(isFinite(lookahead) ? lookahead : defaults.lookaheadDays, 1, 30))

    var chars = Number(next.maxDisplayChars === undefined || next.maxDisplayChars === null ? defaults.maxDisplayChars : next.maxDisplayChars)
    next.maxDisplayChars = Math.round(clamp(isFinite(chars) ? chars : defaults.maxDisplayChars, 12, 120))

    next.scheduleClearText = String(next.scheduleClearText === undefined || next.scheduleClearText === null ? defaults.scheduleClearText : next.scheduleClearText)
    var mode = String(next.meetOpenMode || defaults.meetOpenMode)
    if (mode === "chrome-app") mode = "system-browser"
    if (["system-browser", "custom-command"].indexOf(mode) < 0) mode = defaults.meetOpenMode
    next.meetOpenMode = mode
    next.meetOpenCommand = String(next.meetOpenCommand || "")
    delete next.chromeAppFlags
    next.calendars = normalizeCalendars(next.calendars)
    return next
  }

  function draftValue(name, fallback) {
    var value = draftSettings ? draftSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setDraftValue(name, value) {
    var next = cloneObject(draftSettings, {}) || {}
    next[name] = value
    draftSettings = next
  }

  function openSettings() {
    draftSettings = normalizedSettings(settings)
    settingsStatusText = ""
    settingsMode = true
    popupOpen = true
    loadCalendarOptions(false)
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function showUsage() {
    showAgenda()
  }

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function saveSettings() {
    var next = normalizedSettings(draftSettings)
    draftSettings = next
    root.settings = next
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, next)
      settingsStatusText = "Saved to shell.json"
    } else {
      settingsStatusText = "Saved for this session"
    }
    main.refresh(true)
  }

  function bestInitialEventIndex() {
    var events = dayEvents
    if (!events || events.length === 0) return 0
    for (var i = 0; i < events.length; i++) if (events[i].hasMeeting && !events[i].past) return i
    for (var j = 0; j < events.length; j++) if (!events[j].past) return j
    return Math.max(0, events.length - 1)
  }

  function ensureSelection() {
    var count = dayEvents ? dayEvents.length : 0
    if (count <= 0) {
      selectedEventIndex = 0
      return
    }
    if (selectedEventIndex < 0 || selectedEventIndex >= count) selectedEventIndex = bestInitialEventIndex()
  }

  function moveSelection(delta) {
    var count = dayEvents ? dayEvents.length : 0
    if (count <= 0) return
    selectedEventIndex = clamp(selectedEventIndex + delta, 0, count - 1)
    scrollSelectedIntoView()
  }

  function selectedEvent() {
    if (!dayEvents || dayEvents.length === 0) return null
    return dayEvents[clamp(selectedEventIndex, 0, dayEvents.length - 1)]
  }

  function setDayOffset(offset) {
    var next = clamp(Number(offset || 0), 0, maxDayOffset)
    if (next === selectedDayOffset) return
    selectedDayOffset = next
    Qt.callLater(function() {
      selectedEventIndex = bestInitialEventIndex()
      if (flick) flick.contentY = 0
      scrollSelectedIntoView()
    })
  }

  function shiftDay(delta) {
    setDayOffset(selectedDayOffset + delta)
  }

  function joinEvent(event) {
    if (!event || !event.hasMeeting || !event.url) return
    main.openEvent(event)
    close()
  }

  function openSelectedEvent() {
    joinEvent(selectedEvent())
  }

  function scrollSelectedIntoView() {
    if (!eventsRepeater || selectedEventIndex < 0) return
    Qt.callLater(function() {
      if (!eventsRepeater || selectedEventIndex < 0 || selectedEventIndex >= eventsRepeater.count) return
      var item = eventsRepeater.itemAt(selectedEventIndex)
      if (!item) return
      var margin = 8
      var point = item.mapToItem(flick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = flick.contentY
      var viewBottom = viewTop + flick.height
      var maxY = Math.max(0, flick.contentHeight - flick.height)
      if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) flick.contentY = Math.min(maxY, bottom + margin - flick.height)
    })
  }

  function providerLabel(provider) {
    if (provider === "meet") return "Google Meet"
    if (provider === "zoom") return "Zoom"
    if (provider === "teams") return "Teams"
    if (provider === "webex") return "Webex"
    if (provider === "whereby") return "Whereby"
    return "Video"
  }

  function joinButtonText(provider) {
    if (provider === "meet") return "Meet"
    if (provider === "zoom") return "Zoom"
    if (provider === "teams") return "Teams"
    if (provider === "webex") return "Webex"
    return "Join"
  }

  function joinIcon(provider) {
    return "" // nf-fa-video_camera
  }

  function eventSubtitle(event) {
    if (!event) return ""
    var bits = []
    if (event.ongoing) bits.push("In progress")
    else if (event.startsText) bits.push(event.startsText)
    if (event.hasMeeting) bits.push(providerLabel(String(event.provider || "")))
    return bits.join(" · ")
  }

  function tooltipText() {
    return main.tooltipText || "NextMeeting"
  }

  visible: main.text !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onPopupOpenChanged: {
    if (popupOpen) {
      if (!settingsMode) {
        main.refresh()
        ensureSelection()
      }
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  onSelectedEventIndexChanged: scrollSelectedIntoView()
  onSelectedDayOffsetChanged: ensureSelection()
  onDayEventsChanged: ensureSelection()
  onMaxDayOffsetChanged: if (selectedDayOffset > maxDayOffset) setDayOffset(maxDayOffset)

  Main {
    id: main
    settings: root.settings
  }

  Connections {
    target: main
    function onEventsChanged() {
      selectedEventIndex = bestInitialEventIndex()
      if (popupOpen && !settingsMode) scrollSelectedIntoView()
    }
  }

  Timer {
    id: refreshFlashTimer
    interval: 900
    repeat: false
    onTriggered: root.refreshFlash = false
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = new Date()
  }

  Process {
    id: calendarOptionsProcess
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyCalendarOptions(text)
    }
  }

  IpcHandler {
    target: "next-meeting"
    function open(): string { main.openNextEvent(); return main.hasMeeting ? "ok" : "no-meeting" }
    function join(): string { main.openNextEvent(); return main.hasMeeting ? "ok" : "no-meeting" }
    function show(): string { root.showAgenda(); return "ok" }
    function toggle(): string { root.toggleAgenda(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function refresh(): string { root.triggerRefresh(); return "ok" }
    function settings(): string { root.openSettings(); return "ok" }
    function openSettings(): string { root.openSettings(); return "ok" }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: main.text
    tooltipText: root.tooltipText()
    active: root.popupOpen && !root.settingsMode
    pressable: true
    dimmed: main.isLoading

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.openSettings()
      } else if (b === Qt.MiddleButton) {
        root.triggerRefresh()
      } else {
        root.toggleAgenda()
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
    contentWidth: panel.fittedContentWidth(Style.space(470))
    // Size to the full panel content (header + separator + agenda/footer)
    // until the max is reached; then only the agenda Flickable scrolls.
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsMode && settingsContent.editorActive

      onMoveRequested: function(dx, dy) {
        if (root.settingsMode) {
          if (dy !== 0) flick.contentY = root.clamp(flick.contentY + dy * 56, 0, Math.max(0, flick.contentHeight - flick.height))
          return
        }
        if (dy !== 0) root.moveSelection(dy)
        if (dx !== 0) root.shiftDay(dx)
      }
      onActivateRequested: if (!root.settingsMode) root.openSelectedEvent()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.triggerRefresh()
        if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
      }

      ColumnLayout {
        id: panelColumn
        anchors.fill: parent
        spacing: 10

        AgendaHeader { visible: !root.settingsMode }
        SettingsHeader { visible: root.settingsMode }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: contentColumn.implicitHeight
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
              visible: !root.settingsMode && main.isLoading && root.dayEvents.length === 0
              Layout.fillWidth: true
              Layout.topMargin: 18
              text: "Fetching calendar events…"
              color: dim
              font.family: fontFamily
              font.pixelSize: 11
              horizontalAlignment: Text.AlignHCenter
            }

            NowMarker {
              visible: !root.settingsMode && root.selectedDayIsToday && !main.isLoading && root.dayEvents.length === 0
            }

            SectionCard {
              visible: !root.settingsMode && !main.isLoading && root.dayEvents.length === 0
              title: root.selectedDayOffset === 0 ? "No events today" : "No events"
              subtitle: root.selectedDayOffset === 0 ? "Your calendar is clear for today." : "No events found for " + root.selectedDateLabel + "."
            }

            ColumnLayout {
              id: eventColumn
              visible: !root.settingsMode && root.dayEvents.length > 0
              Layout.fillWidth: true
              spacing: 6

              Repeater {
                id: eventsRepeater
                model: root.dayEvents

                ColumnLayout {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  spacing: 6

                  NowMarker { visible: root.nowMarkerIndex === index }

                  EventRow {
                    Layout.fillWidth: true
                    event: modelData
                    rowIndex: index
                    selected: root.selectedEventIndex === index
                  }
                }
              }

              NowMarker { visible: root.nowMarkerIndex === root.dayEvents.length }
            }

            AgendaFooter { visible: !root.settingsMode }

            SettingsContent {
              id: settingsContent
              visible: root.settingsMode
            }
          }
        }
      }
    }
  }

  component AgendaHeader: RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      text: root.selectedDateLabel
      color: foreground
      font.family: fontFamily
      font.pixelSize: 15
      font.bold: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      visible: root.selectedDayIsToday
      text: "Now " + root.currentTimeLabel
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      text: "←"
      enabled: root.selectedDayOffset > 0
      opacity: enabled ? 1.0 : 0.35
      foreground: root.foreground
      tooltipText: "Previous day"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 7
      verticalPadding: 4
      onClicked: root.shiftDay(-1)
    }

    Button {
      visible: root.selectedDayOffset !== 0
      text: "Today"
      foreground: root.foreground
      tooltipText: "Jump back to today"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 7
      verticalPadding: 4
      onClicked: root.setDayOffset(0)
    }

    Button {
      text: "→"
      enabled: root.selectedDayOffset < root.maxDayOffset
      opacity: enabled ? 1.0 : 0.35
      foreground: root.foreground
      tooltipText: "Next day"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 7
      verticalPadding: 4
      onClicked: root.shiftDay(1)
    }

    Button {
      text: "Settings"
      foreground: root.foreground
      tooltipText: "Open NextMeeting settings"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      onClicked: root.openSettings()
    }

    Button {
      text: (root.refreshFlash || main.isLoading) ? "Refreshing…" : "Refresh"
      foreground: root.foreground
      tooltipText: (root.refreshFlash || main.isLoading) ? "Refreshing calendar…" : "Refresh calendar"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      active: root.refreshFlash || main.isLoading
      onClicked: {
        root.triggerRefresh()
        keyCatcher.forceActiveFocus()
      }
    }
  }

  component SettingsHeader: RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      text: "NextMeeting Settings"
      color: foreground
      font.family: fontFamily
      font.pixelSize: 15
      font.bold: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      text: "Agenda"
      foreground: root.foreground
      tooltipText: "Back to agenda"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      onClicked: root.showAgenda()
    }

    Button {
      text: "Save"
      foreground: root.foreground
      tooltipText: "Save settings"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      active: true
      onClicked: root.saveSettings()
    }
  }

  component EventRow: Rectangle {
    id: rowRoot
    property var event: ({})
    property int rowIndex: 0
    property bool selected: false

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + 14
    color: selected ? Style.hoverFillFor(root.foreground, Color.accent) : (event.past ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025) : "transparent")
    border.color: selected ? Style.hoverBorderFor(root.foreground, Color.accent) : "transparent"
    border.width: selected ? Style.hoverBorderWidth : 0
    radius: Style.cornerRadius
    opacity: event.past ? 0.62 : 1.0

    HoverHandler {
      onHoveredChanged: if (hovered) root.selectedEventIndex = rowRoot.rowIndex
    }

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 10

      Text {
        text: event.timeRange || event.timeLabel || ""
        color: dim
        font.family: fontFamily
        font.pixelSize: 11
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        clip: true
        Layout.preferredWidth: 122
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: event.title || "(untitled)"
          color: event.ongoing ? urgent : foreground
          font.family: fontFamily
          font.pixelSize: 12
          font.bold: event.ongoing || rowRoot.selected
          elide: Text.ElideRight
        }

        Text {
          visible: root.eventSubtitle(event) !== ""
          Layout.fillWidth: true
          text: root.eventSubtitle(event)
          color: dim
          font.family: fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
        }
      }

      Button {
        visible: event.hasMeeting === true
        text: root.joinButtonText(String(event.provider || ""))
        iconText: root.joinIcon(String(event.provider || ""))
        foreground: root.foreground
        tooltipText: "Join " + root.providerLabel(String(event.provider || ""))
        tooltipBackground: root.background
        tooltipForeground: root.foreground
        fontFamily: root.fontFamily
        fontSize: 10
        iconSize: 11
        horizontalPadding: 8
        verticalPadding: 4
        active: event.ongoing === true
        onClicked: root.joinEvent(event)
      }
    }
  }

  component NowMarker: RowLayout {
    Layout.fillWidth: true
    Layout.leftMargin: 4
    Layout.rightMargin: 4
    spacing: 8

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 1
      color: root.alpha(Color.accent, 0.55)
    }

    Text {
      text: "Now · " + root.currentTimeLabel
      color: Color.accent
      font.family: fontFamily
      font.pixelSize: 10
      font.bold: true
      Layout.alignment: Qt.AlignVCenter
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: 1
      color: root.alpha(Color.accent, 0.55)
    }
  }

  component AgendaFooter: Text {
    Layout.fillWidth: true
    text: "h/l day · j/k select · enter joins selected video meeting · r refresh · s settings · esc close"
    color: dim
    font.family: fontFamily
    font.pixelSize: 10
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }

  component CalendarSelector: ColumnLayout {
    Layout.fillWidth: true
    spacing: 7

    RowLayout {
      Layout.fillWidth: true
      spacing: 8

      FieldLabel {
        text: "Calendars"
        Layout.fillWidth: true
      }

      Button {
        text: root.calendarsLoading ? "Loading…" : "Reload"
        enabled: !root.calendarsLoading
        opacity: enabled ? 1.0 : 0.45
        foreground: root.foreground
        tooltipText: "Reload calendars from gcalcli"
        tooltipBackground: root.background
        tooltipForeground: root.foreground
        fontFamily: root.fontFamily
        fontSize: 10
        horizontalPadding: 7
        verticalPadding: 4
        onClicked: root.loadCalendarOptions(true)
      }
    }

    Text {
      Layout.fillWidth: true
      text: root.selectedCalendarSummary()
      color: root.selectedCalendarCount() > 0 ? root.foreground : dim
      font.family: fontFamily
      font.pixelSize: 10
      elide: Text.ElideRight
    }

    Text {
      visible: root.calendarsStatusText !== ""
      Layout.fillWidth: true
      text: root.calendarsStatusText
      color: urgent
      font.family: fontFamily
      font.pixelSize: 10
      wrapMode: Text.WordWrap
    }

    Text {
      visible: root.calendarsLoading && root.calendarOptions.length === 0
      Layout.fillWidth: true
      text: "Loading calendars…"
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
    }

    Text {
      visible: !root.calendarsLoading && root.calendarOptions.length === 0
      Layout.fillWidth: true
      text: "No calendars found. Leave the selection empty to include all calendars."
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      wrapMode: Text.WordWrap
    }

    ColumnLayout {
      visible: root.calendarOptions.length > 0
      Layout.fillWidth: true
      spacing: 5

      Repeater {
        model: root.calendarOptions

        CalendarOptionRow {
          required property var modelData
          Layout.fillWidth: true
          option: modelData
        }
      }
    }

    Button {
      visible: root.selectedCalendarCount() > 0
      text: "Use all calendars"
      foreground: root.foreground
      tooltipText: "Clear selected calendars"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      onClicked: root.clearDraftCalendars()
    }
  }

  component CalendarOptionRow: Rectangle {
    id: optionRow
    property var option: ({})
    readonly property string value: String(option.value || option.label || "")
    readonly property string label: String(option.label || option.value || "")
    readonly property string description: String(option.description || "")
    readonly property bool checked: root.calendarSelected(value)

    Layout.fillWidth: true
    implicitHeight: optionRow.description !== "" ? 46 : 34
    color: checked ? root.alpha(Color.accent, 0.15) : (optionHover.hovered ? root.cardHover : "transparent")
    border.color: checked ? root.alpha(Color.accent, 0.55) : root.outline
    border.width: checked || optionHover.hovered ? 1 : 0
    radius: Style.cornerRadius

    HoverHandler { id: optionHover }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleDraftCalendar(optionRow.value)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 9
      anchors.rightMargin: 9
      spacing: 8

      Rectangle {
        Layout.preferredWidth: 15
        Layout.preferredHeight: 15
        Layout.alignment: Qt.AlignVCenter
        radius: 4
        color: optionRow.checked ? Color.accent : "transparent"
        border.color: optionRow.checked ? Color.accent : root.outline
        border.width: 1

        Text {
          anchors.centerIn: parent
          visible: optionRow.checked
          text: "✓"
          color: Color.background
          font.family: fontFamily
          font.pixelSize: 10
          font.bold: true
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 1

        Text {
          Layout.fillWidth: true
          text: optionRow.label
          color: root.foreground
          font.family: fontFamily
          font.pixelSize: 11
          elide: Text.ElideRight
        }

        Text {
          id: optionDescription
          visible: optionRow.description !== ""
          Layout.fillWidth: true
          text: optionRow.description
          color: dim
          font.family: fontFamily
          font.pixelSize: 9
          elide: Text.ElideRight
        }
      }
    }
  }

  component SettingsContent: ColumnLayout {
    id: settingsRoot
    Layout.fillWidth: true
    spacing: 10

    readonly property bool customOpen: root.draftValue("meetOpenMode", "system-browser") === "custom-command"
    readonly property bool editorActive: refreshIntervalField.field.activeFocus
      || lookaheadField.field.activeFocus
      || maxCharsField.field.activeFocus
      || clearTextField.activeFocus
      || customCommandField.activeFocus

    SectionCard {
      title: "Calendar"

      ColumnLayout {
        width: parent.width
        spacing: 8

        NumberField {
          id: refreshIntervalField
          label: "Auto-fetch interval (seconds)"
          value: Number(root.draftValue("refreshIntervalSec", 1800))
          from: 60
          to: 86400
          stepSize: 60
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onModified: function(value) { root.setDraftValue("refreshIntervalSec", value) }
        }

        NumberField {
          id: lookaheadField
          label: "Lookahead window (days)"
          value: Number(root.draftValue("lookaheadDays", 7))
          from: 1
          to: 30
          stepSize: 1
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onModified: function(value) { root.setDraftValue("lookaheadDays", value) }
        }

        CalendarSelector { Layout.fillWidth: true }
      }
    }

    SectionCard {
      title: "Display"

      ColumnLayout {
        width: parent.width
        spacing: 8

        FieldLabel { text: "Schedule clear text" }
        TextField {
          id: clearTextField
          Layout.fillWidth: true
          text: String(root.draftValue("scheduleClearText", "No more meetings today ✅"))
          placeholderText: "No more meetings today ✅"
          foreground: root.foreground
          onTextChanged: if (text !== root.draftValue("scheduleClearText", "")) root.setDraftValue("scheduleClearText", text)
        }

        NumberField {
          id: maxCharsField
          label: "Maximum bar characters"
          value: Number(root.draftValue("maxDisplayChars", 42))
          from: 12
          to: 120
          stepSize: 1
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onModified: function(value) { root.setDraftValue("maxDisplayChars", value) }
        }
      }
    }

    SectionCard {
      title: "Join links"
      subtitle: "Open meeting links in your default browser, or provide a custom command."

      ColumnLayout {
        width: parent.width
        spacing: 8

        ButtonGroup {
          Layout.fillWidth: true
          options: [
            { value: "system-browser", label: "Browser" },
            { value: "custom-command", label: "Custom" }
          ]
          value: String(root.draftValue("meetOpenMode", "system-browser"))
          foreground: root.foreground
          background: "transparent"
          accent: Color.accent
          fontFamily: root.fontFamily
          fontSize: 10
          onChanged: function(value) { root.setDraftValue("meetOpenMode", value) }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 6
          enabled: settingsRoot.customOpen
          opacity: enabled ? 1.0 : 0.45

          FieldLabel { text: "Custom open command" }
          TextField {
            id: customCommandField
            Layout.fillWidth: true
            text: String(root.draftValue("meetOpenCommand", ""))
            placeholderText: "firefox --new-window \"$NEXT_MEETING_URL\""
            foreground: root.foreground
            onTextChanged: if (text !== root.draftValue("meetOpenCommand", "")) root.setDraftValue("meetOpenCommand", text)
          }
        }
      }
    }

    Text {
      visible: root.settingsStatusText !== ""
      Layout.fillWidth: true
      text: root.settingsStatusText
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      Layout.fillWidth: true
      text: "Right-click the bar widget to return here · s saves · esc closes"
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }

  component FieldLabel: Text {
    color: dim
    font.family: fontFamily
    font.pixelSize: 10
    font.bold: true
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
}
