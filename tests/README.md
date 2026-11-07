# Tests

    make test                    # replay recorded Agda sessions (no Agda needed)
    make test FILTER=navigation  # only cases whose "file: name" matches the Lua pattern
    make test-live               # run against the real Agda
    make record                  # run against the real Agda, rewrite tests/transcripts/

Tests run in `nvim --clean --headless -l tests/run.lua` and need nothing
beyond Neovim.  If the `lua-utf8` module is not installed, a pure-Lua
shim (`tests/shim/lua-utf8.lua`) is used instead.

## How the Agda interaction is tested

The plugin is configured to use `tests/bin/agda` as its Agda binary.
This wrapper either runs the real Agda (`live`/`record`; set `AGDA_REAL`
to choose the binary) or `tests/replay.lua`, which answers with a
recorded transcript (`tests/transcripts/<test>.json`).  The replay
checks that the plugin sends exactly the recorded commands and writes
the responses in randomly sized chunks to exercise stream handling; set
`AGDA_TEST_SEED` to reproduce a particular chunking.

In every mode the session's stdin/stdout is logged in the test's
temporary directory, which is how `wait_idle()` knows that Agda has
answered everything.

Transcripts depend on the Agda version that recorded them (stored in
the `agda` field).  After changing a test, run `make record` and review
the diff.

## Golden files

Some tests compare output with `tests/golden/<name>.txt`.  To update
them after an intended change, run with `UPDATE_GOLDEN=1` and review
the diff.

Expectations marked `FIXME` capture known bugs of the current code; they
should change when the bug is fixed.
