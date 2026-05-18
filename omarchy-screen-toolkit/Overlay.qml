import QtQuick
import Quickshell

// Router for the screen-toolkit's full-screen / floating overlays
// (pin, measure, mirror). The bar widget summons us via
// `summon("omarchy-screen-toolkit", { tool: "...", ...payload })`;
// open() dispatches into a per-tool slot.
//
// Pins are additive — each summon spawns a new floating image and they
// pile up on screen. Measure and mirror are singletons; summoning a
// second time is a no-op while the existing instance is up.
//
// We keep pins in a ListModel (not a JS array) so adding a new pin
// doesn't reset the geometry the user already adjusted on an existing
// pin — a Repeater fed a JS array recreates *all* delegates on every
// change, which would yank existing pin windows out from under the
// user.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  ListModel { id: pinsModel }
  property bool measureActive: false
  property bool mirrorActive: false

  property int nextPinId: 1

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) } catch (e) { payload = {} }
    var tool = String(payload.tool || "")
    if (!tool) return
    if (tool === "pin")          appendPin(payload)
    else if (tool === "measure") measureActive = true
    else if (tool === "mirror")  mirrorActive = true
  }

  // Called by the shell on hide. Drop every slot — keeping any of them
  // alive would leave the panel-open state desynced from the actual UI.
  function close() {
    pinsModel.clear()
    measureActive = false
    mirrorActive = false
  }

  function appendPin(payload) {
    pinsModel.append({
      pinId: nextPinId++,
      path:  String(payload.path || ""),
      srcW:  payload.w ? parseInt(payload.w) || 600 : 600,
      srcH:  payload.h ? parseInt(payload.h) || 400 : 400,
      stackIndex: pinsModel.count
    })
  }

  function _maybeAutoHide() {
    if (pinsModel.count === 0 && !measureActive && !mirrorActive &&
        root.shell && typeof root.shell.hide === "function")
      root.shell.hide("omarchy-screen-toolkit")
  }

  function removePinAt(i) {
    if (i < 0 || i >= pinsModel.count) return
    pinsModel.remove(i)
    _maybeAutoHide()
  }

  function dismissMeasure() {
    measureActive = false
    _maybeAutoHide()
  }

  function dismissMirror() {
    mirrorActive = false
    _maybeAutoHide()
  }

  // Pins live in a ListModel so delegates persist across appends —
  // Repeater only destroys the row that was actually removed (a Repeater
  // fed a JS array recreates *all* delegates on every assignment, which
  // would yank existing pin windows the user has already repositioned).
  Repeater {
    model: pinsModel
    delegate: Loader {
      id: pinLoader
      required property int index
      required property string path
      required property int srcW
      required property int srcH
      required property int stackIndex
      source: Qt.resolvedUrl("components/Pin.qml")
      onLoaded: {
        if (!item) return
        item.payload = {
          path: pinLoader.path,
          w:    pinLoader.srcW,
          h:    pinLoader.srcH,
          stackIndex: pinLoader.stackIndex
        }
        item.closeRequested.connect(function() { root.removePinAt(pinLoader.index) })
      }
    }
  }

  // Measure and mirror are singletons — one Loader each, active
  // toggled by the corresponding *Active flag. The Loader holds onto
  // the instance while active so it can cleanly tear down on dismiss.
  Loader {
    active: root.measureActive
    source: active ? Qt.resolvedUrl("components/Measure.qml") : ""
    onLoaded: {
      if (!item) return
      item.closeRequested.connect(function() { root.dismissMeasure() })
    }
  }

  Loader {
    active: root.mirrorActive
    source: active ? Qt.resolvedUrl("components/Mirror.qml") : ""
    onLoaded: {
      if (!item) return
      item.closeRequested.connect(function() { root.dismissMirror() })
    }
  }
}
