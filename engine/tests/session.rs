use engine::{
    Action, DecisionContext, LayoutId, RiderPolicy, Session, SessionEvent, SessionPhase, Span,
};

const US: LayoutId = LayoutId::Us;
const UA: LayoutId = LayoutId::UkrainianPc;

#[test]
fn emits_a_rewrite_after_a_wrong_layout_word() {
    let mut session = Session::default();
    type_word(&mut session, US, UA, "привіт");
    assert_eq!(session.phase(), SessionPhase::Typing);

    assert_eq!(
        rewrite(boundary(&mut session, US)),
        Some((Span::WordAndBoundary, 6, "привіт".into(), UA, false))
    );
    assert_eq!(session.phase(), SessionPhase::Undo);
}

#[test]
fn converts_wrong_layout_english_typed_on_ukrainian() {
    let mut session = Session::default();
    type_word(&mut session, UA, US, "hello");
    assert_eq!(
        rewrite(boundary(&mut session, UA)),
        Some((Span::WordAndBoundary, 5, "hello".into(), US, false))
    );
}

#[test]
fn first_undo_reverts_and_second_undo_of_the_same_word_learns_it() {
    let mut session = Session::default();
    for learned in [false, true] {
        type_word(&mut session, US, UA, "привіт");
        assert!(boundary(&mut session, US).is_some());
        assert_eq!(
            rewrite(session.handle(SessionEvent::Undo)),
            Some((Span::WordAndBoundary, 6, "ghbdsn".into(), US, learned))
        );
        session.handle(SessionEvent::Reset);
    }
    assert!(session.exceptions().contains(US, "ghbdsn"));

    type_word(&mut session, US, UA, "привіт");
    assert_eq!(boundary(&mut session, US), None);
}

#[test]
fn undo_without_a_rewrite_does_nothing() {
    let mut session = Session::default();
    type_word(&mut session, US, US, "hello");
    assert_eq!(session.handle(SessionEvent::Undo), None);
    assert_eq!(session.phase(), SessionPhase::Typing);
}

#[test]
fn editing_inside_a_word_blocks_its_conversion() {
    let mut session = Session::default();
    type_word(&mut session, US, UA, "прив");
    session.handle(SessionEvent::Edit);
    type_word(&mut session, US, UA, "віт");
    assert_eq!(boundary(&mut session, US), None);

    type_word(&mut session, US, UA, "привіт");
    assert!(boundary(&mut session, US).is_some());
}

#[test]
fn manual_convert_rewrites_the_current_word_then_blocks_the_rest() {
    let mut session = Session::default();
    type_word(&mut session, US, US, "hello");
    assert_eq!(
        rewrite(session.handle(SessionEvent::Convert)),
        Some((Span::CurrentWord, 5, "руддщ".into(), UA, false))
    );
    type_word(&mut session, UA, UA, "ф");
    assert_eq!(boundary(&mut session, UA), None);
}

#[test]
fn manual_convert_after_a_kept_word_includes_the_boundary_and_toggles_back() {
    let mut session = Session::default();
    type_word(&mut session, US, US, "hello");
    assert_eq!(boundary(&mut session, US), None);
    assert_eq!(session.phase(), SessionPhase::Finished);

    assert_eq!(
        rewrite(session.handle(SessionEvent::Convert)),
        Some((Span::WordAndBoundary, 5, "руддщ".into(), UA, false))
    );
    assert_eq!(
        rewrite(session.handle(SessionEvent::Undo)),
        Some((Span::WordAndBoundary, 5, "hello".into(), US, false))
    );
    assert!(session.exceptions().is_empty());
}

#[test]
fn a_key_after_the_boundary_ends_the_manual_convert_window() {
    let mut session = Session::default();
    type_word(&mut session, US, US, "hello");
    boundary(&mut session, US);
    type_word(&mut session, US, US, "w");
    assert_eq!(
        rewrite(session.handle(SessionEvent::Convert)),
        Some((Span::CurrentWord, 1, "ц".into(), UA, false))
    );
}

#[test]
fn words_longer_than_32_keystrokes_are_never_converted() {
    let mut session = Session::default();
    type_word(&mut session, US, UA, &"привіт".repeat(6));
    assert_eq!(boundary(&mut session, US), None);
}

#[test]
fn layout_change_mid_word_starts_a_new_word() {
    let mut session = Session::default();
    let strokes = US.layout().keystrokes_for("hello").unwrap();
    session.handle(SessionEvent::Key {
        stroke: strokes[0],
        current_layout: US,
    });
    session.handle(SessionEvent::Key {
        stroke: strokes[1],
        current_layout: UA,
    });
    assert_eq!(boundary(&mut session, US), None);
}

#[test]
fn a_confident_word_carries_the_short_words_typed_before_it() {
    let mut session = Session::default();
    type_phrase(&mut session, UA, US, &["i", "am"]);
    assert_eq!(session.undecided_words(), 2);
    type_word(&mut session, UA, US, "switching");
    let action = boundary(&mut session, UA).unwrap();
    assert_eq!(
        rewrite(Some(action.clone())),
        Some((
            Span::WordAndBoundary,
            14,
            "i am switching".into(),
            US,
            false
        ))
    );
    assert_eq!(riders(&action), (2, "i am ".len()));
    assert_eq!(session.undecided_words(), 0);

    let mut session = Session::default();
    type_phrase(&mut session, US, UA, &["а"]);
    type_word(&mut session, US, UA, "потім");
    assert_eq!(
        rewrite(boundary(&mut session, US)),
        Some((Span::WordAndBoundary, 7, "а потім".into(), UA, false))
    );
}

#[test]
fn one_undo_restores_the_whole_run_and_learns_only_the_long_word() {
    let mut session = Session::default();
    for learned in [false, true] {
        type_phrase(&mut session, UA, US, &["i", "am"]);
        type_word(&mut session, UA, US, "switching");
        assert!(boundary(&mut session, UA).is_some());
        let undo = session.handle(SessionEvent::Undo).unwrap();
        assert_eq!(
            rewrite(Some(undo.clone())),
            Some((
                Span::WordAndBoundary,
                14,
                "ш фь іцшесрштп".into(),
                UA,
                learned
            ))
        );
        assert_eq!(riders(&undo), (2, "ш фь ".len()));
        assert_eq!(session.phase(), SessionPhase::Finished);
        session.handle(SessionEvent::Reset);
    }
    let learned: Vec<_> = session.exceptions().iter().collect();
    assert_eq!(learned, vec![(UA, "іцшесрштп")]);
}

#[test]
fn convert_after_undoing_a_run_converts_only_the_long_word() {
    let mut session = Session::default();
    type_phrase(&mut session, UA, US, &["i", "am"]);
    type_word(&mut session, UA, US, "switching");
    boundary(&mut session, UA);
    session.handle(SessionEvent::Undo);
    let convert = session.handle(SessionEvent::Convert).unwrap();
    assert_eq!(
        rewrite(Some(convert.clone())),
        Some((Span::WordAndBoundary, 9, "switching".into(), US, false))
    );
    assert_eq!(riders(&convert), (0, 0));
}

#[test]
fn anything_that_breaks_the_run_drops_it() {
    let breaks: [RunBreak; 4] = [
        ("reset", |session| {
            session.handle(SessionEvent::Reset);
        }),
        ("second boundary", |session| {
            boundary(session, UA);
        }),
        ("known word", |session| {
            type_word(session, UA, UA, "так");
            boundary(session, UA);
        }),
        ("manual convert", |session| {
            session.handle(SessionEvent::Convert);
            session.handle(SessionEvent::Undo);
        }),
    ];
    for (name, break_run) in breaks {
        let mut session = Session::default();
        type_phrase(&mut session, UA, US, &["i", "am"]);
        break_run(&mut session);
        assert_eq!(session.undecided_words(), 0, "{name}");
        type_word(&mut session, UA, US, "switching");
        assert_eq!(
            rewrite(boundary(&mut session, UA)).map(|rewrite| rewrite.2),
            Some("switching".into()),
            "{name}"
        );
    }
}

#[test]
fn a_layout_change_an_edit_or_a_non_space_boundary_drops_the_run() {
    let mut session = Session::default();
    type_phrase(&mut session, UA, US, &["i", "am"]);
    type_word(&mut session, US, US, "switching");
    assert_eq!(session.undecided_words(), 0);
    assert_eq!(boundary(&mut session, US), None);

    let mut session = Session::default();
    type_phrase(&mut session, UA, US, &["i", "am"]);
    type_word(&mut session, UA, US, "swit");
    session.handle(SessionEvent::Edit);
    assert_eq!(session.undecided_words(), 0);
    type_word(&mut session, UA, US, "ching");
    assert_eq!(boundary(&mut session, UA), None);

    let mut session = Session::default();
    type_word(&mut session, UA, US, "am");
    session.handle(SessionEvent::Boundary {
        current_layout: UA,
        context: DecisionContext::default(),
        is_space: false,
    });
    assert_eq!(session.undecided_words(), 0);
}

#[test]
fn a_correct_short_word_never_rides() {
    for (layout, other, short, long) in [
        (US, UA, "a", "привіт"),
        (US, UA, "i", "привіт"),
        (UA, US, "і", "switching"),
        (UA, US, "в", "switching"),
    ] {
        let mut session = Session::default();
        type_phrase(&mut session, layout, layout, &[short]);
        assert_eq!(session.undecided_words(), 0, "{short}");
        type_word(&mut session, layout, other, long);
        let action = boundary(&mut session, layout).unwrap();
        assert_eq!(riders(&action).0, 0, "{short}");
    }
}

#[test]
fn a_run_keeps_only_its_last_three_words() {
    let mut session = Session::default();
    type_phrase(&mut session, UA, US, &["oh", "i", "am", "a"]);
    assert_eq!(session.undecided_words(), 3);
    type_word(&mut session, UA, US, "teacher");
    assert_eq!(
        rewrite(boundary(&mut session, UA)).map(|rewrite| rewrite.2),
        Some("i am a teacher".into())
    );
}

#[test]
fn rider_policy_decides_whether_a_non_word_rides() {
    for (policy, expected) in [
        (RiderPolicy::Off, "привіт"),
        (RiderPolicy::AllLetters, "чй привіт"),
        (RiderPolicy::TargetWords, "привіт"),
    ] {
        let mut session = Session::default().with_rider_policy(policy);
        type_phrase(&mut session, US, US, &["xq"]);
        type_word(&mut session, US, UA, "привіт");
        assert_eq!(
            rewrite(boundary(&mut session, US)).map(|rewrite| rewrite.2),
            Some(expected.into()),
            "{policy:?}"
        );
    }
}

fn type_phrase(
    session: &mut Session,
    current_layout: LayoutId,
    intended_layout: LayoutId,
    words: &[&str],
) {
    for word in words {
        type_word(session, current_layout, intended_layout, word);
        assert_eq!(boundary(session, current_layout), None, "{word}");
    }
}

fn riders(action: &Action) -> (usize, usize) {
    match action {
        Action::Rewrite {
            riders, word_start, ..
        } => (*riders, *word_start),
    }
}

type Rewrite = (Span, usize, String, LayoutId, bool);
type RunBreak = (&'static str, fn(&mut Session));

fn rewrite(action: Option<Action>) -> Option<Rewrite> {
    action.map(|action| match action {
        Action::Rewrite {
            span,
            delete_chars,
            insert_text,
            switch_to,
            learned_exception,
            ..
        } => (
            span,
            delete_chars,
            insert_text,
            switch_to,
            learned_exception,
        ),
    })
}

fn boundary(session: &mut Session, current_layout: LayoutId) -> Option<Action> {
    session.handle(SessionEvent::Boundary {
        current_layout,
        context: DecisionContext::default(),
        is_space: true,
    })
}

fn type_word(
    session: &mut Session,
    current_layout: LayoutId,
    intended_layout: LayoutId,
    word: &str,
) {
    for stroke in intended_layout.layout().keystrokes_for(word).unwrap() {
        assert_eq!(
            session.handle(SessionEvent::Key {
                stroke,
                current_layout,
            }),
            None
        );
    }
}
