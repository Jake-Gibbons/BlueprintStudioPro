import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var floorPlan: Floorplan
    
    @State private var workingFloorName: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Project")) {
                    TextField("Current floor name",
                              text: Binding(
                                get: { floorPlan.floors[floorPlan.currentFloorIndex].name },
                                set: { floorPlan.renameCurrentFloor(to: $0) }
                              ))
                }
                
                Section(header: Text("Canvas")) {
                    Toggle("Show Grid", isOn: $settings.showGrid)
                    HStack {
                        Text("Grid Step")
                        Spacer()
                        Slider(value: Binding(get: {
                            Double(settings.gridStepMeters)
                        }, set: { settings.gridStepMeters = CGFloat($0) }),
                               in: 0.25...5.0, step: 0.25)
                        Text("\(settings.gridStepMeters, specifier: "%.2f") m")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    ColorPicker("Background", selection: $settings.backgroundColor, supportsOpacity: false)
                }
                
                Section(header: Text("Walls")) {
                    Stepper(value: $settings.externalWallWidthPt, in: 1...12, step: 0.5) {
                        HStack {
                            Text("External Width")
                            Spacer()
                            Text("\(settings.externalWallWidthPt, specifier: "%.1f") pt")
                                .foregroundColor(.secondary)
                        }
                    }
                    Stepper(value: $settings.internalWallWidthPt, in: 0.5...8, step: 0.5) {
                        HStack {
                            Text("Internal Width")
                            Spacer()
                            Text("\(settings.internalWallWidthPt, specifier: "%.1f") pt")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Rooms")) {
                    HStack {
                        Text("Fill Opacity")
                        Spacer()
                        Slider(value: $settings.roomFillOpacity, in: 0...0.6, step: 0.02)
                        Text("\(settings.roomFillOpacity, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Dimensions")) {
                    Toggle("Show Dimensions", isOn: $settings.showDimensions)
                    Stepper(value: $settings.dimensionFontSize, in: 8...18, step: 1) {
                        HStack {
                            Text("Label Size")
                            Spacer()
                            Text("\(Int(settings.dimensionFontSize)) pt")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
