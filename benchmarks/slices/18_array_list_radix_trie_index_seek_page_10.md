# #18. `Array_List (Radix Trie) index-seek page(10)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path**](../zig-guide/01_core_memory_zero_vtable_io.md) · [Odin Harness (`bench_xitdb.odin#L1118-L1134`)](../bench_xitdb.odin#L1118-L1134) · [Zig Harness (`bench_xitdb.zig#L920-L933`)](../bench_xitdb.zig#L920-L933)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **576** | 575.8 ± 2.6 | 0.4% | 578.6 | 1,736,111 | - | **2.91x Odin** (`z = 37.7`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,679 | 1,690.2 ± 66.0 | 3.9% | 1,776.4 | 595,593 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path**](../zig-guide/01_core_memory_zero_vtable_io.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Zero-Vtable `Core_Memory` Slice Reads ([`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360), [`xitdb/hamt.odin#L345-L452`](../../xitdb/hamt.odin#L345-L452)):** Odin's `read_array_list_slot` decodes 9-byte `Slot`s directly from `Core_Memory.buf`, whereas Zig's [`CoreMemory.reader()`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003) initializes `std.Io.Reader` with `.buffer = &.{}` (empty slice). Because `.buffer` is empty, every `takeInt` in `readArrayListSlot` misses `std.Io.Reader`'s inline fast path and dispatches through `vtable.readVec` → `CoreMemory.Reader.stream` → `Writer.fixed.drain` (two virtual calls per integer).
- **Stack-Allocated `Cursor_Iterator` ([`xitdb/cursor.odin#L655-L1096`](../../xitdb/cursor.odin#L655-L1096)):** On `#16 Array_List iterator scan` (**12 ns vs 33 ns**) and `#18 index-seek page(10)` (**4.45x faster in Odin**), Odin decodes each 144-byte `index_block` directly from memory without per-slot `std.Io` vtable calls.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Use `std.Io.Reader.fixed` in `CoreMemory.reader()` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Setting `self.interface = .fixed(self.parent.buffer.written())` (refreshed in `seekTo()`) lets `takeInt` and `readSliceAll` execute inline with zero vtable calls (`-12 net LOC`, removing `CoreMemory.Reader.stream`).

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1118-L1134`](../bench_xitdb.odin#L1118-L1134))

```odin
1118 | 		sp4 := span_begin()
1119 | 		for i in 0 ..< n {
1120 | 			ait, _ := xitdb.array_list_iterator_from(rlist, i64(i))
1121 | 			for _ in 0 ..< 10 {
1122 | 				c_maybe, _ := xitdb.cursor_iterator_next(&ait)
1123 | 				if c_maybe == nil do break
1124 | 			}
1125 | 		}
1126 | 		elapsed_arr_seek, hw4, has_hw4 := span_end(sp4)
1127 | 
1128 | 		print_result(Bench_Result{
1129 | 			name         = "Array_List (Radix Trie) index-seek page(10)",
1130 | 			ops          = n,
1131 | 			elapsed      = elapsed_arr_seek,
1132 | 			counters     = hw4,
1133 | 			has_counters = has_hw4,
1134 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L920-L933`](../bench_xitdb.zig#L920-L933))

```zig
 920 |         const t4 = std.Io.Clock.awake.now(io);
 921 |         for (0..n) |i| {
 922 |             var ait = try rlist.iteratorFrom(@intCast(i));
 923 |             for (0..10) |_| {
 924 |                 if ((try ait.next()) == null) break;
 925 |             }
 926 |         }
 927 |         const elapsed_arr_seek = t4.untilNow(io, .awake).nanoseconds;
 928 | 
 929 |         try printResult(stdout, .{
 930 |             .name = "Array_List (Radix Trie) index-seek page(10)",
 931 |             .ops = n,
 932 |             .elapsed_ns = elapsed_arr_seek,
 933 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `ArrayList` | 90 | Typed 16-way Radix Trie `ArrayList` wrapper (`append`, `getCursor`, `put`, `slice`) | [`lib.zig#L4299-L4388`](../../reference/xitdb-zig/src/lib.zig#L4299-L4388) |
| `readSlotPointer.array_list` | 122 | `PathPart` switch arms: `.array_list_init`, `.array_list_get`, `.array_list_append`, `.array_list_slice` | [`lib.zig#L927-L1048`](../../reference/xitdb-zig/src/lib.zig#L927-L1048) |
| `readArrayListSlotAppend` | 35 | 16-way Radix Trie tail append and root overflow growth | [`lib.zig#L1820-L1854`](../../reference/xitdb-zig/src/lib.zig#L1820-L1854) |
| `readArrayListSlot` | 49 | 16-way Radix Trie O(log16 N) slot descent and CoW path copy | [`lib.zig#L1856-L1904`](../../reference/xitdb-zig/src/lib.zig#L1856-L1904) |
| `readArrayListSlice` | 37 | 16-way Radix Trie truncation and root depth collapse | [`lib.zig#L1906-L1942`](../../reference/xitdb-zig/src/lib.zig#L1906-L1942) |
| `Cursor` | 864 | Read/Write `Cursor`, `Cursor.Reader`, `Cursor.Writer`, and `Cursor.Iterator` | [`lib.zig#L2956-L3819`](../../reference/xitdb-zig/src/lib.zig#L2956-L3819) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |

### Reached Odin Procedures (`45` procedures across `6` files · `981` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_iterator_from` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L53-L55`](../../xitdb/collections.odin#L53-L55) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 40 | [`xitdb/cursor.odin#L1791-L1830`](../../xitdb/cursor.odin#L1791-L1830) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index` | `depth 1` (from `array_list_iterator_from`) | 4 | [`xitdb/cursor.odin#L1441-L1444`](../../xitdb/cursor.odin#L1441-L1444) |
| `xitdb/cursor.odin` | `_iterator_step_internal` | `depth 1` (from `cursor_iterator_next`) | 93 | [`xitdb/cursor.odin#L1697-L1789`](../../xitdb/cursor.odin#L1697-L1789) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index_init` | `depth 2` (from `cursor_iterator_array_list_from_index`) | 30 | [`xitdb/cursor.odin#L1410-L1439`](../../xitdb/cursor.odin#L1410-L1439) |
| `xitdb/cursor.odin` | `_read_btree_iter_level` | `depth 2` (from `_iterator_step_internal`) | 55 | [`xitdb/cursor.odin#L852-L906`](../../xitdb/cursor.odin#L852-L906) |
| `xitdb/cursor.odin` | `_init_iter_level_rev` | `depth 2` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L840-L843`](../../xitdb/cursor.odin#L840-L843) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `_iterator_step_internal`) | 4 | [`xitdb/cursor.odin#L835-L838`](../../xitdb/cursor.odin#L835-L838) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_step_internal`, `_init_array_list_stack`, `read_btree_node`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/cursor.odin` | `_reset_cursor_iterator` | `depth 3` (from `cursor_iterator_array_list_from_index_init`) | 8 | [`xitdb/cursor.odin#L1023-L1030`](../../xitdb/cursor.odin#L1023-L1030) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 3` (from `cursor_iterator_array_list_from_index_init`) | 4 | [`xitdb/cursor.odin#L57-L60`](../../xitdb/cursor.odin#L57-L60) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `cursor_iterator_array_list_from_index_init`, `_fill_slot_block_rev`, `_fill_slot_block_from`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 3` (from `cursor_iterator_array_list_from_index_init`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 3` (from `cursor_iterator_array_list_from_index_init`) | 11 | [`xitdb/cursor.odin#L1130-L1140`](../../xitdb/cursor.odin#L1130-L1140) |
| `xitdb/cursor.odin` | `_init_array_list_stack` | `depth 3` (from `cursor_iterator_array_list_from_index_init`) | 38 | [`xitdb/cursor.odin#L941-L978`](../../xitdb/cursor.odin#L941-L978) |
| `xitdb/types.odin` | `_checked_add_i64` | `depth 3` (from `_read_btree_iter_level`, `read_btree_node`, `read_sorted_node`) | 7 | [`xitdb/types.odin#L1498-L1504`](../../xitdb/types.odin#L1498-L1504) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 3` (from `_read_btree_iter_level`) | 66 | [`xitdb/btree.odin#L8-L73`](../../xitdb/btree.odin#L8-L73) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 3` (from `_read_btree_iter_level`) | 10 | [`xitdb/types.odin#L1308-L1317`](../../xitdb/types.odin#L1308-L1317) |
| `xitdb/btree.odin` | `read_sorted_node` | `depth 3` (from `_read_btree_iter_level`) | 83 | [`xitdb/btree.odin#L1262-L1344`](../../xitdb/btree.odin#L1262-L1344) |
| `xitdb/types.odin` | `sorted_node_subtree_count` | `depth 3` (from `_read_btree_iter_level`) | 10 | [`xitdb/types.odin#L1358-L1367`](../../xitdb/types.odin#L1358-L1367) |
| `xitdb/cursor.odin` | `_fill_slot_block_rev` | `depth 3` (from `_init_iter_level_rev`, `_init_array_list_stack`) | 38 | [`xitdb/cursor.odin#L796-L833`](../../xitdb/cursor.odin#L796-L833) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_iter_level`, `_init_array_list_stack`) | 41 | [`xitdb/cursor.odin#L754-L794`](../../xitdb/cursor.odin#L754-L794) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 4` (from `cursor_resolved_cursor`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`, `core_read_short_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_init_array_list_stack`) | 6 | [`xitdb/types.odin#L1484-L1489`](../../xitdb/types.odin#L1484-L1489) |
| `xitdb/core.odin` | `core_read_block_at` | `depth 4` (from `read_btree_node`, `read_sorted_node`) | 24 | [`xitdb/core.odin#L808-L831`](../../xitdb/core.odin#L808-L831) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 4` (from `read_btree_node`, `read_sorted_node`, `_fill_slot_block_rev`) | 5 | [`xitdb/types.odin#L912-L916`](../../xitdb/types.odin#L912-L916) |
| `xitdb/types.odin` | `is_sorted_entry_tag` | `depth 4` (from `read_sorted_node`) | 8 | [`xitdb/types.odin#L1392-L1399`](../../xitdb/types.odin#L1392-L1399) |
| `xitdb/core.odin` | `core_slice_at` | `depth 4` (from `_fill_slot_block_rev`, `_fill_slot_block_from`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/database.odin` | `is_root` | `depth 5` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 5` (from `cursor_resolved`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/core.odin` | `core_read_short_at` | `depth 5` (from `core_read_block_at`) | 46 | [`xitdb/core.odin#L759-L804`](../../xitdb/core.odin#L759-L804) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 5` (from `slot_from_slice`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `tag_validate` | `depth 5` (from `slot_from_slice`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 5` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 6` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 6` (from `database_read_root_header`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 6` (from `database_read_root_header`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 6` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/core.odin` | `_overlay_length` | `depth 6` (from `_overlay_read_at`, `_overlay_slice_at`, `core_length`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 7` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 7` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 8` (from `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 8` (from `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
