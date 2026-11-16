use std::{slice, str};

use engine::{
    ffi::{
        mova_engine_boundary, mova_engine_convert, mova_engine_edit, mova_engine_free,
        mova_engine_key, mova_engine_new, mova_engine_reset, mova_engine_undo, MovaAction,
        MovaActionKind, MovaEngine,
    },
    LayoutId, Span,
};

#[test]
fn c_api_rewrites_and_undoes_a_word() {
    let handle = mova_engine_new();
    assert!(!handle.is_null());
    type_word(handle, LayoutId::UkrainianPc, "привіт");

    let rewrite = unsafe { mova_engine_boundary(handle, LayoutId::Us as u8, 0, 1) };
    assert_eq!(rewrite.kind, MovaActionKind::Rewrite);
    assert_eq!(rewrite.span, Span::WordAndBoundary as u8);
    assert_eq!(rewrite.delete_chars, 6);
    assert_eq!(action_text(&rewrite), "привіт");
    assert_eq!(rewrite.switch_to, LayoutId::UkrainianPc as u8);

    let undo = unsafe { mova_engine_undo(handle) };
    assert_eq!(undo.kind, MovaActionKind::Rewrite);
    assert_eq!(undo.delete_chars, 6);
    assert_eq!(action_text(&undo), "ghbdsn");
    assert_eq!(undo.switch_to, LayoutId::Us as u8);
    assert_eq!(undo.learned_exception, 0);

    unsafe { mova_engine_free(handle) };
}

#[test]
fn c_api_carries_short_words_and_points_learning_at_the_long_word() {
    let handle = mova_engine_new();
    for learned in [0, 1] {
        type_word(handle, LayoutId::UkrainianPc, "а");
        let kept = unsafe { mova_engine_boundary(handle, LayoutId::Us as u8, 0, 1) };
        assert_eq!(kept.kind, MovaActionKind::None);
        assert_eq!(kept.undecided_words, 1);

        type_word(handle, LayoutId::UkrainianPc, "потім");
        let rewrite = unsafe { mova_engine_boundary(handle, LayoutId::Us as u8, 0, 1) };
        assert_eq!(rewrite.kind, MovaActionKind::Rewrite);
        assert_eq!(rewrite.delete_chars, 7);
        assert_eq!(action_text(&rewrite), "а потім");
        assert_eq!(rewrite.rider_count, 1);
        assert_eq!(rewrite.word_offset, "а ".len());
        assert_eq!(rewrite.undecided_words, 0);

        let undo = unsafe { mova_engine_undo(handle) };
        assert_eq!(undo.delete_chars, 7);
        assert_eq!(action_text(&undo), "f gjnsv");
        assert_eq!(undo.rider_count, 1);
        assert_eq!(&action_text(&undo)[undo.word_offset..], "gjnsv");
        assert_eq!(undo.learned_exception, learned);
        unsafe { mova_engine_reset(handle) };
    }
    unsafe { mova_engine_free(handle) };
}

#[test]
fn c_api_edit_blocks_and_convert_forces() {
    let handle = mova_engine_new();
    type_word(handle, LayoutId::UkrainianPc, "привіт");
    assert_eq!(
        unsafe { mova_engine_edit(handle) }.kind,
        MovaActionKind::None
    );
    assert_eq!(
        unsafe { mova_engine_boundary(handle, LayoutId::Us as u8, 0, 1) }.kind,
        MovaActionKind::None
    );

    type_word(handle, LayoutId::Us, "hello");
    let convert = unsafe { mova_engine_convert(handle) };
    assert_eq!(convert.kind, MovaActionKind::Rewrite);
    assert_eq!(convert.span, Span::CurrentWord as u8);
    assert_eq!(action_text(&convert), "руддщ");
    unsafe { mova_engine_free(handle) };
}

#[test]
fn c_api_rejects_invalid_values_and_null_handles() {
    let handle = mova_engine_new();
    let action = unsafe { mova_engine_key(handle, 200, 0, LayoutId::Us as u8) };
    assert_eq!(action.kind, MovaActionKind::Error);
    let action = unsafe { mova_engine_boundary(handle, 9, 0, 1) };
    assert_eq!(action.kind, MovaActionKind::Error);
    let action = unsafe { mova_engine_undo(std::ptr::null_mut()) };
    assert_eq!(action.kind, MovaActionKind::Error);
    unsafe { mova_engine_free(handle) };
}

fn type_word(handle: *mut MovaEngine, intended: LayoutId, word: &str) {
    for stroke in intended.layout().keystrokes_for(word).unwrap() {
        let action = unsafe {
            mova_engine_key(
                handle,
                stroke.key as u8,
                u8::from(stroke.shift),
                LayoutId::Us as u8,
            )
        };
        assert_eq!(action.kind, MovaActionKind::None);
    }
}

fn action_text(action: &MovaAction) -> &str {
    let bytes = unsafe { slice::from_raw_parts(action.insert_utf8, action.insert_len) };
    str::from_utf8(bytes).unwrap()
}
