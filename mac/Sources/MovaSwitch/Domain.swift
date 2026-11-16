import Foundation

enum SupportedLayout: String, CaseIterable, Codable, Equatable {
	case us = "com.apple.keylayout.US"
	case ukrainianPC = "com.apple.keylayout.Ukrainian-PC"

	var other: SupportedLayout {
		switch self {
		case .us: return .ukrainianPC
		case .ukrainianPC: return .us
		}
	}

	var displayName: String {
		switch self {
		case .us: return "U.S."
		case .ukrainianPC: return "Ukrainian-PC"
		}
	}
}

struct PhysicalKeyStroke: Equatable {
	let keyCode: UInt16
	let shifted: Bool
	let layout: SupportedLayout
}

enum DecisionInput: Equatable {
	case key(PhysicalKeyStroke)
	/// Backspace inside the current word. The word is no longer converted automatically.
	case edit
	/// A word boundary typed under `layout`. `automatic` is false in manual-only apps.
	/// `isSpace` is true only for a plain Space, the one boundary that joins short words.
	case boundary(layout: SupportedLayout, automatic: Bool, isSpace: Bool)
	case undo
	case convert
	case reset
}

enum RewriteSpan: Equatable {
	/// The word is the last text in the document.
	case currentWord
	/// The boundary key typed after the word follows it in the document.
	case wordAndBoundary
	case selection
}

struct SelectionConversion: Equatable {
	let source: SupportedLayout
	let target: SupportedLayout
	let replacement: String
}

protocol SelectionConverting: AnyObject {
	func convertSelection() -> RewriteAction?
}

struct RewriteAction: Equatable {
	let span: RewriteSpan
	let deleteCount: Int
	/// One character per replayed key, including the Space after each carried word.
	let insertText: String
	/// Short words before the word that this rewrite carries, each followed by its Space.
	var riderCount = 0
	let switchTo: SupportedLayout
}

struct DecisionOutcome: Equatable {
	let action: RewriteAction?
	/// How many of its last finished words the shell keeps as keys for a later rewrite.
	var undecidedWords = 0

	static let none = DecisionOutcome(action: nil)
}

protocol DecisionCore: AnyObject {
	var name: String { get }
	func handle(_ input: DecisionInput) -> DecisionOutcome
	func clearExceptions()
}

protocol LayoutTranslating: AnyObject {
	func text(for strokes: [PhysicalKeyStroke], using layout: SupportedLayout) -> String?
}

struct LearnedException: Hashable {
	let layout: SupportedLayout
	let text: String
}

protocol ExceptionStoring: AnyObject {
	var exceptions: Set<LearnedException> { get }
	func add(_ exception: LearnedException)
	func removeAllExceptions()
}

enum AppMode: String, CaseIterable {
	case auto
	case manualOnly
	case off

	var title: String {
		switch self {
		case .auto: return "Convert automatically"
		case .manualOnly: return "Right Option tap only"
		case .off: return "Off"
		}
	}
}

enum RuntimeState: Equatable {
	case needsPermission
	case disabled
	case secureInput
	case appMode(AppMode, String)
	case active
}
