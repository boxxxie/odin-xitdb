# `odin-xitdb` (`package xitdb`) — Embeddable Immutable Database for Odin

[![CI](https://github.com/boxxxie/odin-xitdb/actions/workflows/ci.yml/badge.svg)](https://github.com/boxxxie/odin-xitdb/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-v0.1.0-blue.svg)](README.md)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09%2B-3882D2.svg)](https://odin-lang.org)
[![Format](https://img.shields.io/badge/xitdb-v1%20wire%20format-5C6BC0.svg)](https://github.com/xit-vcs/xitdb)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

An idiomatic [Odin](https://odin-lang.org/) implementation of **[xitdb](https://github.com/xit-vcs/xitdb)** — an embeddable, immutable, append-only database with persistent structural sharing.

Wire-compatible (`v1` binary format) with the official [Zig](https://github.com/xit-vcs/xitdb), [Go](https://github.com/xit-vcs/xitdb-go), [Java](https://github.com/xit-vcs/xitdb-java), [Clojure](https://github.com/xit-vcs/xitdb-clj), and [TypeScript](https://github.com/xit-vcs/xitdb-ts) implementations.

---

## Features

- **100% v1 Wire Compatibility:** Reads and writes databases interchangeable with Zig, Go, Java, Clojure, and TypeScript `xitdb`.
- **Zero External Dependencies:** Pure-Odin SHA-1 (`20` bytes) and SHA-256 (`32` bytes) hashers (`sha1_hasher`, `sha256_hasher`), plus custom `Hasher` support with runtime `hash_size` validation.
- **Persistent Collections with Structural Sharing:**
  - `Array_List` (`Read_Array_List` / `Write_Array_List`) — 16-way radix trie (`O(log16 N)` random access, append, slice)
  - `Linked_Array_List` (`Read_Linked_Array_List` / `Write_Linked_Array_List`) — Count-augmented B-Tree (`O(log N)` random access, insert, remove, slice, concat)
  - `Hash_Map` & `Counted_Hash_Map` (`Read_Hash_Map` / `Write_Hash_Map` / `Read_Counted_Hash_Map` / `Write_Counted_Hash_Map`) — 16-way HAMT keyed by explicit hash (`[]u8`), `string`, or `Bytes`
  - `Hash_Set` & `Counted_Hash_Set` (`Read_Hash_Set` / `Write_Hash_Set` / `Read_Counted_Hash_Set` / `Write_Counted_Hash_Set`)
  - `Sorted_Map` & `Sorted_Set` (`Read_Sorted_Map` / `Write_Sorted_Map` / `Read_Sorted_Set` / `Write_Sorted_Set`) — Count-augmented B+Tree ordered lexicographically by key bytes, supporting `rank`, index lookup, and range iterators
- **Storage Backends (`Core`):**
  - `Core_Memory` — In-memory dynamic byte buffer
  - `Core_File` — Direct OS file storage with configurable `fsync`
  - `Core_Buffered_File` — Write-buffered OS file storage
- **Compaction & Replication:**
  - `database_compact` with `Memory_Offset_Map` or disk-backed `File_Offset_Map`
  - Incremental log shipping via `database_replica_state`, `database_replication_start`, `database_read_committed`, and `database_apply_replicated` (protected by CRC-64/XZ commit trailer checksums)

---

## Project Layout

```text
xitdb/
├── xitdb/
│   ├── types.odin             # Wire format constants, tags, slots, headers, trailers, SHA-1/SHA-256
│   ├── core.odin              # Core_Memory, Core_File, Core_Buffered_File I/O backends
│   ├── database.odin          # Database init, root commits, path traversal, transactions
│   ├── hamt.odin              # 16-way HAMT & Radix-Trie operations
│   ├── btree.odin             # Count-augmented B-Tree & B+Tree operations
│   ├── cursor.odin            # Read_Cursor, Write_Cursor, Cursor_Reader, Cursor_Writer, Cursor_Iterator
│   ├── collections.odin       # High-level collection wrappers
│   └── compact_replicate.odin # Compaction & incremental replication
├── tests/
│   ├── spec_xitdb.odin        # Layer 1: ATDD Executable Specifications & Property Invariants
│   ├── dsl_xitdb.odin         # Layer 2: Domain-Specific Language (`given_*` / `upon_*` / `then_*`)
│   ├── driver_xitdb.odin      # Layer 3: Composable Protocol Drivers & Cross-Cutting Invariants
│   └── testdata/test.db       # Reference binary fixture from upstream xitdb
├── benchmarks/
│   ├── bench_xitdb.odin       # 63-benchmark suite for xitdb-odin
│   ├── bench_xitdb.zig        # 1:1 mirrored 63-benchmark suite for upstream xitdb-zig
│   └── compare_1v1.py         # Automated 1v1 runner & side-by-side comparison table
├── vendor/
│   └── xitdb-zig/             # Upstream canonical Zig implementation (git submodule)
└── build.zig                  # Zig 0.17.0 build configuration for upstream tests & 1v1 benchmarks
```

---

## Quick Start

```odin
package main

import "core:fmt"
import "xitdb"

write_moment :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
	moment := xitdb.write_hash_map_init(cursor^) or_return
	xitdb.hash_map_put(&moment, "greeting", "Hello, xitdb!") or_return

	fruits_cur := xitdb.hash_map_put_cursor(&moment, "fruits") or_return
	fruits := xitdb.write_array_list_init(fruits_cur) or_return
	xitdb.array_list_append(&fruits, "apple") or_return
	xitdb.array_list_append(&fruits, "mango") or_return
	return nil
}

main :: proc() {
	core: xitdb.Core = xitdb.core_memory_init()
	defer xitdb.core_destroy(&core)

	db, _ := xitdb.database_init(&core, xitdb.sha1_hasher(xitdb.string_to_id("sha1")))
	root_cursor := xitdb.database_root_cursor(&db)
	history, _ := xitdb.write_array_list_init(root_cursor)

	// Commit an immutable transaction moment
	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, write_moment, nil)

	// Read back from moment 0
	m0_cur, _ := xitdb.array_list_get_cursor(history, 0)
	moment, _ := xitdb.read_hash_map_init(m0_cur.?)
	greeting_cur, _ := xitdb.hash_map_get_cursor(moment, "greeting")
	greeting, _ := xitdb.cursor_read_string(greeting_cur.?, 1024, context.temp_allocator)
	fmt.println(greeting) // "Hello, xitdb!"
}
```

---

## Running Tests & Benchmarks

```bash
# Run the 28-test ATDD suite (with memory leak tracking enabled)
odin test tests

# Run the Odin 63-benchmark suite
odin run benchmarks -o:speed

# Run the mirrored Zig 63-benchmark suite against the vendor/xitdb-zig submodule (requires Zig 0.17.0)
zig build bench -Doptimize=ReleaseFast

# Run the automated 1v1 side-by-side comparison (Odin vs Zig)
./benchmarks/compare_1v1.py
```
