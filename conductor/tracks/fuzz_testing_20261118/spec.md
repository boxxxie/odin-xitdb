# Specification: Combined `libFuzzer` + ASan & Differential Simulation Fuzzing (`fuzz_testing_20261118`)

## Overview
Add a lightweight, two-part fuzzing setup to [`xitdb-odin`](../../../AGENTS.md) where each technique targets a genuinely distinct class of bugs:

1. **Coverage-Guided `libFuzzer` + AddressSanitizer (`fuzz/` via `-build-mode:llvm-ir` + `clang -fsanitize=fuzzer,address`):**
   - Mutates raw byte inputs guided by LLVM sanitizer coverage (`__sancov_*`) directly inside compiled Odin IR while ASan checks memory bounds and lifetimes.
   - Catches parser crashes, out-of-bounds reads/writes, malformed `.xit` binary trailer/slot handling, integer overflows, and hang/timeout paths.
2. **Deterministic Differential Simulation (`tests/fuzz_sim_xitdb.odin` via `odin test` + `-sanitize:address`):**
   - Drives seeded PRNG operation sequences (`core:math/rand`) over valid multi-moment database transactions and compares `xitdb` collections, iterators, diffs, compaction, and storage backends against a pure-Odin reference model.
   - Catches logical/structural-sharing bugs (e.g., B-Tree/B+Tree splits & deletions, stale branch separators, HAMT unwritten-element accounting, forward vs. reverse iterator parity, `Core_Memory` vs. `Core_Buffered_File` vs. `Core_Overlay` consistency) that random byte mutation rarely reaches.

## Architecture & Scope

### 1. Coverage-Guided `libFuzzer` + ASan Harnesses (`fuzz/`)
Build pipeline using Odin's LLVM-IR output (`-build-mode:llvm-ir -no-entry-point`) linked with `clang -O1 -g -fsanitize=fuzzer,address -Wno-override-module` (`-lm -lpthread -ldl -lluajit-5.1`):
* **`fuzz/fuzz_dsl.odin` (DSL & Query Parsers):**
  - Export `LLVMFuzzerTestOneInput` calling `context = runtime.default_context()` and `defer free_all(context.temp_allocator)`.
  - Exercise `xitdb.parse_selector`, `xitdb.parse_steps`, `xitdb.parse_datalog`, `xitdb.pull` (against a seeded `Core_Memory` DB), and `xitdb.transact_script`.
  - Include a minimal seed corpus and optional token dictionary for selector/Datalog sigils and keywords.
* **`fuzz/fuzz_wire.odin` (Corrupted `.xit` Wire Format & Compaction):**
  - Seed corpus with valid minimal v1 and v2 `Core_Memory` byte snapshots (`core_memory_bytes`).
  - Feed mutated/truncated bytes via `core_memory_init_from_bytes` into `database_init`, `database_read_and_validate_header`, `database_read_root_header`, `database_committed_size`, `database_compact`, `diff_moments`, and shallow cursor reads.
  - Invariant: corrupted or truncated `.xit` payloads must return structured `Error` values without panicking, hanging, or triggering ASan OOB reads.
* **`fuzz/fuzz_lua.odin` (LuaJIT Bridge Safety):**
  - Exercise untrusted/mutated Lua chunks against a fresh `lua.State` + `Core_Memory` database under ASan to guard `xitdb/lua.odin` userdata lifetimes and error paths.
* **Runner Script (`fuzz/run.sh`) & Git Hygiene:**
  - Provide a single script to build any target (`dsl`, `wire`, `lua`, or `all`), run bounded campaigns (e.g., `-max_total_time=30`), and store ephemeral `.ll` build outputs and crash artifacts under git-ignored directories (`.tmp/` or `fuzz/.tmp/`), while keeping curated small seeds under `fuzz/corpus/`.

### 2. Deterministic Differential Simulation (`tests/fuzz_sim_xitdb.odin`)
* Implement a seeded PRNG operation-stream fuzzer inside `package xitdb_tests` configurable at compile time via `-define:ODIN_FUZZ_SEED=<n>` and `-define:ODIN_FUZZ_OPS=<n>` (with a fast deterministic default so `odin test tests` stays quick in CI).
* Maintain a simple in-memory reference oracle (plain Odin dynamic arrays, maps, and moment snapshots) and execute randomized interleaved sequences of:
  - `Array_List` (`append`, `insert`, `slice`, `get`) and `Linked_Array_List` (`insert`, `delete`, `slice`, `concat`)
  - `Hash_Map` / `Counted_Hash_Map` / `Sorted_Map` (`put`, `remove`, range/prefix queries) and Set variants
  - Multi-moment branching (`base_moment`), `diff_moments` / `collection_diff`, `database_compact`, and forward vs. reverse `Cursor_Iterator` checks
  - Cross-backend parity checks across `Core_Memory`, `Core_Buffered_File`, and `Core_Overlay`
* Verify zero memory leaks under `odin test`'s tracking allocator and run deeper sweeps under `-sanitize:address` (`odin test tests -sanitize:address -define:ODIN_FUZZ_OPS=2000`).

### 3. Remediation & Permanent Regression Tests
* Run bounded initial campaigns for both `libFuzzer` targets and simulation sweeps.
* Fix any bugs, panics, OOB reads, leaks, or model mismatches discovered in `xitdb/` while strictly preserving v1/v2 wire compatibility (`SLOT_LENGTH`, `INDEX_BLOCK_SIZE`, `HEADER_LENGTH`, big-endian encoding, `Tag` enum values).
* Promote any minimized crasher inputs or failing simulation seeds into deterministic `@(test)` regression tests inside `tests/` so standard CI (`odin check` + `odin test tests` across Linux, macOS, and Windows) protects against regressions without requiring `libFuzzer` in CI.

## Out of Scope
* Requiring `clang` / `libFuzzer` inside `.github/workflows/ci.yml` for standard PR checks (CI continues running `odin check` and `odin test tests`, which includes the deterministic simulation smoke test and saved regression cases).
* Modifying `reference/xitdb-zig*` submodules.
