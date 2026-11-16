# Detection engine architecture

## Usage sketch

The shell records physical keys and asks for one decision before it emits a word boundary.

```rust
let strokes = vec![
	KeyStroke::new(PhysicalKey::KeyG, false),
	KeyStroke::new(PhysicalKey::KeyH, false),
	KeyStroke::new(PhysicalKey::KeyB, false),
	KeyStroke::new(PhysicalKey::KeyD, false),
	KeyStroke::new(PhysicalKey::KeyS, false),
	KeyStroke::new(PhysicalKey::KeyN, false),
];

let verdict = detector.decide(
	&strokes,
	LayoutId::Us,
	DecisionContext::default(),
	&exceptions,
);

assert!(matches!(verdict, Verdict::Switch { to: LayoutId::UkrainianPc, .. }));
```

The session reducer owns buffering and undo. It emits a `Rewrite` value. The shell owns all input and output.

```rust
let action = session.handle(SessionEvent::Boundary {
	current_layout: LayoutId::Us,
	context: DecisionContext::default(),
	is_space: true,
});
```

## Data shape

`KeyStroke` stores a physical ANSI key position and a shift bit. `Layout` tables render the same strokes as U.S. or Ukrainian PC text. No OS key code enters the engine.

`Detector::decide` is pure for a fixed model. Its inputs are the strokes, the current layout, the token context, and the user exception set. Its output is `Verdict::Keep` or `Verdict::Switch`, and both variants carry a confidence value.

`Session` is a reducer over `SessionEvent`. Its states are `Idle`, `Typing`, `Finished`, `Blocked`, and `Undo`. `Finished` keeps a word that ended at a boundary so the convert key can still reach it. `Blocked` marks a word the user edited or that was already rewritten. `Undo` retains the last rewrite until the next event. An undo emits the inverse rewrite. The second undo of the same word adds it to the exception set.

Next to its state, the session keeps a run of at most three undecided short words. A word joins the run when the detector keeps it only as `ShortAmbiguous`, it ended at a Space, every key renders as a letter in both layouts, it is no listed common short word of its own layout, and its other rendering is one of the other language's (`RiderPolicy::TargetWords`). The next automatic switch takes the run along: one rewrite deletes and retypes the run, its Spaces and the word, and switches the layout once. Any other outcome ends the run: a word kept for another reason, a non-Space boundary, a layout change, an edit, a reset, or a manual conversion. The shell resets the session after a pause of two seconds between words. An undo restores the whole run; only the word that decided the switch earns a strike. `bin/eval` measures runs on `data/eval/phrases.tsv`, on held-out words in six-word phrases, and on every dictionary short word followed by a wrong-layout word.

The compiled model contains sorted words and dense bigram and trigram scores for each language. The model builder owns source filtering, train and held-out separation, and serialization. `data/model.tsv` excludes the deterministic held-out set. `data/model-shipped.tsv` merges it back for the runtime dictionary. Runtime code only parses the committed shipped model, while the eval selects the held-out-safe model by default.

## Module map

| Module | Ownership |
| --- | --- |
| `layout` | Physical keys and table-driven layout rendering. |
| `detect` | Public verdict types, token guards, and language score comparison. |
| `model` | Read-only embedded dictionaries and character language models. |
| `session` | The state reducer, rewrite actions, undo, and exceptions. |
| `ffi` | C-compatible handles, events, and borrowed action strings. |
| `bin/build-data` | Reproducible model and held-out corpus generation. |
| `bin/eval` | Quality and latency gates over held-out text. |

## Alternatives

| Design | Result | Reason |
| --- | --- | --- |
| One stateful classifier that accepts rendered characters | Rejected | It would bind detection to the active layout and make alternate rendering lossy. |
| A pure detector plus a separate session reducer | Chosen | The detector stays testable and the C boundary exposes only events and actions. |
| Generated Rust arrays | Rejected | Large generated source slows review and compilation. |
| A compact data file parsed once | Chosen | The model remains reproducible, inspectable, and independent of the OS shell. |
| Dictionary membership alone | Rejected | It cannot catch unseen inflections or names. |
| Dictionary and character n-grams with a margin | Chosen | It can score unseen words while requiring evidence against the current rendering. |

The default mode decides only at a word boundary. Mid-word scoring uses a higher threshold and is measured on every prefix from the fourth key onward. The report includes false prefix switches, catches before the final key, and lead-key percentiles. The session reducer does not enable early rewriting in phase one.

