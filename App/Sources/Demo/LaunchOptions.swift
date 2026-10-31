import Foundation

/// The screen demo mode opens on, chosen with `-CrateScreen <name>`.
enum StartScreen: String, CaseIterable {
    /// Scan tab. On the Simulator this shows the no-camera fallback.
    case scan
    /// Scan tab with the manual entry sheet open and a catalogue number typed.
    case manual
    /// A barcode lookup that identifies one pressing: on the wantlist, with a
    /// different pressing owned, and prices.
    case result
    /// A catalogue number shared by two pressings, with the run-outs that tell them apart.
    case pressings
    case wantlist
    case collection
    case diglog
    case settings
}

/// Reads launch arguments. Demo mode only exists in Debug builds: a Release
/// build ignores the arguments and always runs normally.
///
/// Launch arguments of the form `-Key value` land in the UserDefaults argument
/// domain for that launch only, so nothing here is persisted.
///
///     -CrateDemo YES              seed invented data, use no network or Keychain
///     -CrateScreen result         open on a given screen (see StartScreen)
enum LaunchOptions {
    static var isDemo: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CrateDemo")
        #else
        false
        #endif
    }

    /// Only honoured in demo mode.
    static var startScreen: StartScreen? {
        guard isDemo, let raw = UserDefaults.standard.string(forKey: "CrateScreen") else { return nil }
        return StartScreen(rawValue: raw.lowercased())
    }
}
