import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "js/ThinkingOrbs.js" as Orbs

// XARVIN — Floating Overlay Command Bar (Quickshell Standalone)
// Pure #000000 black background, unvarying #121212 border, embedded 3D Thinking Orb,
// and Lucide React icons. Completely decoupled from third-party plugins.
PanelWindow {
    id: notchWin

    signal closeRequested()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "xarvin-notch"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    anchors {
        bottom: true
    }

    margins {
        bottom: 36
    }

    width: 560
    height: 54
    color: "transparent"

    readonly property string homeDir: Quickshell.env("HOME") || "/home/theajmalrazaq"
    readonly property string cliBin: homeDir + "/Projects/xarvin/bin/xarvin"
    readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/xarvin-state.json"
    readonly property string legacyStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/jarvis-state.json"

    readonly property string orbStateOpt: "auto"
    readonly property bool monochrome: false
    readonly property string placeholderOpt: "Tell XARVIN what to do..."

    // Live daemon status
    property string status: "idle"
    property string currentTool: ""
    property string currentMessage: ""
    property real tSec: 0.6

    // Speech pulsation for dynamic wave animations
    property real speechPulsation: 0.3
    SequentialAnimation on speechPulsation {
        running: notchWin.status === "speaking"
        loops: Animation.Infinite
        NumberAnimation { to: 0.95; duration: 420; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 0.35; duration: 380; easing.type: Easing.InOutQuad }
    }

    readonly property real audioLevel: (notchWin.status === "speaking") ? speechPulsation : 0

    // Map XARVIN status to 3D thinking-orbs mode
    readonly property string activeOrbMode: {
        if (orbStateOpt !== "auto") return orbStateOpt;
        switch (notchWin.status) {
            case "listening": return "listening";
            case "thinking":  return "searching";
            case "working":   return "solving";
            case "speaking":  return "composing";
            default:          return "searching";
        }
    }

    property color coreColor: {
        switch (notchWin.status) {
            case "listening": return "#5cc8b4";
            case "thinking":  return "#c39bd3";
            case "working":   return "#e0a458";
            case "speaking":  return "#6ab0f3";
            default:          return "#eeeae2";
        }
    }

    Behavior on coreColor { ColorAnimation { duration: 200 } }

    // Live state watching via native Quickshell FileView
    FileView {
        id: stateWatcher
        path: notchWin.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var str = text();
                if (str && str.length > 0) {
                    var s = JSON.parse(str);
                    notchWin.status = s.status || "idle";
                    notchWin.currentTool = s.tool || "";
                    notchWin.currentMessage = s.message || "";
                }
            } catch (e) {}
        }
    }

    // Periodic safety sync timer
    Timer {
        interval: 150
        running: notchWin.visible
        repeat: true
        onTriggered: stateWatcher.reload()
    }

    // 45ms animation ticker for 3D Thinking Orb (matches bar orb speed)
    Timer {
        interval: 45
        running: notchWin.visible
        repeat: true
        onTriggered: {
            notchWin.tSec += 0.045 * (1 + notchWin.audioLevel * 0.8);
            notchOrbCanvas.requestPaint();
        }
    }

    function submitPrompt() {
        var query = promptInput.text.trim();
        if (query.length > 0) {
            promptInput.focus = false;
            Quickshell.execDetached([notchWin.cliBin, "ask", query]);
            promptInput.text = "";
            notchWin.closeRequested(); // Hide immediately until user opens it again
        }
    }

    function closeNotch() {
        promptInput.text = "";
        notchWin.closeRequested();
    }

    // Outer notch pill container
    Rectangle {
        id: container
        anchors.fill: parent
        radius: height / 2

        // Exact requested styling: Pure #000000 Black background with strictly constant #121212 border
        color: "#000000"
        border.color: "#121212"
        border.width: 1.5

        // Click anywhere on bar to focus text input
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: promptInput.forceActiveFocus()
        }

        // 3D Thinking Orb inside the input field (Left)
        Item {
            id: orbBox
            width: 38
            height: 38
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            Canvas {
                id: notchOrbCanvas
                readonly property real renderPx: 96
                width: renderPx
                height: renderPx
                anchors.centerIn: parent
                scale: 38 / renderPx
                renderTarget: Canvas.Image
                renderStrategy: Canvas.Immediate

                onPaint: {
                    var ctx = getContext("2d");
                    if (!ctx) return;
                    ctx.resetTransform();
                    ctx.clearRect(0, 0, width, height);

                    var t = notchWin.tSec;
                    var mode = notchWin.activeOrbMode;
                    var tint = notchWin.monochrome ? null : notchWin.coreColor;
                    var audio = notchWin.audioLevel;

                    Orbs.drawOrb(ctx, width, mode, t, true, tint, audio);
                }
            }

            // Click orb to stop speech/action if active
            MouseArea {
                anchors.fill: parent
                cursorShape: notchWin.status !== "idle" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (notchWin.status !== "idle") {
                        Quickshell.execDetached([notchWin.cliBin, "stop"]);
                    }
                }
            }
        }

        // Interactive Input Field (Center)
        Item {
            id: textContainer
            anchors.left: orbBox.right
            anchors.leftMargin: 10
            anchors.right: actionRow.left
            anchors.rightMargin: 8
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            TextInput {
                id: promptInput
                anchors.fill: parent
                verticalAlignment: TextInput.AlignVCenter
                color: "#ffffff"
                font.family: "JetBrains Mono, Inter, Cantarell, Sans"
                font.pixelSize: 13
                font.weight: Font.Normal
                font.italic: false
                clip: true
                focus: true
                selectByMouse: true
                selectionColor: "#333333"
                selectedTextColor: "#ffffff"

                onAccepted: notchWin.submitPrompt()

                Keys.onEscapePressed: {
                    notchWin.closeNotch();
                }

                // Placeholder text when empty
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: notchWin.placeholderOpt
                    color: "#555555"
                    font.family: promptInput.font.family
                    font.pixelSize: promptInput.font.pixelSize
                    font.italic: false
                    visible: promptInput.text.length === 0
                }
            }
        }

        // Action Buttons (Right)
        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // Clear Input Button (Lucide X)
            Rectangle {
                id: clearBtn
                visible: promptInput.text.length > 0
                width: 28
                height: 28
                radius: 14
                color: clearMouse.containsMouse ? "#1c1c1c" : "#121212"
                border.color: "#222222"
                border.width: 1

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 13 / 24
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: clearMouse.containsMouse ? "#ffffff" : "#999999"
                        strokeWidth: 2.2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M18 6L6 18M6 6L18 18" }
                    }
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        promptInput.text = "";
                        promptInput.forceActiveFocus();
                    }
                }
            }

            // Submit Prompt Button (Lucide CornerDownLeft)
            Rectangle {
                id: sendBtn
                visible: promptInput.text.trim().length > 0
                width: 30
                height: 30
                radius: 15
                color: sendMouse.containsMouse ? "#ffffff" : "#e0e0e0"

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 14 / 24
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: "#000000"
                        strokeWidth: 2.4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M9 10L4 15L9 20M20 4V11C20 13.2091 18.2091 15 16 15H4" }
                    }
                }

                MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notchWin.submitPrompt()
                }
            }

            // Stop / Interrupt Button (Lucide Square)
            Rectangle {
                id: stopBtn
                visible: promptInput.text.length === 0 && notchWin.status !== "idle"
                width: 28
                height: 28
                radius: 14
                color: stopMouse.containsMouse ? "#1c1c1c" : "#121212"
                border.color: notchWin.coreColor
                border.width: 1

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 12 / 24
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: notchWin.coreColor
                        strokeWidth: 2.2
                        fillColor: notchWin.coreColor
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg {
                            path: "M5 3H19C20.1046 3 21 3.89543 21 5V19C21 20.1046 20.1046 21 19 21H5C3.89543 21 3 20.1046 3 19V5C3 3.89543 3.89543 3 5 3Z"
                        }
                    }
                }

                MouseArea {
                    id: stopMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached([notchWin.cliBin, "stop"]);
                    }
                }
            }

            // Close Notch Button (Lucide X)
            Rectangle {
                id: closeBtn
                visible: promptInput.text.length === 0
                width: 28
                height: 28
                radius: 14
                color: closeMouse.containsMouse ? "#28171a" : "#121212"
                border.color: closeMouse.containsMouse ? "#ff4757" : "#1f1f1f"
                border.width: 1

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 12 / 24
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: closeMouse.containsMouse ? "#ff4757" : "#888888"
                        strokeWidth: 2.0
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M18 6L6 18M6 6L18 18" }
                    }
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: notchWin.closeNotch()
                }
            }
        }
    }

    Component.onCompleted: {
        promptInput.forceActiveFocus();
    }
}
