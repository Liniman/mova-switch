# MovaSwitch

[![MovaSwitch turns ghbdsn into привіт as you type](docs/demo.gif)](video/out/mova-switch.mp4)

[![CI](https://github.com/Liniman/mova-switch/actions/workflows/ci.yml/badge.svg)](https://github.com/Liniman/mova-switch/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey.svg)

You typed `ghbdsn` and meant `привіт`. MovaSwitch rewrites the word and switches the keyboard layout, so you keep typing. It runs on your Mac and nowhere else.

## Install

You need macOS 13 or later on an Apple silicon Mac. Add the **U.S.** and **Ukrainian – PC** keyboards in **System Settings > Keyboard > Input Sources**.

```sh
curl -fsSL https://raw.githubusercontent.com/Liniman/mova-switch/main/install.sh | sh
```

Run the same line to update. The installer opens **Privacy & Security > Accessibility**. Turn on **MovaSwitch** there.

With Homebrew, run `brew install --HEAD liniman/tap/mova-switch`, then `mova-switch-install`. To build from a clone instead, install the Xcode Command Line Tools and [Rust](https://rustup.rs), then run `mac/install.sh`.

To remove the app, run `curl -fsSL https://raw.githubusercontent.com/Liniman/mova-switch/main/uninstall.sh | sh`.

## Use

- **Type.** A word in the wrong layout is fixed when you end it with Space, Return, or punctuation.
- **Tap Right Option** to undo the fix. The same tap converts the word you just typed or the text you selected.
- **Undo a word twice** and MovaSwitch never converts that word again.
- **Click `МА` in the menu bar** to pause MovaSwitch or set it per app.

## Languages

Ukrainian ↔ English, on the Apple **Ukrainian – PC** and **U.S.** layouts. No other language is supported.

## Privacy

- MovaSwitch makes no network connections.
- It keeps the current word in memory and saves only your never-convert list. It does not log what you type.
- It does nothing in password fields.

To report a security problem, see [SECURITY.md](SECURITY.md).

## Accuracy

On held-out words, MovaSwitch wrongly rewrites 0.03% of correct words and catches 98% of wrong-layout words of four letters or more. To reproduce the numbers, run `cargo run --release -p engine --bin eval`.

## Plans

- A notarized download
- Conversion while you are still typing the word
- Better handling of one- and two-letter words
- A documented way to add a language
- Intel Macs

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The engine design is in [engine/ARCHITECTURE.md](engine/ARCHITECTURE.md) and the app design is in [mac/ARCHITECTURE.md](mac/ARCHITECTURE.md).

## License

The code is under the [MIT License](LICENSE). The word data in `data/` is under CC BY-SA 4.0. See [data/NOTICE.md](data/NOTICE.md).
