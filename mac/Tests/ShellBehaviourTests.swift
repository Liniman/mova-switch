import CoreGraphics
import Foundation

/// Drives the real EventTapController with the real decision core and the installed macOS
/// layouts. Posted events come back through `receive` the way the session tap returns them,
/// and the events that reach the "application" are applied to an in-memory document.
final class SimulatedDesk: EventSink, InputSourceControl, SelectionConverting {
	var document = ""
	var layout: SupportedLayout = .us
	var policy: TypingPolicy = .automatic
	var deferDelivery = false
	var selectedText: String?
	var allowsLayoutSelection = true
	var clock: TimeInterval = 0
	var store: MemoryExceptions?
	private var pending: [CGEvent] = []
	private var pumping = false
	private let translator: KeyboardLayoutTranslator
	private(set) var controller: EventTapController!

	init(translator: KeyboardLayoutTranslator, core: DecisionCore) {
		self.translator = translator
		controller = EventTapController(
			core: core,
			translator: translator,
			inputSource: self,
			selectionConverter: self,
			sink: self,
			now: { [unowned self] in self.clock },
			policy: { [unowned self] in self.policy }
		)
	}

	func currentLayout() -> SupportedLayout? { layout }

	func select(_ layout: SupportedLayout) -> Bool {
		guard allowsLayoutSelection else { return false }
		self.layout = layout
		return true
	}

	func convertSelection() -> RewriteAction? {
		guard let selectedText,
			  let conversion = translator.selectionConversion(for: selectedText),
			  select(conversion.target) else { return nil }
		document = conversion.replacement
		self.selectedText = nil
		return RewriteAction(
			span: .selection,
			deleteCount: selectedText.count,
			insertText: conversion.replacement,
			switchTo: conversion.target
		)
	}

	/// macOS delivers posted events later, never inside the tap callback that posted them.
	func post(_ event: CGEvent) {
		pending.append(event)
	}

	func flush() {
		deferDelivery = false
		pump()
	}

	private func pump() {
		guard !pumping else { return }
		pumping = true
		while !deferDelivery, !pending.isEmpty {
			apply(pending.removeFirst())
		}
		pumping = false
	}

	/// Types keys by U.S. position, the way fingers do regardless of the active layout.
	func type(_ keys: String) {
		for character in keys {
			if character == " " {
				press(49)
				continue
			}
			let lower = Character(character.lowercased())
			guard let keyCode = TestCommand.keyCodes[lower] else { fatalError("no key for \(character)") }
			press(keyCode, flags: character.isUppercase ? .maskShift : [])
		}
	}

	func press(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
		for keyDown in [true, false] {
			let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: keyDown)!
			event.flags = flags
			if let character = translator.character(keyCode: UInt16(keyCode), shifted: flags.contains(.maskShift), layout: layout) {
				setText(String(character), on: event)
			}
			deliver(event)
		}
	}

	func click() {
		let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
		deliver(event)
	}

	func tapOption(_ keyCode: CGKeyCode = 61) {
		for flags in [CGEventFlags.maskAlternate, []] {
			let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: !flags.isEmpty)!
			event.type = .flagsChanged
			event.flags = flags
			deliver(event)
		}
	}

	private func deliver(_ event: CGEvent) {
		apply(event)
		pump()
	}

	/// What a text field does with an event that reached it.
	private func apply(_ event: CGEvent) {
		guard controller.receive(type: event.type, event: event), event.type == .keyDown,
			  event.flags.intersection([.maskCommand, .maskControl]).isEmpty else { return }
		switch event.getIntegerValueField(.keyboardEventKeycode) {
		case 51: if !document.isEmpty { document.removeLast() }
		case 49: document.append(" ")
		case 36: document.append("\n")
		default:
			let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
			let shifted = event.flags.contains(.maskShift) != event.flags.contains(.maskAlphaShift)
			let typed = event.getIntegerValueField(.eventSourceUserData) == movaSyntheticEventMarker
				? translator.character(keyCode: keyCode, shifted: shifted, layout: layout).map(String.init) ?? ""
				: text(of: event)
			if !typed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
				document.append(typed)
			}
		}
	}

	private func text(of event: CGEvent) -> String {
		var length = 0
		var buffer = [UniChar](repeating: 0, count: 8)
		event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
		return String(utf16CodeUnits: buffer, count: length)
	}

	private func setText(_ text: String, on event: CGEvent) {
		let units = Array(text.utf16)
		event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
	}
}

final class MemoryExceptions: ExceptionStoring {
	var exceptions: Set<LearnedException> = []
	func add(_ exception: LearnedException) { exceptions.insert(exception) }
	func removeAllExceptions() { exceptions.removeAll() }
}

@main
enum ShellBehaviourTests {
	static var failures = 0

	static func main() throws {
		let translator = try KeyboardLayoutTranslator()
		checkEngineLayoutsMatchMacOS(translator)

		for coreName in ["rust", "builtin"] {
			func desk() -> SimulatedDesk {
				let store = MemoryExceptions()
				let core: DecisionCore = coreName == "rust"
					? RustDecisionCore(exceptionStore: store)!
					: BuiltinDecisionCore(translator: translator, exceptionStore: store)
				let desk = SimulatedDesk(translator: translator, core: core)
				desk.store = store
				return desk
			}
			run(coreName, desk)
		}
		guard failures == 0 else {
			print("shell-behaviour-tests=failed count=\(failures)")
			exit(1)
		}
		print("shell-behaviour-tests=passed")
	}

	static func run(_ core: String, _ makeDesk: () -> SimulatedDesk) {
		var desk = makeDesk()
		desk.type("ghbdsn ")
		expect(core, desk, "привіт ", .ukrainianPC, "wrong-layout word is rewritten and the layout switches")

		desk.tapOption()
		expect(core, desk, "ghbdsn ", .us, "Option tap right after a conversion restores text and layout")

		desk = makeDesk()
		desk.type("hello ")
		expect(core, desk, "hello ", .us, "a correct word is untouched")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("hello ")
		expect(core, desk, "hello ", .us, "English typed on Ukrainian is rewritten")

		desk = makeDesk()
		desk.type("Ghbdsn ")
		expect(core, desk, "Привіт ", .ukrainianPC, "capitalised word keeps its case")

		desk = makeDesk()
		desk.type("ghbd")
		desk.press(51)
		desk.type("dsn ")
		expect(core, desk, "ghbdsn ", .us, "Backspace inside a word blocks its conversion")

		desk = makeDesk()
		desk.type("ghbdsn")
		desk.press(0, flags: .maskCommand)
		desk.type(" ")
		expect(core, desk, "ghbdsn ", .us, "a Command chord clears the word")

		desk = makeDesk()
		desk.policy = .inert
		desk.type("ghbdsn ")
		expect(core, desk, "ghbdsn ", .us, "secure input or a paused app is never touched")

		desk = makeDesk()
		desk.policy = .manualOnly
		desk.type("ghbdsn ")
		expect(core, desk, "ghbdsn ", .us, "manual-only apps do not convert by themselves")
		desk.tapOption()
		expect(core, desk, "привіт ", .ukrainianPC, "Option tap converts the last word in a manual-only app")

		desk = makeDesk()
		desk.document = "ghbdsn"
		desk.selectedText = "ghbdsn"
		desk.tapOption()
		expect(core, desk, "привіт", .ukrainianPC, "Right Option converts selected text")

		desk = makeDesk()
		desk.type("ghbdsn")
		desk.tapOption(58)
		expect(core, desk, "ghbdsn", .us, "Left Option remains available for normal typing")

		desk = makeDesk()
		desk.type("hello")
		desk.tapOption()
		desk.type("world ")
		expect(core, desk, "руддщцщкдв ", .ukrainianPC, "Option tap mid-word converts once and typing continues in the new layout")

		desk = makeDesk()
		desk.type("ghbdsn")
		desk.press(44)
		expect(core, desk, "привіт.", .ukrainianPC, "a punctuation boundary is re-sent in the new layout")

		desk = makeDesk()
		desk.allowsLayoutSelection = false
		desk.type("ghbdsn ")
		expect(core, desk, "ghbdsn ", .us, "a failed layout switch leaves text and boundary untouched")

		desk = makeDesk()
		desk.type("ghbdsn")
		desk.deferDelivery = true
		desk.type(" ")
		desk.type("nt")
		desk.flush()
		expect(core, desk, "привіт те", .ukrainianPC, "keys typed during a rewrite arrive after it, in the new layout")

		desk = makeDesk()
		for _ in 0..<2 {
			desk.type("ghbdsn ")
			desk.tapOption()
			desk.press(36)
		}
		desk.type("ghbdsn ")
		expect(core, desk, "ghbdsn \nghbdsn \nghbdsn ", .us, "the second undo of a word adds it to the never-convert list")

		desk = makeDesk()
		desk.type("ghbdsn ")
		desk.press(124)
		desk.tapOption()
		expect(core, desk, "привіт ", .ukrainianPC, "an arrow after a conversion does not undo it")

		desk = makeDesk()
		desk.type("gh")
		desk.layout = .ukrainianPC
		desk.type("hello ")
		expect(core, desk, "ghhello ", .us, "an external layout change starts a fresh word")

		desk = makeDesk()
		desk.type("ghbdsn")
		desk.press(48)
		desk.tapOption()
		expect(core, desk, "привіт", .ukrainianPC, "Tab clears undo state before focus moves")

		if core == "rust" {
			runShortWordRuns(core, makeDesk)
		} else {
			desk = makeDesk()
			desk.type("nf ghbdsn ")
			expect(core, desk, "nf привіт ", .ukrainianPC, "the fallback core never carries short words")
		}
	}

	static func runShortWordRuns(_ core: String, _ makeDesk: () -> SimulatedDesk) {
		var desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am switching ")
		expect(core, desk, "i am switching ", .us, "short words typed before a converted word are rewritten with it")
		desk.tapOption()
		expect(core, desk, "ш фь іцшесрштп ", .ukrainianPC, "one Option tap restores the whole run and the layout")
		desk.tapOption()
		expect(core, desk, "ш фь switching ", .us, "a second Option tap converts only the long word")

		desk = makeDesk()
		desk.type("f gjnsv ")
		expect(core, desk, "а потім ", .ukrainianPC, "a one-letter word rides along on U.S.")

		desk = makeDesk()
		desk.type("nf ghbdsn ")
		expect(core, desk, "та привіт ", .ukrainianPC, "a two-letter word rides along on U.S.")

		desk = makeDesk()
		desk.type("a ghbdsn ")
		expect(core, desk, "a привіт ", .ukrainianPC, "a correct short word stays when the next word converts")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am ")
		desk.press(123)
		desk.type("switching ")
		expect(core, desk, "ш фь switching ", .us, "an arrow key drops the run")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am ")
		desk.click()
		desk.type("switching ")
		expect(core, desk, "ш фь switching ", .us, "a mouse click drops the run")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am ")
		desk.press(51)
		desk.type(" switching ")
		expect(core, desk, "ш фь switching ", .us, "Backspace drops the run")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am ")
		desk.layout = .us
		desk.type("ghbdsn ")
		expect(core, desk, "ш фь привіт ", .ukrainianPC, "a layout change drops the run")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am ")
		desk.clock += EventTapController.runPause + 1
		desk.type("switching ")
		expect(core, desk, "ш фь switching ", .us, "a pause between words drops the run")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		desk.type("i am")
		desk.press(36)
		desk.type("switching ")
		expect(core, desk, "ш фь\nswitching ", .us, "Return between words drops the run")

		desk = makeDesk()
		desk.layout = .ukrainianPC
		for _ in 0..<2 {
			desk.type("i am switching ")
			desk.tapOption()
			desk.press(36)
		}
		let learned = desk.store?.exceptions ?? []
		let onlyLongWord = learned == [LearnedException(layout: .ukrainianPC, text: "іцшесрштп")]
		desk.type("i am switching ")
		expect(
			core, desk, "ш фь іцшесрштп \nш фь іцшесрштп \nш фь іцшесрштп ", .ukrainianPC,
			"two undos learn the long word" + (onlyLongWord ? "" : ", but learned \(learned)")
		)
		if !onlyLongWord { failures += 1 }
	}

	static func expect(_ core: String, _ desk: SimulatedDesk, _ text: String, _ layout: SupportedLayout, _ behaviour: String) {
		if desk.document == text && desk.layout == layout {
			print("ok   [\(core)] \(behaviour)")
		} else {
			failures += 1
			print("FAIL [\(core)] \(behaviour): got \(desk.document.debugDescription) on \(desk.layout.displayName), want \(text.debugDescription) on \(layout.displayName)")
		}
	}

	/// The engine renders words from built-in tables. They must agree with the layouts macOS
	/// actually has installed, key by key, through the real C ABI.
	static func checkEngineLayoutsMatchMacOS(_ translator: KeyboardLayoutTranslator) {
		var mismatches: [String] = []
		for (keyCode, key) in RustDecisionCore.physicalKeys.sorted(by: { $0.key < $1.key }) {
			for shifted in [false, true] {
				for source in SupportedLayout.allCases {
					let engine = mova_engine_new()!
					defer { mova_engine_free(engine) }
					let sourceCode: UInt8 = source == .us ? 0 : 1
					_ = mova_engine_key(engine, key, shifted ? 1 : 0, sourceCode)
					let action = mova_engine_convert(engine)
					let rendered = String(decoding: UnsafeBufferPointer(start: action.insert_utf8, count: action.insert_len), as: UTF8.self)
					let expected = translator.character(keyCode: keyCode, shifted: shifted, layout: source.other).map(String.init) ?? "∅"
					if rendered != expected {
						mismatches.append("key \(keyCode) shift=\(shifted) \(source.other.displayName): engine \(rendered.debugDescription) macOS \(expected.debugDescription)")
					}
				}
			}
		}
		if mismatches.isEmpty {
			print("ok   engine layouts match macOS for \(RustDecisionCore.physicalKeys.count) keys")
		} else {
			failures += 1
			print("FAIL engine layouts differ from macOS:\n  " + mismatches.joined(separator: "\n  "))
		}
	}
}
