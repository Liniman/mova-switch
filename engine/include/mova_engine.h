#ifndef MOVA_ENGINE_H
#define MOVA_ENGINE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MovaEngine MovaEngine;

typedef uint8_t MovaLayout;
enum {
	MOVA_LAYOUT_US = 0,
	MOVA_LAYOUT_UKRAINIAN_PC = 1,
};

typedef uint8_t MovaTokenClass;
enum {
	MOVA_TOKEN_PLAIN = 0,
	MOVA_TOKEN_CODE = 1,
	MOVA_TOKEN_EMAIL = 2,
	MOVA_TOKEN_PATH = 3,
	MOVA_TOKEN_URL = 4,
};

typedef uint8_t MovaActionKind;
enum {
	MOVA_ACTION_NONE = 0,
	MOVA_ACTION_REWRITE = 1,
	MOVA_ACTION_ERROR = 255,
};

typedef uint8_t MovaPhysicalKey;
enum {
	MOVA_KEY_BACKQUOTE = 0,
	MOVA_KEY_DIGIT_1 = 1,
	MOVA_KEY_DIGIT_2 = 2,
	MOVA_KEY_DIGIT_3 = 3,
	MOVA_KEY_DIGIT_4 = 4,
	MOVA_KEY_DIGIT_5 = 5,
	MOVA_KEY_DIGIT_6 = 6,
	MOVA_KEY_DIGIT_7 = 7,
	MOVA_KEY_DIGIT_8 = 8,
	MOVA_KEY_DIGIT_9 = 9,
	MOVA_KEY_DIGIT_0 = 10,
	MOVA_KEY_MINUS = 11,
	MOVA_KEY_EQUAL = 12,
	MOVA_KEY_Q = 13,
	MOVA_KEY_W = 14,
	MOVA_KEY_E = 15,
	MOVA_KEY_R = 16,
	MOVA_KEY_T = 17,
	MOVA_KEY_Y = 18,
	MOVA_KEY_U = 19,
	MOVA_KEY_I = 20,
	MOVA_KEY_O = 21,
	MOVA_KEY_P = 22,
	MOVA_KEY_BRACKET_LEFT = 23,
	MOVA_KEY_BRACKET_RIGHT = 24,
	MOVA_KEY_BACKSLASH = 25,
	MOVA_KEY_A = 26,
	MOVA_KEY_S = 27,
	MOVA_KEY_D = 28,
	MOVA_KEY_F = 29,
	MOVA_KEY_G = 30,
	MOVA_KEY_H = 31,
	MOVA_KEY_J = 32,
	MOVA_KEY_K = 33,
	MOVA_KEY_L = 34,
	MOVA_KEY_SEMICOLON = 35,
	MOVA_KEY_QUOTE = 36,
	MOVA_KEY_Z = 37,
	MOVA_KEY_X = 38,
	MOVA_KEY_C = 39,
	MOVA_KEY_V = 40,
	MOVA_KEY_B = 41,
	MOVA_KEY_N = 42,
	MOVA_KEY_M = 43,
	MOVA_KEY_COMMA = 44,
	MOVA_KEY_PERIOD = 45,
	MOVA_KEY_SLASH = 46,
};

typedef uint8_t MovaSpan;
enum {
	/* The word is the last text in the document. */
	MOVA_SPAN_CURRENT_WORD = 0,
	/* The boundary key the user typed follows the word: delete it too, then send it again. */
	MOVA_SPAN_WORD_AND_BOUNDARY = 1,
};

typedef struct MovaAction {
	MovaActionKind kind;
	MovaSpan span;
	MovaLayout switch_to;
	uint8_t learned_exception;
	float confidence;
	size_t delete_chars;
	const uint8_t *insert_utf8;
	size_t insert_len;
	/* Short words before the word that this rewrite carries, each followed by one Space. */
	size_t rider_count;
	/* Byte offset in insert_utf8 where the word that decided the rewrite starts. */
	size_t word_offset;
	/* Finished short words the engine still holds after this call, for any action kind. */
	size_t undecided_words;
} MovaAction;

MovaEngine *mova_engine_new(void);
void mova_engine_free(MovaEngine *engine);

MovaAction mova_engine_key(
	MovaEngine *engine,
	MovaPhysicalKey key,
	uint8_t shift,
	MovaLayout current_layout
);

MovaAction mova_engine_boundary(
	MovaEngine *engine,
	MovaLayout current_layout,
	MovaTokenClass token_class,
	uint8_t is_space
);

MovaAction mova_engine_edit(MovaEngine *engine);
MovaAction mova_engine_undo(MovaEngine *engine);
MovaAction mova_engine_convert(MovaEngine *engine);
void mova_engine_reset(MovaEngine *engine);
void mova_engine_clear_exceptions(MovaEngine *engine);

uint8_t mova_engine_add_exception(
	MovaEngine *engine,
	MovaLayout layout,
	const uint8_t *text_utf8,
	size_t text_len
);

#ifdef __cplusplus
}
#endif

#endif
