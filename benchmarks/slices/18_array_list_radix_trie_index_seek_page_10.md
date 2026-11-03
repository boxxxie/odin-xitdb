# #18. `Array_List (Radix Trie) index-seek page(10)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L886-L900`)](../bench_xitdb.odin#L886-L900) · [Zig Harness (`bench_xitdb.zig#L920-L933`)](../bench_xitdb.zig#L920-L933)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **347** | 349.4 ± 6.3 | 1.8% | 357.2 | 2,881,844 | - | **4.45x Odin** (`z = 40.3`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,545 | 1,562.6 ± 67.0 | 4.3% | 1,644.4 | 647,249 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Direct Slice-Backed `Core_Memory` Reads & Writes ([`xitdb/core.odin#L125-L192`](../../xitdb/core.odin#L125-L192), [`xitdb/hamt.odin#L345-L452`](../../xitdb/hamt.odin#L345-L452)):** Odin's `read_array_list_slot` and `read_array_list_slot_append` decode the 9-byte `Slot` directly from the in-memory `Core_Memory` buffer (`endian.unchecked_get_u64be`), whereas Zig's [`readArrayListSlot`](../../reference/xitdb-zig/src/lib.zig#L1856-L1904) instantiates `self.core.reader()` (a 256-byte buffered `std.Io.Reader`) and resets its stream window on every `seekTo`.
- **Stack-Allocated `Cursor_Iterator` Without Per-Step Vtable Seeks ([`xitdb/cursor.odin#L630-L810`](../../xitdb/cursor.odin#L630-L810)):** On `#16 Array_List iterator scan` (**13 ns vs 33 ns**) and `#18 index-seek page(10)` (**4.45x faster in Odin**), Odin reads the 144-byte `index_block` once per radix node into the iterator's stack frame and steps through the 16 slots in memory.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Use `std.Io.Reader.fixed` in `CoreMemory.reader()` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Pointing `std.Io.Reader` directly at `self.bytes.items[offset..]` eliminates the 256-byte `stream()` vtable copy on every `seekTo` + `takeInt` in `readArrayListSlot`.
- **Combine slot clear + value write in `readArrayListSlotAppend` ([`lib.zig#L1841-L1846`](../../reference/xitdb-zig/src/lib.zig#L1841-L1846)):** When `ArrayList.append` is followed immediately by `.write`, skip writing the temporary empty slot before `.write` overwrites the exact same 9 bytes.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L886-L900`](../bench_xitdb.odin#L886-L900))

```odin
 886 | 		t4 := time.now()
 887 | 		for i in 0 ..< n {
 888 | 			ait, _ := xitdb.array_list_iterator_from(rlist, i64(i))
 889 | 			for _ in 0 ..< 10 {
 890 | 				c_maybe, _ := xitdb.cursor_iterator_next(&ait)
 891 | 				if c_maybe == nil do break
 892 | 			}
 893 | 		}
 894 | 		elapsed_arr_seek := time.since(t4)
 895 | 
 896 | 		print_result(Bench_Result{
 897 | 			name    = "Array_List (Radix Trie) index-seek page(10)",
 898 | 			ops     = n,
 899 | 			elapsed = elapsed_arr_seek,
 900 | 		})
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
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |

### Reached Odin Procedures (`21` procedures across `5` files · `320` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_iterator_from` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L53-L55`](../../xitdb/collections.odin#L53-L55) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_iterator_array_list_from_index` | `depth 1` (from `array_list_iterator_from`) | 36 | [`xitdb/cursor.odin#L951-L986`](../../xitdb/cursor.odin#L951-L986) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 1` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1050-L1083`](../../xitdb/cursor.odin#L1050-L1083) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 2` (from `cursor_iterator_array_list_from_index`) | 4 | [`xitdb/cursor.odin#L58-L61`](../../xitdb/cursor.odin#L58-L61) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_iterator_array_list_from_index`, `_fill_slot_block_from`, `_init_btree_iter_level`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_iterator_array_list_from_index`, `_fill_slot_block_from`, `_init_btree_iter_level`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 2` (from `cursor_iterator_array_list_from_index`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/cursor.odin` | `_resolve_start_index` | `depth 2` (from `cursor_iterator_array_list_from_index`) | 11 | [`xitdb/cursor.odin#L767-L777`](../../xitdb/cursor.odin#L767-L777) |
| `xitdb/types.odin` | `radix_shift` | `depth 2` (from `cursor_iterator_array_list_from_index`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 2` (from `cursor_iterator_array_list_from_index`, `_init_iter_level`) | 21 | [`xitdb/cursor.odin#L648-L668`](../../xitdb/cursor.odin#L648-L668) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 2` (from `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L695-L721`](../../xitdb/cursor.odin#L695-L721) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L690-L693`](../../xitdb/cursor.odin#L690-L693) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 3` (from `cursor_resolved_cursor`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `_fill_slot_block_from`, `_init_btree_iter_level`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `_fill_slot_block_from`, `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `is_root` | `depth 4` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 4` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 5` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
