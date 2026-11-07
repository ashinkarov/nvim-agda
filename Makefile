NVIM ?= nvim

.PHONY: test
test:
	$(NVIM) --clean --headless -l tests/run.lua $(FILTER)
