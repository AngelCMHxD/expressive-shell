pragma Singleton
import QtQuick
import Quickshell

// Material 3 Expressive motion tokens
Singleton {
    // Expressive spatial spring (subtle overshoot for pop-ins & morphs)
    readonly property real spatialSpring: 9.0
    readonly property real spatialDamping: 0.46

    // Pop-y spring for shades, toasts, and OSDs (snappy M3E overshoot)
    readonly property real popSpring: 13.0
    readonly property real popDamping: 0.44

    // Snappy spring for pill width & workspace morphs
    readonly property real morphSpring: 8.5
    readonly property real morphDamping: 0.46

    // Durations (ms)
    readonly property int fast: 160
    readonly property int medium: 280
    readonly property int expressive: 380

    // M3 Emphasized Decelerate bezier
    readonly property list<real> emphasizedDecelerate: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
    readonly property list<real> standardCurve: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
}
