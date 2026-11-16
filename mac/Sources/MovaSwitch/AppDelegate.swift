import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
	private let preferences = PreferenceStore()
	private var statusItem: NSStatusItem!
	private let menu = NSMenu()
	private var core: DecisionCore?
	private var controller: EventTapController?
	private var startupError: String?
	private var frontmostBundleID: String?
	private var frontmostName: String?
	private var watchdog: Timer?
	private var guidedThisUnlock = false
	private var screenLocked = AppDelegate.isScreenLocked

	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		menu.delegate = self
		statusItem.menu = menu
		configureCore()
		observeSystem()
		frontmostApplicationChanged()
		refresh()
		watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
	}

	func applicationWillTerminate(_ notification: Notification) {
		watchdog?.invalidate()
		controller?.stop()
	}

	func menuWillOpen(_ menu: NSMenu) {
		rebuildMenu()
	}

	private func configureCore() {
		do {
			let translator = try KeyboardLayoutTranslator()
			let rust = preferences.prefersBuiltinCore ? nil : RustDecisionCore(exceptionStore: preferences)
			let core: DecisionCore = rust ?? BuiltinDecisionCore(translator: translator, exceptionStore: preferences)
			let selectionConverter = AXSelectionConverter(translator: translator, inputSource: translator)
			let controller = EventTapController(
				core: core,
				translator: translator,
				inputSource: translator,
				selectionConverter: selectionConverter,
				policy: { [weak self] in self?.typingPolicy ?? .inert }
			)
			controller.onRewrite = { [weak self] _ in
				guard let self, self.preferences.soundEnabled else { return }
				NSSound(named: "Tink")?.play()
			}
			controller.onTapStateChange = { [weak self] in self?.updateStatusItem() }
			self.core = core
			self.controller = controller
		} catch {
			startupError = error.localizedDescription
		}
	}

	private func observeSystem() {
		let workspace = NSWorkspace.shared.notificationCenter
		workspace.addObserver(self, selector: #selector(frontmostApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
		workspace.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
		let distributed = DistributedNotificationCenter.default()
		distributed.addObserver(self, selector: #selector(screenDidUnlock), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
		distributed.addObserver(self, selector: #selector(screenDidLock), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
	}

	/// Runs every second. Starting the tap is the permission check: it succeeds the moment
	/// Accessibility is granted, so the app goes live without a relaunch.
	private func refresh() {
		guard let controller, startupError == nil else {
			updateStatusItem()
			return
		}
		if !controller.isRunning {
			controller.start()
		}
		PermissionMarker.update(granted: controller.isRunning)
		if !controller.isRunning && !guidedThisUnlock && !Self.isScreenLocked {
			guidedThisUnlock = true
			guideToAccessibility()
		}
		updateStatusItem()
	}

	private var hasPermission: Bool {
		controller?.isRunning == true
	}

	private var typingPolicy: TypingPolicy {
		guard preferences.enabled, !screenLocked, !IsSecureEventInputEnabled() else { return .inert }
		guard let bundleID = frontmostBundleID else { return .automatic }
		if bundleID == Bundle.main.bundleIdentifier { return .inert }
		switch preferences.mode(for: bundleID) {
		case .auto: return .automatic
		case .manualOnly: return .manualOnly
		case .off: return .inert
		}
	}

	private var runtimeState: RuntimeState {
		if !hasPermission { return .needsPermission }
		if !preferences.enabled { return .disabled }
		if IsSecureEventInputEnabled() { return .secureInput }
		if let bundleID = frontmostBundleID, let name = frontmostName {
			let mode = preferences.mode(for: bundleID)
			if mode != .auto { return .appMode(mode, name) }
		}
		return .active
	}

	private func updateStatusItem() {
		guard let button = statusItem?.button else { return }
		switch runtimeState {
		case .active:
			button.title = "МA"
			button.toolTip = "MovaSwitch is converting"
		case .needsPermission:
			button.title = "МA ⚠︎"
			button.toolTip = "MovaSwitch needs Accessibility permission"
		case .disabled, .secureInput, .appMode:
			button.title = "МA ‖"
			button.toolTip = statusText
		}
	}

	private var statusText: String {
		if let startupError { return startupError }
		switch runtimeState {
		case .active: return "Converting automatically"
		case .needsPermission: return "Needs Accessibility permission"
		case .disabled: return "Off"
		case .secureInput: return "Paused: a password field has secure input on"
		case .appMode(let mode, let app): return "\(app): \(mode.title)"
		}
	}

	private func rebuildMenu() {
		menu.removeAllItems()
		menu.addItem(item(statusText, nil, enabled: false))
		if !hasPermission {
			menu.addItem(item("Grant Accessibility Permission…", #selector(grantPermission)))
		}
		menu.addItem(.separator())

		let enabled = item("Automatic Switching", #selector(toggleEnabled))
		enabled.state = preferences.enabled ? .on : .off
		menu.addItem(enabled)

		if let bundleID = frontmostBundleID, let name = frontmostName, bundleID != Bundle.main.bundleIdentifier {
			let header = item("In \(name)", nil, enabled: false)
			menu.addItem(header)
			let current = preferences.mode(for: bundleID)
			for mode in AppMode.allCases {
				let modeItem = item("    \(mode.title)", #selector(chooseAppMode(_:)))
				modeItem.representedObject = mode.rawValue
				modeItem.state = mode == current ? .on : .off
				menu.addItem(modeItem)
			}
		}

		let sound = item("Sound on Conversion", #selector(toggleSound))
		sound.state = preferences.soundEnabled ? .on : .off
		menu.addItem(sound)
		menu.addItem(item("Never-Convert Words…", #selector(showExceptions)))
		menu.addItem(.separator())
		menu.addItem(item("Tap Right Option to undo, convert a word, or convert a selection", nil, enabled: false))
		menu.addItem(item("Decision core: \(core?.name ?? "unavailable")", nil, enabled: false))
		menu.addItem(.separator())
		menu.addItem(item("Quit Until Next Login", #selector(quitUntilNextLogin)))
	}

	private func item(_ title: String, _ action: Selector?, enabled: Bool = true) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
		item.target = self
		item.isEnabled = enabled
		return item
	}

	/// Shows the standard macOS prompt and opens the Accessibility pane, so the only human
	/// step left is the MovaSwitch toggle.
	private func guideToAccessibility() {
		let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
		_ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
			NSWorkspace.shared.open(url)
		}
	}

	static var isScreenLocked: Bool {
		guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
		return session["CGSSessionScreenIsLocked"] as? Bool ?? false
	}

	@objc private func frontmostApplicationChanged() {
		let app = NSWorkspace.shared.frontmostApplication
		frontmostBundleID = app?.bundleIdentifier
		frontmostName = app?.localizedName
		controller?.reset()
		updateStatusItem()
	}

	@objc private func systemDidWake() {
		screenLocked = Self.isScreenLocked
		controller?.reset()
		controller?.start()
		refresh()
	}

	@objc private func screenDidLock() {
		screenLocked = true
		guidedThisUnlock = true
		controller?.reset()
		updateStatusItem()
	}

	@objc private func screenDidUnlock() {
		screenLocked = false
		guidedThisUnlock = false
		refresh()
	}

	@objc private func grantPermission() {
		guideToAccessibility()
	}

	@objc private func toggleEnabled() {
		preferences.enabled.toggle()
		controller?.reset()
		updateStatusItem()
	}

	@objc private func chooseAppMode(_ sender: NSMenuItem) {
		guard let bundleID = frontmostBundleID, let raw = sender.representedObject as? String,
			  let mode = AppMode(rawValue: raw) else { return }
		preferences.setMode(mode, for: bundleID)
		controller?.reset()
		updateStatusItem()
	}

	@objc private func toggleSound() {
		preferences.soundEnabled.toggle()
	}

	@objc private func showExceptions() {
		let words = preferences.exceptions.map(\.text).sorted()
		let alert = NSAlert()
		alert.messageText = "Never-convert words"
		alert.informativeText = words.isEmpty
			? "None yet. Undo the same conversion twice and the word is added here."
			: words.joined(separator: "\n")
		if !words.isEmpty { alert.addButton(withTitle: "Clear All") }
		alert.addButton(withTitle: "Close")
		NSApp.activate(ignoringOtherApps: true)
		if alert.runModal() == .alertFirstButtonReturn && !words.isEmpty {
			core?.clearExceptions()
		}
	}

	@objc private func quitUntilNextLogin() {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
		process.arguments = ["bootout", "gui/\(getuid())/com.liniman.MovaSwitch"]
		try? process.run()
		NSApp.terminate(nil)
	}
}

/// A file the unlock watcher reads to know it can retire. It holds no typed text.
enum PermissionMarker {
	static let url = FileManager.default.homeDirectoryForCurrentUser
		.appendingPathComponent("Library/Application Support/MovaSwitch/accessibility-granted")

	static func update(granted: Bool) {
		let exists = FileManager.default.fileExists(atPath: url.path)
		if granted && !exists {
			try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
			FileManager.default.createFile(atPath: url.path, contents: Data("granted\n".utf8))
		} else if !granted && exists {
			try? FileManager.default.removeItem(at: url)
		}
	}
}
