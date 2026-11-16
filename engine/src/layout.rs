#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
#[repr(u8)]
pub enum LayoutId {
    Us = 0,
    UkrainianPc = 1,
}

impl LayoutId {
    pub const fn alternate(self) -> Self {
        match self {
            Self::Us => Self::UkrainianPc,
            Self::UkrainianPc => Self::Us,
        }
    }

    pub const fn layout(self) -> Layout {
        Layout { id: self }
    }
}

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
#[repr(u8)]
pub enum PhysicalKey {
    Backquote,
    Digit1,
    Digit2,
    Digit3,
    Digit4,
    Digit5,
    Digit6,
    Digit7,
    Digit8,
    Digit9,
    Digit0,
    Minus,
    Equal,
    KeyQ,
    KeyW,
    KeyE,
    KeyR,
    KeyT,
    KeyY,
    KeyU,
    KeyI,
    KeyO,
    KeyP,
    BracketLeft,
    BracketRight,
    Backslash,
    KeyA,
    KeyS,
    KeyD,
    KeyF,
    KeyG,
    KeyH,
    KeyJ,
    KeyK,
    KeyL,
    Semicolon,
    Quote,
    KeyZ,
    KeyX,
    KeyC,
    KeyV,
    KeyB,
    KeyN,
    KeyM,
    Comma,
    Period,
    Slash,
}

impl PhysicalKey {
    pub const ALL: [Self; 47] = [
        Self::Backquote,
        Self::Digit1,
        Self::Digit2,
        Self::Digit3,
        Self::Digit4,
        Self::Digit5,
        Self::Digit6,
        Self::Digit7,
        Self::Digit8,
        Self::Digit9,
        Self::Digit0,
        Self::Minus,
        Self::Equal,
        Self::KeyQ,
        Self::KeyW,
        Self::KeyE,
        Self::KeyR,
        Self::KeyT,
        Self::KeyY,
        Self::KeyU,
        Self::KeyI,
        Self::KeyO,
        Self::KeyP,
        Self::BracketLeft,
        Self::BracketRight,
        Self::Backslash,
        Self::KeyA,
        Self::KeyS,
        Self::KeyD,
        Self::KeyF,
        Self::KeyG,
        Self::KeyH,
        Self::KeyJ,
        Self::KeyK,
        Self::KeyL,
        Self::Semicolon,
        Self::Quote,
        Self::KeyZ,
        Self::KeyX,
        Self::KeyC,
        Self::KeyV,
        Self::KeyB,
        Self::KeyN,
        Self::KeyM,
        Self::Comma,
        Self::Period,
        Self::Slash,
    ];
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct KeyStroke {
    pub key: PhysicalKey,
    pub shift: bool,
}

impl KeyStroke {
    pub const fn new(key: PhysicalKey, shift: bool) -> Self {
        Self { key, shift }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Glyph {
    plain: char,
    shifted: char,
}

impl Glyph {
    const fn new(plain: char, shifted: char) -> Self {
        Self { plain, shifted }
    }
}

const US: [Glyph; 47] = [
    Glyph::new('`', '~'),
    Glyph::new('1', '!'),
    Glyph::new('2', '@'),
    Glyph::new('3', '#'),
    Glyph::new('4', '$'),
    Glyph::new('5', '%'),
    Glyph::new('6', '^'),
    Glyph::new('7', '&'),
    Glyph::new('8', '*'),
    Glyph::new('9', '('),
    Glyph::new('0', ')'),
    Glyph::new('-', '_'),
    Glyph::new('=', '+'),
    Glyph::new('q', 'Q'),
    Glyph::new('w', 'W'),
    Glyph::new('e', 'E'),
    Glyph::new('r', 'R'),
    Glyph::new('t', 'T'),
    Glyph::new('y', 'Y'),
    Glyph::new('u', 'U'),
    Glyph::new('i', 'I'),
    Glyph::new('o', 'O'),
    Glyph::new('p', 'P'),
    Glyph::new('[', '{'),
    Glyph::new(']', '}'),
    Glyph::new('\\', '|'),
    Glyph::new('a', 'A'),
    Glyph::new('s', 'S'),
    Glyph::new('d', 'D'),
    Glyph::new('f', 'F'),
    Glyph::new('g', 'G'),
    Glyph::new('h', 'H'),
    Glyph::new('j', 'J'),
    Glyph::new('k', 'K'),
    Glyph::new('l', 'L'),
    Glyph::new(';', ':'),
    Glyph::new('\'', '"'),
    Glyph::new('z', 'Z'),
    Glyph::new('x', 'X'),
    Glyph::new('c', 'C'),
    Glyph::new('v', 'V'),
    Glyph::new('b', 'B'),
    Glyph::new('n', 'N'),
    Glyph::new('m', 'M'),
    Glyph::new(',', '<'),
    Glyph::new('.', '>'),
    Glyph::new('/', '?'),
];

const UKRAINIAN_PC: [Glyph; 47] = [
    Glyph::new('ґ', 'Ґ'),
    Glyph::new('1', '!'),
    Glyph::new('2', '"'),
    Glyph::new('3', '№'),
    Glyph::new('4', ';'),
    Glyph::new('5', '%'),
    Glyph::new('6', ':'),
    Glyph::new('7', '?'),
    Glyph::new('8', '*'),
    Glyph::new('9', '('),
    Glyph::new('0', ')'),
    Glyph::new('-', '_'),
    Glyph::new('=', '+'),
    Glyph::new('й', 'Й'),
    Glyph::new('ц', 'Ц'),
    Glyph::new('у', 'У'),
    Glyph::new('к', 'К'),
    Glyph::new('е', 'Е'),
    Glyph::new('н', 'Н'),
    Glyph::new('г', 'Г'),
    Glyph::new('ш', 'Ш'),
    Glyph::new('щ', 'Щ'),
    Glyph::new('з', 'З'),
    Glyph::new('х', 'Х'),
    Glyph::new('ї', 'Ї'),
    Glyph::new('ʼ', '₴'),
    Glyph::new('ф', 'Ф'),
    Glyph::new('і', 'І'),
    Glyph::new('в', 'В'),
    Glyph::new('а', 'А'),
    Glyph::new('п', 'П'),
    Glyph::new('р', 'Р'),
    Glyph::new('о', 'О'),
    Glyph::new('л', 'Л'),
    Glyph::new('д', 'Д'),
    Glyph::new('ж', 'Ж'),
    Glyph::new('є', 'Є'),
    Glyph::new('я', 'Я'),
    Glyph::new('ч', 'Ч'),
    Glyph::new('с', 'С'),
    Glyph::new('м', 'М'),
    Glyph::new('и', 'И'),
    Glyph::new('т', 'Т'),
    Glyph::new('ь', 'Ь'),
    Glyph::new('б', 'Б'),
    Glyph::new('ю', 'Ю'),
    Glyph::new('.', ','),
];

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Layout {
    id: LayoutId,
}

impl Layout {
    pub const fn id(self) -> LayoutId {
        self.id
    }

    pub fn render(self, strokes: &[KeyStroke]) -> String {
        strokes
            .iter()
            .map(|stroke| self.render_key(*stroke))
            .collect()
    }

    pub fn render_key(self, stroke: KeyStroke) -> char {
        let glyph = self.table()[stroke.key as usize];
        if stroke.shift {
            glyph.shifted
        } else {
            glyph.plain
        }
    }

    pub fn keystrokes_for(self, text: &str) -> Option<Vec<KeyStroke>> {
        text.chars()
            .map(|character| self.keystroke_for(character))
            .collect()
    }

    pub fn keystroke_for(self, character: char) -> Option<KeyStroke> {
        let normalized = match character {
            '\'' | '’' if self.id == LayoutId::UkrainianPc => 'ʼ',
            other => other,
        };

        self.table().iter().enumerate().find_map(|(index, glyph)| {
            let shift = if glyph.plain == normalized {
                false
            } else if glyph.shifted == normalized {
                true
            } else {
                return None;
            };

            Some(KeyStroke::new(PhysicalKey::ALL[index], shift))
        })
    }

    fn table(self) -> &'static [Glyph; 47] {
        match self.id {
            LayoutId::Us => &US,
            LayoutId::UkrainianPc => &UKRAINIAN_PC,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_reference_layout_mistakes() {
        let hello = LayoutId::Us.layout().keystrokes_for("hello").unwrap();
        assert_eq!(LayoutId::UkrainianPc.layout().render(&hello), "руддщ");

        let pryvit = LayoutId::UkrainianPc
            .layout()
            .keystrokes_for("привіт")
            .unwrap();
        assert_eq!(LayoutId::Us.layout().render(&pryvit), "ghbdsn");
    }

    #[test]
    fn round_trips_layout_specific_letters_and_punctuation() {
        for (layout, text) in [
            (LayoutId::Us, "[];',.\\`Qq"),
            (LayoutId::UkrainianPc, "хїжєбюґʼЇЄҐ₴"),
        ] {
            let strokes = layout.layout().keystrokes_for(text).unwrap();
            assert_eq!(layout.layout().render(&strokes), text);
        }
    }
}
