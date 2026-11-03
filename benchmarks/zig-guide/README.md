# Idiomatic Zig Optimization Guide for `xitdb`

[← Back to Benchmark Suite (`benchmarks/README.md`)](../README.md) · [Per-Benchmark Code Slices (`benchmarks/slices/README.md`)](../slices/README.md) · [**Download Tested Patch (`zig_optimizations.patch`)**](zig_optimizations.patch)

This directory is a practical, peer-engineering reference prepared for [`xitdb`](../../reference/xitdb-zig/src/lib.zig) maintainers and contributors. It isolates the exact architectural differences between the Odin implementation ([`xitdb/*.odin`](../../xitdb)) and the upstream Zig `0.17.0` reference ([`reference/xitdb-zig/src/lib.zig`](../../reference/xitdb-zig/src/lib.zig)) across all **63 shared 1v1 benchmarks**, and proposes small, idiomatic Zig adjustments that capture the same speedups **without sacrificing human readability, altering the v1 wire format, or inflating code size**.

> [!TIP]
> **Ready-to-Apply Git Patch:** All 6 adjustments have been implemented, verified against 100% of upstream `src/test.zig` (11/11 test suites), and benchmarked across all 63 `ReleaseFast` workloads with **0 byte-footprint mismatches**. You can inspect or apply the complete diff directly from [**`benchmarks/zig-guide/zig_optimizations.patch`**](zig_optimizations.patch) (`git -C reference/xitdb-zig apply ../../benchmarks/zig-guide/zig_optimizations.patch`).
> *(Note: The main [`benchmarks/README.md`](../README.md) and [`benchmarks/zig.jsonl`](../zig.jsonl) intentionally track unpatched upstream `reference/xitdb-zig`.)*

---

## Design Constraints for Every Recommendation

`reference/xitdb-zig/src/lib.zig` (~5,300 lines) is remarkably clean: every persistent data structure, cursor, compactor, and storage backend fits in a single, self-contained file with clear invariants. Every suggestion in this guide adheres to four rules:

1. **Zero Wire-Format Changes:** All 63 shared benchmarks produce **byte-for-byte identical** databases (`0` footprint mismatches). Every proposed change preserves exact big-endian slot, node, header, and CRC-64/XZ trailer layouts.
2. **Preserve Public APIs & Abstractions:** Keep `Database(db_kind, HashInt)`, `Cursor(write_mode)`, `BTreeNode`, `SortedNode`, and `std.Io.Reader` / `std.Io.Writer` intact.
3. **No Code Explosion:** All 6 adjustments combined total **~140 net lines of Zig**—and in several places (such as `SortedMap` node search) *reduce* repetition by replacing four separate linear scan loops with two 12-line binary search helpers.
4. **Keep What Zig Already Wins:** On `#43 Compaction (Heterogeneous DAG + dedup)`, **Zig is 1.15x faster than Odin** (`110.1 ms` vs `126.6 ms`) because Zig's `std.AutoHashMap(u64, u64)` uses SIMD SwissTable metadata probing. All recommendations keep `Compactor`'s `AutoHashMap` architecture untouched.

---

## The 6 Practical Adjustments (Ranked by Impact-to-LOC Ratio)

| Guide | Target in `lib.zig` | Baseline Zig | Patched Zig | Measured Zig Speedup | Net Zig Delta | Key Change |
| :--- | :--- | ---: | ---: | :--- | ---: | :--- |
| [**01. Zero-Vtable `CoreMemory` I/O**](01_core_memory_zero_vtable_io.md) | [`CoreMemory`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027), [`takeInt`](../../reference/xitdb-zig/src/lib.zig#L5251-L5255) | `85–1,545 ns` | **`50–925 ns`** | **1.42x – 1.73x** across all in-memory reads & iterators | `~15 LOC` | Back `CoreMemory.Reader` with `std.Io.Reader.fixed(written)` instead of `.buffer = &.{}` so `takeInt` / `readSliceAll` run inline without 2 vtable calls per read. |
| [**02. B-Tree Batch Node I/O & Leaf Seek**](02_btree_node_batch_io_and_leaf_seek.md) | [`readBTreeNode`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991), [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) | `2,335–36,262 ns` | **`130–5,978 ns`** | **4.88x – 17.96x faster** (`#20–#27`) | `~35 LOC` | Decode/encode 16-slot B-Tree nodes via one stack `[274]u8` buffer (`0..node.num` instead of 18–34 `takeInt`/`writeInt` calls), and seek straight to the single 9-byte leaf slot in `readBTreeSlot` (**`17.96x`**). |
| [**03. Sorted B+Tree Binary Search & Select**](03_sorted_bptree_binary_search.md) | [`sortedGet`](../../reference/xitdb-zig/src/lib.zig#L2634-L2760), [`readSortedNode`](../../reference/xitdb-zig/src/lib.zig#L2481-L2528), [`sortedGetByIndex`](../../reference/xitdb-zig/src/lib.zig#L2661-L2680) | `3,280–5,966 ns` | **`169–1,532 ns`** | **3.34x – 19.41x faster** (`#28–#38`) | `~40 LOC` | Replace $O(B)$ linear scans with $O(\log_2 16)$ binary search ($\le 4$ key comparisons), drop `@splat(0)` in `compareKey`, batch-decode `SortedNode` (1 read vs 50 `takeInt`s), and seek directly in `sortedGetByIndex` (**`19.41x`**). |
| [**04. HAMT Single-Pass KV & Lazy Remove**](04_hamt_single_pass_kv_and_lazy_remove.md) | [`HashMap`](../../reference/xitdb-zig/src/lib.zig#L3835-L3930), [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1600-L1726), [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1728-L1811) | `973–2,816 ns` | **`361–485 ns`** | **2.70x – 5.81x faster** on remove (`#5`, `#9`, `#11`) | `~30 LOC` | Defer reading the 144-byte sibling block in `removeMapSlot` until unwind when a child actually collapses (**`5.81x`**), iteratively build shared-nibble chains (`1.36x`), and add single-pass `putKeyValue`. |
| [**05. Cursor Bytes, Streams & Nested Paths**](05_cursor_bytes_streams_and_paths.md) | [`Cursor.readBytesObject`](../../reference/xitdb-zig/src/lib.zig#L3289-L3340), [`Cursor.reader`](../../reference/xitdb-zig/src/lib.zig#L3366-L3409), [`writePath`](../../reference/xitdb-zig/src/lib.zig#L3149-L3185) | `28–1,548 ns` | **`5–530 ns`** | **2.85x – 5.67x faster** (`#48`, `#50`, `#53`, `#55`, `#56`) | `~15 LOC` | Drop redundant `seekTo` before `format_tag` (**`2.98x`**), return a zero-copy `.fixed(slice)` on `CoreMemory` in `Cursor.reader()` (**`5.67x`**, beating Odin at `5 ns` vs `6 ns`!), and accelerate 4-level paths (**`2.92x`**). |
| [**06. `CoreBufferedFile` Hot-Tail Cache & Compaction**](06_buffered_file_tail_cache_and_compaction.md) | [`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232), [`Compactor`](../../reference/xitdb-zig/src/lib.zig#L4508-L4913) | `18.6 µs` / `110.1 ms` | **`6.3 µs` / `84.1 ms`** | **2.95x** (`#59`), **1.92x** (`#41`), **1.51x Zig win vs Odin** (`#43`) | `~18 LOC` | Track `flushed_len: usize` in `CoreBufferedFile` so `flush()` retains the clean tail cache across commits (**`2.95x`**), and batch-write `Compactor` nodes (**`84.1 ms` vs Odin's `126.6 ms`**). |

---

## Empirical Validation (Applied to `reference/xitdb-zig/src/lib.zig`)

All 6 adjustments were applied directly to [`reference/xitdb-zig/src/lib.zig`](../../reference/xitdb-zig/src/lib.zig) and verified against:
1. **100% of upstream `xitdb-zig` unit & corruption tests** (`zig build test` — 11/11 test suites passing).
2. **All 63 `ReleaseFast` benchmarks** (`zig build bench -Doptimize=ReleaseFast -Dcpu=native -- --runs 5 --warmup 2`), with **0 byte-footprint mismatches** across every database workload.

Across all 63 benchmarks, the geometric-mean Zig speedup is **2.22x**, cutting the overall Zig-vs-Odin ratio from **5.12x down to 2.30x** (and expanding Zig's lead on `#43 Compaction (Heterogeneous DAG + dedup)` to **1.51x faster than Odin** and `#53 Stream: Cursor_Reader random seek + 64B read` to **1.22x faster than Odin**):

| # | Benchmark | Upstream Zig (`ns`) | Patched Zig (`ns`) | Measured Zig Speedup | Odin (`ns`) | Byte Footprint |
| ---: | :--- | ---: | ---: | :--- | ---: | :--- |
| 34 | `Sorted_Map (B+Tree) get_index select` | 3,280 | **169** | **19.41x faster** | 65 | Identical |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,335 | **130** | **17.96x faster** | 53 | Identical |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,481 | **297** | **8.35x faster** | 161 | Identical |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 3,953 | **529** | **7.47x faster** | 144 | `80.0 KB` |
| 30 | `Sorted_Map (B+Tree) rank query` | 4,205 | **605** | **6.95x faster** | 131 | Identical |
| 29 | `Sorted_Map (B+Tree) key lookup` | 4,242 | **661** | **6.42x faster** | 163 | Identical |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 36,262 | **5,978** | **6.07x faster** | 807 | Identical |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 5,966 | **1,021** | **5.84x faster** | 230 | Identical |
| 11 | `HAMT deep suffix-collision branch collapse` | 2,816 | **485** | **5.81x faster** | 211 | Identical |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 28.4 | **5.0** | **5.67x faster** *(beats Odin!)* | 6.1 | Identical |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 3,585 | **694** | **5.16x faster** | 349 | Identical |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 3,562 | **695** | **5.13x faster** | 258 | Identical |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 4,757 | **953** | **4.99x faster** | 362 | Identical |
| 20 | `Linked_Array_List (B-Tree) append` | 3,007 | **616** | **4.88x faster** | 231 | `45.3 KB` |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 4,265 | **1,109** | **3.85x faster** | 343 | `80.0 KB` |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 4,388 | **1,197** | **3.67x faster** | 401 | Identical |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 5,407 | **1,532** | **3.53x faster** | 466 | Identical |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 4,511 | **1,349** | **3.34x faster** | 388 | `115.4 KB` |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 3,525 | **1,129** | **3.12x faster** | 394 | Identical |
| 48 | `Bytes: External Bytes read_bytes_buf` | 38.8 | **13.0** | **2.98x faster** | 8.8 | Identical |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 56.6 | **19.0** | **2.98x faster** | 9.2 | Identical |
| 59 | `Backend: Core_Buffered_File commits` | 18,568 | **6,296** | **2.95x faster** | 4,579 | `391.0 KB` |
| 55 | `Path: 4-level nested cursor_write_path` | 1,548 | **530** | **2.92x faster** | 230 | Identical |
| 56 | `Path: 4-level nested cursor_read_path` | 1,293 | **453** | **2.85x faster** | 148 | Identical |
| 5 | `HAMT Hash_Map remove & branch shortening` | 973 | **361** | **2.70x faster** | 167 | Identical |
| 9 | `HAMT Counted_Hash_Map remove` | 1,019 | **379** | **2.69x faster** | 165 | Identical |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 7,594 | **3,957** | **1.92x faster** | 3,707 | `1.2 KB` |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 110,126 | **84,098** | **1.31x faster** *(1.51x vs Odin!)* | 126,618 | `23.4 KB` |

### Four Subtle Compilation & Test Details Caught by `src/test.zig`

Validating [`zig_optimizations.patch`](zig_optimizations.patch) against [`reference/xitdb-zig/src/test.zig`](../../reference/xitdb-zig/src/test.zig) surfaced four subtle requirements that are already incorporated into the code snippets across Guides 01–06:

1. **`CoreMemory.Reader.pos` is asserted directly in `src/test.zig#L154-L170`:** Keep `pos: u64 = 0` on `CoreMemory.Reader` and update `self.pos = offset;` inside `seekTo()` alongside updating `self.interface.buffer`, `self.interface.end`, and `self.interface.seek` ([Guide 01](01_core_memory_zero_vtable_io.md)).
2. **`comptime byteSizeOf(Slot)` for slice-to-array-pointer coercion:** Because `fn byteSizeOf(T: type) u16` in `lib.zig` returns a runtime `u16` unless evaluated in a `comptime` context, bind `const slot_len = comptime byteSizeOf(Slot);` before slicing `body[off..][0..slot_len]` so Zig knows the `*[9]u8` pointer length at compile time ([Guides 02–04](02_btree_node_batch_io_and_leaf_seek.md)).
3. **Full node block read for mid-node truncation detection:** In `readBTreeNode` and `readSortedNode`, call `readSliceAll(&body)` for the full fixed node size (`146B` / `274B` / `418B`) before looping `0..num` in memory so truncated-file corruption tests in `src/test.zig` still return `error.EndOfStream` ([Guides 02 & 03](02_btree_node_batch_io_and_leaf_seek.md)).
4. **Backward seeks in `Cursor.Reader.seekTo` (`src/test.zig#L1468`):** When `Cursor.reader()` returns a zero-copy `.fixed(slice)` over `CoreMemory`, check `const window_start = self.pos - self.interface.end;` in `Cursor.Reader.seekTo` so backward seeks (`try bar_reader.seekTo(0)`) stay inside the buffered window instead of resetting `self.interface.end = 0` ([Guide 05](05_cursor_bytes_streams_and_paths.md)).

---

## How the Optimizations Compound

Several of these adjustments reinforce one another without touching each other's code:

- Applying **Guide 01** (`CoreMemory` fixed-slice reader) immediately accelerates every collection (`ArrayList`, `HashMap`, `LinkedArrayList`, `SortedMap`, `Cursor.Reader`, `Compactor`, and `Database.init`) because `takeInt` stops doing two virtual calls per integer.
- Applying **Guides 02 & 03** (stack-buffered node serialization + leaf slot seek + binary search) also accelerates **disk-backed databases** (`CoreFile` and `CoreBufferedFile`), where collapsing 34–50 `writeInt` calls into a single `writeAll` turns 34–50 `pwritev` syscalls per B-Tree/B+Tree node into 1 syscall, and speeds up `Compactor` (`#41–#43`) as a free side effect.
