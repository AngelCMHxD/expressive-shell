#!/usr/bin/env python3
"""Hold a logind sleep delay inhibitor and notify Quickshell to lock before suspend."""
import os
import signal
import sys
import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


class SleepLockWatcher:
    def __init__(self) -> None:
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.inhibit_fd: int | None = None
        self.acquire_inhibitor()

        # Listen for PrepareForSleep on org.freedesktop.login1.Manager
        self.bus.signal_subscribe(
            "org.freedesktop.login1",
            "org.freedesktop.login1.Manager",
            "PrepareForSleep",
            "/org/freedesktop/login1",
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_prepare_for_sleep,
            None,
        )

        # Also listen for `loginctl lock-session` on any session object
        self.bus.signal_subscribe(
            "org.freedesktop.login1",
            "org.freedesktop.login1.Session",
            "Lock",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            self.on_session_lock,
            None,
        )

    def acquire_inhibitor(self) -> None:
        if self.inhibit_fd is not None:
            return
        try:
            res, fd_list = self.bus.call_with_unix_fd_list_sync(
                "org.freedesktop.login1",
                "/org/freedesktop/login1",
                "org.freedesktop.login1.Manager",
                "Inhibit",
                GLib.Variant("(ssss)", ("sleep", "Expressive Shell", "Lock before suspend", "delay")),
                GLib.VariantType("(h)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
                None,
            )
            idx = res.unpack()[0]
            self.inhibit_fd = fd_list.steal_fds()[idx]
        except Exception as exc:
            print(f"WARN:{exc}", file=sys.stderr, flush=True)

    def release_inhibitor(self) -> None:
        if self.inhibit_fd is not None:
            try:
                os.close(self.inhibit_fd)
            except OSError:
                pass
            self.inhibit_fd = None

    def on_prepare_for_sleep(self, _conn, _sender, _path, _iface, _signal, params, _user) -> None:
        going_to_sleep = bool(params.unpack()[0])
        if going_to_sleep:
            print("LOCK", flush=True)
            # Give Quickshell 300ms to map WlSessionLockSurface before allowing suspend
            GLib.timeout_add(300, self._finish_sleep_handoff)
        else:
            self.acquire_inhibitor()

    def _finish_sleep_handoff(self) -> bool:
        self.release_inhibitor()
        return False

    def on_session_lock(self, _conn, _sender, _path, _iface, _signal, _params, _user) -> None:
        print("LOCK", flush=True)


def main() -> int:
    watcher = SleepLockWatcher()
    loop = GLib.MainLoop()

    def shutdown(*_args):
        watcher.release_inhibitor()
        loop.quit()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    loop.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
