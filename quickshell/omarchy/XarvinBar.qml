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

  property string status: "idle"
  property real tSec: 0.6

  visible: true
  implicitWidth: root.vertical ? root.barSize : Style.bar.iconSlot
  implicitHeight: root.vertical ? Style.bar.iconSlot : root.barSize

  property real speechPulsation: 0.3
  SequentialAnimation on speechPulsation {
    running: root.status === "speaking"
    loops: Animation.Infinite
    NumberAnimation { to: 0.95; duration: 420; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutQuad }
  }

  readonly property real audioLevel: (root.status === "speaking") ? speechPulsation : ((root.status === "listening") ? 0.6 : 0)

  // Original XARVIN orb geometry per state
  readonly property string activeOrbState: {
    if (root.status === "listening") return "listening"
    if (root.status === "working")   return "solving"
    if (root.status === "thinking")  return "searching"
    if (root.status === "speaking")  return "composing"
    return "searching"
  }

  // Original XARVIN palette
  property color coreColor: {
    if (root.status === "working")   return "#e0a458"
    if (root.status === "listening") return "#5cc8b4"
    if (root.status === "thinking")  return "#c39bd3"
    if (root.status === "speaking")  return "#6ab0f3"
    return "#eeeae2"
  }

  Behavior on coreColor { ColorAnimation { duration: 180 } }

  // Animate 3D orb smoothly
  Timer {
    interval: 45
    running: root.visible
    repeat: true
    onTriggered: {
      root.tSec += 0.045 * (1 + root.audioLevel * 0.8)
      orbCanvas.requestPaint()
    }
  }

  // Exact Quickshell FileView file watcher pattern
  FileView {
    id: stateWatcher
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var str = text();
        if (str && str.length > 0) {
          var s = JSON.parse(str);
          root.status = s.status || "idle";
        }
      } catch (e) {}
    }
  }

  // Periodic safety reload timer (150ms)
  Timer {
    interval: 150
    running: true
    repeat: true
    onTriggered: stateWatcher.reload()
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
    onEntered: if (root.bar) root.bar.showTooltip(root, "XARVIN")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
