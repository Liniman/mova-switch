import Foundation

/// Fallback core used when the Rust engine cannot start. Same contract, smaller vocabulary.
final class BuiltinDecisionCore: DecisionCore {
	private struct Word {
		var strokes: [PhysicalKeyStroke]
		let layout: SupportedLayout
	}

	private struct LastRewrite {
		let word: Word
		let span: RewriteSpan
		let automatic: Bool
	}

	private enum State {
		case idle
		case typing(Word)
		case finished(Word)
		case blocked
		case undo(LastRewrite)
	}

	let name = "Built-in Swift"

	private let translator: LayoutTranslating
	private let exceptionStore: ExceptionStoring
	private var state = State.idle
	private var strikes: [LearnedException: Int] = [:]

	init(translator: LayoutTranslating, exceptionStore: ExceptionStoring) {
		self.translator = translator
		self.exceptionStore = exceptionStore
	}

	/// The fallback never carries short words: it reports no undecided words, so the shell
	/// keeps none and every rewrite covers one word. Runs depend on the Rust detector's keep
	/// reasons and word lists, and a second copy here would drift from the one the eval measures.
	func handle(_ input: DecisionInput) -> DecisionOutcome {
		DecisionOutcome(action: decide(input))
	}

	private func decide(_ input: DecisionInput) -> RewriteAction? {
		switch input {
		case .key(let stroke):
			switch state {
			case .typing(var word) where word.layout == stroke.layout:
				word.strokes.append(stroke)
				state = .typing(word)
			case .blocked:
				break
			case .undo(let last) where last.span == .currentWord:
				state = .blocked
			default:
				state = .typing(Word(strokes: [stroke], layout: stroke.layout))
			}
			return nil

		case .edit:
			state = .blocked
			return nil

		case .boundary(let layout, let automatic, _):
			guard case .typing(let word) = state, word.layout == layout else {
				state = .idle
				return nil
			}
			guard automatic, word.strokes.count <= 32, shouldRewrite(word) else {
				state = .finished(word)
				return nil
			}
			return rewrite(word, span: .wordAndBoundary, automatic: true)

		case .convert:
			switch state {
			case .typing(let word): return rewrite(word, span: .currentWord, automatic: false)
			case .finished(let word): return rewrite(word, span: .wordAndBoundary, automatic: false)
			default: return nil
			}

		case .undo:
			guard case .undo(let last) = state,
				  let original = translator.text(for: last.word.strokes, using: last.word.layout) else { return nil }
			if last.automatic { recordStrike(LearnedException(layout: last.word.layout, text: normalize(original))) }
			state = last.span == .currentWord ? .blocked : .finished(last.word)
			return RewriteAction(
				span: last.span,
				deleteCount: last.word.strokes.count,
				insertText: original,
				switchTo: last.word.layout
			)

		case .reset:
			state = .idle
			return nil
		}
	}

	func clearExceptions() {
		exceptionStore.removeAllExceptions()
		strikes.removeAll()
	}

	private func rewrite(_ word: Word, span: RewriteSpan, automatic: Bool) -> RewriteAction? {
		let target = word.layout.other
		guard let replacement = translator.text(for: word.strokes, using: target) else {
			state = .idle
			return nil
		}
		state = .undo(LastRewrite(word: word, span: span, automatic: automatic))
		return RewriteAction(span: span, deleteCount: word.strokes.count, insertText: replacement, switchTo: target)
	}

	private func recordStrike(_ exception: LearnedException) {
		let count = (strikes[exception] ?? 0) + 1
		strikes[exception] = count
		if count >= 2 {
			strikes[exception] = nil
			exceptionStore.add(exception)
		}
	}

	private func shouldRewrite(_ word: Word) -> Bool {
		guard let original = translator.text(for: word.strokes, using: word.layout),
			  let replacement = translator.text(for: word.strokes, using: word.layout.other) else { return false }
		if exceptionStore.exceptions.contains(LearnedException(layout: word.layout, text: normalize(original))) {
			return false
		}
		return shouldRewrite(original, as: word.layout, to: replacement)
	}

	private func shouldRewrite(_ original: String, as source: SupportedLayout, to replacement: String) -> Bool {
		let originalWord = normalize(original)
		let replacementWord = normalize(replacement)
		let sourceWords = source == .us ? Self.englishWords : Self.ukrainianWords
		let targetWords = source == .us ? Self.ukrainianWords : Self.englishWords
		if sourceWords.contains(originalWord) { return false }
		if targetWords.contains(replacementWord) { return true }
		if originalWord.count < 4 { return false }
		let originalScore = score(originalWord, language: source)
		let replacementScore = score(replacementWord, language: source.other)
		return replacementScore >= 4 && replacementScore >= originalScore + 5
	}

	private func score(_ word: String, language: SupportedLayout) -> Int {
		let letters = Array(word)
		guard !letters.isEmpty else { return -20 }
		let expected = language == .us ? Self.englishLetters : Self.ukrainianLetters
		guard letters.allSatisfy(expected.contains) else { return -20 }

		let words = language == .us ? Self.englishWords : Self.ukrainianWords
		let vowels = language == .us ? Self.englishVowels : Self.ukrainianVowels
		let ngrams = language == .us ? Self.englishNgrams : Self.ukrainianNgrams
		var result = words.contains(word) ? 12 : 0
		let vowelCount = letters.filter(vowels.contains).count
		result += vowelCount == 0 ? -3 : 1
		if letters.count >= 3 { result += 1 }
		for index in 0..<(letters.count - 1) {
			let pair = String([letters[index], letters[index + 1]])
			if ngrams.contains(pair) { result += 1 }
		}
		return result
	}

	private func normalize(_ word: String) -> String {
		word.lowercased(with: Locale(identifier: "uk_UA"))
	}

	private static let englishLetters = Set("abcdefghijklmnopqrstuvwxyz")
	private static let ukrainianLetters = Set("абвгґдеєжзиіїйклмнопрстуфхцчшщьюя")
	private static let englishVowels = Set("aeiouy")
	private static let ukrainianVowels = Set("аеєиіїоуюя")

	private static let englishNgrams: Set<String> = [
		"th", "he", "in", "er", "an", "re", "on", "at", "en", "nd", "ti", "es", "or", "te",
		"of", "ed", "is", "it", "al", "ar", "st", "to", "nt", "ng", "se", "ha", "as", "ou",
		"io", "le", "ve", "co", "me", "de", "hi", "ri", "ro", "ic", "ne", "ea", "ra", "ce",
		"li", "ch", "ll", "be", "ma", "si", "om", "ur"
	]

	private static let ukrainianNgrams: Set<String> = [
		"ст", "но", "на", "ов", "ни", "то", "ен", "ро", "ко", "ре", "по", "пр", "не", "ра",
		"ал", "ли", "ві", "ти", "ка", "та", "ор", "ва", "ла", "ер", "ет", "ін", "во", "ма",
		"ий", "ня", "ся", "ть", "ри", "іл", "ив", "іт"
	]

	private static let englishWords: Set<String> = [
		"a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are", "as", "at",
		"back", "be", "because", "been", "before", "but", "by", "can", "come", "could", "day", "did",
		"do", "down", "even", "first", "for", "from", "get", "give", "go", "good", "great", "had",
		"has", "have", "he", "hello", "help", "her", "here", "him", "his", "home", "how", "i", "if",
		"in", "into", "is", "it", "just", "know", "like", "look", "make", "me", "more", "my", "need",
		"new", "no", "not", "now", "of", "on", "one", "only", "or", "other", "our", "out", "over",
		"people", "please", "right", "say", "see", "she", "so", "some", "take", "than", "thank", "that",
		"the", "their", "them", "then", "there", "they", "thing", "think", "this", "time", "to", "too",
		"up", "us", "use", "very", "want", "was", "way", "we", "well", "were", "what", "when", "where",
		"which", "who", "why", "will", "with", "work", "would", "yes", "you", "your"
	]

	private static let ukrainianWords: Set<String> = [
		"а", "аби", "або", "але", "без", "був", "була", "були", "бути", "вам", "вас", "ваш", "вже",
		"він", "вона", "вони", "все", "гаразд", "гарний", "геть", "де", "для", "до", "добре", "дякую",
		"є", "з", "за", "зараз", "і", "його", "її", "їх", "коли", "краще", "лише", "має", "мати",
		"мене", "ми", "мій", "може", "можна", "на", "нам", "нас", "наш", "не", "немає", "ні", "новий",
		"о", "один", "ось", "після", "потрібно", "про", "привіт", "просто", "раз", "робити", "робота",
		"саме", "свій", "сьогодні", "так", "також", "там", "тепер", "ти", "тоді", "тому", "тут", "у",
		"хай", "хто", "це", "цей", "час", "ще", "що", "щоб", "як", "який", "якщо"
	]
}
