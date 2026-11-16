use std::{collections::BTreeMap, mem};

use crate::{
    Confidence, DecisionContext, Detector, ExceptionSet, KeepReason, KeyStroke, LayoutId, Verdict,
};

const MAX_WORD_STROKES: usize = 32;
/// The most short words one conversion carries along. Runs of one to three short words
/// before a long word (`i am`, `а потім`, `and i can`) cover nearly every phrase in the
/// phrase corpora; a longer run keeps only its last three words.
const MAX_RUN_WORDS: usize = 3;
const STRIKES_TO_LEARN: u8 = 2;

/// Which short words a confident conversion may carry along with it.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum RiderPolicy {
    /// Single-word decisions only.
    Off,
    /// Any short word kept as ambiguous whose keys are letters in both layouts.
    AllLetters,
    /// As `AllLetters`, and the other rendering must be a common short word there.
    #[default]
    TargetWords,
}

/// Which text a rewrite replaces.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum Span {
    /// The word is the last thing in the document. Nothing follows it.
    CurrentWord = 0,
    /// The word is followed by the boundary key the user typed. The shell
    /// deletes that boundary too and sends it again after the replay.
    WordAndBoundary = 1,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Action {
    Rewrite {
        span: Span,
        /// Characters before the boundary: the carried words, their Spaces, and the word.
        delete_chars: usize,
        /// The replacement for those characters, with one character per keystroke.
        insert_text: String,
        /// How many short words before the word this rewrite carries. Each is followed by
        /// one Space in both the deleted and the inserted text.
        riders: usize,
        /// Byte offset of the word that decided the rewrite within `insert_text`.
        word_start: usize,
        switch_to: LayoutId,
        confidence: Confidence,
        learned_exception: bool,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionEvent {
    Key {
        stroke: KeyStroke,
        current_layout: LayoutId,
    },
    /// The user edited inside the current word (Backspace, Delete, arrows).
    Edit,
    Boundary {
        current_layout: LayoutId,
        context: DecisionContext,
        /// The boundary key is a plain Space. Only a Space joins short words into a run.
        is_space: bool,
    },
    /// The user asked for the last automatic conversion to be reverted.
    Undo,
    /// The user asked for the current or just-finished word to be converted.
    Convert,
    Reset,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum SessionPhase {
    Idle,
    Typing,
    Finished,
    Blocked,
    Undo,
}

#[derive(Clone, Debug)]
struct Word {
    strokes: Vec<KeyStroke>,
    layout: LayoutId,
}

#[derive(Clone, Debug)]
struct LastRewrite {
    riders: Vec<Word>,
    word: Word,
    span: Span,
    automatic: bool,
}

#[derive(Debug)]
enum State {
    Idle,
    Typing(Word),
    /// A word ended at a boundary and was kept. Manual conversion still applies to it.
    Finished(Word),
    /// The current word was edited or already rewritten. It is never converted again.
    Blocked,
    Undo(LastRewrite),
}

#[derive(Debug)]
pub struct Session {
    detector: Detector,
    exceptions: ExceptionSet,
    strikes: BTreeMap<(LayoutId, String), u8>,
    state: State,
    /// Short words that ended at a Space right before the current word, typed under one
    /// layout with nothing in between that could have moved the caret. Never persisted.
    run: Vec<Word>,
    rider_policy: RiderPolicy,
}

impl Default for Session {
    fn default() -> Self {
        Self::new(Detector::embedded())
    }
}

impl Session {
    pub fn new(detector: Detector) -> Self {
        Self::with_exceptions(detector, ExceptionSet::default())
    }

    pub fn with_exceptions(detector: Detector, exceptions: ExceptionSet) -> Self {
        Self {
            detector,
            exceptions,
            strikes: BTreeMap::new(),
            state: State::Idle,
            run: Vec::new(),
            rider_policy: RiderPolicy::default(),
        }
    }

    pub fn with_rider_policy(mut self, rider_policy: RiderPolicy) -> Self {
        self.rider_policy = rider_policy;
        self
    }

    pub fn handle(&mut self, event: SessionEvent) -> Option<Action> {
        match event {
            SessionEvent::Key {
                stroke,
                current_layout,
            } => {
                self.on_key(stroke, current_layout);
                None
            }
            SessionEvent::Edit => {
                self.run.clear();
                self.state = State::Blocked;
                None
            }
            SessionEvent::Boundary {
                current_layout,
                context,
                is_space,
            } => self.on_boundary(current_layout, context, is_space),
            SessionEvent::Undo => self.on_undo(),
            SessionEvent::Convert => self.on_convert(),
            SessionEvent::Reset => {
                self.run.clear();
                self.state = State::Idle;
                None
            }
        }
    }

    pub fn phase(&self) -> SessionPhase {
        match self.state {
            State::Idle => SessionPhase::Idle,
            State::Typing(_) => SessionPhase::Typing,
            State::Finished(_) => SessionPhase::Finished,
            State::Blocked => SessionPhase::Blocked,
            State::Undo(_) => SessionPhase::Undo,
        }
    }

    /// How many finished short words the next conversion may still carry. A shell that
    /// replays keys keeps exactly this many finished words and their boundaries.
    pub fn undecided_words(&self) -> usize {
        self.run.len()
    }

    pub fn exceptions(&self) -> &ExceptionSet {
        &self.exceptions
    }

    pub fn exceptions_mut(&mut self) -> &mut ExceptionSet {
        &mut self.exceptions
    }

    fn on_key(&mut self, stroke: KeyStroke, current_layout: LayoutId) {
        if self
            .run
            .first()
            .is_some_and(|word| word.layout != current_layout)
        {
            self.run.clear();
        }
        self.state = match mem::replace(&mut self.state, State::Idle) {
            State::Typing(mut word) if word.layout == current_layout => {
                word.strokes.push(stroke);
                State::Typing(word)
            }
            State::Blocked => State::Blocked,
            State::Undo(rewrite) if rewrite.span == Span::CurrentWord => State::Blocked,
            State::Idle | State::Typing(_) | State::Finished(_) | State::Undo(_) => {
                State::Typing(Word {
                    strokes: vec![stroke],
                    layout: current_layout,
                })
            }
        };
    }

    fn on_boundary(
        &mut self,
        current_layout: LayoutId,
        context: DecisionContext,
        is_space: bool,
    ) -> Option<Action> {
        let word = match mem::replace(&mut self.state, State::Idle) {
            State::Typing(word) if word.layout == current_layout => word,
            _ => {
                self.run.clear();
                return None;
            }
        };
        if word.strokes.len() <= MAX_WORD_STROKES {
            match self
                .detector
                .decide(&word.strokes, word.layout, context, &self.exceptions)
            {
                Verdict::Switch { to, confidence } => {
                    let riders = mem::take(&mut self.run);
                    return Some(self.rewrite(
                        riders,
                        word,
                        to,
                        Span::WordAndBoundary,
                        true,
                        confidence,
                    ));
                }
                Verdict::Keep {
                    reason: KeepReason::ShortAmbiguous,
                    ..
                } if is_space && self.may_ride(&word) => {
                    if self.run.len() == MAX_RUN_WORDS {
                        self.run.remove(0);
                    }
                    self.run.push(word.clone());
                    self.state = State::Finished(word);
                    return None;
                }
                Verdict::Keep { .. } => {}
            }
        }
        self.run.clear();
        self.state = State::Finished(word);
        None
    }

    fn may_ride(&self, word: &Word) -> bool {
        let require_target_word = match self.rider_policy {
            RiderPolicy::Off => return false,
            RiderPolicy::AllLetters => false,
            RiderPolicy::TargetWords => true,
        };
        self.detector
            .may_ride(&word.strokes, word.layout, require_target_word)
    }

    fn on_convert(&mut self) -> Option<Action> {
        let (word, span) = match mem::replace(&mut self.state, State::Idle) {
            State::Typing(word) => (word, Span::CurrentWord),
            State::Finished(word) => (word, Span::WordAndBoundary),
            other => {
                self.state = other;
                return None;
            }
        };
        self.run.clear();
        let to = word.layout.alternate();
        Some(self.rewrite(Vec::new(), word, to, span, false, Confidence::CERTAIN))
    }

    fn rewrite(
        &mut self,
        riders: Vec<Word>,
        word: Word,
        to: LayoutId,
        span: Span,
        automatic: bool,
        confidence: Confidence,
    ) -> Action {
        let (insert_text, word_start) = render_run(&riders, &word, to);
        let action = Action::Rewrite {
            span,
            delete_chars: run_keystrokes(&riders, &word),
            insert_text,
            riders: riders.len(),
            word_start,
            switch_to: to,
            confidence,
            learned_exception: false,
        };
        self.state = State::Undo(LastRewrite {
            riders,
            word,
            span,
            automatic,
        });
        action
    }

    /// Restores the whole run and its layout in one step. Only the word that decided the
    /// conversion earns a strike: the carried short words were never judged on their own.
    fn on_undo(&mut self) -> Option<Action> {
        let rewrite = match mem::replace(&mut self.state, State::Idle) {
            State::Undo(rewrite) => rewrite,
            other => {
                self.state = other;
                return None;
            }
        };
        let original_layout = rewrite.word.layout;
        let (original_text, word_start) =
            render_run(&rewrite.riders, &rewrite.word, original_layout);
        let learned_exception =
            rewrite.automatic && self.record_strike(original_layout, &original_text[word_start..]);
        let action = Action::Rewrite {
            span: rewrite.span,
            delete_chars: run_keystrokes(&rewrite.riders, &rewrite.word),
            insert_text: original_text,
            riders: rewrite.riders.len(),
            word_start,
            switch_to: original_layout,
            confidence: Confidence::CERTAIN,
            learned_exception,
        };
        self.state = match rewrite.span {
            Span::CurrentWord => State::Blocked,
            Span::WordAndBoundary => State::Finished(rewrite.word),
        };
        Some(action)
    }

    fn record_strike(&mut self, layout: LayoutId, text: &str) -> bool {
        let key = (layout, text.to_lowercase());
        let strikes = self.strikes.entry(key.clone()).or_insert(0);
        *strikes += 1;
        if *strikes < STRIKES_TO_LEARN {
            return false;
        }
        self.strikes.remove(&key);
        self.exceptions.insert(layout, key.1)
    }
}

/// Renders carried words, each followed by its Space, then the word, under `layout`.
/// Returns the text and the byte offset where the word starts.
fn render_run(riders: &[Word], word: &Word, layout: LayoutId) -> (String, usize) {
    let layout = layout.layout();
    let mut text = String::new();
    for rider in riders {
        text.push_str(&layout.render(&rider.strokes));
        text.push(' ');
    }
    let word_start = text.len();
    text.push_str(&layout.render(&word.strokes));
    (text, word_start)
}

fn run_keystrokes(riders: &[Word], word: &Word) -> usize {
    riders
        .iter()
        .map(|rider| rider.strokes.len() + 1)
        .sum::<usize>()
        + word.strokes.len()
}
