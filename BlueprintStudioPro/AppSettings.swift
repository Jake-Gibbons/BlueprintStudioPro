import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    // Canvas
    @Published var showGrid: Bool = true
    @Published var gridStepMeters: CGFloat = 1.0
    
    // Visuals
    @Published var backgroundColor: Color = Color(white: 1.0)
    @Published var roomFillOpacity: Double = 0.10
    
    // Walls
    @Published var externalWallWidthPt: CGFloat = 5.0
    @Published var internalWallWidthPt: CGFloat = 2.5
    
    // Dimensions
    @Published var showDimensions: Bool = true
    @Published var dimensionFontSize: CGFloat = 10.0
}
