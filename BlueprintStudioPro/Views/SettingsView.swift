import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("General")) {
                    Toggle("Snap to Grid by Default", isOn: $settings.defaultSnap)
                    Toggle("Show Dimensions by Default", isOn: $settings.defaultShowDimensions)
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppSettings.Theme.allCases) { t in
                            Text(t.title).tag(t)
                        }
                    }
                }

                Section(header: Text("Interaction")) {
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    Toggle("Autosave", isOn: $settings.autosaveEnabled)
                }

                Section(footer: Text("These settings apply across projects. You can still toggle Snap and Dimensions per-project from the View tab.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Settings")
        }
    }
}
