import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "js/ThinkingOrbs.js" as Orbs

BarWidget {
  id: root
  moduleName: "io.github.xarvin"

  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/xarvin-state.json"
  readonly property string legacyStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/jarvis-state.json"

  property string status: "idle"
  property real tSec: 0.6

  visible: true
  implicitWidth: root.vertical ? root.barSize : Style.bar.iconSlot
  implicitHeight: root.vertical ? Style.bar.iconSlot : root.barSize

  readonly property real audioLevel: (root.status === "speaking" || root.status === "listening") ? 0.6 : 0

  readonly property string activeOrbState: {
    if (root.status === "listening") return "listening"
    if (root.status === "working")   return "solving"
    if (root.status === "thinking")  return "searching"
    if (root.status === "speaking")  return "composing"
    return "searching" // Globe Halftone
  }

  property color coreColor: {
    if (root.status === "working")   return "#a855f7" // Purple
    if (root.status === "listening") return "#60a5fa" // Blue
    if (root.status === "thinking")  return "#f59e0b" // Amber
    if (root.status === "speaking")  return "#10b981" // Green
    return "#ffffff" // White
  }

  Behavior on coreColor { ColorAnimation { duration: 180 } }

  // Animate 3D orb smoothly
  Timer {
    interval: 16
    running: root.visible
    repeat: true
    onTriggered: {
      root.tSec += 0.016
      orbCanvas.requestPaint()
    }
  }

  // Watch state file
  FileView {
    id: stateWatcher
    path: root.statePath
    watchChanges: true
    onTextChanged: {
      if (!text || text.length === 0) return;
      try {
        var s = JSON.parse(text);
        root.status = s.status || "idle";
      } catch (e) {}
    }
  }

  Canvas {
    id: orbCanvas
    readonly property real renderPx: 96
    width: renderPx
    height: renderPx
    anchors.centerIn: parent
    scale: 18 / renderPx

    renderTarget: Canvas.Image
    renderStrategy: Canvas.Immediate

    onPaint: {
      var ctx = getContext("2d")
      if (!ctx) return
      ctx.resetTransform()
      ctx.clearRect(0, 0, width, height)

      var t = root.tSec
      var state = root.activeOrbState
      var tint = root.coreColor
      var audio = root.audioLevel

      Orbs.drawOrb(ctx, width, state, t, true, tint, audio)
    }
  }

  MouseArea {
    id: barMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        Quickshell.execDetached(["xarvin", "stop"])
      } else {
        Quickshell.execDetached(["xarvin", "toggle"])
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, "XARVIN (" + root.status.toUpperCase() + ") — Click to open command bar")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
