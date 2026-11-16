import Foundation

/// The Rust engine behind the C ABI in engine/include/mova_engine.h.
final class RustDecisionCore: DecisionCore {
	let name = "Rust engine"

	private let engine: OpaquePointer
	private let exceptionStore: ExceptionStoring

	init?(exceptionStore: ExceptionStoring) {
		guard let engine = mova_engine_new() else { return nil }
		self.engine = engine
		self.exceptionStore = exceptionStore
		for exception in exceptionStore.exceptions {
			load(exception)
		}
	}

	deinit {
		mova_engine_free(engine)
	}

	func handle(_ input: DecisionInput) -> DecisionOutcome {
		switch input {
		case .key(let stroke):
			guard let key = Self.physicalKeys[stroke.keyCode] else {
				mova_engine_reset(engine)
				return .none
			}
			return decode(mova_engine_key(engine, key, stroke.shifted ? 1 : 0, Self.code(stroke.layout)))
		case .edit:
			return decode(mova_engine_edit(engine))
		case .boundary(let layout, let automatic, let isSpace):
			let tokenClass = automatic ? UInt8(MOVA_TOKEN_PLAIN) : UInt8(MOVA_TOKEN_CODE)
			return decode(mova_engine_boundary(engine, Self.code(layout), tokenClass, isSpace ? 1 : 0))
		case .undo:
			return decode(mova_engine_undo(engine))
		case .convert:
			return decode(mova_engine_convert(engine))
		case .reset:
			mova_engine_reset(engine)
			return .none
		}
	}

	func clearExceptions() {
		mova_engine_clear_exceptions(engine)
		exceptionStore.removeAllExceptions()
	}

	private func decode(_ action: MovaAction) -> DecisionOutcome {
		guard action.kind == UInt8(MOVA_ACTION_REWRITE),
			  let layout = Self.layout(action.switch_to),
			  let bytes = action.insert_utf8,
			  action.word_offset <= action.insert_len else {
			return DecisionOutcome(action: nil, undecidedWords: action.undecided_words)
		}
		let utf8 = UnsafeBufferPointer(start: bytes, count: action.insert_len)
		if action.learned_exception != 0 {
			let word = String(decoding: utf8[action.word_offset...], as: UTF8.self)
			exceptionStore.add(LearnedException(layout: layout, text: word))
		}
		let rewrite = RewriteAction(
			span: action.span == UInt8(MOVA_SPAN_WORD_AND_BOUNDARY) ? .wordAndBoundary : .currentWord,
			deleteCount: action.delete_chars,
			insertText: String(decoding: utf8, as: UTF8.self),
			riderCount: action.rider_count,
			switchTo: layout
		)
		return DecisionOutcome(action: rewrite, undecidedWords: action.undecided_words)
	}

	private func load(_ exception: LearnedException) {
		var bytes = Array(exception.text.utf8)
		_ = mova_engine_add_exception(engine, Self.code(exception.layout), &bytes, bytes.count)
	}

	private static func code(_ layout: SupportedLayout) -> UInt8 {
		switch layout {
		case .us: return UInt8(MOVA_LAYOUT_US)
		case .ukrainianPC: return UInt8(MOVA_LAYOUT_UKRAINIAN_PC)
		}
	}

	private static func layout(_ code: UInt8) -> SupportedLayout? {
		switch Int(code) {
		case Int(MOVA_LAYOUT_US): return .us
		case Int(MOVA_LAYOUT_UKRAINIAN_PC): return .ukrainianPC
		default: return nil
		}
	}

	/// macOS ANSI virtual key codes to the engine's physical key positions.
	static let physicalKeys: [UInt16: UInt8] = [
		50: UInt8(MOVA_KEY_BACKQUOTE),
		18: UInt8(MOVA_KEY_DIGIT_1), 19: UInt8(MOVA_KEY_DIGIT_2), 20: UInt8(MOVA_KEY_DIGIT_3),
		21: UInt8(MOVA_KEY_DIGIT_4), 23: UInt8(MOVA_KEY_DIGIT_5), 22: UInt8(MOVA_KEY_DIGIT_6),
		26: UInt8(MOVA_KEY_DIGIT_7), 28: UInt8(MOVA_KEY_DIGIT_8), 25: UInt8(MOVA_KEY_DIGIT_9),
		29: UInt8(MOVA_KEY_DIGIT_0), 27: UInt8(MOVA_KEY_MINUS), 24: UInt8(MOVA_KEY_EQUAL),
		12: UInt8(MOVA_KEY_Q), 13: UInt8(MOVA_KEY_W), 14: UInt8(MOVA_KEY_E), 15: UInt8(MOVA_KEY_R),
		17: UInt8(MOVA_KEY_T), 16: UInt8(MOVA_KEY_Y), 32: UInt8(MOVA_KEY_U), 34: UInt8(MOVA_KEY_I),
		31: UInt8(MOVA_KEY_O), 35: UInt8(MOVA_KEY_P), 33: UInt8(MOVA_KEY_BRACKET_LEFT),
		30: UInt8(MOVA_KEY_BRACKET_RIGHT), 42: UInt8(MOVA_KEY_BACKSLASH),
		0: UInt8(MOVA_KEY_A), 1: UInt8(MOVA_KEY_S), 2: UInt8(MOVA_KEY_D), 3: UInt8(MOVA_KEY_F),
		5: UInt8(MOVA_KEY_G), 4: UInt8(MOVA_KEY_H), 38: UInt8(MOVA_KEY_J), 40: UInt8(MOVA_KEY_K),
		37: UInt8(MOVA_KEY_L), 41: UInt8(MOVA_KEY_SEMICOLON), 39: UInt8(MOVA_KEY_QUOTE),
		6: UInt8(MOVA_KEY_Z), 7: UInt8(MOVA_KEY_X), 8: UInt8(MOVA_KEY_C), 9: UInt8(MOVA_KEY_V),
		11: UInt8(MOVA_KEY_B), 45: UInt8(MOVA_KEY_N), 46: UInt8(MOVA_KEY_M),
		43: UInt8(MOVA_KEY_COMMA), 47: UInt8(MOVA_KEY_PERIOD), 44: UInt8(MOVA_KEY_SLASH),
	]
}
