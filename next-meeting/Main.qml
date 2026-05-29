import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property var settings: ({})
  property string text: ""
  property string tooltipText: ""
  property string stateClass: "off"
  property bool hasMeeting: false
  property string meetUrl: ""
  property string meetingProvider: ""
  property var events: []
  property string today: ""
  property string todayLabel: ""
  property string generatedAt: ""
  property bool initialLoadPending: true
  property bool manualRefreshPending: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 1800, 60, 86400)
  readonly property string loadingText: "Fetching calendar events..."
  readonly property string scheduleClearText: stringSetting("scheduleClearText", "No more meetings today ✅")
  readonly property int lookaheadDays: intSetting("lookaheadDays", 7, 1, 30)
  readonly property int maxDisplayChars: intSetting("maxDisplayChars", 42, 12, 120)
  readonly property string meetOpenMode: stringSetting("meetOpenMode", "chrome-app")
  readonly property string meetOpenCommand: stringSetting("meetOpenCommand", "")
  readonly property string chromeAppFlags: stringSetting("chromeAppFlags",
    "--ozone-platform=x11 --disable-features=WaylandWpColorManagerV1 --disable-gpu-compositing")
  // Accept either a JSON array (new multiselect format) or a CSV string
  // (legacy / inline settings). Calendars are passed downstream as repeated
  // argv entries so calendar names containing commas survive when stored as
  // arrays in shell.json.
  readonly property var calendars: {
    var v = setting("calendars", [])
    var out = []
    if (v && typeof v.length === "number" && typeof v !== "string") {
      for (var i = 0; i < v.length; i++) {
        var s = String(v[i]).trim()
        if (s !== "") out.push(s)
      }
    } else if (typeof v === "string" && v !== "") {
      var parts = v.split(",")
      for (var j = 0; j < parts.length; j++) {
        var p = parts[j].trim()
        if (p !== "") out.push(p)
      }
    }
    return out
  }
  readonly property bool isLoading: initialLoadPending || manualRefreshPending

  readonly property string nextEventScriptPath: pathFromUrl(Qt.resolvedUrl("scripts/next-event.sh"))
  readonly property string openEventScriptPath: pathFromUrl(Qt.resolvedUrl("scripts/next-event-open.sh"))

  function pathFromUrl(url) {
    var value = String(url)
    if (value.indexOf("file://") === 0) return decodeURIComponent(value.substring(7))
    return value
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function stringSetting(name, fallback) {
    return String(setting(name, fallback))
  }

  function refresh(showLoading) {
    if (showLoading === true && isLoading) return
    if (refreshProcess.running) return

    var shouldShowLoading = showLoading === true || initialLoadPending
    if (showLoading === true) manualRefreshPending = true
    if (shouldShowLoading) {
      text = loadingText
      tooltipText = ""
      hasMeeting = false
      meetUrl = ""
      meetingProvider = ""
      stateClass = "on"
    }

    var argv = [
      nextEventScriptPath,
      scheduleClearText,
      String(lookaheadDays),
      String(maxDisplayChars)
    ]
    for (var i = 0; i < calendars.length; i++) argv.push(calendars[i])
    refreshProcess.command = argv
    refreshProcess.running = true
  }

  function openNextEvent() {
    openUrl(meetUrl)
  }

  function openEvent(event) {
    if (!event) return
    openUrl(String(event.url || ""))
  }

  function openUrl(url) {
    if (!url) return
    openProcess.command = [
      openEventScriptPath,
      url,
      meetOpenMode,
      meetOpenCommand,
      chromeAppFlags
    ]
    openProcess.running = true
  }

  function applyPayload(raw) {
    initialLoadPending = false
    manualRefreshPending = false

    var payload = String(raw || "").trim()
    if (payload === "") {
      text = ""
      tooltipText = ""
      hasMeeting = false
      meetUrl = ""
      meetingProvider = ""
      events = []
      today = ""
      todayLabel = ""
      generatedAt = ""
      stateClass = "off"
      return
    }

    try {
      var parsed = JSON.parse(payload)
      text = parsed.text ? String(parsed.text) : ""
      tooltipText = parsed.tooltip ? String(parsed.tooltip) : ""
      hasMeeting = parsed.hasMeeting === true
      meetUrl = parsed.url ? String(parsed.url) : ""
      meetingProvider = parsed.provider ? String(parsed.provider) : ""
      events = Array.isArray(parsed.events) ? parsed.events : []
      today = parsed.today ? String(parsed.today) : ""
      todayLabel = parsed.todayLabel ? String(parsed.todayLabel) : ""
      generatedAt = parsed.generatedAt ? String(parsed.generatedAt) : ""
      stateClass = parsed.class ? String(parsed.class) : (text === "" ? "off" : "on")
    } catch (e) {
      text = ""
      tooltipText = ""
      hasMeeting = false
      meetUrl = ""
      meetingProvider = ""
      events = []
      today = ""
      todayLabel = ""
      generatedAt = ""
      stateClass = "off"
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: refreshProcess
    running: false
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyPayload(text)
    }
  }

  Process {
    id: openProcess
    running: false
    command: []
  }
}
