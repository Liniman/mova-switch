import Carbon
import Foundation

enum KeyboardLayoutError: LocalizedError {
	case missingInputSource(SupportedLayout)
	case missingLayoutData(SupportedLayout)

	var errorDescription: String? {
		switch self {
		case .missingInputSource(let layout):
			return "The \(layout.displayName) input source is not enabled."
		case .missingLayoutData(let layout):
			return "The \(layout.displayName) input source has no Unicode layout data."
		}
	}
}

/// Reads the installed U.S. and Ukrainian-PC layouts through TIS and `UCKeyTranslate`.
final class KeyboardLayoutTranslator: LayoutTranslating, InputSourceControl {
	private var sources: [SupportedLayout: TISInputSource] = [:]
	private var layoutData: [SupportedLayout: Data] = [:]
	private var characters: [SupportedLayout: [UInt32: Character]] = [:]
	private var keysByCharacter: [SupportedLayout: [Character: (keyCode: UInt16, shifted: Bool)]] = [:]

	init() throws {
		let inputSources = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
		for case let source as TISInputSource in inputSources {
			guard let identifier = Self.stringProperty(source, key: kTISPropertyInputSourceID),
				  let layout = SupportedLayout(rawValue: identifier) else { continue }
			sources[layout] = source
		}

		for layout in SupportedLayout.allCases {
			guard let source = sources[layout] else {
				throw KeyboardLayoutError.missingInputSource(layout)
			}
			guard let data = Self.dataProperty(source, key: kTISPropertyUnicodeKeyLayoutData) else {
				throw KeyboardLayoutError.missingLayoutData(layout)
			}
			layoutData[layout] = data
			var table: [UInt32: Character] = [:]
			for keyCode in UInt16(0)...UInt16(127) {
				for shifted in [false, true] {
					if let character = translate(keyCode: keyCode, shifted: shifted, layout: layout) {
						table[Self.slot(keyCode, shifted)] = character
					}
				}
			}
			characters[layout] = table
			var reverse: [Character: (keyCode: UInt16, shifted: Bool)] = [:]
			for keyCode in UInt16(0)...UInt16(127) {
				for shifted in [false, true] {
					guard let character = table[Self.slot(keyCode, shifted)], reverse[character] == nil else { continue }
					reverse[character] = (keyCode, shifted)
				}
			}
			keysByCharacter[layout] = reverse
		}
	}

	func character(keyCode: UInt16, shifted: Bool, layout: SupportedLayout) -> Character? {
		characters[layout]?[Self.slot(keyCode, shifted)]
	}

	/// A key belongs to a word when either layout renders it as a letter or an apostrophe.
	func isWordKey(_ keyCode: UInt16, shifted: Bool) -> Bool {
		SupportedLayout.allCases.contains { layout in
			guard let character = character(keyCode: keyCode, shifted: shifted, layout: layout) else { return false }
			return character.isLetter || "'ʼ’".contains(character)
		}
	}

	func text(for strokes: [PhysicalKeyStroke], using layout: SupportedLayout) -> String? {
		var result = ""
		for stroke in strokes {
			guard let character = character(keyCode: stroke.keyCode, shifted: stroke.shifted, layout: layout) else {
				return nil
			}
			result.append(character)
		}
		return result
	}

	func selectionConversion(for text: String) -> SelectionConversion? {
		let letters = text.filter(\.isLetter)
		guard !letters.isEmpty else { return nil }
		let candidates = SupportedLayout.allCases.filter { layout in
			letters.allSatisfy { keysByCharacter[layout]?[$0] != nil }
		}
		guard candidates.count == 1, let source = candidates.first else { return nil }

		var replacement = ""
		for character in text {
			if character.isWhitespace {
				replacement.append(character)
				continue
			}
			guard let key = keysByCharacter[source]?[character],
				  let translated = self.character(keyCode: key.keyCode, shifted: key.shifted, layout: source.other) else {
				return nil
			}
			replacement.append(translated)
		}
		guard replacement != text else { return nil }
		return SelectionConversion(source: source, target: source.other, replacement: replacement)
	}

	func currentLayout() -> SupportedLayout? {
		let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
		guard let identifier = Self.stringProperty(source, key: kTISPropertyInputSourceID) else { return nil }
		return SupportedLayout(rawValue: identifier)
	}

	@discardableResult
	func select(_ layout: SupportedLayout) -> Bool {
		guard let source = sources[layout] else { return false }
		return TISSelectInputSource(source) == noErr
	}

	private static func slot(_ keyCode: UInt16, _ shifted: Bool) -> UInt32 {
		UInt32(keyCode) << 1 | (shifted ? 1 : 0)
	}

	private func translate(keyCode: UInt16, shifted: Bool, layout: SupportedLayout) -> Character? {
		guard let data = layoutData[layout] else { return nil }
		var deadKeyState: UInt32 = 0
		var length = 0
		var buffer = [UniChar](repeating: 0, count: 8)
		let modifier = shifted ? UInt32(shiftKey >> 8) : 0
		let status = data.withUnsafeBytes { bytes -> OSStatus in
			guard let baseAddress = bytes.baseAddress else { return OSStatus(paramErr) }
			let keyboardLayout = baseAddress.assumingMemoryBound(to: UCKeyboardLayout.self)
			return UCKeyTranslate(
				keyboardLayout,
				keyCode,
				UInt16(kUCKeyActionDown),
				modifier,
				UInt32(LMGetKbdType()),
				OptionBits(kUCKeyTranslateNoDeadKeysMask),
				&deadKeyState,
				buffer.count,
				&length,
				&buffer
			)
		}
		guard status == noErr, length > 0 else { return nil }
		let value = String(utf16CodeUnits: buffer, count: length)
		guard value.count == 1, let character = value.first, !character.isWhitespace else { return nil }
		return character
	}

	private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
		guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
		return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
	}

	private static func dataProperty(_ source: TISInputSource, key: CFString) -> Data? {
		guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
		return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
	}
}
