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
            case "thinking":  return "solving";
            case "working":   return "working";
            case "speaking":  return "composing";
            default:          return "searching";
        }
    }

    property color coreColor: {
        switch (notchWin.status) {
            case "listening": return "#60a5fa"; // Soft Blue
            case "thinking":  return "#f59e0b"; // Warm Amber
            case "working":   return "#a855f7"; // Vibrant Purple
            case "speaking":  return "#10b981"; // Emerald Green
            default:          return "#ffffff"; // Pure White
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

    // 60 FPS animation ticker for 3D Thinking Orb
    Timer {
        interval: 16
        running: notchWin.visible
        repeat: true
        onTriggered: {
            notchWin.tSec += 0.016;
            notchOrbCanvas.requestPaint();
        }
    }

    function submitPrompt() {
        if (notchWin.status !== "idle") return;
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

        // Click anywhere on bar to focus text input (when idle)
        MouseArea {
            anchors.fill: parent
            cursorShape: notchWin.status === "idle" ? Qt.IBeamCursor : Qt.ArrowCursor
            enabled: notchWin.status === "idle"
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
        }

        // Interactive Input Field / Dynamic Status Display (Center)
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
                clip: true
                focus: true
                selectByMouse: true
                selectionColor: "#333333"
                selectedTextColor: "#ffffff"
                visible: notchWin.status === "idle"
                enabled: notchWin.status === "idle"

                onAccepted: notchWin.submitPrompt()

                Keys.onEscapePressed: {
                    notchWin.closeNotch();
                }

                // Placeholder text when idle and empty
                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    text: notchWin.placeholderOpt
                    color: "#555555"
                    font.family: promptInput.font.family
                    font.pixelSize: promptInput.font.pixelSize
                    visible: promptInput.text.length === 0 && notchWin.status === "idle"
                }
            }

            // Live Activity Status Indicator (when AI is thinking, working, or speaking)
            Item {
                anchors.fill: parent
                visible: notchWin.status !== "idle"

                Text {
                    id: statusLabel
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    color: notchWin.coreColor
                    font.family: "JetBrains Mono, Inter, Cantarell, Sans"
                    font.pixelSize: 13
                    font.italic: true
                    elide: Text.ElideRight

                    text: {
                        switch (notchWin.status) {
                            case "thinking":
                                return "Thinking: " + (notchWin.currentMessage || "Processing...");
                            case "working":
                                return "Running: " + (notchWin.currentTool || "Executing action") + "...";
                            case "speaking":
                                return "Speaking: " + (notchWin.currentMessage || "Answering...");
                            case "listening":
                                return "Listening...";
                            default:
                                return "Active";
                        }
                    }
                }
            }
        }

        // Action Buttons (Right)
        Row {
            id: actionRow
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Clear Input Button (Lucide X)
            Rectangle {
                id: clearBtn
                visible: promptInput.text.length > 0 && notchWin.status === "idle"
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
                        strokeColor: clearMouse.containsMouse ? "#ffffff" : "#888888"
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathMove { x: 18; y: 6 }
                        PathLine { x: 6; y: 18 }
                    }
                    ShapePath {
                        strokeColor: clearMouse.containsMouse ? "#ffffff" : "#888888"
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathMove { x: 6; y: 6 }
                        PathLine { x: 18; y: 18 }
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

            // Stop / Interrupt Button (Lucide Square)
            Rectangle {
                id: stopBtn
                visible: promptInput.text.length === 0 && notchWin.status !== "idle"
                width: 28
                height: 28
                radius: 14
                color: stopMouse.containsMouse ? "#1c1c1c" : "#121212"
                border.color: "#222222"
                border.width: 1

                Shape {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    scale: 12 / 24
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: notchWin.coreColor
                        strokeWidth: 2
                        fillColor: notchWin.coreColor
                        PathSvg {
                            path: "M9 9h6v6H9z"
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
                    scale: 13 / 24
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: closeMouse.containsMouse ? "#ff4757" : "#666666"
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathMove { x: 18; y: 6 }
                        PathLine { x: 6; y: 18 }
                    }
                    ShapePath {
                        strokeColor: closeMouse.containsMouse ? "#ff4757" : "#666666"
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        fillColor: "transparent"
                        PathMove { x: 6; y: 6 }
                        PathLine { x: 18; y: 18 }
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
