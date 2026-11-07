NVIM ?= nvim

.PHONY: test test-live record
# Replay recorded Agda sessions (no Agda needed).
test:
	$(NVIM) --clean --headless -l tests/run.lua $(FILTER)

# Run against the real Agda.
test-live:
	AGDA_TEST_MODE=live $(NVIM) --clean --headless -l tests/run.lua $(FILTER)

# Run against the real Agda and rewrite the transcripts.
record:
	AGDA_TEST_MODE=record $(NVIM) --clean --headless -l tests/run.lua $(FILTER)
