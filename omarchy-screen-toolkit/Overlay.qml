import QtQuick
import Quickshell

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  // Active sub-tools keyed by an internal slot id. Pins are additive; measure
  // and mirror are singletons so a second summon replaces the existing one.
  property var slots: ({})
  property int nextSlotId: 1

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (e) { payload = {} }
    var tool = String(payload.tool || "")
    if (!tool) return
    mountTool(tool, payload)
  }

  function close() {
    var next = ({})
    slots = next
  }

  function mountTool(tool, payload) {
    var slotId = (tool === "pin") ? ("pin-" + nextSlotId++) : tool
    var next = ({})
    for (var k in slots) next[k] = slots[k]
    next[slotId] = { tool: tool, payload: payload }
    slots = next
  }

  function dismissSlot(slotId) {
    if (!slots[slotId]) return
    var next = ({})
    for (var k in slots) if (k !== slotId) next[k] = slots[k]
    slots = next
    if (Object.keys(slots).length === 0 && root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy-screen-toolkit")
  }

  // Sub-component repeater. Each active slot mounts the matching tool. Real
  // components land in later steps — pin/measure/mirror under components/.
  Repeater {
    model: {
      var ids = Object.keys(root.slots)
      var arr = []
      for (var i = 0; i < ids.length; i++) arr.push({ slotId: ids[i], entry: root.slots[ids[i]] })
      return arr
    }

    delegate: Item {
      required property var modelData
      readonly property string slotId: modelData.slotId
      readonly property string tool: modelData.entry.tool
      readonly property var payload: modelData.entry.payload
    }
  }
}
