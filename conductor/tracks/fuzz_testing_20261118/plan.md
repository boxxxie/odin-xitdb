# Implementation Plan: `fuzz_testing_20261118`

## Phase 1: `libFuzzer` + ASan Build Pipeline & Parser/Wire/Lua Harnesses (`fuzz/`)
- [x] Add `fuzz/run.sh` to compile `LLVMFuzzerTestOneInput` targets via `odin build ... -collection:xitdb=./xitdb -build-mode:llvm-ir -sanitize:address -no-entry-point` and link with `clang -O1 -g -fsanitize=fuzzer,address -Wno-override-module -Wno-backend-plugin ...` (writing IR/binaries/artifacts to git-ignored `.tmp/fuzz/`).
- [x] Implement [`fuzz/dsl/fuzz_dsl.odin`](../../fuzz/dsl/fuzz_dsl.odin) exercising `parse_selector`, `parse_steps`, `parse_datalog`, `pull`, and `transact_script` against a seeded `Core_Memory` DB, plus initial seeds/dictionary in `fuzz/corpus/dsl/`.
- [x] Implement [`fuzz/wire/fuzz_wire.odin`](../../fuzz/wire/fuzz_wire.odin) seeded with valid v1/v2 `.xit` byte blobs via `core_memory_init_from_bytes`, exercising `database_init`, header/trailer validation, `database_compact`, `diff_moments`, and cursor reads to verify corrupted blobs fail safely without panics or ASan violations.
- [x] Implement [`fuzz/lua/fuzz_lua.odin`](../../fuzz/lua/fuzz_lua.odin) exercising mutated Lua snippets against `xitdb/lua.odin` + `Core_Memory` under ASan.
- [x] Verify all `fuzz/` targets build cleanly and pass a smoke run (`-runs=1000`).

## Phase 2: Deterministic Differential Simulation Harness (`tests/fuzz_sim_xitdb.odin`)
- [x] Implement a pure-Odin reference model and seeded PRNG (`core:math/rand`, `-define:ODIN_FUZZ_SEED`, `-define:ODIN_FUZZ_OPS`) in [`tests/fuzz_sim_xitdb.odin`](../../tests/fuzz_sim_xitdb.odin).
- [x] Cover randomized interleavings of `Hash_Map`, `Counted_Hash_Map`, `Sorted_Map`, `Array_List`, `Linked_Array_List`, sets, `base_moment` forks, `diff_moments` / `collection_diff`, `database_compact`, forward vs. reverse `Cursor_Iterator` equality, and `Core_Memory` / `Core_Buffered_File` / `Core_Overlay` backend parity.
- [x] Verify fast default smoke execution under `odin test tests` with zero leaks in Odin's tracking allocator and heavier sweeps under `odin test tests -sanitize:address -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_FUZZ_OPS=2000`.

## Phase 3: Initial Fuzz Campaigns, Bug Fixes & Regression Promotion
- [x] Run bounded `libFuzzer` campaigns across `dsl`, `wire`, and `lua` targets (e.g., 30–60s each) and deep seeded simulation sweeps (`ODIN_FUZZ_OPS=2000+` under `-sanitize:address`).
- [x] Fix any crashes, OOB reads, leaks, or invariant mismatches uncovered in [`xitdb/`](../../xitdb/) while preserving v1/v2 wire compatibility.
- [x] Add deterministic `@(test)` regression cases in [`tests/`](../../tests/) for every minimized `libFuzzer` crasher or failing simulation seed found.
- [x] Document fuzzing commands in [`tests/README.md`](../../tests/README.md) / [`AGENTS.md`](../../AGENTS.md) and run full verification (`odin check xitdb/luajit -no-entry-point`, `odin check xitdb -no-entry-point`, `odin check cmd/xit`, `odin check tests`, `odin test tests`).
