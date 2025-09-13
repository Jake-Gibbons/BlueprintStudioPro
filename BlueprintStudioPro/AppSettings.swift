import Foundation
import SwiftUI
import Combine

/// Persistent app-wide settings backed by UserDefaults.
final class AppSettings: ObservableObject {
    // Keys
    private enum K {
        static let defaultSnap = "settings.defaultSnap"
        static let defaultShowDimensions = "settings.defaultShowDimensions"
        static let theme = "settings.theme"                  // "system" | "light" | "dark"
        static let haptics = "settings.hapticsEnabled"
        static let autosave = "settings.autosaveEnabled"
    }

    @Published var defaultSnap: Bool {
        didSet { UserDefaults.standard.set(defaultSnap, forKey: K.defaultSnap) }
    }

    @Published var defaultShowDimensions: Bool {
        didSet { UserDefaults.standard.set(defaultShowDimensions, forKey: K.defaultShowDimensions) }
    }

    enum Theme: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }

    @Published var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: K.theme) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: K.haptics) }
    }

    @Published var autosaveEnabled: Bool {
        didSet { UserDefaults.standard.set(autosaveEnabled, forKey: K.autosave) }
    }

    init() {
        let d = UserDefaults.standard
        self.defaultSnap = d.object(forKey: K.defaultSnap) as? Bool ?? true
        self.defaultShowDimensions = d.object(forKey: K.defaultShowDimensions) as? Bool ?? true
        self.theme = Theme(rawValue: d.string(forKey: K.theme) ?? "system") ?? .system
        self.hapticsEnabled = d.object(forKey: K.haptics) as? Bool ?? true
        self.autosaveEnabled = d.object(forKey: K.autosave) as? Bool ?? true
    }
}
