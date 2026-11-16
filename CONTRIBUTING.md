# Contributing

Bug reports and pull requests are welcome. For a wrong or missed conversion, open an issue with the keys you pressed, the layout that was active, and the app you typed in.

## Check a change

Run the engine checks on any platform:

```sh
cargo test --workspace
cargo clippy --workspace --all-targets -- -D warnings
cargo run --release -p engine --bin eval
```

The eval fails if correct words are rewritten more often than 0.1% of the time. A change that raises the catch rate must stay under that limit.

Run the app tests on a Mac:

```sh
mac/test.sh
```

`mac/e2e.sh` posts real keystrokes to the screen, so run it only when you are not typing.

## Rules for the app

- Do not log or store typed text.
- Do not add network access.
- Do not act while macOS Secure Input is on.

## Data

Add only word data that you may redistribute, and record the source and the license in [data/NOTICE.md](data/NOTICE.md). Do not copy code or data from other layout switchers.
