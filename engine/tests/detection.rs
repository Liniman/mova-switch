use engine::{DecisionContext, Detector, ExceptionSet, LayoutId, TokenClass, Verdict};

#[test]
fn switches_reference_wrong_layout_words() {
    let detector = Detector::embedded();
    let exceptions = ExceptionSet::default();

    let ukrainian = LayoutId::UkrainianPc
        .layout()
        .keystrokes_for("привіт")
        .unwrap();
    assert_eq!(LayoutId::Us.layout().render(&ukrainian), "ghbdsn");
    assert!(matches!(
        detector.decide(
            &ukrainian,
            LayoutId::Us,
            DecisionContext::default(),
            &exceptions
        ),
        Verdict::Switch {
            to: LayoutId::UkrainianPc,
            ..
        }
    ));

    let english = LayoutId::Us.layout().keystrokes_for("hello").unwrap();
    assert_eq!(LayoutId::UkrainianPc.layout().render(&english), "руддщ");
    assert!(matches!(
        detector.decide(
            &english,
            LayoutId::UkrainianPc,
            DecisionContext::default(),
            &exceptions
        ),
        Verdict::Switch {
            to: LayoutId::Us,
            ..
        }
    ));
}

#[test]
fn keeps_correct_words_short_words_and_transliteration() {
    let detector = Detector::embedded();
    let exceptions = ExceptionSet::default();

    for (layout, word) in [
        (LayoutId::Us, "hello"),
        (LayoutId::UkrainianPc, "привіт"),
        (LayoutId::Us, "ssh"),
        (LayoutId::UkrainianPc, "так"),
        (LayoutId::Us, "dyakuyu"),
    ] {
        let strokes = layout.layout().keystrokes_for(word).unwrap();
        assert!(matches!(
            detector.decide(&strokes, layout, DecisionContext::default(), &exceptions),
            Verdict::Keep { .. }
        ));
    }
}

#[test]
fn keeps_protected_contexts_and_user_exceptions() {
    let detector = Detector::embedded();
    let ukrainian = LayoutId::UkrainianPc
        .layout()
        .keystrokes_for("привіт")
        .unwrap();

    let protected = DecisionContext {
        token_class: TokenClass::Code,
        ..DecisionContext::default()
    };
    assert!(matches!(
        detector.decide(
            &ukrainian,
            LayoutId::Us,
            protected,
            &ExceptionSet::default()
        ),
        Verdict::Keep { .. }
    ));

    let mut exceptions = ExceptionSet::default();
    exceptions.insert(LayoutId::Us, "ghbdsn");
    assert!(matches!(
        detector.decide(
            &ukrainian,
            LayoutId::Us,
            DecisionContext::default(),
            &exceptions
        ),
        Verdict::Keep { .. }
    ));
}

#[test]
fn everyday_words_typed_in_the_wrong_layout_switch() {
    use LayoutId::{UkrainianPc as UA, Us as US};
    for (typed_on, intended, word) in [
        (US, UA, "дякую"),
        (US, UA, "Привіт"),
        (US, UA, "будь"),
        (US, UA, "як"),
        (US, UA, "так"),
        (UA, US, "help"),
        (UA, US, "the"),
        (UA, US, "you"),
        (UA, US, "hello,"),
    ] {
        assert!(
            is_switch(typed_on, intended, word),
            "{word} typed on {typed_on:?} should switch"
        );
    }
}

#[test]
fn correct_words_abbreviations_and_punctuated_words_stay() {
    use LayoutId::{UkrainianPc as UA, Us as US};
    for (layout, word) in [
        (US, "hello."),
        (US, "don't"),
        (US, "claude"),
        (US, "pryvit"),
        (US, "yt"),
        (US, "ns"),
        (US, "GHBDSN"),
        (UA, "привіт,"),
        (UA, "хліб"),
        (UA, "жешув"),
    ] {
        assert!(
            !is_switch(layout, layout, word),
            "{word} on {layout:?} should stay"
        );
    }
}

fn is_switch(typed_on: LayoutId, intended: LayoutId, word: &str) -> bool {
    let strokes = intended.layout().keystrokes_for(word).unwrap();
    matches!(
        Detector::embedded().decide(
            &strokes,
            typed_on,
            DecisionContext::default(),
            &ExceptionSet::default()
        ),
        Verdict::Switch { .. }
    )
}
