# Data notices

The phase-one build uses the sources below. `data/raw/` contains local clones and is not committed.

## FrequencyWords

- Source repository: `https://github.com/hermitdave/FrequencyWords`
- Pinned revision: `525f9b560de45753a5ea01069454e72e9aa541c6`
- Files: `content/2018/en/en_50k.txt` and `content/2018/uk/uk_full.txt`
- Content license: Creative Commons Attribution-ShareAlike 4.0 International
- Code license: MIT
- Upstream corpus: OPUS OpenSubtitles 2018

The compiled word frequencies and held-out word samples are adapted from the CC BY-SA 4.0 content. Those derived data remain under CC BY-SA 4.0.

## LibreOffice dictionaries

- Source repository: `https://github.com/LibreOffice/dictionaries`
- Pinned revision: `c0865a85eb67dc377f2cf8e8fe2c4fa9e53f0dcb`
- Files: `en/en_US.dic` and `uk_UA/uk_UA.dic`
- U.S. English dictionary license: the SCOWL permission notice reproduced in `en/README_en_US.txt`
- Ukrainian dictionary license: Mozilla Public License 1.1

The builder uses these spelling dictionaries as validation sets. It does not commit the source dictionaries.

## xneur study

- Source repository: `https://github.com/AndrewCrewKuznetsov/xneur-devel`
- Studied revision: `5a964810103cf73783f8f8ebb2998be8a5b91eda`
- License: GNU General Public License 2.0 or later

The implementation studied xneur's dictionary and impossible n-gram ordering. It contains no xneur source code or language data.


## Phrase corpus

`eval/phrases.tsv` was written for this project and is distributed under the repository's own license. It quotes no outside text. The phrase eval also chains the held-out words above into six-word phrases at run time and reads the short words of `model-shipped.tsv`; neither adds data to the repository.
