import CoreGraphics
import Foundation

let movaSyntheticEventMarker: Int64 = 0x4D4F564153574954

protocol InputSourceControl: AnyObject {
	func currentLayout() -> SupportedLayout?
	@discardableResult func select(_ layout: SupportedLayout) -> Bool
}

protocol EventSink: AnyObject {
	/// Post a synthetic event. It must come back through the tap carrying the marker.
	func post(_ event: CGEvent)
}

final class HIDEventSink: EventSink {
	func post(_ event: CGEvent) {
		event.post(tap: .cghidEventTap)
	}
}

/// What the shell may do in the focused context right now.
enum TypingPolicy: Equatable {
	case automatic
	case manualOnly
	/// Secure input, a paused app, or switching turned off: observe nothing.
	case inert
}

private func movaEventTapCallback(
	proxy: CGEventTapProxy,
	type: CGEventType,
	event: CGEvent,
	userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
	guard let userInfo else { return Unmanaged.passUnretained(event) }
	let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
	return controller.receive(type: type, event: event) ? Unmanaged.passUnretained(event) : nil
}

/// Owns the event tap and all typing state: the current word, the last finished word,
/// the lone-Option detector, and the queue that holds physical keys during a rewrite.
final class EventTapController {
	private struct CapturedKey {
		let keyCode: CGKeyCode
		let flags: CGEventFlags
	}

	private struct FinishedWord {
		let keys: [CapturedKey]
		let boundary: CapturedKey
		/// The short words, each with its Space, that the rewrite of this word carried along.
		var carried: [CapturedKey] = []
	}

	private enum KeyRole {
		case word(shifted: Bool)
		case boundary
		case edit
		case staleBuffer
	}

	private let core: DecisionCore
	private let translator: KeyboardLayoutTranslator
	private let inputSource: InputSourceControl
	private let selectionConverter: SelectionConverting
	private let sink: EventSink
	private let policy: () -> TypingPolicy
	private let now: () -> TimeInterval
	private let eventSource = CGEventSource(stateID: .privateState)
	private var eventTap: CFMachPort?
	private var runLoopSource: CFRunLoopSource?

	private var word: [CapturedKey] = []
	private var wordLayout: SupportedLayout?
	private var finished: FinishedWord?
	/// The finished short words the core may still carry, newest last. At most three, in
	/// memory only, and the core decides how many: see `keepUndecided`.
	private var undecided: [FinishedWord] = []
	private var lastKeyDownAt: TimeInterval?
	private var suppressedKeyUps: Set<CGKeyCode> = []
	private var optionTapStart: TimeInterval?
	private var heldModifiers: CGEventFlags = []

	private var outstandingSynthetic = 0
	private var heldEvents: [(CGEventType, CGEvent)] = []
	private var holdGeneration = 0

	var onRewrite: ((RewriteAction) -> Void)?
	var onTapStateChange: (() -> Void)?

	static let optionTapWindow: TimeInterval = 0.3
	/// A longer pause between words drops undecided short words: the user may have looked
	/// away or moved the caret in a way the tap cannot see, and the next word starts afresh.
	static let runPause: TimeInterval = 2.0
	private static let modifierMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

	init(
		core: DecisionCore,
		translator: KeyboardLayoutTranslator,
		inputSource: InputSourceControl,
		selectionConverter: SelectionConverting,
		sink: EventSink = HIDEventSink(),
		now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
		policy: @escaping () -> TypingPolicy
	) {
		self.core = core
		self.translator = translator
		self.inputSource = inputSource
		self.selectionConverter = selectionConverter
		self.sink = sink
		self.now = now
		self.policy = policy
	}

	deinit {
		stop()
	}

	var isRunning: Bool {
		guard let eventTap else { return false }
		return CGEvent.tapIsEnabled(tap: eventTap)
	}

	/// Creates the tap. Returns false while macOS has not granted Accessibility.
	@discardableResult
	func start() -> Bool {
		if isRunning { return true }
		if let eventTap, CFMachPortIsValid(eventTap) {
			CGEvent.tapEnable(tap: eventTap, enable: true)
			onTapStateChange?()
			return isRunning
		}
		stop()

		let eventTypes: [CGEventType] = [
			.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown,
		]
		let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
		guard let tap = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .defaultTap,
			eventsOfInterest: mask,
			callback: movaEventTapCallback,
			userInfo: Unmanaged.passUnretained(self).toOpaque()
		) else {
			return false
		}
		let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
		eventTap = tap
		runLoopSource = source
		CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)
		onTapStateChange?()
		return true
	}

	func stop() {
		if let runLoopSource {
			CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
		}
		if let eventTap {
			CGEvent.tapEnable(tap: eventTap, enable: false)
			CFMachPortInvalidate(eventTap)
		}
		runLoopSource = nil
		eventTap = nil
		releaseHeldEvents()
		reset()
	}

	func reset() {
		word.removeAll()
		wordLayout = nil
		finished = nil
		undecided.removeAll()
		suppressedKeyUps.removeAll()
		optionTapStart = nil
		_ = core.handle(.reset)
	}

	/// Returns true when the event should continue to the focused application.
	func receive(type: CGEventType, event: CGEvent) -> Bool {
		if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
			if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
			reset()
			onTapStateChange?()
			return true
		}

		if event.getIntegerValueField(.eventSourceUserData) == movaSyntheticEventMarker {
			outstandingSynthetic = max(0, outstandingSynthetic - 1)
			if outstandingSynthetic == 0 { drainHeldEvents() }
			return true
		}

		if outstandingSynthetic > 0 {
			guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
				reset()
				return true
			}
			if let copy = event.copy() { heldEvents.append((type, copy)) }
			return false
		}
		return route(type: type, event: event)
	}

	private func route(type: CGEventType, event: CGEvent) -> Bool {
		let policy = policy()
		guard policy != .inert else {
			reset()
			return true
		}

		switch type {
		case .leftMouseDown, .rightMouseDown, .otherMouseDown:
			reset()
			return true

		case .flagsChanged:
			handleModifiers(event)
			return true

		case .keyUp:
			let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
			return suppressedKeyUps.remove(keyCode) == nil

		case .keyDown:
			optionTapStart = nil
			return routeKeyDown(event, policy: policy)

		default:
			return true
		}
	}

	private func handleModifiers(_ event: CGEvent) {
		let flags = event.flags
		let modifiers = flags.intersection(Self.modifierMask)
		let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
		defer { heldModifiers = modifiers }
		if keyCode == 61, modifiers == .maskAlternate, heldModifiers.isEmpty {
			optionTapStart = ProcessInfo.processInfo.systemUptime
			return
		}
		guard keyCode == 61, modifiers.isEmpty, heldModifiers == .maskAlternate, let start = optionTapStart else {
			optionTapStart = nil
			return
		}
		optionTapStart = nil
		if ProcessInfo.processInfo.systemUptime - start <= Self.optionTapWindow {
			undoOrConvert()
		}
	}

	private func undoOrConvert() {
		let undo = core.handle(.undo)
		keepUndecided(undo.undecidedWords)
		if let action = undo.action {
			if performCoreAction(action) {
				// The run is back as typed. A further convert reaches only the long word.
				finished?.carried = []
			}
			return
		}
		if let action = selectionConverter.convertSelection() {
			reset()
			onRewrite?(action)
			return
		}
		let conversion = core.handle(.convert)
		keepUndecided(conversion.undecidedWords)
		guard let action = conversion.action else { return }
		performCoreAction(action)
	}

	@discardableResult
	private func performCoreAction(_ action: RewriteAction) -> Bool {
		switch action.span {
		case .currentWord:
			guard perform(action, keys: word, boundary: nil, boundaryInDocument: false) else { return false }
			wordLayout = action.switchTo
			return true
		case .wordAndBoundary:
			guard let finished else {
				reset()
				return false
			}
			let keys = action.riderCount > 0 ? finished.carried + finished.keys : finished.keys
			return perform(action, keys: keys, boundary: finished.boundary, boundaryInDocument: true)
		case .selection:
			reset()
			return true
		}
	}

	private func routeKeyDown(_ event: CGEvent, policy: TypingPolicy) -> Bool {
		let time = now()
		defer { lastKeyDownAt = time }
		if word.isEmpty, !undecided.isEmpty, let lastKeyDownAt, time - lastKeyDownAt > Self.runPause {
			// Between words nothing else is pending: the next key would end the finished
			// word's convert window anyway, so a full reset only drops the undecided run.
			reset()
		}
		let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
		let flags = event.flags
		guard flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty,
			  let layout = inputSource.currentLayout() else {
			reset()
			return true
		}
		let shifted = flags.contains(.maskShift) != flags.contains(.maskAlphaShift)
		let key = CapturedKey(keyCode: keyCode, flags: flags.intersection([.maskShift, .maskAlphaShift]))

		switch role(of: keyCode, shifted: shifted) {
		case .word(let shifted):
			if let wordLayout, wordLayout != layout {
				word.removeAll()
				finished = nil
				_ = core.handle(.reset)
			}
			wordLayout = layout
			finished = nil
			word.append(key)
			let outcome = core.handle(.key(PhysicalKeyStroke(keyCode: UInt16(keyCode), shifted: shifted, layout: layout)))
			keepUndecided(outcome.undecidedWords)
			return true

		case .edit:
			if word.isEmpty {
				reset()
			} else {
				word.removeLast()
				keepUndecided(core.handle(.edit).undecidedWords)
			}
			return true

		case .staleBuffer:
			reset()
			return true

		case .boundary:
			let typed = word
			word.removeAll()
			wordLayout = nil
			finished = typed.isEmpty ? nil : FinishedWord(keys: typed, boundary: key)
			let outcome = core.handle(.boundary(layout: layout, automatic: policy == .automatic, isSpace: keyCode == 49))
			guard let action = outcome.action else {
				if let finished { undecided.append(finished) }
				keepUndecided(outcome.undecidedWords)
				if keyCode == 48 { reset() }
				return true
			}
			guard action.riderCount <= undecided.count else {
				reset()
				return true
			}
			let carried = undecided.suffix(action.riderCount).flatMap { $0.keys + [$0.boundary] }
			undecided.removeAll()
			finished = FinishedWord(keys: typed, boundary: key, carried: carried)
			guard perform(action, keys: carried + typed, boundary: key, boundaryInDocument: false) else {
				return true
			}
			suppressedKeyUps.insert(keyCode)
			if keyCode == 48 { reset() }
			return false
		}
	}

	/// Keeps the newest `count` finished words, the ones the core may still carry. A count
	/// the shell cannot match means the two disagree about the text, so both start over.
	private func keepUndecided(_ count: Int) {
		guard count <= undecided.count else {
			reset()
			return
		}
		undecided.removeFirst(undecided.count - count)
	}

	private func role(of keyCode: CGKeyCode, shifted: Bool) -> KeyRole {
		switch keyCode {
		case 49, 36, 76, 48: return .boundary
		case 51: return .edit
		default: break
		}
		guard RustDecisionCore.physicalKeys[UInt16(keyCode)] != nil else { return .staleBuffer }
		if translator.isWordKey(UInt16(keyCode), shifted: shifted) { return .word(shifted: shifted) }
		if !shifted && Self.digitKeys.contains(keyCode) { return .staleBuffer }
		return .boundary
	}

	/// Switch the input source, delete the old text, replay the same physical keys, then send
	/// the boundary key again.
	@discardableResult
	private func perform(_ action: RewriteAction, keys: [CapturedKey], boundary: CapturedKey?, boundaryInDocument: Bool) -> Bool {
		let characters = Array(action.insertText)
		guard characters.count == keys.count, characters.count == action.deleteCount else {
			reset()
			return false
		}
		guard inputSource.select(action.switchTo), inputSource.currentLayout() == action.switchTo else {
			reset()
			return false
		}
		for _ in 0..<(action.deleteCount + (boundaryInDocument ? 1 : 0)) {
			postKey(CapturedKey(keyCode: 51, flags: []))
		}
		for key in keys {
			postKey(key)
		}
		if let boundary {
			postKey(boundary)
		}
		onRewrite?(action)
		return true
	}

	private func postKey(_ key: CapturedKey) {
		for keyDown in [true, false] {
			guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key.keyCode, keyDown: keyDown) else { continue }
			event.flags = key.flags
			postTagged(event)
		}
	}

	private func postTagged(_ event: CGEvent) {
		event.setIntegerValueField(.eventSourceUserData, value: movaSyntheticEventMarker)
		outstandingSynthetic += 1
		armHoldTimeout()
		sink.post(event)
	}

	/// Keys typed during a rewrite reach the application after it, in order, rendered in the
	/// layout that is current once the rewrite is done.
	private func drainHeldEvents() {
		while outstandingSynthetic == 0, !heldEvents.isEmpty {
			let (type, event) = heldEvents.removeFirst()
			guard route(type: type, event: event) else { continue }
			postFresh(type: type, from: event)
		}
	}

	private func postFresh(type: CGEventType, from event: CGEvent) {
		guard type == .keyDown || type == .keyUp else {
			postTagged(event)
			return
		}
		let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
		guard let fresh = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: type == .keyDown) else { return }
		fresh.flags = event.flags
		postTagged(fresh)
	}

	private func armHoldTimeout() {
		holdGeneration += 1
		let generation = holdGeneration
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
			guard let self, self.holdGeneration == generation, self.outstandingSynthetic > 0 else { return }
			self.outstandingSynthetic = 0
			self.drainHeldEvents()
		}
	}

	private func releaseHeldEvents() {
		let held = heldEvents
		heldEvents.removeAll()
		outstandingSynthetic = 0
		for (type, event) in held { postFresh(type: type, from: event) }
		outstandingSynthetic = 0
	}

	private static let digitKeys: Set<CGKeyCode> = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
}
