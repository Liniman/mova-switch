# C API reference

`include/mova_engine.h` is the complete shell interface. The crate builds a static library and a dynamic library.

Create one `MovaEngine` per input stream. Every call on a handle must come from one thread at a time.

## Events

| Call | When the shell sends it |
| --- | --- |
| `mova_engine_key` | A key that belongs to a word: its rendering is a letter in either layout. Pass the `MovaPhysicalKey` position, never an OS key code. |
| `mova_engine_edit` | Backspace, Forward Delete or an arrow inside the current word. The word is then never converted. |
| `mova_engine_boundary` | Before the shell lets Space, Return, Tab or a sentence mark reach the application. Set `is_space` to 1 only for a plain Space. |
| `mova_engine_undo` | The user pressed the undo key right after a conversion. |
| `mova_engine_convert` | The user pressed the convert key with no conversion to undo. |
| `mova_engine_reset` | Focus change, click, Escape, a Command or Control chord, a pause between words, or anything else that makes the buffered text stale. |

## Actions

A result with kind `MOVA_ACTION_REWRITE` asks the shell to switch the input source to `switch_to`, delete `delete_chars` characters, and type `insert_utf8`. The inserted text always has one character per buffered keystroke, so a shell can replay the original keys instead of inserting text.

`span` says what the deletion covers. `MOVA_SPAN_CURRENT_WORD` means the word is the last text in the document. `MOVA_SPAN_WORD_AND_BOUNDARY` means the boundary key the user typed sits after the word. The shell deletes one more character for it and sends that key again after the replay. For a rewrite returned by `mova_engine_boundary`, the shell has held the boundary key back, so it deletes only the word and sends the boundary once.

`insert_utf8` stays valid until the next call on the same handle. `MOVA_ACTION_ERROR` means a null handle or an invalid enum value.

## Short-word runs

A word of one to three letters is often too ambiguous to judge. When the engine keeps such a word only for that reason and it ended at a Space, it remembers it as undecided. Every action reports `undecided_words`, the number of such finished words the engine holds after the call, at most three. A shell that replays keys keeps exactly that many of its last finished words, each with its Space.

When a later word converts automatically, the rewrite also covers the undecided words right before it. `rider_count` says how many. `delete_chars` and `insert_utf8` then span those words, one Space after each, and the word; the Spaces are part of the text, so the one-character-per-keystroke rule still holds when the shell replays each word's keys and its Space. `word_offset` is the byte offset in `insert_utf8` where the deciding word starts. An undo of such a rewrite has the same `rider_count` and restores the whole run in one step. Every rewrite that carries nothing has `rider_count` and `word_offset` 0.

## Learning

The first undo of an automatic conversion only reverts it. The second undo of the same word in the same session sets `learned_exception`. The shell should then persist the bytes of `insert_utf8` from `word_offset` on, with layout `switch_to`, and load them on the next launch with `mova_engine_add_exception`. Carried short words are never learned. First strikes stay in memory, because the shell stores no typed text other than the exception list. Undoing a manual conversion never teaches an exception.

Call `mova_engine_free` once for each handle returned by `mova_engine_new`.
