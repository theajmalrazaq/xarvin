import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property bool notchOpen: false

    IpcHandler {
        target: "xarvin"

        function toggle(): void {
            root.notchOpen = !root.notchOpen;
        }

        function open(): void {
            root.notchOpen = true;
        }

        function close(): void {
            root.notchOpen = false;
        }

        function status(): string {
            return root.notchOpen ? "open" : "closed";
        }
    }

    Loader {
        active: root.notchOpen
        sourceComponent: XarvinNotch {
            onCloseRequested: root.notchOpen = false
        }
    }
}
