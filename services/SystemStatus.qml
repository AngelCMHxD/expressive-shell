pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import "../theme"

Singleton {
    id: root

    // Clock
    property string timeShort: ""
    property string dateShort: ""
    property string dayNumber: ""
    property string weekdayFull: ""
    property string monthDay: ""

    function refreshClock() {
        const now = new Date();
        timeShort = Qt.formatDateTime(now, ShellState.use24HourClock ? "HH:mm" : "h:mm AP");
        dateShort = Qt.formatDateTime(now, "ddd, MMM d");
        dayNumber = Qt.formatDateTime(now, "d");
        weekdayFull = Qt.formatDateTime(now, "dddd");
        monthDay = Qt.formatDateTime(now, "MMMM d");
    }

    Connections {
        target: ShellState
        function onUse24HourClockChanged() {
            root.refreshClock();
        }
    }

    Component.onCompleted: refreshClock()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.refreshClock()
    }

    // Battery (UPower) + Low / Critical warning notifications
    readonly property bool hasBattery: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
    readonly property int batteryPercent: UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) : 100
    readonly property bool batteryCharging: UPower.displayDevice
        ? (UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged)
        : false

    property bool _warnedLow: false
    property bool _warnedCrit: false

    function checkBatteryWarnings() {
        if (!hasBattery || !ShellState.ready) return;
        if (batteryCharging || batteryPercent > ShellState.batteryWarnThreshold) {
            _warnedLow = false;
            _warnedCrit = false;
            return;
        }
        if (batteryPercent <= ShellState.batteryCriticalThreshold && !_warnedCrit) {
            _warnedCrit = true;
            _warnedLow = true;
            Notifications.pushMock(JSON.stringify({
                appName: "Battery",
                appIcon: "battery-caution",
                summary: "Critical battery (" + batteryPercent + "%)",
                body: "Plug in your charger immediately to avoid shutdown."
            }));
        } else if (batteryPercent <= ShellState.batteryWarnThreshold && !_warnedLow) {
            _warnedLow = true;
            Notifications.pushMock(JSON.stringify({
                appName: "Battery",
                appIcon: "battery-low",
                summary: "Low battery (" + batteryPercent + "%)",
                body: "Connect your charger soon."
            }));
        }
    }

    onBatteryPercentChanged: checkBatteryWarnings()
    onBatteryChargingChanged: checkBatteryWarnings()

    // Audio (PipeWire)
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property real volume: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
        ? Pipewire.defaultAudioSink.audio.volume : 0
    readonly property bool muted: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
        ? Pipewire.defaultAudioSink.audio.muted : false
    readonly property real micVolume: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio)
        ? Pipewire.defaultAudioSource.audio.volume : 0
    readonly property bool micMuted: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio)
        ? Pipewire.defaultAudioSource.audio.muted : false

    // Built-in Audio Mixer state (outputs, inputs, per-app streams via pactl JSON)
    property var audioSinks: []
    property var audioSources: []
    property var audioApps: []

    function setVolume(val) {
        const clamped = Math.max(0, Math.min(1.0, val));
        if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) {
            Pipewire.defaultAudioSink.audio.volume = clamped;
            if (clamped > 0 && Pipewire.defaultAudioSink.audio.muted) {
                Pipewire.defaultAudioSink.audio.muted = false;
            }
        } else {
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", Math.round(clamped * 100) + "%"]);
        }
    }

    function setMicVolume(val) {
        const clamped = Math.max(0, Math.min(1.0, val));
        if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) {
            Pipewire.defaultAudioSource.audio.volume = clamped;
            if (clamped > 0 && Pipewire.defaultAudioSource.audio.muted) {
                Pipewire.defaultAudioSource.audio.muted = false;
            }
        } else {
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", Math.round(clamped * 100) + "%"]);
        }
    }

    function toggleMute() {
        if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) {
            Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted;
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        }
    }

    function toggleMicMute() {
        if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) {
            Pipewire.defaultAudioSource.audio.muted = !Pipewire.defaultAudioSource.audio.muted;
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]);
        }
    }

    Process {
        id: audioDetailsProc
        command: [
            "python3", "-c",
            "import json, subprocess\n" +
            "def run(cmd):\n" +
            "    try: return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()\n" +
            "    except Exception: return ''\n" +
            "def jrun(cmd):\n" +
            "    out = run(cmd)\n" +
            "    try: return json.loads(out) if out else []\n" +
            "    except Exception: return []\n" +
            "def avg_vol(v):\n" +
            "    if not isinstance(v, dict) or not v: return 0.0\n" +
            "    vals = [int(str(ch.get('value_percent','0%')).replace('%','')) for ch in v.values() if isinstance(ch, dict)]\n" +
            "    return round(min(1.5, max(0.0, (sum(vals)/len(vals))/100.0)), 3) if vals else 0.0\n" +
            "def_sink = run(['pactl', 'get-default-sink'])\n" +
            "def_src = run(['pactl', 'get-default-source'])\n" +
            "sinks = [{'name': s.get('name',''), 'description': s.get('description') or s.get('name','Output'), 'isDefault': s.get('name') == def_sink, 'muted': bool(s.get('mute')), 'volume': avg_vol(s.get('volume'))} for s in jrun(['pactl','-f','json','list','sinks'])]\n" +
            "sources = [{'name': s.get('name',''), 'description': s.get('description') or s.get('name','Input'), 'isDefault': s.get('name') == def_src, 'muted': bool(s.get('mute')), 'volume': avg_vol(s.get('volume'))} for s in jrun(['pactl','-f','json','list','sources']) if not str(s.get('name','')).endswith('.monitor')]\n" +
            "apps = []\n" +
            "for a in jrun(['pactl','-f','json','list','sink-inputs']):\n" +
            "    p = a.get('properties') or {}\n" +
            "    name = p.get('application.name') or p.get('media.name') or 'Audio stream'\n" +
            "    media = p.get('media.name') or ''\n" +
            "    apps.append({'id': a.get('index', -1), 'name': name, 'media': media if media != name else '', 'muted': bool(a.get('mute')), 'volume': avg_vol(a.get('volume'))})\n" +
            "print(json.dumps({'sinks': sinks, 'sources': sources, 'apps': apps}))"
        ]
        stdout: SplitParser {
            onRead: line => {
                if (!line || !line.trim()) return;
                try {
                    const data = JSON.parse(line);
                    root.audioSinks = Array.isArray(data.sinks) ? data.sinks : [];
                    root.audioSources = Array.isArray(data.sources) ? data.sources : [];
                    root.audioApps = Array.isArray(data.apps) ? data.apps : [];
                } catch (e) {
                    console.warn("SystemStatus: audio JSON parse error:", e);
                }
            }
        }
    }

    Timer {
        id: refreshAudioSoon
        interval: 260
        onTriggered: root.refreshAudioDetails()
    }

    function refreshAudioDetails() {
        if (!audioDetailsProc.running) audioDetailsProc.running = true;
    }

    function setDefaultSink(sinkName) {
        if (!sinkName) return;
        Quickshell.execDetached(["pactl", "set-default-sink", sinkName]);
        refreshAudioSoon.restart();
    }

    function setDefaultSource(sourceName) {
        if (!sourceName) return;
        Quickshell.execDetached(["pactl", "set-default-source", sourceName]);
        refreshAudioSoon.restart();
    }

    function setAppVolume(inputId, val) {
        const clamped = Math.max(0, Math.min(1.0, val));
        const pct = Math.round(clamped * 100);
        // Optimistic update so slider drags smoothly
        root.audioApps = root.audioApps.map(a => a.id === inputId
            ? Object.assign({}, a, { volume: clamped, muted: clamped > 0 ? false : a.muted })
            : a);
        Quickshell.execDetached(["pactl", "set-sink-input-volume", String(inputId), pct + "%"]);
        if (clamped > 0) {
            Quickshell.execDetached(["pactl", "set-sink-input-mute", String(inputId), "0"]);
        }
    }

    function toggleAppMute(inputId) {
        root.audioApps = root.audioApps.map(a => a.id === inputId
            ? Object.assign({}, a, { muted: !a.muted })
            : a);
        Quickshell.execDetached(["pactl", "set-sink-input-mute", String(inputId), "toggle"]);
        refreshAudioSoon.restart();
    }

    // Brightness (instant udevadm + sysfs FileView + brightnessctl)
    property real brightness: 0.6
    property bool hasBrightness: true
    property string backlightDir: ""
    property int maxBrightness: 100

    Process {
        id: blDetectProc
        command: ["sh", "-c", "d=$(ls -d /sys/class/backlight/* 2>/dev/null | head -n1); [ -n \"$d\" ] && printf '%s|%s\\n' \"$d\" \"$(cat \"$d/max_brightness\")\""]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split("|");
                if (parts.length === 2 && parts[0]) {
                    root.backlightDir = parts[0];
                    root.maxBrightness = Math.max(1, parseInt(parts[1], 10) || 100);
                    root.hasBrightness = true;
                }
            }
        }
    }

    FileView {
        id: blFile
        path: root.backlightDir ? (root.backlightDir + "/brightness") : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = parseInt(text().trim(), 10);
            if (!isNaN(raw) && root.maxBrightness > 0) {
                root.brightness = Math.max(0.01, Math.min(1.0, raw / root.maxBrightness));
            }
        }
    }

    Process {
        id: brightReadProc
        command: ["brightnessctl", "-m"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(",");
                if (parts.length >= 4) {
                    const pct = parseInt(parts[3].replace("%", ""), 10);
                    if (!isNaN(pct)) {
                        root.brightness = Math.max(0.01, Math.min(1.0, pct / 100.0));
                        root.hasBrightness = true;
                    }
                }
            }
        }
    }

    Process {
        id: brightMonitorProc
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=backlight"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("change") !== -1) {
                    if (root.backlightDir) blFile.reload();
                    else if (!brightReadProc.running) brightReadProc.running = true;
                }
            }
        }
    }

    function setBrightness(val) {
        const pct = Math.max(2, Math.min(100, Math.round(val * 100)));
        brightness = pct / 100.0;
        Quickshell.execDetached(["brightnessctl", "set", pct + "%"]);
    }

    function stepBrightness(deltaPct) {
        const arg = deltaPct >= 0 ? (deltaPct + "%+") : (Math.abs(deltaPct) + "%-");
        Quickshell.execDetached(["brightnessctl", "set", arg]);
    }

    // =========================================================================
    // Wi-Fi (nmcli status + network list + connect/disconnect)
    // =========================================================================
    property bool wifiEnabled: true
    property bool wifiConnected: true
    property string wifiSsid: ""
    property int wifiSignal: 100
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string wifiStatusMsg: ""

    function wifiIconForSignal(sig) {
        if (!wifiEnabled) return "󰤭";
        if (!wifiConnected) return "󰤮";
        if (sig >= 85) return "󰤨";
        if (sig >= 65) return "󰤥";
        if (sig >= 40) return "󰤢";
        return "󰤟";
    }

    property var _wifiBuf: []

    Process {
        id: wifiProc
        command: ["sh", "-c", "printf '%s|%s\\n' \"$(nmcli radio wifi 2>/dev/null)\" \"$(nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi list --rescan no 2>/dev/null | awk -F: '$1==\"yes\"{print $2 \"|\" $3; exit}')\""]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split("|");
                if (parts.length >= 2) {
                    root.wifiEnabled = parts[0] === "enabled";
                    root.wifiSsid = parts[1];
                    root.wifiConnected = root.wifiEnabled && root.wifiSsid.length > 0;
                    if (parts.length >= 3) {
                        const sig = parseInt(parts[2], 10);
                        if (!isNaN(sig)) root.wifiSignal = sig;
                    }
                }
            }
        }
    }

    Process {
        id: wifiListProc
        stdout: SplitParser {
            onRead: line => {
                // Format: IN-USE:SSID:SIGNAL:SECURITY (note escaped colons in nmcli -t)
                const raw = line.trim();
                if (!raw) return;
                const parts = raw.split(":");
                if (parts.length < 3) return;
                const inUse = parts[0] === "*";
                const security = parts[parts.length - 1];
                const signal = parseInt(parts[parts.length - 2], 10) || 0;
                const ssid = parts.slice(1, parts.length - 2).join(":").trim();
                if (!ssid) return;
                root._wifiBuf.push({
                    ssid: ssid,
                    inUse: inUse,
                    signal: signal,
                    secured: security.length > 0 && security !== "--"
                });
            }
        }
        onExited: {
            // Deduplicate by SSID keeping strongest / connected entry
            const bySsid = {};
            for (const net of root._wifiBuf) {
                const cur = bySsid[net.ssid];
                if (!cur || net.inUse || (!cur.inUse && net.signal > cur.signal)) {
                    bySsid[net.ssid] = net;
                }
            }
            const list = Object.values(bySsid);
            list.sort((a, b) => (b.inUse ? 1 : 0) - (a.inUse ? 1 : 0) || b.signal - a.signal);
            root.wifiNetworks = list.slice(0, 12);
            root._wifiBuf = [];
            root.wifiScanning = false;
        }
    }

    Process {
        id: wifiConnectProc
        stdout: SplitParser {
            onRead: line => { if (line.trim()) root.wifiStatusMsg = line.trim(); }
        }
        stderr: SplitParser {
            onRead: line => { if (line.trim()) root.wifiStatusMsg = line.trim(); }
        }
        onExited: code => {
            if (code === 0) root.wifiStatusMsg = "";
            refreshStatusSoon.restart();
            refreshWifiNetworks(false);
        }
    }

    function toggleWifi() {
        const next = !wifiEnabled;
        wifiEnabled = next;
        Quickshell.execDetached(["nmcli", "radio", "wifi", next ? "on" : "off"]);
        refreshStatusSoon.restart();
    }

    function refreshWifiNetworks(rescan) {
        if (wifiNetworks.length === 0 && wifiConnected && wifiSsid.length > 0) {
            wifiNetworks = [{
                ssid: wifiSsid,
                inUse: true,
                signal: 100,
                secured: true
            }];
        }
        if (wifiListProc.running) return;
        _wifiBuf = [];
        wifiScanning = Boolean(rescan);
        wifiListProc.command = [
            "nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY",
            "dev", "wifi", "list", "--rescan", rescan ? "yes" : "no"
        ];
        wifiListProc.running = true;
    }

    function connectWifi(ssid, password) {
        if (!ssid) return;
        wifiStatusMsg = "Connecting to " + ssid + "...";
        if (wifiConnectProc.running) wifiConnectProc.running = false;
        if (password && password.length > 0) {
            wifiConnectProc.command = ["nmcli", "dev", "wifi", "connect", ssid, "password", password];
        } else {
            // Try saved profile first, then direct connect
            wifiConnectProc.command = ["sh", "-c", "nmcli con up \"$1\" 2>/dev/null || nmcli dev wifi connect \"$1\"", "_", ssid];
        }
        wifiConnectProc.running = true;
    }

    function disconnectWifi(ssid) {
        if (!ssid) return;
        Quickshell.execDetached(["nmcli", "con", "down", ssid]);
        refreshStatusSoon.restart();
        refreshWifiSoon.restart();
    }

    Timer {
        id: refreshWifiSoon
        interval: 900
        onTriggered: root.refreshWifiNetworks(false)
    }

    // =========================================================================
    // Bluetooth (bluetoothctl power + device list + connect/disconnect/scan)
    // =========================================================================
    property bool btAvailable: false
    property bool btPowered: false
    property var btDevices: []
    property string btConnectedName: ""
    property bool btScanning: false
    property string btStatusMsg: ""

    property var _btBuf: []

    Process {
        id: btProc
        command: [
            "sh", "-c",
            "info=$(bluetoothctl show 2>/dev/null); " +
            "if echo \"$info\" | grep -q '^Controller '; then avail=1; else avail=0; fi; " +
            "pwr=$(echo \"$info\" | awk '/Powered:/{print $2; exit}'); " +
            "cname=$(bluetoothctl devices Connected 2>/dev/null | awk '$1==\"Device\" && $2 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/{$1=\"\"; $2=\"\"; sub(/^  /, \"\"); print; exit}'); " +
            "printf '%s|%s|%s\\n' \"$avail\" \"$pwr\" \"$cname\""
        ]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split("|");
                if (parts.length >= 3) {
                    root.btAvailable = parts[0] === "1";
                    root.btPowered = root.btAvailable && parts[1] === "yes";
                    root.btConnectedName = root.btAvailable ? parts.slice(2).join("|").trim() : "";
                    if (root.btAvailable) {
                        root.btStatusMsg = "";
                    }
                }
            }
        }
    }

    Process {
        id: btListProc
        command: [
            "sh", "-c",
            "conn=$(bluetoothctl devices Connected 2>/dev/null | awk '$1==\"Device\" && $2 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/{print $2}'); " +
            "bluetoothctl devices 2>/dev/null | awk '$1==\"Device\" && $2 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/{mac=$2; $1=\"\"; $2=\"\"; sub(/^  /, \"\"); print mac \"\\t\" $0}' | " +
            "while IFS=$(printf '\\t') read -r mac name; do " +
            "  [ -z \"$mac\" ] && continue; " +
            "  is_c=0; echo \"$conn\" | grep -qxF \"$mac\" && is_c=1; " +
            "  printf '%s|%s|%s\\n' \"$is_c\" \"$mac\" \"$name\"; " +
            "done"
        ]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split("|");
                if (parts.length >= 3 && /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(parts[1])) {
                    root._btBuf.push({
                        connected: parts[0] === "1",
                        mac: parts[1],
                        name: parts.slice(2).join("|") || parts[1]
                    });
                }
            }
        }
        onExited: {
            const list = root._btBuf;
            list.sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0) || a.name.localeCompare(b.name));
            root.btDevices = list.slice(0, 12);
            root._btBuf = [];
        }
    }

    Process {
        id: btScanProc
        command: ["bluetoothctl", "--timeout", "6", "scan", "on"]
        onExited: {
            root.btScanning = false;
            root.refreshBtDevices();
        }
    }

    function toggleBluetooth() {
        if (!btAvailable) {
            btStatusMsg = "No Bluetooth adapter detected";
            Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth 2>/dev/null; bluetoothctl power on 2>/dev/null"]);
            refreshStatusSoon.restart();
            return;
        }
        const next = !btPowered;
        btPowered = next;
        btStatusMsg = "";
        if (next) {
            Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth 2>/dev/null; bluetoothctl power on"]);
        } else {
            Quickshell.execDetached(["bluetoothctl", "power", "off"]);
        }
        refreshStatusSoon.restart();
        refreshBtSoon.restart();
    }

    function refreshBtDevices() {
        if (!btProc.running) btProc.running = true;
        if (!btAvailable) {
            btDevices = [];
            return;
        }
        if (btListProc.running) return;
        _btBuf = [];
        btListProc.running = true;
    }

    function scanBluetooth() {
        if (!btAvailable || !btPowered || btScanProc.running) return;
        btScanning = true;
        btScanProc.running = true;
    }

    function toggleBtDevice(mac, connected) {
        if (!mac) return;
        Quickshell.execDetached(["bluetoothctl", connected ? "disconnect" : "connect", mac]);
        refreshStatusSoon.restart();
        refreshBtSoon.restart();
    }

    Timer {
        id: refreshBtSoon
        interval: 1200
        onTriggered: root.refreshBtDevices()
    }

    // Fingerprint reader + enrolled finger detection (so systems without fprintd/reader stay clean)
    property bool hasFingerprint: false

    Process {
        id: fprintCheckProc
        command: ["sh", "-c", "command -v fprintd-verify >/dev/null 2>&1 && fprintd-list \"$USER\" 2>/dev/null | grep -q ' - #' && echo 1 || echo 0"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                root.hasFingerprint = line.trim() === "1";
            }
        }
    }

    // Power Profiles Daemon (powerprofilesctl)
    property bool hasPowerProfiles: false
    property string powerProfile: "balanced"
    readonly property string powerProfileLabel: powerProfile === "performance"
        ? "Performance"
        : (powerProfile === "power-saver" ? "Power saver" : "Balanced")

    Process {
        id: ppdProc
        command: ["sh", "-c", "command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get 2>/dev/null || echo ''"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const p = line.trim();
                if (p === "power-saver" || p === "balanced" || p === "performance") {
                    root.hasPowerProfiles = true;
                    root.powerProfile = p;
                }
            }
        }
    }

    function cyclePowerProfile() {
        if (!hasPowerProfiles) return;
        const order = ["power-saver", "balanced", "performance"];
        const idx = order.indexOf(powerProfile);
        const next = order[(idx + 1) % order.length];
        powerProfile = next;
        Quickshell.execDetached(["powerprofilesctl", "set", next]);
        refreshStatusSoon.restart();
    }

    // Power / session actions
    function lockSession() {
        ShellState.lock();
    }
    function suspendSystem() {
        Quickshell.execDetached(["systemctl", "suspend"]);
    }
    function rebootSystem() {
        Quickshell.execDetached(["systemctl", "reboot"]);
    }
    function poweroffSystem() {
        Quickshell.execDetached(["systemctl", "poweroff"]);
    }

    Timer {
        id: refreshStatusSoon
        interval: 900
        onTriggered: {
            if (!wifiProc.running) wifiProc.running = true;
            if (!btProc.running) btProc.running = true;
            if (!brightReadProc.running) brightReadProc.running = true;
        }
    }

    Timer {
        interval: 6000
        running: true
        repeat: true
        onTriggered: {
            if (!wifiProc.running) wifiProc.running = true;
            if (!btProc.running) btProc.running = true;
            if (!brightReadProc.running) brightReadProc.running = true;
        }
    }
}
