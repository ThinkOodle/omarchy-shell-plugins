import QtQuick
import Quickshell
import "providers"

Item {
  id: root
  visible: false

  property var settings: ({})

  Claude {
    id: claudeProvider
    enabled: root.providerEnabled("claude")
    providerSettings: root.settings && root.settings.providers && root.settings.providers.claude ? root.settings.providers.claude : ({})
  }

  Codex {
    id: codexProvider
    enabled: root.providerEnabled("codex")
    providerSettings: root.settings && root.settings.providers && root.settings.providers.codex ? root.settings.providers.codex : ({})
  }

  property var providers: [claudeProvider, codexProvider]
  property var enabledProviders: {
    var result = []
    if (claudeProvider.enabled) result.push(claudeProvider)
    if (codexProvider.enabled) result.push(codexProvider)
    return result
  }

  property int activeIndex: 0
  property var activeProvider: enabledProviders.length > 0 ? enabledProviders[Math.min(activeIndex, enabledProviders.length - 1)] : null
  property bool refreshing: claudeProvider.refreshing || codexProvider.refreshing
  property double lastRefreshedAtMs: Math.max(claudeProvider.lastRefreshedAtMs || 0, codexProvider.lastRefreshedAtMs || 0)
  property string barDisplayMode: setting("barDisplayMode", "active")
  property int barCycleIntervalSec: Math.max(1, Number(setting("barCycleIntervalSec", 5)))
  property string barMetric: setting("barMetric", "prompts")
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 300)))

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  Timer {
    interval: root.barCycleIntervalSec * 1000
    running: root.barDisplayMode === "cycle" && root.enabledProviders.length > 1
    repeat: true
    onTriggered: root.activeIndex = (root.activeIndex + 1) % root.enabledProviders.length
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAll()
  }

  onEnabledProvidersChanged: {
    if (enabledProviders.length === 0 || activeIndex >= enabledProviders.length) activeIndex = 0
  }

  function providerEnabled(id) {
    if (!settings || !settings.providers || !settings.providers[id]) return id === "claude" || id === "codex"
    return settings.providers[id].enabled !== false
  }

  function refresh() { refreshAll(true) }

  function refreshAll(force) {
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      if (p.enabled && typeof p.refresh === "function") p.refresh(force === true)
    }
  }

  function formatTokenCount(n) {
    if (n === undefined || n === null) return "0"
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  function friendlyModelName(id) {
    if (!id) return "Unknown"
    var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "")
    var parts = name.split("-")
    if (parts.length >= 3) return parts[0].charAt(0).toUpperCase() + parts[0].slice(1) + " " + parts[1] + "." + parts[2]
    if (parts.length === 2) return parts[0].charAt(0).toUpperCase() + parts[0].slice(1) + " " + parts[1]
    return name.charAt(0).toUpperCase() + name.slice(1)
  }
}
