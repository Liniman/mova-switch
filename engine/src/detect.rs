use std::collections::BTreeSet;

use crate::{model::ModelSet, KeyStroke, LayoutId};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Confidence(f32);

impl Confidence {
    pub const CERTAIN: Self = Self(1.0);

    pub fn new(value: f32) -> Self {
        Self(value.clamp(0.0, 1.0))
    }

    pub fn get(self) -> f32 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum DecisionMoment {
    #[default]
    Boundary,
    MidWord,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
#[repr(u8)]
pub enum TokenClass {
    #[default]
    Plain,
    Code,
    Email,
    Path,
    Url,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct DecisionContext {
    pub moment: DecisionMoment,
    pub token_class: TokenClass,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Verdict {
    Keep {
        confidence: Confidence,
        reason: KeepReason,
    },
    Switch {
        to: LayoutId,
        confidence: Confidence,
    },
}

/// Why a token stayed in its current layout. Only `ShortAmbiguous` may join an undecided
/// run of short words; every other reason ends the run.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum KeepReason {
    /// A learned exception, a non-plain token class, digits, ALLCAPS or inner capitals.
    Protected,
    /// The current rendering is a word of the current language.
    KnownCurrent,
    /// One to three letters that are no known word here and no listed word there.
    ShortAmbiguous,
    /// Four or more letters the language model would not switch.
    InsufficientEvidence,
}

impl Verdict {
    pub fn confidence(self) -> Confidence {
        match self {
            Self::Keep { confidence, .. } | Self::Switch { confidence, .. } => confidence,
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct ExceptionSet {
    entries: BTreeSet<(LayoutId, String)>,
}

impl ExceptionSet {
    pub fn insert(&mut self, layout: LayoutId, text: impl Into<String>) -> bool {
        self.entries.insert((layout, text.into().to_lowercase()))
    }

    pub fn contains(&self, layout: LayoutId, text: &str) -> bool {
        self.entries.contains(&(layout, text.to_lowercase()))
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = (LayoutId, &str)> {
        self.entries
            .iter()
            .map(|(layout, text)| (*layout, text.as_str()))
    }
}

#[derive(Clone, Copy, Debug)]
pub struct DetectorConfig {
    pub boundary_margin: f32,
    pub mid_word_margin: f32,
    pub minimum_target_score: f32,
}

impl Default for DetectorConfig {
    fn default() -> Self {
        Self {
            boundary_margin: 0.7,
            mid_word_margin: 4.0,
            minimum_target_score: -3.5,
        }
    }
}

#[derive(Clone, Debug)]
pub struct Detector {
    model: &'static ModelSet,
    config: DetectorConfig,
}

impl Default for Detector {
    fn default() -> Self {
        Self::embedded()
    }
}

impl Detector {
    pub fn embedded() -> Self {
        Self {
            model: ModelSet::embedded(),
            config: DetectorConfig::default(),
        }
    }

    pub fn with_config(config: DetectorConfig) -> Self {
        Self {
            model: ModelSet::embedded(),
            config,
        }
    }

    /// Build a detector from another serialized model. The parsed model lives until exit.
    pub fn with_model_source(source: &str, config: DetectorConfig) -> Self {
        Self {
            model: ModelSet::leak(source),
            config,
        }
    }

    pub fn decide(
        &self,
        strokes: &[KeyStroke],
        current_layout: LayoutId,
        context: DecisionContext,
        exceptions: &ExceptionSet,
    ) -> Verdict {
        let current_text = current_layout.layout().render(strokes);
        if exceptions.contains(current_layout, &current_text)
            || !is_plain_word(&current_text, context)
        {
            return keep(Confidence::CERTAIN, KeepReason::Protected);
        }

        let target_layout = current_layout.alternate();
        let core = trim_trailing_punctuation(strokes, target_layout);
        let current_core = current_layout.layout().render(core);
        if core.len() < SHORT_WORD_MIN {
            let letter = current_core.to_lowercase();
            let reason = if one_letter_words(current_layout).contains(&letter.as_str()) {
                KeepReason::KnownCurrent
            } else {
                KeepReason::ShortAmbiguous
            };
            return keep(Confidence::CERTAIN, reason);
        }
        if self.is_known_word(current_layout, &current_core) {
            return keep(Confidence::CERTAIN, KeepReason::KnownCurrent);
        }

        let target_core = target_layout.layout().render(core).to_lowercase();
        if core.len() < MODEL_WORD_MIN {
            return if short_words(target_layout).contains(&target_core.as_str()) {
                Verdict::Switch {
                    to: target_layout,
                    confidence: Confidence::new(0.6),
                }
            } else {
                keep(Confidence::CERTAIN, KeepReason::ShortAmbiguous)
            };
        }

        let current_score = self.model.language(current_layout).score(&current_core);
        let Some(target_score) = self.model.language(target_layout).score(&target_core) else {
            return keep(Confidence::CERTAIN, KeepReason::InsufficientEvidence);
        };

        let current_total = current_score.map_or(-16.0, |score| score.total());
        let target_total = target_score.total();
        let margin = target_total - current_total;
        let required_margin = match context.moment {
            DecisionMoment::Boundary => self.config.boundary_margin,
            DecisionMoment::MidWord => self.config.mid_word_margin,
        };

        if target_score.ngram >= self.config.minimum_target_score && margin >= required_margin {
            Verdict::Switch {
                to: target_layout,
                confidence: Confidence::new(0.5 + (margin - required_margin) / 12.0),
            }
        } else {
            keep(
                Confidence::new(0.5 + (required_margin - margin) / 12.0),
                KeepReason::InsufficientEvidence,
            )
        }
    }

    fn is_known_word(&self, layout: LayoutId, text: &str) -> bool {
        !text.is_empty()
            && self
                .model
                .language(layout)
                .score(text)
                .is_some_and(|score| score.frequency.is_some())
    }

    /// Whether a word kept as `ShortAmbiguous` may be rewritten together with a confident
    /// conversion that follows it. Every keystroke must render as a letter in both layouts,
    /// so `a,` (`фб`) or `f.` (`аю`) never ride, and the word must not be a listed common
    /// short word of its own layout. With `require_target_word`, the other rendering must
    /// be a listed common short word of the other language.
    pub fn may_ride(
        &self,
        strokes: &[KeyStroke],
        current_layout: LayoutId,
        require_target_word: bool,
    ) -> bool {
        let target_layout = current_layout.alternate();
        let all_letters = |layout: LayoutId| {
            let layout = layout.layout();
            strokes
                .iter()
                .all(|stroke| layout.render_key(*stroke).is_alphabetic())
        };
        if strokes.is_empty() || !all_letters(current_layout) || !all_letters(target_layout) {
            return false;
        }
        // The dictionary misses some common short words (`is`), so check the list as well.
        let current = current_layout.layout().render(strokes).to_lowercase();
        if rider_targets(current_layout).contains(&current.as_str()) {
            return false;
        }
        let target = target_layout.layout().render(strokes).to_lowercase();
        !require_target_word || rider_targets(target_layout).contains(&target.as_str())
    }
}

const SHORT_WORD_MIN: usize = 2;
const MODEL_WORD_MIN: usize = 4;

/// One-letter words. A single letter outside this list is no word of its layout. The
/// dictionary cannot answer this: its subtitle frequency lists hold almost every letter.
const ONE_LETTER_ENGLISH: &[&str] = &["a", "i"];
const ONE_LETTER_UKRAINIAN: &[&str] = &["а", "в", "ж", "з", "і", "й", "о", "у", "я"];

fn one_letter_words(layout: LayoutId) -> &'static [&'static str] {
    match layout {
        LayoutId::Us => ONE_LETTER_ENGLISH,
        LayoutId::UkrainianPc => ONE_LETTER_UKRAINIAN,
    }
}

/// Common one- to three-letter words that a carried short word may become. The dictionary
/// is no filter here either: it holds nearly every two-letter string (`фб`, `вш`, `hq`).
const RIDER_ENGLISH: &[&str] = &[
    "a", "i", "am", "an", "as", "at", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it",
    "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "up", "us", "we", "ago", "all",
    "and", "any", "are", "ask", "bad", "big", "bit", "but", "buy", "can", "car", "day", "did",
    "dog", "eat", "end", "far", "few", "for", "fun", "get", "got", "guy", "had", "has", "her",
    "hey", "him", "his", "hot", "how", "its", "job", "let", "lot", "man", "may", "men", "new",
    "not", "now", "off", "old", "one", "our", "out", "own", "pay", "put", "red", "run", "saw",
    "say", "see", "set", "she", "sit", "six", "son", "ten", "the", "too", "top", "try", "two",
    "use", "was", "way", "who", "why", "win", "yes", "yet", "you",
];
const RIDER_UKRAINIAN: &[&str] = &[
    "а", "в", "ж", "з", "і", "й", "о", "у", "я", "би", "бо", "ви", "де", "до", "же", "за", "зі",
    "із", "її", "їй", "їм", "їх", "ми", "на", "не", "ні", "ну", "об", "от", "по", "та", "те", "ти",
    "ті", "то", "ту", "це", "ці", "ця", "цю", "чи", "що", "ще", "як", "аби", "або", "але", "без",
    "був", "вам", "вас", "ваш", "вже", "від", "він", "все", "всі", "два", "дві", "для", "дім",
    "ким", "мій", "моє", "моя", "нам", "нас", "наш", "над", "них", "ним", "ніж", "ось", "під",
    "при", "про", "раз", "рік", "сам", "так", "там", "теж", "тим", "той", "три", "тут", "хай",
    "хоч", "хто", "цей", "час", "чим", "щоб",
];

fn rider_targets(layout: LayoutId) -> &'static [&'static str] {
    match layout {
        LayoutId::Us => RIDER_ENGLISH,
        LayoutId::UkrainianPc => RIDER_UKRAINIAN,
    }
}

/// Two- and three-letter words that convert without the language model. Each entry was
/// checked against the Latin or Cyrillic gibberish it comes from: `yt` (не), `ns` (ти),
/// `vb` (ми) and similar collide with common abbreviations, so they stay out.
const SHORT_UKRAINIAN: &[&str] = &[
    "що", "як", "бо", "так", "все", "але", "для", "тут", "він", "вже", "які", "хто",
];
const SHORT_ENGLISH: &[&str] = &[
    "is", "in", "on", "to", "at", "we", "me", "my", "so", "do", "go", "no", "up", "be", "he", "if",
    "or", "an", "as", "by", "ok", "hi", "it", "the", "and", "you", "for", "not", "are", "but",
    "was", "can", "how", "why", "yes", "its", "all", "get", "has", "had", "her", "him", "his",
    "our", "out", "one", "two", "now", "new", "who", "did", "let", "use", "way", "day", "too",
    "any", "off", "yet", "got", "see", "she",
];

fn short_words(layout: LayoutId) -> &'static [&'static str] {
    match layout {
        LayoutId::Us => SHORT_ENGLISH,
        LayoutId::UkrainianPc => SHORT_UKRAINIAN,
    }
}

fn is_word_character(character: char) -> bool {
    character.is_alphabetic() || matches!(character, '\'' | 'ʼ' | '’')
}

/// Drop the trailing strokes that the target layout renders as punctuation, so `руддщб`
/// is judged as `hello` and still rewritten whole as `hello,`. Leading strokes stay:
/// Ukrainian words that start with `б`, `ю` or `ж` would otherwise lose real letters.
fn trim_trailing_punctuation(strokes: &[KeyStroke], target: LayoutId) -> &[KeyStroke] {
    let layout = target.layout();
    let end = strokes
        .iter()
        .rposition(|stroke| is_word_character(layout.render_key(*stroke)))
        .map_or(0, |index| index + 1);
    &strokes[..end]
}

fn keep(confidence: Confidence, reason: KeepReason) -> Verdict {
    Verdict::Keep { confidence, reason }
}

fn is_plain_word(current_text: &str, context: DecisionContext) -> bool {
    if context.token_class != TokenClass::Plain
        || current_text
            .chars()
            .any(|character| character.is_ascii_digit())
    {
        return false;
    }
    let letters: Vec<_> = current_text
        .chars()
        .filter(|character| character.is_alphabetic())
        .collect();
    let all_caps = letters.len() > 1 && letters.iter().all(|character| character.is_uppercase());
    let camel_case = letters
        .iter()
        .skip(1)
        .any(|character| character.is_uppercase());
    !(all_caps || camel_case)
}
