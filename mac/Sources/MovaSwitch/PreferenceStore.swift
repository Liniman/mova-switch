import Foundation

/// Persistent settings. The only typed text stored is the never-convert exception list.
final class PreferenceStore: ExceptionStoring {
	private enum Key {
		static let enabled = "enabled"
		static let soundEnabled = "soundEnabled"
		static let appModes = "appModes"
		static let exceptions = "layoutExceptions"
		static let core = "decisionCore"
	}

	/// Terminals, remote sessions and password managers default to manual conversion only.
	static let defaultManualOnlyBundleIDs: Set<String> = [
		"com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
		"org.alacritty", "com.github.wez.wezterm", "dev.warp.Warp-Stable", "co.zeit.hyper",
		"com.apple.ScreenSharing", "com.microsoft.rdc.macos", "com.parallels.desktop.console",
		"com.vmware.fusion", "com.utmapp.UTM", "com.1password.1password", "com.agilebits.onepassword7",
		"com.bitwarden.desktop", "com.apple.Passwords", "com.apple.keychainaccess",
	]

	private let defaults: UserDefaults

	init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	var enabled: Bool {
		get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
		set { defaults.set(newValue, forKey: Key.enabled) }
	}

	var soundEnabled: Bool {
		get { defaults.object(forKey: Key.soundEnabled) as? Bool ?? true }
		set { defaults.set(newValue, forKey: Key.soundEnabled) }
	}

	/// `builtin` selects the Swift fallback core. Anything else selects the Rust engine.
	var prefersBuiltinCore: Bool {
		defaults.string(forKey: Key.core) == "builtin"
	}

	func mode(for bundleID: String) -> AppMode {
		if let raw = (defaults.dictionary(forKey: Key.appModes) as? [String: String])?[bundleID],
		   let mode = AppMode(rawValue: raw) {
			return mode
		}
		return Self.defaultManualOnlyBundleIDs.contains(bundleID) ? .manualOnly : .auto
	}

	func setMode(_ mode: AppMode, for bundleID: String) {
		var modes = defaults.dictionary(forKey: Key.appModes) as? [String: String] ?? [:]
		modes[bundleID] = mode.rawValue
		defaults.set(modes, forKey: Key.appModes)
	}

	var exceptions: Set<LearnedException> {
		let stored = defaults.stringArray(forKey: Key.exceptions) ?? []
		return Set(stored.compactMap { entry in
			let parts = entry.split(separator: "\t", maxSplits: 1).map(String.init)
			guard parts.count == 2, let layout = SupportedLayout(rawValue: parts[0]) else { return nil }
			return LearnedException(layout: layout, text: parts[1])
		})
	}

	func add(_ exception: LearnedException) {
		var updated = exceptions
		updated.insert(LearnedException(layout: exception.layout, text: exception.text.lowercased()))
		defaults.set(updated.map { "\($0.layout.rawValue)\t\($0.text)" }.sorted(), forKey: Key.exceptions)
	}

	func removeAllExceptions() {
		defaults.removeObject(forKey: Key.exceptions)
	}
}
