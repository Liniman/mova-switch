use std::{
    collections::BTreeSet,
    env,
    error::Error,
    fs::{self, File},
    io::{BufRead, BufReader, BufWriter, Write},
    path::{Path, PathBuf},
};

const ENGLISH_ALPHABET: &str = "abcdefghijklmnopqrstuvwxyz'";
const UKRAINIAN_ALPHABET: &str = "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя'";
const FREQUENCY_REVISION: &str = "525f9b560de45753a5ea01069454e72e9aa541c6";
const DICTIONARIES_REVISION: &str = "c0865a85eb67dc377f2cf8e8fe2c4fa9e53f0dcb";
const MAX_ACCEPTED_WORDS: usize = 50_000;

#[derive(Clone, Debug)]
struct Word {
    text: String,
    frequency: u32,
}

struct LanguageData {
    id: &'static str,
    group: &'static str,
    layout: &'static str,
    alphabet: &'static str,
    train: Vec<Word>,
    heldout: Vec<Word>,
}

struct Scores {
    bigrams: Vec<i16>,
    trigrams: Vec<i16>,
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut arguments = env::args_os().skip(1);
    let frequency_root = required_path(&mut arguments, "FrequencyWords root")?;
    let dictionaries_root = required_path(&mut arguments, "LibreOffice dictionaries root")?;
    let model_path = required_path(&mut arguments, "eval model output")?;
    let shipped_model_path = required_path(&mut arguments, "shipped model output")?;
    let heldout_path = required_path(&mut arguments, "held-out output")?;
    if arguments.next().is_some() {
        return Err("expected exactly five arguments".into());
    }

    let english_dictionary =
        load_dictionary(&dictionaries_root.join("en/en_US.dic"), ENGLISH_ALPHABET)?;
    let ukrainian_dictionary = load_dictionary(
        &dictionaries_root.join("uk_UA/uk_UA.dic"),
        UKRAINIAN_ALPHABET,
    )?;

    let english = prepare_language(
        "us",
        "english",
        "us",
        ENGLISH_ALPHABET,
        &frequency_root.join("content/2018/en/en_50k.txt"),
        &english_dictionary,
    )?;
    let ukrainian = prepare_language(
        "ukrainian-pc",
        "ukrainian",
        "ukrainian-pc",
        UKRAINIAN_ALPHABET,
        &frequency_root.join("content/2018/uk/uk_full.txt"),
        &ukrainian_dictionary,
    )?;

    for language in [&english, &ukrainian] {
        if language.train.len() < 10_000 || language.heldout.len() < 1_000 {
            return Err(format!(
                "{} data is too small: {} train and {} held out",
                language.id,
                language.train.len(),
                language.heldout.len()
            )
            .into());
        }
    }

    write_model(&model_path, [&english, &ukrainian])?;
    write_model(
        &shipped_model_path,
        [
            &with_heldout_merged(&english),
            &with_heldout_merged(&ukrainian),
        ],
    )?;
    write_heldout(&heldout_path, [&english, &ukrainian])?;
    println!(
        "english: {} train, {} held out; ukrainian: {} train, {} held out",
        english.train.len(),
        english.heldout.len(),
        ukrainian.train.len(),
        ukrainian.heldout.len()
    );
    Ok(())
}

/// The shipped model learns from every accepted word. The eval model leaves the held-out words out.
fn with_heldout_merged(language: &LanguageData) -> LanguageData {
    LanguageData {
        train: language
            .train
            .iter()
            .chain(&language.heldout)
            .cloned()
            .collect(),
        heldout: Vec::new(),
        ..*language
    }
}

fn required_path(
    arguments: &mut impl Iterator<Item = std::ffi::OsString>,
    name: &str,
) -> Result<PathBuf, Box<dyn Error>> {
    arguments
        .next()
        .map(PathBuf::from)
        .ok_or_else(|| format!("missing {name}").into())
}

fn load_dictionary(path: &Path, alphabet: &str) -> Result<BTreeSet<String>, Box<dyn Error>> {
    let reader = BufReader::new(File::open(path)?);
    let mut words = BTreeSet::new();
    for (line_number, line) in reader.lines().enumerate() {
        let line = line?;
        if line_number == 0 && line.parse::<usize>().is_ok() {
            continue;
        }
        if line.starts_with('+') {
            continue;
        }
        let raw = line.split('/').next().unwrap_or_default();
        if let Some(word) = normalize(raw, alphabet) {
            words.insert(word);
        }
    }
    Ok(words)
}

fn prepare_language(
    id: &'static str,
    group: &'static str,
    layout: &'static str,
    alphabet: &'static str,
    frequency_path: &Path,
    dictionary: &BTreeSet<String>,
) -> Result<LanguageData, Box<dyn Error>> {
    let reader = BufReader::new(File::open(frequency_path)?);
    let mut seen = BTreeSet::new();
    let mut train = Vec::new();
    let mut heldout = Vec::new();

    for line in reader.lines() {
        let line = line?;
        let Some((raw_word, raw_frequency)) = line.rsplit_once(' ') else {
            continue;
        };
        let Some(word) = normalize(raw_word, alphabet) else {
            continue;
        };
        if !dictionary.contains(&word) || !seen.insert(word.clone()) {
            continue;
        }
        let frequency = raw_frequency.parse::<u32>()?;
        let entry = Word {
            text: word,
            frequency,
        };
        if is_heldout(&entry.text) {
            heldout.push(entry);
        } else {
            train.push(entry);
        }
        if train.len() + heldout.len() == MAX_ACCEPTED_WORDS {
            break;
        }
    }

    Ok(LanguageData {
        id,
        group,
        layout,
        alphabet,
        train,
        heldout,
    })
}

fn normalize(raw: &str, alphabet: &str) -> Option<String> {
    let normalized: String = raw
        .trim()
        .to_lowercase()
        .chars()
        .map(|character| match character {
            '’' | 'ʼ' => '\'',
            other => other,
        })
        .collect();
    let mut characters = normalized.chars();
    let first = characters.next()?;
    if first == '\'' || normalized.ends_with('\'') || normalized.chars().count() > 32 {
        return None;
    }
    if normalized
        .chars()
        .all(|character| alphabet.contains(character))
    {
        Some(normalized)
    } else {
        None
    }
}

fn is_heldout(word: &str) -> bool {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in word.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash % 5 == 0
}

fn write_model<const N: usize>(
    path: &Path,
    languages: [&LanguageData; N],
) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut writer = BufWriter::new(File::create(path)?);
    writeln!(writer, "MOVA_MODEL_V1")?;
    writeln!(writer, "SOURCE\tfrequency\t{FREQUENCY_REVISION}")?;
    writeln!(writer, "SOURCE\tdictionaries\t{DICTIONARIES_REVISION}")?;

    for language in languages {
        let scores = build_scores(language);
        let mut words = language.train.clone();
        words.sort_unstable_by(|left, right| left.text.cmp(&right.text));

        writeln!(writer, "LANG\t{}", language.id)?;
        writeln!(writer, "ALPHABET\t{}", language.alphabet)?;
        writeln!(writer, "WORDS\t{}", words.len())?;
        for word in words {
            writeln!(writer, "WORD\t{}\t{}", word.text, word.frequency)?;
        }
        writeln!(writer, "BIGRAMS\t{}", scores.bigrams.len())?;
        write_scores(&mut writer, &scores.bigrams)?;
        writeln!(writer, "TRIGRAMS\t{}", scores.trigrams.len())?;
        write_scores(&mut writer, &scores.trigrams)?;
        writeln!(writer, "END")?;
    }
    writer.flush()?;
    Ok(())
}

fn write_scores(writer: &mut impl Write, scores: &[i16]) -> Result<(), Box<dyn Error>> {
    for chunk in scores.chunks(32) {
        for (index, score) in chunk.iter().enumerate() {
            if index > 0 {
                write!(writer, " ")?;
            }
            write!(writer, "{score}")?;
        }
        writeln!(writer)?;
    }
    Ok(())
}

fn build_scores(language: &LanguageData) -> Scores {
    let alphabet: Vec<_> = language.alphabet.chars().collect();
    let symbols = alphabet.len() + 2;
    let start = alphabet.len();
    let end = start + 1;
    let mut bigrams = vec![0.0_f64; symbols * symbols];
    let mut bigram_totals = vec![0.0_f64; symbols];
    let mut trigrams = vec![0.0_f64; symbols * symbols * symbols];
    let mut trigram_totals = vec![0.0_f64; symbols * symbols];

    for word in &language.train {
        let weight = f64::from(word.frequency).ln_1p().max(1.0);
        let mut sequence = Vec::with_capacity(word.text.chars().count() + 4);
        sequence.extend([start, start]);
        sequence.extend(
            word.text
                .chars()
                .map(|character| alphabet.iter().position(|item| *item == character).unwrap()),
        );
        sequence.extend([end, end]);

        for pair in sequence.windows(2) {
            bigrams[pair[0] * symbols + pair[1]] += weight;
            bigram_totals[pair[0]] += weight;
        }
        for triple in sequence.windows(3) {
            let context = triple[0] * symbols + triple[1];
            trigrams[context * symbols + triple[2]] += weight;
            trigram_totals[context] += weight;
        }
    }

    Scores {
        bigrams: quantize(&bigrams, &bigram_totals, symbols),
        trigrams: quantize(&trigrams, &trigram_totals, symbols),
    }
}

fn quantize(counts: &[f64], totals: &[f64], symbols: usize) -> Vec<i16> {
    const SMOOTHING: f64 = 0.1;
    counts
        .iter()
        .enumerate()
        .map(|(index, count)| {
            let total = totals[index / symbols];
            let probability = (count + SMOOTHING) / (total + SMOOTHING * symbols as f64);
            (probability.ln() * 256.0).round() as i16
        })
        .collect()
}

fn write_heldout<const N: usize>(
    path: &Path,
    languages: [&LanguageData; N],
) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut writer = BufWriter::new(File::create(path)?);
    writeln!(writer, "# suite\tgroup\tlayout\tcatch\tcontext\tword")?;
    for language in languages {
        for word in &language.heldout {
            writeln!(
                writer,
                "heldout\t{}\t{}\tyes\tplain\t{}",
                language.group, language.layout, word.text
            )?;
        }
    }
    writer.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_apostrophes_and_rejects_other_scripts() {
        assert_eq!(
            normalize("П'ЯТЬ", UKRAINIAN_ALPHABET).as_deref(),
            Some("п'ять")
        );
        assert_eq!(
            normalize("пʼять", UKRAINIAN_ALPHABET).as_deref(),
            Some("п'ять")
        );
        assert_eq!(normalize("съезд", UKRAINIAN_ALPHABET), None);
        assert_eq!(normalize("hello", UKRAINIAN_ALPHABET), None);
    }

    #[test]
    fn split_is_stable() {
        assert_eq!(is_heldout("keyboard"), is_heldout("keyboard"));
    }
}
