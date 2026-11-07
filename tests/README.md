# Tests

    make test                    # replay recorded Agda sessions (no Agda needed)
    make test FILTER=navigation  # only cases whose "file: name" matches the Lua pattern
    make test FILTER='stop|wipe' # ... or one of several patterns
    make test-live               # run against the real Agda
    make record                  # run against the real Agda, rewrite tests/transcripts/

Tests run in `nvim --clean --headless -l tests/run.lua` and need nothing
beyond Neovim.  If the `lua-utf8` library is installed (for instance with
`luarocks install --local --lua-version=5.1 luautf8`), `tests/test_utf8.lua`
also checks that `lua/agda/utf8.lua` agrees with it.

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

A few transcripts are edited by hand to simulate output that Agda does
not produce on demand (for example `non_json_output.json`).  Their tests
use `h.skip_unless_replay()`, so they are never re-recorded.

## Golden files

Some tests compare output with `tests/golden/<name>.txt`.  To update
them after an intended change, run with `UPDATE_GOLDEN=1` and review
the diff.

Expectations marked `FIXME` capture known bugs of the current code; they
should change when the bug is fixed.
