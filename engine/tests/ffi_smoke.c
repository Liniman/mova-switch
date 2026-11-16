#include "mova_engine.h"

#include <assert.h>
#include <string.h>

int main(void) {
	MovaEngine *engine = mova_engine_new();
	assert(engine != NULL);

	const MovaPhysicalKey keys[] = {
		MOVA_KEY_G,
		MOVA_KEY_H,
		MOVA_KEY_B,
		MOVA_KEY_D,
		MOVA_KEY_S,
		MOVA_KEY_N,
	};
	for (size_t index = 0; index < sizeof(keys) / sizeof(keys[0]); index++) {
		MovaAction action = mova_engine_key(engine, keys[index], 0, MOVA_LAYOUT_US);
		assert(action.kind == MOVA_ACTION_NONE);
	}

	MovaAction rewrite = mova_engine_boundary(engine, MOVA_LAYOUT_US, MOVA_TOKEN_PLAIN, 1);
	assert(rewrite.kind == MOVA_ACTION_REWRITE);
	assert(rewrite.span == MOVA_SPAN_WORD_AND_BOUNDARY);
	assert(rewrite.switch_to == MOVA_LAYOUT_UKRAINIAN_PC);
	assert(rewrite.delete_chars == 6);
	assert(rewrite.rider_count == 0);
	assert(rewrite.undecided_words == 0);
	assert(rewrite.insert_len == strlen("привіт"));
	assert(memcmp(rewrite.insert_utf8, "привіт", rewrite.insert_len) == 0);

	MovaAction undo = mova_engine_undo(engine);
	assert(undo.kind == MOVA_ACTION_REWRITE);
	assert(undo.switch_to == MOVA_LAYOUT_US);
	assert(undo.insert_len == strlen("ghbdsn"));
	assert(memcmp(undo.insert_utf8, "ghbdsn", undo.insert_len) == 0);

	mova_engine_free(engine);
	return 0;
}
