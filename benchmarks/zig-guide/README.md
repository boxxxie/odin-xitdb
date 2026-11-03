# Idiomatic Zig Optimization Guide for `xitdb`

[← Back to Benchmark Suite (`benchmarks/README.md`)](../README.md) · [Per-Benchmark Code Slices (`benchmarks/slices/README.md`)](../slices/README.md)

This directory is a practical, peer-engineering reference prepared for [`xitdb`](../../reference/xitdb-zig/src/lib.zig) maintainers and contributors. It isolates the exact architectural differences between the Odin implementation ([`xitdb/*.odin`](../../xitdb)) and the upstream Zig `0.17.0` reference ([`reference/xitdb-zig/src/lib.zig`](../../reference/xitdb-zig/src/lib.zig)) across all **63 shared 1v1 benchmarks**, and proposes small, idiomatic Zig adjustments that capture the same speedups **without sacrificing human readability, altering the v1 wire format, or inflating code size**.

---

## Design Constraints for Every Recommendation

`reference/xitdb-zig/src/lib.zig` (~5,300 lines) is remarkably clean: every persistent data structure, cursor, compactor, and storage backend fits in a single, self-contained file with clear invariants. Every suggestion in this guide adheres to four rules:

1. **Zero Wire-Format Changes:** All 63 shared benchmarks produce **byte-for-byte identical** databases (`0` footprint mismatches). Every proposed change preserves exact big-endian slot, node, header, and CRC-64/XZ trailer layouts.
2. **Preserve Public APIs & Abstractions:** Keep `Database(db_kind, HashInt)`, `Cursor(write_mode)`, `BTreeNode`, `SortedNode`, and `std.Io.Reader` / `std.Io.Writer` intact.
3. **No Code Explosion:** All 6 adjustments combined total **~140 net lines of Zig**—and in several places (such as `SortedMap` node search) *reduce* repetition by replacing four separate linear scan loops with two 12-line binary search helpers.
4. **Keep What Zig Already Wins:** On `#43 Compaction (Heterogeneous DAG + dedup)`, **Zig is 1.15x faster than Odin** (`110.1 ms` vs `126.6 ms`) because Zig's `std.AutoHashMap(u64, u64)` uses SIMD SwissTable metadata probing. All recommendations keep `Compactor`'s `AutoHashMap` architecture untouched.

---

## The 6 Practical Adjustments (Ranked by Impact-to-LOC Ratio)

| Guide | Target in `lib.zig` | Measured Gap Today | Net Zig Delta | Key Change |
| :--- | :--- | :--- | ---: | :--- |
| [**01. Zero-Vtable `CoreMemory` I/O**](01_core_memory_zero_vtable_io.md) | [`CoreMemory`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027), [`takeInt`](../../reference/xitdb-zig/src/lib.zig#L5251-L5255) | **2.0x – 6.3x** across all in-memory reads | `~15 LOC` | Back `CoreMemory.Reader` with `std.Io.Reader.fixed(written)` instead of `.buffer = &.{}` so `takeInt` / `readSliceAll` run inline without 2 vtable calls per read. |
| [**02. B-Tree Batch Node I/O & Leaf Seek**](02_btree_node_batch_io_and_leaf_seek.md) | [`readBTreeNode`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991), [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) | **4.6x – 44.9x** (`#20–#27`) | `~35 LOC` | Decode/encode 16-slot B-Tree nodes via one stack `[274]u8` buffer (`0..node.num` instead of 18–34 `takeInt`/`writeInt` calls), and seek straight to the single 9-byte leaf slot in `readBTreeSlot` (`44.1x`). |
| [**03. Sorted B+Tree Binary Search & Select**](03_sorted_bptree_binary_search.md) | [`sortedGet`](../../reference/xitdb-zig/src/lib.zig#L2634-L2760), [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528), [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) | **4.1x – 51.3x** (`#28–#38`) | `~40 LOC` | Replace $O(B)$ linear scans with $O(\log_2 16)$ binary search ($\le 4$ key comparisons), drop `@splat(0)` in `compareKey`, batch-decode `SortedNode` (1 read vs 50 `takeInt`s), and seek directly in `sortedGetByIndex` (`51.3x`). |
| [**04. HAMT Single-Pass KV & Lazy Remove**](04_hamt_single_pass_kv_and_lazy_remove.md) | [`HashMap`](../../reference/xitdb-zig/src/lib.zig#L3835-L3930), [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1600-L1726), [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1728-L1811) | **2.4x – 13.4x** (`#1–#13`, `#45–#46`) | `~30 LOC` | Add single-pass `putKeyValue` to avoid traversing the HAMT twice per insert, and defer reading the 144-byte sibling block in `removeMapSlot` until unwind when a child actually collapses (`13.4x`). |
| [**05. Cursor Bytes, Streams & Nested Paths**](05_cursor_bytes_streams_and_paths.md) | [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3289-L3340), [`Cursor.Writer`](../../reference/xitdb-zig/src/lib.zig#L3005-L3093), [`writePath`](../../reference/xitdb-zig/src/lib.zig#L3149-L3185) | **1.3x – 8.7x** (`#47–#57`) | `~15 LOC` | Coalesce payload + 2-byte `format_tag` reads (`6.3x`), reserve stream capacity up front, and skip redundant slot reloads on read-only / un-frozen path steps. |
| [**06. `CoreBufferedFile` Hot-Tail Cache & Compaction**](06_buffered_file_tail_cache_and_compaction.md) | [`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232), [`Compactor`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913) | **4.1x** (`#59`), **10.0x** (`#39`), **1.15x Zig win** (`#43`) | `~18 LOC` | Track `flushed_len: usize` in `CoreBufferedFile` so `flush()` persists dirty tail bytes without evicting the in-memory read window or losing `file_len` across commits. |

---

## How the Optimizations Compound

Several of these adjustments reinforce one another without touching each other's code:

- Applying **Guide 01** (`CoreMemory` fixed-slice reader) immediately accelerates every collection (`ArrayList`, `HashMap`, `LinkedArrayList`, `SortedMap`, `Cursor.Reader`, `Compactor`, and `Database.init`) because `takeInt` stops doing two virtual calls per integer.
- Applying **Guides 02 & 03** (stack-buffered node serialization + leaf slot seek + binary search) also accelerates **disk-backed databases** (`CoreFile` and `CoreBufferedFile`), where collapsing 34–50 `writeInt` calls into a single `writeAll` turns 34–50 `pwritev` syscalls per B-Tree/B+Tree node into 1 syscall, and speeds up `Compactor` (`#41–#43`) as a free side effect.
