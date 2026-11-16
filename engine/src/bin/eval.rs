use std::{
    collections::BTreeMap,
    time::{Duration, Instant},
};

use engine::{
    Action, DecisionContext, DecisionMoment, Detector, DetectorConfig, ExceptionSet, LayoutId,
    RiderPolicy, Session, SessionEvent, TokenClass, Verdict,
};

const EVAL_MODEL: &str = include_str!("../../../data/model.tsv");
const HELDOUT: &str = include_str!("../../../data/eval/heldout.tsv");
const HARD_NEGATIVES: &str = include_str!("../../../data/eval/hard-negatives.tsv");
const PHRASES: &str = include_str!("../../../data/eval/phrases.tsv");
const SHIPPED_MODEL: &str = include_str!("../../../data/model-shipped.tsv");
const FALSE_TARGET: f64 = 0.001;
const HARD_FALSE_TARGET: f64 = 0.005;
const CATCH_TARGET: f64 = 0.98;
const LATENCY_TARGET: Duration = Duration::from_micros(1_000);
const TIMING_ROUNDS: usize = 5;
const MID_WORD_MIN_PREFIX: usize = 4;

#[derive(Clone, Debug)]
struct Case {
    suite: String,
    group: String,
    layout: LayoutId,
    catch: bool,
    context: TokenClass,
    word: String,
}

#[derive(Default)]
struct Count {
    total: usize,
    success: usize,
    examples: Vec<String>,
}

#[derive(Default)]
struct EarlyMode {
    false_rows: BTreeMap<String, Count>,
    overall_false: Count,
    catches: BTreeMap<String, Count>,
    catches_before_final_key: BTreeMap<String, Count>,
    lead_keys: BTreeMap<String, Vec<usize>>,
}

impl Count {
    fn rate(&self) -> f64 {
        if self.total == 0 {
            0.0
        } else {
            self.success as f64 / self.total as f64
        }
    }
}

fn main() {
    let cases = parse_corpus();
    let (config, model) = parse_arguments();
    let detector = match model {
        ModelChoice::Eval => Detector::with_model_source(EVAL_MODEL, config),
        ModelChoice::Shipped => Detector::with_config(config),
    };
    let exceptions = ExceptionSet::default();
    let mut false_rows: BTreeMap<String, Count> = BTreeMap::new();
    let mut catch_rows: BTreeMap<String, Count> = BTreeMap::new();
    let mut overall_false = Count::default();
    let mut catch_aggregates: BTreeMap<String, Count> = BTreeMap::new();

    for case in &cases {
        let strokes = case
            .layout
            .layout()
            .keystrokes_for(&case.word)
            .unwrap_or_else(|| panic!("cannot encode {:?}", case.word));
        let context = DecisionContext {
            token_class: case.context,
            ..DecisionContext::default()
        };
        let verdict = detector.decide(&strokes, case.layout, context, &exceptions);
        let row = false_rows
            .entry(format!("{}/{}", case.suite, case.group))
            .or_default();
        row.total += 1;
        overall_false.total += 1;
        if matches!(verdict, Verdict::Switch { .. }) {
            row.success += 1;
            overall_false.success += 1;
            if row.examples.len() < 8 {
                row.examples.push(case.word.clone());
            }
            if overall_false.examples.len() < 8 {
                overall_false.examples.push(case.word.clone());
            }
        }

        if case.catch {
            let wrong_layout = case.layout.alternate();
            let verdict = detector.decide(&strokes, wrong_layout, context, &exceptions);
            let bucket = length_bucket(case.word.chars().count());
            let direction = format!(
                "{}->{}",
                layout_name(wrong_layout),
                layout_name(case.layout)
            );
            let row = catch_rows
                .entry(format!("{direction}/{bucket}"))
                .or_default();
            row.total += 1;
            let caught = matches!(verdict, Verdict::Switch { to, .. } if to == case.layout);
            if caught {
                row.success += 1;
            } else if row.examples.len() < 8 {
                row.examples.push(case.word.clone());
            }
            if case.word.chars().count() >= 4 {
                let aggregate = catch_aggregates.entry(direction).or_default();
                aggregate.total += 1;
                if caught {
                    aggregate.success += 1;
                } else if aggregate.examples.len() < 8 {
                    aggregate.examples.push(case.word.clone());
                }
            }
        }
    }

    let early = measure_early_mode(&detector, &exceptions, &cases);
    let timing = measure_latency(&detector, &exceptions, &cases);
    let mut failed = false;
    println!(
        "config: model={}, boundary_margin={:.3}, mid_word_margin={:.3}, minimum_target_score={:.3}",
        match model {
            ModelChoice::Eval => "eval (held-out words unseen)",
            ModelChoice::Shipped => "shipped (all words)",
        },
        config.boundary_margin,
        config.mid_word_margin,
        config.minimum_target_score
    );
    println!("metric | row | n | result | target | status");
    println!("--- | --- | ---: | ---: | ---: | ---");
    let overall_false_pass = overall_false.rate() <= FALSE_TARGET;
    failed |= !overall_false_pass;
    println!(
        "false-switch | overall correct text | {} | {:.3}% | <= {:.3}% | {}",
        overall_false.total,
        overall_false.rate() * 100.0,
        FALSE_TARGET * 100.0,
        status(overall_false_pass)
    );
    for (name, count) in &false_rows {
        let hard_negative = name.starts_with("hard/");
        let pass = !hard_negative || count.rate() <= HARD_FALSE_TARGET;
        failed |= hard_negative && !pass;
        println!(
            "false-switch | {name} | {} | {:.3}% | {} | {}",
            count.total,
            count.rate() * 100.0,
            if hard_negative {
                "<= 0.500%"
            } else {
                "report only"
            },
            status(pass)
        );
    }
    for (name, count) in &catch_aggregates {
        let pass = count.rate() >= CATCH_TARGET;
        failed |= !pass;
        println!(
            "catch | {name}/4+ aggregate | {} | {:.3}% | >= 98.000% | {}",
            count.total,
            count.rate() * 100.0,
            status(pass)
        );
    }
    for (name, count) in &catch_rows {
        let measured = count.rate();
        println!(
            "catch | {name} | {} | {:.3}% | report only | PASS",
            count.total,
            measured * 100.0
        );
    }
    println!(
        "mid-word | false switch on any correct prefix (key {MID_WORD_MIN_PREFIX}+) | {} | {:.3}% | report only, disabled | MEASURED",
        early.overall_false.total,
        early.overall_false.rate() * 100.0,
    );
    for (name, count) in &early.false_rows {
        if name.starts_with("hard/") {
            println!(
                "mid-word | false switch on {name} prefix | {} | {:.3}% | report only, disabled | MEASURED",
                count.total,
                count.rate() * 100.0,
            );
        }
    }
    for (name, count) in &early.catches {
        println!(
            "mid-word | {name}/4+ caught on any prefix | {} | {:.3}% | report only, disabled | MEASURED",
            count.total,
            count.rate() * 100.0,
        );
        let before_final = &early.catches_before_final_key[name];
        println!(
            "mid-word | {name}/4+ caught before final key | {} | {:.3}% | report only, disabled | MEASURED",
            before_final.total,
            before_final.rate() * 100.0,
        );
        let mut leads = early.lead_keys[name].clone();
        leads.sort_unstable();
        println!(
            "mid-word | {name}/4+ lead for early catches | {} | p50 {} keys, p99 {} keys | report only, disabled | MEASURED",
            leads.len(),
            percentile_usize(&leads, 50),
            percentile_usize(&leads, 99),
        );
    }
    let latency_pass = timing.p99 <= LATENCY_TARGET;
    failed |= !latency_pass;
    println!(
        "latency | all decisions p99 | {} | {:.3} us | < 1000.000 us | {}",
        timing.samples,
        timing.p99.as_secs_f64() * 1_000_000.0,
        status(latency_pass)
    );
    println!(
        "latency | per-round p99 range | {TIMING_ROUNDS} | {:.3}-{:.3} us | report only | PASS",
        timing.min_round_p99.as_secs_f64() * 1_000_000.0,
        timing.max_round_p99.as_secs_f64() * 1_000_000.0
    );
    println!(
        "latency | timer floor p99 | {} | {:.3} us | report only | PASS",
        timing.samples,
        timing.timer_floor_p99.as_secs_f64() * 1_000_000.0,
    );

    print_examples("false switches", &false_rows);
    print_examples("missed catches", &catch_rows);
    print_examples("mid-word false switches", &early.false_rows);
    print_examples("mid-word missed catches", &early.catches);
    failed |= !report_phrases(&detector, &parse_phrases(&cases));
    println!("work count: {} decisions, 0 runtime errors", timing.samples);

    if failed {
        std::process::exit(1);
    }
}

/// `eval` leaves the held-out words out of the dictionary, so it measures unseen words.
/// `shipped` is the model the app embeds, trained on every word.
#[derive(Clone, Copy)]
enum ModelChoice {
    Eval,
    Shipped,
}

fn parse_arguments() -> (DetectorConfig, ModelChoice) {
    let mut config = DetectorConfig::default();
    let mut model = ModelChoice::Eval;
    let mut arguments = std::env::args().skip(1);
    while let Some(argument) = arguments.next() {
        let raw = arguments
            .next()
            .unwrap_or_else(|| panic!("missing value after {argument}"));
        if argument == "--model" {
            model = match raw.as_str() {
                "eval" => ModelChoice::Eval,
                "shipped" => ModelChoice::Shipped,
                _ => panic!("--model takes eval or shipped"),
            };
            continue;
        }
        let value = raw
            .parse::<f32>()
            .unwrap_or_else(|_| panic!("bad value after {argument}"));
        match argument.as_str() {
            "--boundary-margin" => config.boundary_margin = value,
            "--mid-word-margin" => config.mid_word_margin = value,
            "--minimum-target-score" => config.minimum_target_score = value,
            _ => panic!("unknown argument {argument}"),
        }
    }
    (config, model)
}

struct Timing {
    samples: usize,
    p99: Duration,
    min_round_p99: Duration,
    max_round_p99: Duration,
    timer_floor_p99: Duration,
}

fn measure_latency(detector: &Detector, exceptions: &ExceptionSet, cases: &[Case]) -> Timing {
    let prepared: Vec<_> = cases
        .iter()
        .map(|case| {
            (
                case.layout.layout().keystrokes_for(&case.word).unwrap(),
                case.layout,
                DecisionContext {
                    token_class: case.context,
                    ..DecisionContext::default()
                },
            )
        })
        .collect();
    let mut all = Vec::with_capacity(prepared.len() * TIMING_ROUNDS);
    let mut timer_floor = Vec::with_capacity(prepared.len() * TIMING_ROUNDS);
    let mut round_p99s = Vec::with_capacity(TIMING_ROUNDS);

    for _ in 0..TIMING_ROUNDS {
        let mut round = Vec::with_capacity(prepared.len());
        for (strokes, layout, context) in &prepared {
            let start = Instant::now();
            std::hint::black_box(detector.decide(strokes, *layout, *context, exceptions));
            round.push(start.elapsed());

            let start = Instant::now();
            std::hint::black_box(());
            timer_floor.push(start.elapsed());
        }
        round.sort_unstable();
        round_p99s.push(percentile(&round, 99));
        all.extend(round);
    }

    all.sort_unstable();
    timer_floor.sort_unstable();
    round_p99s.sort_unstable();
    Timing {
        samples: all.len(),
        p99: percentile(&all, 99),
        min_round_p99: round_p99s[0],
        max_round_p99: round_p99s[round_p99s.len() - 1],
        timer_floor_p99: percentile(&timer_floor, 99),
    }
}

fn measure_early_mode(detector: &Detector, exceptions: &ExceptionSet, cases: &[Case]) -> EarlyMode {
    let mut measured = EarlyMode::default();
    for case in cases {
        let strokes = case.layout.layout().keystrokes_for(&case.word).unwrap();
        let context = DecisionContext {
            moment: DecisionMoment::MidWord,
            token_class: case.context,
        };
        let row_name = format!("{}/{}", case.suite, case.group);
        let false_row = measured.false_rows.entry(row_name).or_default();
        false_row.total += 1;
        measured.overall_false.total += 1;
        let false_switch = (strokes.len() >= MID_WORD_MIN_PREFIX)
            .then(|| {
                (MID_WORD_MIN_PREFIX..=strokes.len()).find(|prefix_len| {
                    matches!(
                        detector.decide(&strokes[..*prefix_len], case.layout, context, exceptions),
                        Verdict::Switch { .. }
                    )
                })
            })
            .flatten();
        if let Some(prefix_len) = false_switch {
            false_row.success += 1;
            measured.overall_false.success += 1;
            if false_row.examples.len() < 8 {
                false_row
                    .examples
                    .push(format!("{}@{}", case.word, prefix_len));
            }
        }

        let word_len = strokes.len();
        if !case.catch || word_len < MID_WORD_MIN_PREFIX {
            continue;
        }
        let wrong_layout = case.layout.alternate();
        let direction = format!(
            "{}->{}",
            layout_name(wrong_layout),
            layout_name(case.layout)
        );
        let first_catch = (MID_WORD_MIN_PREFIX..=word_len).find(|prefix_len| {
            matches!(
                detector.decide(
                    &strokes[..*prefix_len],
                    wrong_layout,
                    context,
                    exceptions
                ),
                Verdict::Switch { to, .. } if to == case.layout
            )
        });
        let catch = measured.catches.entry(direction.clone()).or_default();
        catch.total += 1;
        let before_final = measured
            .catches_before_final_key
            .entry(direction.clone())
            .or_default();
        before_final.total += 1;
        measured.lead_keys.entry(direction.clone()).or_default();
        if let Some(prefix_len) = first_catch {
            catch.success += 1;
            if prefix_len < word_len {
                before_final.success += 1;
                measured
                    .lead_keys
                    .entry(direction)
                    .or_default()
                    .push(word_len - prefix_len);
            }
        } else if catch.examples.len() < 8 {
            catch.examples.push(case.word.clone());
        }
    }
    measured
}

fn percentile(sorted: &[Duration], percentile: usize) -> Duration {
    let index = ((sorted.len() - 1) * percentile).div_ceil(100);
    sorted[index]
}

fn percentile_usize(sorted: &[usize], percentile: usize) -> usize {
    if sorted.is_empty() {
        return 0;
    }
    let index = ((sorted.len() - 1) * percentile).div_ceil(100);
    sorted[index]
}

fn print_examples(label: &str, rows: &BTreeMap<String, Count>) {
    let examples: Vec<_> = rows
        .iter()
        .filter(|(_, count)| !count.examples.is_empty())
        .map(|(name, count)| format!("{name}: {}", count.examples.join(", ")))
        .collect();
    if !examples.is_empty() {
        println!("{label}: {}", examples.join(" | "));
    }
}

fn parse_corpus() -> Vec<Case> {
    HELDOUT
        .lines()
        .chain(HARD_NEGATIVES.lines())
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(|line| {
            let fields: Vec<_> = line.split('\t').collect();
            assert_eq!(fields.len(), 6, "bad corpus row: {line:?}");
            Case {
                suite: fields[0].to_owned(),
                group: fields[1].to_owned(),
                layout: parse_layout(fields[2]),
                catch: fields[3] == "yes",
                context: parse_context(fields[4]),
                word: fields[5].to_owned(),
            }
        })
        .collect()
}

fn parse_layout(value: &str) -> LayoutId {
    match value {
        "us" => LayoutId::Us,
        "ukrainian-pc" => LayoutId::UkrainianPc,
        _ => panic!("unknown layout {value:?}"),
    }
}

fn parse_context(value: &str) -> TokenClass {
    match value {
        "plain" => TokenClass::Plain,
        "code" => TokenClass::Code,
        "email" => TokenClass::Email,
        "path" => TokenClass::Path,
        "url" => TokenClass::Url,
        _ => panic!("unknown context {value:?}"),
    }
}

fn length_bucket(length: usize) -> &'static str {
    match length {
        0..=3 => "1-3",
        4..=5 => "4-5",
        6..=8 => "6-8",
        _ => "9+",
    }
}

fn layout_name(layout: LayoutId) -> &'static str {
    match layout {
        LayoutId::Us => "us",
        LayoutId::UkrainianPc => "ukrainian-pc",
    }
}

fn status(pass: bool) -> &'static str {
    if pass {
        "PASS"
    } else {
        "FAIL"
    }
}

/// Phrase-level behaviour of the session: short words carried along with a confident
/// conversion that follows them. Every phrase is typed key by key with Space boundaries.
/// The active layout follows the engine's switches, the way a person keeps typing.
struct Phrase {
    row: String,
    active: LayoutId,
    words: Vec<(String, LayoutId)>,
}

#[derive(Clone, Copy)]
struct Token {
    short: bool,
    typed_wrong: bool,
    fixed: bool,
    rode: bool,
}

#[derive(Default)]
struct PhraseReport {
    false_short: BTreeMap<String, Count>,
    false_short_all: Count,
    false_long: Count,
    rider_false: usize,
    runs: BTreeMap<String, Count>,
    natural_runs: Count,
    run_lengths: BTreeMap<usize, usize>,
    boundary_times: Vec<Duration>,
}

const POLICIES: [(RiderPolicy, &str); 3] = [
    (RiderPolicy::Off, "off (before)"),
    (RiderPolicy::AllLetters, "all-letters"),
    (RiderPolicy::TargetWords, "target-words"),
];
const PHRASE_FALSE_TARGET: f64 = 0.001;
const HELDOUT_PHRASE_WORDS: usize = 6;

fn parse_phrases(cases: &[Case]) -> Vec<Phrase> {
    let mut phrases = Vec::new();
    for line in PHRASES
        .lines()
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
    {
        let fields: Vec<_> = line.split('\t').collect();
        assert_eq!(fields.len(), 4, "bad phrase row: {line:?}");
        let words: Vec<_> = fields[3]
            .split(' ')
            .map(|word| (word.to_owned(), script_layout(word)))
            .collect();
        let actives = match fields[2] {
            "both" => vec![LayoutId::Us, LayoutId::UkrainianPc],
            other => vec![parse_layout(other)],
        };
        for active in actives {
            phrases.push(Phrase {
                row: format!("{}/{}@{}", fields[0], fields[1], layout_name(active)),
                active,
                words: words.clone(),
            });
        }
    }
    // Held-out words in corpus order, six to a phrase. Under the eval model these words are
    // missing from the dictionary, so even common short words look ambiguous: a stress test.
    for group in ["english", "ukrainian"] {
        let words: Vec<_> = cases
            .iter()
            .filter(|case| case.suite == "heldout" && case.group == group && case.catch)
            .map(|case| (case.word.clone(), case.layout))
            .collect();
        for chunk in words.chunks(HELDOUT_PHRASE_WORDS) {
            for active in [LayoutId::Us, LayoutId::UkrainianPc] {
                phrases.push(Phrase {
                    row: format!("heldout-phrases/{group}@{}", layout_name(active)),
                    active,
                    words: chunk.to_vec(),
                });
            }
        }
    }
    phrases
}

fn script_layout(word: &str) -> LayoutId {
    if word
        .chars()
        .any(|character| ('\u{400}'..='\u{4ff}').contains(&character))
    {
        LayoutId::UkrainianPc
    } else {
        LayoutId::Us
    }
}

fn simulate_phrase(
    detector: &Detector,
    policy: RiderPolicy,
    phrase: &Phrase,
    times: &mut Vec<Duration>,
) -> Vec<Token> {
    let mut session = Session::new(detector.clone()).with_rider_policy(policy);
    let mut active = phrase.active;
    let mut screen: Vec<String> = Vec::new();
    let mut tokens: Vec<Token> = Vec::new();
    for (word, intended) in &phrase.words {
        let strokes = intended
            .layout()
            .keystrokes_for(word)
            .unwrap_or_else(|| panic!("cannot encode {word:?}"));
        tokens.push(Token {
            short: word.chars().count() < 4,
            typed_wrong: active != *intended,
            fixed: false,
            rode: false,
        });
        screen.push(active.layout().render(&strokes));
        for stroke in strokes {
            session.handle(SessionEvent::Key {
                stroke,
                current_layout: active,
            });
        }
        let start = Instant::now();
        let action = session.handle(SessionEvent::Boundary {
            current_layout: active,
            context: DecisionContext::default(),
            is_space: true,
        });
        times.push(start.elapsed());
        let Some(Action::Rewrite {
            delete_chars,
            insert_text,
            riders,
            switch_to,
            ..
        }) = action
        else {
            continue;
        };
        let first = screen.len() - 1 - riders;
        let replaced = screen[first..].join(" ");
        assert_eq!(delete_chars, replaced.chars().count(), "{replaced:?}");
        screen.truncate(first);
        screen.extend(insert_text.split(' ').map(str::to_owned));
        for token in &mut tokens[first..first + riders] {
            token.rode = true;
        }
        active = switch_to;
    }
    for ((token, rendered), (word, _)) in tokens.iter_mut().zip(&screen).zip(&phrase.words) {
        token.fixed = rendered == word;
    }
    tokens
}

fn measure_phrases(detector: &Detector, policy: RiderPolicy, phrases: &[Phrase]) -> PhraseReport {
    let mut report = PhraseReport::default();
    for phrase in phrases {
        let tokens = simulate_phrase(detector, policy, phrase, &mut report.boundary_times);
        for (token, (word, _)) in tokens.iter().zip(&phrase.words) {
            if token.typed_wrong {
                continue;
            }
            let wrongly_rewritten = !token.fixed;
            if token.short {
                let row = report.false_short.entry(phrase.row.clone()).or_default();
                for count in [row, &mut report.false_short_all] {
                    count.total += 1;
                    if wrongly_rewritten {
                        count.success += 1;
                        if count.examples.len() < 8 {
                            count
                                .examples
                                .push(format!("{word} in {:?}", phrase_text(phrase)));
                        }
                    }
                }
                report.rider_false += usize::from(wrongly_rewritten && token.rode);
            } else {
                report.false_long.total += 1;
                report.false_long.success += usize::from(wrongly_rewritten);
            }
        }
        // A run: one or more short words typed in the wrong layout, then a long one.
        let mut start = 0;
        while start < tokens.len() {
            let mut end = start;
            while end < tokens.len() && tokens[end].typed_wrong && tokens[end].short {
                end += 1;
            }
            if end > start && end < tokens.len() && tokens[end].typed_wrong {
                if phrase.row.starts_with("phrase/") {
                    *report.run_lengths.entry(end - start).or_default() += 1;
                }
                let fixed = tokens[start..=end].iter().all(|token| token.fixed);
                let row = report.runs.entry(phrase.row.clone()).or_default();
                let natural = phrase
                    .row
                    .starts_with("phrase/")
                    .then_some(&mut report.natural_runs);
                for count in std::iter::once(row).chain(natural) {
                    count.total += 1;
                    if fixed {
                        count.success += 1;
                    } else if count.examples.len() < 8 {
                        count.examples.push(phrase_text(phrase));
                    }
                }
            }
            start = end.max(start + 1);
        }
    }
    report.boundary_times.sort_unstable();
    report
}

fn phrase_text(phrase: &Phrase) -> String {
    phrase
        .words
        .iter()
        .map(|(word, _)| word.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Prints the phrase rows and returns false when the default policy misses a gate.
fn report_phrases(detector: &Detector, phrases: &[Phrase]) -> bool {
    let mut passed = true;
    let mut false_examples = BTreeMap::new();
    let mut run_examples = BTreeMap::new();
    for (policy, name) in POLICIES {
        let report = measure_phrases(detector, policy, phrases);
        let gated = policy == RiderPolicy::default();
        let false_pass = report.false_short_all.rate() <= PHRASE_FALSE_TARGET;
        passed &= !gated || false_pass;
        println!(
            "phrase | {name}: correct short words wrongly rewritten | {} | {:.3}% ({} by riding) | {} | {}",
            report.false_short_all.total,
            report.false_short_all.rate() * 100.0,
            report.rider_false,
            if gated { "<= 0.100%" } else { "report only" },
            status(!gated || false_pass)
        );
        for (row, count) in &report.false_short {
            println!(
                "phrase | {name}: correct short words wrongly rewritten, {row} | {} | {:.3}% | report only | PASS",
                count.total,
                count.rate() * 100.0
            );
        }
        println!(
            "phrase | {name}: correct long words wrongly rewritten | {} | {:.3}% | report only | PASS",
            report.false_long.total,
            report.false_long.rate() * 100.0
        );
        println!(
            "phrase | {name}: wrong-layout runs fully fixed, written phrases | {} | {:.3}% | report only | PASS",
            report.natural_runs.total,
            report.natural_runs.rate() * 100.0
        );
        for (row, count) in &report.runs {
            println!(
                "phrase | {name}: runs fully fixed, {row} | {} | {:.3}% | report only | PASS",
                count.total,
                count.rate() * 100.0
            );
        }
        let exposure = short_word_exposure(detector, policy);
        let exposure_pass = exposure.rate() <= PHRASE_FALSE_TARGET;
        passed &= !gated || exposure_pass;
        println!(
            "phrase | {name}: correct short words rewritten before a wrong-layout word (dictionary, frequency-weighted) | {} | {:.3}% | {} | {}",
            exposure.total,
            exposure.rate() * 100.0,
            if gated { "<= 0.100%" } else { "report only" },
            status(!gated || exposure_pass)
        );
        if !exposure.examples.is_empty() {
            println!(
                "phrase | {name}: most frequent of those: {}",
                exposure.examples.join(", ")
            );
        }
        let lengths: Vec<_> = report
            .run_lengths
            .iter()
            .map(|(length, count)| format!("{length}:{count}"))
            .collect();
        let p99 = percentile(&report.boundary_times, 99);
        let latency_pass = p99 <= LATENCY_TARGET;
        passed &= !gated || latency_pass;
        println!(
            "phrase | {name}: boundary p99 (short words before the long word: {}) | {} | {:.3} us | < 1000.000 us | {}",
            lengths.join(" "),
            report.boundary_times.len(),
            p99.as_secs_f64() * 1_000_000.0,
            status(!gated || latency_pass)
        );
        false_examples.insert(name.to_owned(), report.false_short_all);
        run_examples.insert(name.to_owned(), report.natural_runs);
    }
    print_examples("phrase false rewrites", &false_examples);
    print_examples("phrase runs not fully fixed", &run_examples);
    passed
}

/// Mixed text at dictionary scale: every one- to three-letter dictionary word, typed in its
/// own layout, then a word of the other language typed without switching (`привіт` on U.S.,
/// `switching` on Ukrainian). Counts the short words the conversion takes along, weighted by
/// corpus frequency, so the denominator is every short-word occurrence in the corpus.
fn short_word_exposure(detector: &Detector, policy: RiderPolicy) -> Count {
    let mut exposure = Count::default();
    let mut layout = LayoutId::Us;
    let mut riding: Vec<(u64, &str)> = Vec::new();
    for line in SHIPPED_MODEL.lines() {
        if let Some(id) = line.strip_prefix("LANG\t") {
            layout = parse_layout(id);
            continue;
        }
        let Some(row) = line.strip_prefix("WORD\t") else {
            continue;
        };
        let (word, frequency) = row.split_once('\t').expect("bad word row");
        if word.chars().count() > 3 {
            continue;
        }
        let Some(strokes) = layout.layout().keystrokes_for(word) else {
            continue;
        };
        let frequency: u64 = frequency.parse().expect("bad frequency");
        let mut session = Session::new(detector.clone()).with_rider_policy(policy);
        for stroke in strokes {
            session.handle(SessionEvent::Key {
                stroke,
                current_layout: layout,
            });
        }
        session.handle(SessionEvent::Boundary {
            current_layout: layout,
            context: DecisionContext::default(),
            is_space: true,
        });
        let (other, foreign) = match layout {
            LayoutId::Us => (LayoutId::UkrainianPc, "привіт"),
            LayoutId::UkrainianPc => (LayoutId::Us, "switching"),
        };
        for stroke in other.layout().keystrokes_for(foreign).unwrap() {
            session.handle(SessionEvent::Key {
                stroke,
                current_layout: layout,
            });
        }
        let action = session.handle(SessionEvent::Boundary {
            current_layout: layout,
            context: DecisionContext::default(),
            is_space: true,
        });
        exposure.total += frequency as usize;
        if matches!(action, Some(Action::Rewrite { riders, .. }) if riders > 0) {
            exposure.success += frequency as usize;
            riding.push((frequency, word));
        }
    }
    riding.sort_unstable_by(|left, right| right.cmp(left));
    exposure.examples = riding
        .iter()
        .take(8)
        .map(|(_, word)| (*word).to_owned())
        .collect();
    exposure
}
