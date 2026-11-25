# Changelog

All notable changes to **`odin-xitdb`** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.1] - 2026-11-25

### Fixed

- **Unified 64-Level Depth Ceiling & Iterator Init Safety (`xitdb/types.odin`, `xitdb/btree.odin`, `xitdb/database.odin`, `xitdb/cursor.odin`, `xitdb/collections.odin`):**
  - Synced `MAX_BTREE_DEPTH` and `ITERATOR_STACK_SIZE` at `64` levels across `Cursor_Iterator`, B-tree descents/writes, and root-collapse loops (upstream `xitdb-zig` `c126134`).
  - Resolved `unresolved_cursor` before `_reset_cursor_iterator` across all 10 `cursor_iterator_*_init` procedures so self-aliased restarts on 48-byte `Read_Cursor` lvalues do not zero the input cursor, and initialized named `res` in place across all 28 collection iterator wrappers.
- **Iterative Compaction Worklist (`xitdb/compact_replicate.odin`):**
  - Replaced recursive compaction traversal with an explicit heap worklist (`_Compact_Task` / `_compactor_drain`) and uninlined `_compactor_reserve_block` so `database_compact` runs in `O(1)` C stack space on `512 KiB` thread stacks across 64-level B-trees, 64-nibble HAMTs, and deeply nested mixed collections while preserving cyclic graph identity and OOM handling.
- **Lua Unmarshal Cycle Detection Past Depth 64 (`xitdb/lua.odin`):**
  - Extended `_Lua_Visited_Stack` in `lua_unmarshal_cursor` to spill past its 64-entry inline buffer into a lazily allocated dynamic slice so cycles at depth `>= 64` are detected cleanly without stack overflow while preserving zero heap overhead for depth `<= 64`.

### Changed

- **Compact 64-Level Diff Walkers & Zero-Copy Iterator Paths (`xitdb/collection_diff.odin`, `xitdb/dsl.odin`, `xitdb/lua.odin`):**
  - Unified HAMT and B+Tree diff depth bounds to `64`, shrank `Tree_Frame`, and backed `Tree_Walker` with height-sized `scratch_allocator` slices instead of fixed `[64]Sorted_Node` arrays.
  - Switched DSL (`history_of`, `query_prefix`, `query_page`) and Lua cursor/collection iterator userdata constructors (`_l_cursor_iterator`, `_col_acquire_iterator`) to in-place `Cursor_Iterator` initialization.
- **Benchmarks, CI & Deep-Stack Test Coverage (`benchmarks/render/`, `.github/workflows/ci.yml`, `tests/`):**
  - Replaced `benchmarks/update_readme.sh` with the `temple` AOT SVG renderer and wired CI `hugi` collection paths.
  - Added `512 KiB` small-stack and 64-level boundary tests covering `Cursor_Iterator` self-aliasing, 64-nibble HAMTs, 64-level B-trees, `database_compact`, 45-level recursive Odin struct `unmarshal`, Lua deep cycles (`>= 64`), and recursive Lua `:iterator()` traversals.

## [2.2.0] - 2026-11-22

### Added

- **Collection Diff Telemetry & Scratch Allocator (`xitdb/collection_diff.odin`):**
  - Added `Diff_Stats` (`slots_skipped`, `blocks_compared`, `keys_decoded`) and `diff_collection_with_stats(cur_a, cur_b, stats, allocator, scratch_allocator)` with explicit `scratch_allocator` cleanup on normal and error paths, zero-allocation equal-slot short-circuiting, B+Tree `blocks_compared` telemetry, and single-decode leaf traversal.
- **Database `hash_id` Validation (`xitdb/types.odin`, `xitdb/database.odin`, `xitdb/compact_replicate.odin`):**
  - Added `Xitdb_Error.Invalid_Hash_Id` and `header_validate_hasher` across database open and full replication (`start == 0`), rejecting mismatched non-zero `Hasher.id` values while preserving untagged `header.hash_id == 0` and wildcard `hasher.id == 0` compatibility.

### Changed

- **Same-`Database` Diff Guard & Documentation (`xitdb/collection_diff.odin`, `docs/CORE_API.md`, `usage-rules.md`, `README.md`):**
  - Enforced the same-`Database` cursor invariant up front in `diff_collection` / `diff_collection_with_stats` (returning `.Invalid_Database` for cross-database cursors or non-empty cursors with `db == nil`, while allowing empty `Read_Cursor{}` sentinels).
  - Updated `docs/CORE_API.md`, `usage-rules.md`, and `README.md` with current `Hasher` signatures, `header_validate_hasher` / `.Invalid_Hash_Id` compatibility rules, and `diff_collection_with_stats` / `Core_Overlay` guidance.
- **CI & Release Workflows (`.github/workflows/ci.yml`, `.github/workflows/release.yml`):**
  - Bumped ephemeral `boxxxie/hugi` runner checkout from `v0.1.0` to `v0.1.2`.

## [2.1.0] - 2026-11-21

### Added

- **In-Place `Cursor_Iterator` Initialization (`xitdb/cursor.odin`):**
  - Added 10 `@(require_results)` pointer-initialized iterator procedures (`cursor_iterator_init`, `cursor_iterator_reverse_init`, `cursor_iterator_sorted_from_index_init`, `cursor_iterator_sorted_from_key_init`, `cursor_iterator_sorted_reverse_from_index_init`, `cursor_iterator_sorted_reverse_from_key_init`, `cursor_iterator_array_list_from_index_init`, `cursor_iterator_array_list_reverse_from_index_init`, `cursor_iterator_linked_array_list_from_index_init`, and `cursor_iterator_linked_array_list_reverse_from_index_init`) that reset iterator state up front and zero the target on error for safe reuse across collections and small thread stacks.
- **Stack-Buffered DSL & Slot-Only KV Helpers (`xitdb/dsl.odin`, `xitdb/database.odin`):**
  - Added `parse_selector_buf`, `parse_steps_buf`, `selector_destroy_buf`, and `steps_destroy_buf` for `[16]Path_Step` stack-buffered path parsing without heap allocations on common paths.
  - Added `database_kv_key_position` and `database_kv_value_position` for slot-only KV offset reads without decoding full payloads.
- **Coverage-Guided Fuzzing & Differential Simulation (`fuzz/`, `tests/`):**
  - Added `libFuzzer` + ASan/LSan harnesses for DSL (`fuzz/dsl`), wire corruption (`fuzz/wire`), and LuaJIT (`fuzz/lua`) driven by [`fuzz/run.sh`](fuzz/run.sh), plus deterministic differential simulation (`tests/fuzz_sim_xitdb.odin`) and regression suites (`tests/unit_fuzz_regressions.odin`).
- **Benchmarking & Release Automation (`benchmarks/`, `hugi.json`, `.github/workflows/`):**
  - Integrated [`hugi`](https://github.com/boxxxie/hugi) `v0.1.0` (`hugi.json`, `benchmarks/history.hugidb`, CPU pinning `--pin`, Linux `perf_event` hardware counters `--counters`, `--test` smoke mode, `--host-warned`, and `HENV` host provenance) with CI verification against `boxxxie/hugi@v0.1.0`.
  - Added `CHANGELOG.md` and tag/manual GitHub Release workflow (`.github/workflows/release.yml`).

### Changed

- **DSL & Recursive Traversal Performance (`xitdb/dsl.odin`, `xitdb/lua.odin`):**
  - Accelerated `select_cursor`, `history_of` (pre-hashed steps and metadata keys), and slot-only KV reads.
  - Pooled recursive `Cursor_Iterator` instances in DSL `pull`, `diff_cursors`, `unmarshal_into`, and Datalog pattern evaluation (`_Iter_Pool`), as well as Lua `unmarshal`, so deep recursive traversals run safely on `512 KiB` thread stacks.
- **Reference Submodules & Benchmarks:**
  - Synced `reference/xitdb-zig` to `274418f` and rebased `reference/xitdb-zig-patched` with active PRs; refreshed Odin, LuaJIT, and Zig benchmark tables (`benchmarks/README.md`, `benchmarks/slices/`).

### Fixed

- **Wire, B-Tree, HAMT & Cursor Integrity (`xitdb/btree.odin`, `xitdb/hamt.odin`, `xitdb/cursor.odin`, `xitdb/database.odin`, `xitdb/types.odin`):**
  - Validated full node blocks, depth/height/count/rank bounds, iterator spines, counted-map bounds, and interior `.Index` tags across reads, splits, joins, and iterations.
  - Hardened wire bounds, negative slot values, OOM and allocation-failure rollback paths, DSL/Datalog parser edge cases, `_pull_range` tag validation, and LuaJIT sandbox/commit-error use-after-free guards.
- **Odin `dev-2026-11a+` Escape Analysis & ARM64 `-vet` Compatibility (`xitdb/sha_ni_amd64.odin`, `xitdb/sha_ni_other.odin`, `xitdb/types.odin`, `xitdb/database.odin`, `xitdb/cursor.odin`):**
  - Isolated `amd64`-only `core:simd` / `core:simd/x86` SHA-NI intrinsics into `xitdb/sha_ni_amd64.odin` (`#+build amd64`) with non-`amd64` stubs in `xitdb/sha_ni_other.odin` (`#+build !amd64`), resolving unused-import `-vet` failures on ARM64 targets (macOS/Linux).
  - Replaced stack-pointed `Database.transaction` with value-embedded `Maybe(Transaction)` and monotonic `tx_seq` / `Write_Cursor.transaction_id`, hardening `.Expired_Transaction` enforcement across subsequent transactions and removing stack-escape warnings.
  - Reconstructed pointer-free `Slot` values from scalar fields in `slot_with_full`, `_try_encode_inline_data`, and `_encode_writeable_data`, and kept CI/release workflows unpinned on Odin `latest` with cross-OS `-vet -warnings-as-errors`.

## [2.0.1] - 2026-11-16

### Fixed

- Resolved variable shadowing warnings under `odin check -vet` in `xitdb/cursor.odin`, `xitdb/lua.odin`, and `xitdb/types.odin`.

## [2.0.0] - 2026-11-16

### Added

- **`xitdb` v2 Wire Format:** Added `FILE_SIZE_START` root header layout (`VERSION :: 2`) with backward-compatible v1 reading and automatic recovery of databases whose first commit did not complete.
- **`Core_Overlay` & `diff_collection` (`xitdb/core.odin`, `xitdb/collection_diff.odin`):** Added zero-copy copy-on-write forks (`core_overlay_init`) and structural byte-key HAMT/B+Tree diffs skipping shared subtrees.
- **Lock-Free Stateless Cursors & Virtual Memory Core (`xitdb/core.odin`, `xitdb/cursor.odin`):** Added stateless positional `core_read_*_at` I/O across `Core_Memory`, `Core_File`, and `Core_Buffered_File`, plus `vmem.reserve`-backed `Core_Memory` so `raw_data(buf)` remains stable during concurrent appends.
- **Reverse & Upper-Bound Range Iterators (`xitdb/cursor.odin`, `xitdb/collections.odin`):** Added `cursor_iterator_reverse`, `cursor_iterator_prev`, and reverse/from-key/from-index iterators across collections.
- **Embedded LuaJIT 2.1 Client & CLI (`xitdb/lua.odin`, `xitdb/luajit/`, `cmd/xit/`):** Added LuaJIT 2.1 userdata bindings, 5-layer DSL Lua bridge, `\x1bLJ` bytecode workflows (`lua-eval`, `lua-run`, `lua-compile`), and `--version` support in `cmd/xit`.
