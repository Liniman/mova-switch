use std::{ptr, slice, str};

use crate::{
    Action, DecisionContext, KeyStroke, LayoutId, PhysicalKey, Session, SessionEvent, TokenClass,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u8)]
pub enum MovaActionKind {
    None = 0,
    Rewrite = 1,
    Error = 255,
}

#[derive(Clone, Copy, Debug)]
#[repr(C)]
pub struct MovaAction {
    pub kind: MovaActionKind,
    pub span: u8,
    pub switch_to: u8,
    pub learned_exception: u8,
    pub confidence: f32,
    pub delete_chars: usize,
    pub insert_utf8: *const u8,
    pub insert_len: usize,
    pub rider_count: usize,
    pub word_offset: usize,
    pub undecided_words: usize,
}

impl MovaAction {
    fn none() -> Self {
        Self {
            kind: MovaActionKind::None,
            span: 0,
            switch_to: 0,
            learned_exception: 0,
            confidence: 0.0,
            delete_chars: 0,
            insert_utf8: ptr::null(),
            insert_len: 0,
            rider_count: 0,
            word_offset: 0,
            undecided_words: 0,
        }
    }

    fn error() -> Self {
        Self {
            kind: MovaActionKind::Error,
            ..Self::none()
        }
    }
}

pub struct MovaEngine {
    session: Session,
    output: Vec<u8>,
}

impl MovaEngine {
    fn apply(&mut self, event: SessionEvent) -> MovaAction {
        let action = self.session.handle(event);
        let undecided_words = self.session.undecided_words();
        self.output.clear();
        let Some(Action::Rewrite {
            span,
            delete_chars,
            insert_text,
            riders,
            word_start,
            switch_to,
            confidence,
            learned_exception,
        }) = action
        else {
            return MovaAction {
                undecided_words,
                ..MovaAction::none()
            };
        };
        self.output.extend_from_slice(insert_text.as_bytes());
        MovaAction {
            kind: MovaActionKind::Rewrite,
            span: span as u8,
            switch_to: switch_to as u8,
            learned_exception: u8::from(learned_exception),
            confidence: confidence.get(),
            delete_chars,
            insert_utf8: self.output.as_ptr(),
            insert_len: self.output.len(),
            rider_count: riders,
            word_offset: word_start,
            undecided_words,
        }
    }
}

/// Run `body` on the engine behind `engine`, or return an error action for a null handle.
///
/// # Safety
/// `engine` must be null or a live pointer from `mova_engine_new`, not used concurrently.
unsafe fn with_engine(
    engine: *mut MovaEngine,
    body: impl FnOnce(&mut MovaEngine) -> MovaAction,
) -> MovaAction {
    match unsafe { engine.as_mut() } {
        Some(engine) => body(engine),
        None => MovaAction::error(),
    }
}

#[no_mangle]
pub extern "C" fn mova_engine_new() -> *mut MovaEngine {
    Box::into_raw(Box::new(MovaEngine {
        session: Session::default(),
        output: Vec::new(),
    }))
}

/// # Safety
/// `engine` must be null or a pointer from `mova_engine_new` that was not freed yet.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_free(engine: *mut MovaEngine) {
    if !engine.is_null() {
        drop(unsafe { Box::from_raw(engine) });
    }
}

/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_key(
    engine: *mut MovaEngine,
    key: u8,
    shift: u8,
    current_layout: u8,
) -> MovaAction {
    let (Some(key), Some(current_layout)) = (
        PhysicalKey::ALL.get(usize::from(key)).copied(),
        layout_from_u8(current_layout),
    ) else {
        return MovaAction::error();
    };
    unsafe {
        with_engine(engine, |engine| {
            engine.apply(SessionEvent::Key {
                stroke: KeyStroke::new(key, shift != 0),
                current_layout,
            })
        })
    }
}

/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_edit(engine: *mut MovaEngine) -> MovaAction {
    unsafe { with_engine(engine, |engine| engine.apply(SessionEvent::Edit)) }
}

/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_boundary(
    engine: *mut MovaEngine,
    current_layout: u8,
    token_class: u8,
    is_space: u8,
) -> MovaAction {
    let (Some(current_layout), Some(token_class)) = (
        layout_from_u8(current_layout),
        token_class_from_u8(token_class),
    ) else {
        return MovaAction::error();
    };
    unsafe {
        with_engine(engine, |engine| {
            engine.apply(SessionEvent::Boundary {
                current_layout,
                context: DecisionContext {
                    token_class,
                    ..DecisionContext::default()
                },
                is_space: is_space != 0,
            })
        })
    }
}

/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_undo(engine: *mut MovaEngine) -> MovaAction {
    unsafe { with_engine(engine, |engine| engine.apply(SessionEvent::Undo)) }
}

/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_convert(engine: *mut MovaEngine) -> MovaAction {
    unsafe { with_engine(engine, |engine| engine.apply(SessionEvent::Convert)) }
}

/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_reset(engine: *mut MovaEngine) {
    unsafe {
        with_engine(engine, |engine| engine.apply(SessionEvent::Reset));
    }
}

/// # Safety
/// `engine` must be null or a live handle. `text_utf8` must point to `text_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_add_exception(
    engine: *mut MovaEngine,
    layout: u8,
    text_utf8: *const u8,
    text_len: usize,
) -> u8 {
    let Some(engine) = (unsafe { engine.as_mut() }) else {
        return 0;
    };
    let Some(layout) = layout_from_u8(layout) else {
        return 0;
    };
    if text_utf8.is_null() {
        return 0;
    }
    let bytes = unsafe { slice::from_raw_parts(text_utf8, text_len) };
    let Ok(text) = str::from_utf8(bytes) else {
        return 0;
    };
    u8::from(engine.session.exceptions_mut().insert(layout, text))
}

/// Forget every exception, learned or loaded.
///
/// # Safety
/// `engine` must be null or a live handle from `mova_engine_new`.
#[no_mangle]
pub unsafe extern "C" fn mova_engine_clear_exceptions(engine: *mut MovaEngine) {
    if let Some(engine) = unsafe { engine.as_mut() } {
        *engine.session.exceptions_mut() = Default::default();
    }
}

fn layout_from_u8(value: u8) -> Option<LayoutId> {
    match value {
        0 => Some(LayoutId::Us),
        1 => Some(LayoutId::UkrainianPc),
        _ => None,
    }
}

fn token_class_from_u8(value: u8) -> Option<TokenClass> {
    match value {
        0 => Some(TokenClass::Plain),
        1 => Some(TokenClass::Code),
        2 => Some(TokenClass::Email),
        3 => Some(TokenClass::Path),
        4 => Some(TokenClass::Url),
        _ => None,
    }
}
