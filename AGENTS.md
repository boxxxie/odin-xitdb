# AGENTS.md — xitdb Repository Guide

This document provides repository architecture, build/test commands, and development rules for coding agents working on `xitdb`.

---

## Repository Overview & Architecture

* **`xitdb/`** — Pure-Odin v1 wire-compatible implementation (`package xitdb`) with zero external dependencies:
  * **`types.odin`**: Wire constants, `Slot`, `Header`, `Root_Header`, `Root_Trailer`, CRC-64/XZ, and SHA-NI hardware-accelerated SHA-1/SHA-256.
  * **`core.odin`**: `Core_Memory` (virtual-memory `vmem.reserve` / `vmem.commit` backed so `raw_data(buf)` never moves), `Core_File` (`os.read_at` / `pread`), and `Core_Buffered_File` storage backends with stateless positional `core_read_*_at` I/O.
  * **`database.odin`**: Transaction lifecycle, `database_freeze`, and central `read_slot_pointer` path engine.
  * **`cursor.odin`**: Lock-free stateless `Read_Cursor`, `Write_Cursor`, `Cursor_Reader`, `Cursor_Writer`, and stack-allocated `Cursor_Iterator`.
  * **`collections.odin`**: Typed wrappers for `Array_List`, `Linked_Array_List`, `Hash_Map`, `Counted_Hash_Map`, `Sorted_Map`, and sets.
  * **`hamt.odin` & `btree.odin`**: 16-way HAMT, 16-way Radix Trie, count-augmented B-Tree, and B+Tree implementations.
  * **`compact_replicate.odin`**: Garbage-collecting compactor (`Memory_Offset_Map` / `File_Offset_Map`) and incremental byte-range replication.
  * **`dsl.odin`**: 5-layer DSL (Selectors, Datomic `Tx` & `transact_script`, `marshal`/`unmarshal`/`pull`, `diff_moments`/`history_of`, and Datalog engine).
  * **`lua.odin` & `luajit/luajit.odin`**: Embedded LuaJIT 2.1 (`system:luajit-5.1`) userdata bindings, 5-layer DSL Lua bridge, and `\x1bLJ` bytecode compilation/storage.
* **`cmd/xit/main.odin`** — Standalone CLI and interactive REPL binary.
* **`tests/`** — 3-layer ATDD executable specification and unit test suite (`package xitdb_tests`).

---

## Build, Check & Test Commands

```bash
# 1. Typecheck library, CLI, and test packages
odin check xitdb
odin check cmd/xit
odin check tests

# 2. Run the full ATDD specification and unit test suite
odin test tests

# 3. Run a single test by name
odin test tests -define:ODIN_TEST_NAMES=xitdb_tests.spec_reference_database_wire_compatibility

# 4. Build and run the CLI / interactive REPL
odin build cmd/xit -out:xit -o:speed
./xit --memory
```

---

## Coding & Testing Rules for Agents

* **Read [`usage-rules.md`](usage-rules.md) First**: Follow all collection sigil rules, `cursor_freeze` invariants, `xitdb:"..."` struct tags, and allocator lifetimes defined in [`usage-rules.md`](usage-rules.md).
* **Preserve Wire Compatibility**: Never alter `SLOT_LENGTH` (9), `INDEX_BLOCK_SIZE` (144), `HEADER_LENGTH` (20), `ROOT_HEADER_LENGTH` (17), `ROOT_TRAILER_LENGTH` (25), big-endian encoding, or `Tag` enum values in [`xitdb/types.odin`](xitdb/types.odin).
* **Zero Leaks Under `odin test`**: The Odin test runner attaches a tracking allocator to `context.allocator`. Free all heap allocations (`defer xitdb.tx_destroy(&tx)`, `defer xitdb.tx_report_destroy(&rep, context.allocator)`) and call `defer free_all(context.temp_allocator)` in standalone unit tests.
* **Follow the 3-Layer ATDD Test Architecture in `tests/`**:
  * **Layer 1 (`tests/spec_xitdb.odin`, `tests/spec_dsl_xitdb.odin`)**: Express behavioral specifications using domain `given_*`, `upon_*`, and `then_*` steps with zero raw offsets or cursor plumbing.
  * **Layer 2 (`tests/dsl_xitdb.odin`)**: Bridge domain steps to protocol driver procedures.
  * **Layer 3 (`tests/driver_xitdb.odin`)**: Isolate direct `xitdb` cursor/core calls, enforce cross-cutting collection invariants, and clean up all temporary files in `driver_destroy_ctx`.
