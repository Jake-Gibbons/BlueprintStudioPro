import SwiftUI
import Combine

/// Global settings shared throughout the app.  This object allows users to
/// control display attributes such as the scale between model metres and
/// on‑screen points.  It is intentionally simple and can be extended as
/// needed.  A default value of 100 points per metre yields reasonably
/// sized rooms on most devices.
final class AppSettings: ObservableObject {
    // Canvas
    /// Toggle displaying a grid overlay on the canvas.  When enabled the
    /// floor plan will show evenly spaced lines representing metres.
    @Published var showGrid: Bool = true
    /// The spacing between grid lines in model metres.  A value of 1.0 means
    /// lines are drawn every metre.
    @Published var gridStepMeters: CGFloat = 1.0

    // Visuals
    /// Background colour for the canvas.
    @Published var backgroundColor: Color = Color(white: 1.0)
    /// Opacity of the room fill.  Smaller values make rooms more transparent.
    @Published var roomFillOpacity: Double = 0.10

    // Walls
    /// Thickness of external walls in points.
    @Published var externalWallWidthPt: CGFloat = 5.0
    /// Thickness of internal walls in points.
    @Published var internalWallWidthPt: CGFloat = 2.5

    // Dimensions
    /// Show or hide dimension labels on the floor plan.
    @Published var showDimensions: Bool = true
    /// Base font size for dimension labels.
    @Published var dimensionFontSize: CGFloat = 10.0

    // Scaling
    /// The number of screen points corresponding to one metre in the model.  A
    /// larger value will make rooms appear bigger on screen and a smaller
    /// value will make them smaller.  Changing this value dynamically will
    /// automatically cause views observing this object to update.
    @Published var pointsPerMeter: CGFloat = 100
}
