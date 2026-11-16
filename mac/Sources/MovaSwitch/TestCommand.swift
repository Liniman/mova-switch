import Carbon
import CoreGraphics
import Foundation

/// Command-line hooks for mac/e2e.sh. They post real keyboard events, so they need the same
/// Accessibility grant as the app.
enum TestCommand {
	static func runIfRequested(_ arguments: [String]) -> Int32? {
		guard arguments.count >= 2, arguments[1].hasPrefix("--test-") else { return nil }
		do {
			let translator = try KeyboardLayoutTranslator()
			switch arguments[1] {
			case "--test-layout":
				guard arguments.count == 3, let layout = parseLayout(arguments[2]) else { return usage() }
				guard translator.select(layout) else { return fail("could not select \(layout.rawValue)") }
				Thread.sleep(forTimeInterval: 0.1)
				print("layout=\(translator.currentLayout()?.rawValue ?? "unknown")")
				return 0

			case "--test-current-layout":
				print("layout=\(translator.currentLayout()?.rawValue ?? "unknown")")
				return 0

			case "--test-inject":
				guard arguments.count == 4 else { return usage() }
				guard AXIsProcessTrusted() else { return fail("Accessibility permission is not granted") }
				guard postPhysicalWord(arguments[2], boundary: arguments[3]) else { return fail("unsupported test key") }
				print("injected=\(arguments[2].count)-keys boundary=\(arguments[3])")
				return 0

			case "--test-option-tap":
				guard AXIsProcessTrusted() else { return fail("Accessibility permission is not granted") }
				postOptionTap()
				print("option-tap=posted")
				return 0

			default:
				return usage()
			}
		} catch {
			return fail(error.localizedDescription)
		}
	}

	/// Types `word` as U.S. key positions, as a person would on the wrong layout.
	private static func postPhysicalWord(_ word: String, boundary: String) -> Bool {
		for character in word {
			guard let keyCode = keyCodes[Character(character.lowercased())] else { return false }
			postKey(keyCode, flags: character.isUppercase ? .maskShift : [])
			Thread.sleep(forTimeInterval: 0.02)
		}
		switch boundary {
		case "none": break
		case "space": postKey(49, flags: [])
		case "return": postKey(36, flags: [])
		case "tab": postKey(48, flags: [])
		default: return false
		}
		return true
	}

	private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
		let source = CGEventSource(stateID: .hidSystemState)
		for keyDown in [true, false] {
			guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
			event.flags = flags
			event.post(tap: .cghidEventTap)
		}
	}

	private static func postOptionTap() {
		let source = CGEventSource(stateID: .hidSystemState)
		for (down, flags) in [(true, CGEventFlags.maskAlternate), (false, CGEventFlags())] {
			guard let event = CGEvent(keyboardEventSource: source, virtualKey: 61, keyDown: down) else { continue }
			event.type = .flagsChanged
			event.flags = flags
			event.post(tap: .cghidEventTap)
			Thread.sleep(forTimeInterval: 0.05)
		}
	}

	private static func parseLayout(_ value: String) -> SupportedLayout? {
		switch value {
		case "us": return .us
		case "ukrainian", "ukrainian-pc": return .ukrainianPC
		default: return nil
		}
	}

	private static func usage() -> Int32 {
		fail("usage: --test-layout us|ukrainian, --test-current-layout, --test-inject WORD none|space|return|tab, or --test-option-tap")
	}

	private static func fail(_ message: String) -> Int32 {
		FileHandle.standardError.write(Data((message + "\n").utf8))
		return 2
	}

	static let keyCodes: [Character: CGKeyCode] = [
		"a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
		"b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
		"[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, ",": 43,
		"/": 44, "n": 45, "m": 46, ".": 47, "]": 30, "`": 50,
	]
}
