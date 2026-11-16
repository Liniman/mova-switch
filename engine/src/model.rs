use std::sync::OnceLock;

use crate::LayoutId;

const EMBEDDED_MODEL: &str = include_str!("../../data/model-shipped.tsv");

#[derive(Debug)]
pub(crate) struct ModelSet {
    us: LanguageModel,
    ukrainian_pc: LanguageModel,
}

impl ModelSet {
    pub(crate) fn embedded() -> &'static Self {
        static MODEL: OnceLock<ModelSet> = OnceLock::new();
        MODEL.get_or_init(|| Self::parse(EMBEDDED_MODEL))
    }

    pub(crate) fn leak(source: &str) -> &'static Self {
        Box::leak(Box::new(Self::parse(source)))
    }

    pub(crate) fn language(&self, layout: LayoutId) -> &LanguageModel {
        match layout {
            LayoutId::Us => &self.us,
            LayoutId::UkrainianPc => &self.ukrainian_pc,
        }
    }

    fn parse(source: &str) -> Self {
        let mut lines = source.lines();
        assert_eq!(
            lines.next(),
            Some("MOVA_MODEL_V1"),
            "bad embedded model header"
        );
        let mut languages = Vec::new();

        while let Some(line) = lines.next() {
            if line.starts_with("SOURCE\t") || line.is_empty() {
                continue;
            }
            let id = line
                .strip_prefix("LANG\t")
                .unwrap_or_else(|| panic!("expected language header, found {line:?}"));
            let alphabet_line = lines.next().expect("missing alphabet");
            let alphabet: Vec<_> = alphabet_line
                .strip_prefix("ALPHABET\t")
                .expect("bad alphabet header")
                .chars()
                .collect();
            let word_count = parse_count(lines.next(), "WORDS");
            let mut words = Vec::with_capacity(word_count);
            for _ in 0..word_count {
                let line = lines.next().expect("missing word row");
                let mut fields = line.split('\t');
                assert_eq!(fields.next(), Some("WORD"), "bad word row");
                let word = fields.next().expect("missing word").to_owned();
                let frequency = fields
                    .next()
                    .expect("missing word frequency")
                    .parse::<u32>()
                    .expect("bad word frequency");
                assert!(fields.next().is_none(), "extra word fields");
                words.push((word, frequency));
            }
            let bigram_count = parse_count(lines.next(), "BIGRAMS");
            let bigrams = read_scores(&mut lines, bigram_count);
            let trigram_count = parse_count(lines.next(), "TRIGRAMS");
            let trigrams = read_scores(&mut lines, trigram_count);
            assert_eq!(lines.next(), Some("END"), "missing language terminator");
            let symbols = alphabet.len() + 2;
            assert_eq!(bigrams.len(), symbols * symbols, "bad bigram table size");
            assert_eq!(
                trigrams.len(),
                symbols * symbols * symbols,
                "bad trigram table size"
            );
            languages.push((
                id.to_owned(),
                LanguageModel {
                    alphabet,
                    words,
                    bigrams,
                    trigrams,
                },
            ));
        }

        let us = take_language(&mut languages, "us");
        let ukrainian_pc = take_language(&mut languages, "ukrainian-pc");
        assert!(
            languages.is_empty(),
            "unexpected language in embedded model"
        );
        Self { us, ukrainian_pc }
    }
}

#[derive(Debug)]
pub(crate) struct LanguageModel {
    alphabet: Vec<char>,
    words: Vec<(String, u32)>,
    bigrams: Vec<i16>,
    trigrams: Vec<i16>,
}

impl LanguageModel {
    pub(crate) fn score(&self, text: &str) -> Option<WordScore> {
        let symbols = self.alphabet.len() + 2;
        let start = self.alphabet.len();
        let end = start + 1;
        let normalized: String = text
            .to_lowercase()
            .chars()
            .map(|character| match character {
                '’' | 'ʼ' => '\'',
                other => other,
            })
            .collect();
        let mut sequence = Vec::with_capacity(normalized.chars().count() + 4);
        sequence.extend([start, start]);
        for character in normalized.chars() {
            sequence.push(self.alphabet.iter().position(|item| *item == character)?);
        }
        sequence.extend([end, end]);

        let bigram_sum: i32 = sequence
            .windows(2)
            .map(|pair| i32::from(self.bigrams[pair[0] * symbols + pair[1]]))
            .sum();
        let trigram_sum: i32 = sequence
            .windows(3)
            .map(|triple| {
                let index = (triple[0] * symbols + triple[1]) * symbols + triple[2];
                i32::from(self.trigrams[index])
            })
            .sum();
        let bigram_average = bigram_sum as f32 / (sequence.len() - 1) as f32 / 256.0;
        let trigram_average = trigram_sum as f32 / (sequence.len() - 2) as f32 / 256.0;
        let frequency = self
            .words
            .binary_search_by(|(word, _)| word.as_str().cmp(&normalized))
            .ok()
            .map(|index| self.words[index].1);
        Some(WordScore {
            ngram: bigram_average * 0.35 + trigram_average * 0.65,
            frequency,
        })
    }
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct WordScore {
    pub(crate) ngram: f32,
    pub(crate) frequency: Option<u32>,
}

impl WordScore {
    pub(crate) fn total(self) -> f32 {
        self.ngram
            + self
                .frequency
                .map_or(0.0, |frequency| 2.0 + (frequency as f32).ln() * 0.08)
    }
}

fn parse_count(line: Option<&str>, label: &str) -> usize {
    let line = line.unwrap_or_else(|| panic!("missing {label} header"));
    let (actual_label, count) = line
        .split_once('\t')
        .unwrap_or_else(|| panic!("bad {label} header"));
    assert_eq!(actual_label, label, "unexpected model section");
    count.parse::<usize>().expect("bad model count")
}

fn read_scores<'a>(lines: &mut impl Iterator<Item = &'a str>, count: usize) -> Vec<i16> {
    let mut scores = Vec::with_capacity(count);
    while scores.len() < count {
        let line = lines.next().expect("missing n-gram scores");
        scores.extend(
            line.split_ascii_whitespace()
                .map(|value| value.parse::<i16>().expect("bad n-gram score")),
        );
    }
    assert_eq!(scores.len(), count, "too many n-gram scores");
    scores
}

fn take_language(languages: &mut Vec<(String, LanguageModel)>, id: &str) -> LanguageModel {
    let index = languages
        .iter()
        .position(|(candidate, _)| candidate == id)
        .unwrap_or_else(|| panic!("missing {id} model"));
    languages.swap_remove(index).1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_models_prefer_real_language_sequences() {
        let model = ModelSet::embedded();
        let english = model.language(LayoutId::Us);
        let ukrainian = model.language(LayoutId::UkrainianPc);

        assert!(english.score("hello").unwrap().ngram > english.score("ghbdsn").unwrap().ngram);
        assert!(ukrainian.score("привіт").unwrap().ngram > ukrainian.score("руддщ").unwrap().ngram);
    }
}
