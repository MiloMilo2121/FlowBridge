import Foundation

#if canImport(SwiftUI)
import SwiftUI

/// Brand palette shared by the app and the widget extension. Programmatic
/// values (not asset-catalog colors) so every target resolves them without
/// bundling the catalog. Discipline: the violet accent is reserved for
/// identity and the listening/polishing states; success and danger stay
/// system-semantic; everything else is monochrome on materials.
public enum FlowBridgeTheme {
    /// Signature accent — luminous violet tuned for dark surfaces.
    public static let flowViolet = Color(red: 0.486, green: 0.424, blue: 1.0)       // #7C6CFF
    /// Deeper anchor of the accent family, for gradients and light mode.
    public static let flowVioletDeep = Color(red: 0.357, green: 0.298, blue: 0.961) // #5B4CF5

    /// Warm pair used only while recording.
    public static let recordingWarm = Color(red: 1.0, green: 0.45, blue: 0.38)
    public static let recordingHot = Color(red: 1.0, green: 0.62, blue: 0.29)

    /// Waveform fill while recording: red rising into orange.
    public static let recordingGradient = LinearGradient(
        colors: [recordingWarm, recordingHot],
        startPoint: .bottom,
        endPoint: .top
    )

    /// Waveform fill while polishing / brand surfaces.
    public static let accentGradient = LinearGradient(
        colors: [flowVioletDeep, flowViolet],
        startPoint: .bottom,
        endPoint: .top
    )
}
#endif
