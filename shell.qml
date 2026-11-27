//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import "theme"
import "services"
import "components"

ShellRoot {
    id: root

    // Native Wayland session lock (automatically spans all monitors)
    LockScreen {}

    // Native Polkit authentication agent (toggleable in Shell settings)
    Loader {
        active: ShellState.polkitEnabled
        sourceComponent: PolkitOverlay {}
    }

    // Spawn shell surfaces per connected monitor
    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property var modelData

            WallpaperLayer {
                modelData: screenScope.modelData
            }

            TopBar {
                modelData: screenScope.modelData
            }

            BottomDock {
                modelData: screenScope.modelData
            }

            DesktopWidget {
                modelData: screenScope.modelData
            }

            QuickSettingsShade {
                modelData: screenScope.modelData
            }

            CalendarShade {
                modelData: screenScope.modelData
            }

            NotificationsShade {
                modelData: screenScope.modelData
            }

            KeyboardShade {
                modelData: screenScope.modelData
            }

            MediaShade {
                modelData: screenScope.modelData
            }

            NotificationToasts {
                modelData: screenScope.modelData
            }

            OsdPopup {
                modelData: screenScope.modelData
            }

            LauncherPopup {
                modelData: screenScope.modelData
            }

            ClipboardPopup {
                modelData: screenScope.modelData
            }

            WallpaperPicker {
                modelData: screenScope.modelData
            }

            SessionOverlay {
                modelData: screenScope.modelData
            }

            ScreenshotOverlay {
                modelData: screenScope.modelData
            }

            AppContextMenu {
                modelData: screenScope.modelData
            }

            TrayContextMenu {
                modelData: screenScope.modelData
            }
        }
    }

    // IPC hooks: `qs ipc call shell <fn> [arg]`
    IpcHandler {
        target: "shell"

        function lock(): string {
            ShellState.lock();
            return "locked";
        }

        function toggle(name: string): string {
            const key = String(name || "").toLowerCase().trim();
            if (key === "screenshot") {
                if (!ShellState.hasGrim) {
                    Notifications.pushMock(JSON.stringify({
                        appName: "Screenshot",
                        appIcon: "applets-screenshooter",
                        summary: "Screenshot unavailable",
                        body: "Install `grim` & `wl-clipboard` to capture screenshots."
                    }));
                    return "missing_grim";
                }
                ShellState.toggleOverlay("screenshot");
                return ShellState.activeOverlay;
            }
            if (key === "theme") {
                ShellState.darkMode = !ShellState.darkMode;
                return ShellState.darkMode ? "dark" : "light";
            }
            if (key === "widgets") {
                ShellState.desktopWidgetsVisible = !ShellState.desktopWidgetsVisible;
                return String(ShellState.desktopWidgetsVisible);
            }
            if (key === "awww") {
                Wallpaper.toggleAwww();
                return String(Wallpaper.useAwww);
            }
            if (key === "launcher" || key === "clipboard" || key === "wallpapers"
                || key === "quicksettings" || key === "notifications"
                || key === "calendar" || key === "keyboard"
                || key === "media" || key === "session") {
                ShellState.toggleOverlay(key);
                return ShellState.activeOverlay;
            }
            return "unknown:" + key;
        }

        function nextWallpaper(): string {
            Wallpaper.randomNext();
            return Wallpaper.currentWallpaper;
        }

        function cycleDock(): string {
            ShellState.cycleDockMode();
            return ShellState.dockMode;
        }

        function setDock(mode: string): string {
            if (mode === "always" || mode === "popup" || mode === "off") {
                ShellState.dockMode = mode;
            }
            return ShellState.dockMode;
        }

        function testNotification(): string {
            Notifications.pushTest("Hello from Quickshell", "M3 Expressive pop-in notifications are live!");
            return "sent";
        }

        function pushMockNotification(payloadJson: string): string {
            Notifications.pushMock(payloadJson);
            return "ok";
        }
    }
}
