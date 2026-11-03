# #16. `Array_List (Radix Trie) iterator scan` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path**](../zig-guide/01_core_memory_zero_vtable_io.md) · [Odin Harness (`bench_xitdb.odin#L847-L864`)](../bench_xitdb.odin#L847-L864) · [Zig Harness (`bench_xitdb.zig#L882-L896`)](../bench_xitdb.zig#L882-L896)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **13** | 12.6 ± 0.5 | 4.3% | 13.0 | 76,923,077 | - | **2.54x Odin** (`z = 9.5`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 33 | 35.6 ± 5.4 | 15.1% | 43.0 | 30,303,030 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 01: Zero-Vtable CoreMemory Reads & takeInt Fast Path**](../zig-guide/01_core_memory_zero_vtable_io.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Zero-Vtable `Core_Memory` Slice Reads ([`xitdb/core.odin#L326-L340`](../../xitdb/core.odin#L326-L340), [`xitdb/hamt.odin#L345-L452`](../../xitdb/hamt.odin#L345-L452)):** Odin's `read_array_list_slot` decodes 9-byte `Slot`s directly from `Core_Memory.buf`, whereas Zig's [`CoreMemory.reader()`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003) initializes `std.Io.Reader` with `.buffer = &.{}` (empty slice). Because `.buffer` is empty, every `takeInt` in `readArrayListSlot` misses `std.Io.Reader`'s inline fast path and dispatches through `vtable.readVec` → `CoreMemory.Reader.stream` → `Writer.fixed.drain` (two virtual calls per integer).
- **Stack-Allocated `Cursor_Iterator` ([`xitdb/cursor.odin#L633-L1028`](../../xitdb/cursor.odin#L633-L1028)):** On `#16 Array_List iterator scan` (**13 ns vs 33 ns**) and `#18 index-seek page(10)` (**4.45x faster in Odin**), Odin decodes each 144-byte `index_block` directly from memory without per-slot `std.Io` vtable calls.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Use `std.Io.Reader.fixed` in `CoreMemory.reader()` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Setting `self.interface = .fixed(self.parent.buffer.written())` (refreshed in `seekTo()`) lets `takeInt` and `readSliceAll` execute inline with zero vtable calls (`-12 net LOC`, removing `CoreMemory.Reader.stream`).

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L847-L864`](../bench_xitdb.odin#L847-L864))

```odin
 847 | 		t2 := time.now()
 848 | 		it, _ := xitdb.array_list_iterator(rlist)
 849 | 		cnt := 0
 850 | 		for {
 851 | 			c_maybe, _ := xitdb.cursor_iterator_next(&it)
 852 | 			c, ok := c_maybe.?
 853 | 			if !ok do break
 854 | 			_, _ = xitdb.cursor_read_uint(c)
 855 | 			cnt += 1
 856 | 		}
 857 | 		assert(cnt == n)
 858 | 		elapsed_iter := time.since(t2)
 859 | 
 860 | 		print_result(Bench_Result{
 861 | 			name    = "Array_List (Radix Trie) iterator scan",
 862 | 			ops     = n,
 863 | 			elapsed = elapsed_iter,
 864 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L882-L896`](../bench_xitdb.zig#L882-L896))

```zig
 882 |         const t2 = std.Io.Clock.awake.now(io);
 883 |         var it = try rlist.iterator();
 884 |         var cnt: usize = 0;
 885 |         while (try it.next()) |c| {
 886 |             _ = try c.readUint();
 887 |             cnt += 1;
 888 |         }
 889 |         std.debug.assert(cnt == n);
 890 |         const elapsed_iter = t2.untilNow(io, .awake).nanoseconds;
 891 | 
 892 |         try printResult(stdout, .{
 893 |             .name = "Array_List (Radix Trie) iterator scan",
 894 |             .ops = n,
 895 |             .elapsed_ns = elapsed_iter,
 896 |         });
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

### Reached Odin Procedures (`21` procedures across `5` files · `329` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_iterator` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L49-L51`](../../xitdb/collections.odin#L49-L51) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 1` (from `array_list_iterator`) | 43 | [`xitdb/cursor.odin#L723-L765`](../../xitdb/cursor.odin#L723-L765) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 1` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1050-L1083`](../../xitdb/cursor.odin#L1050-L1083) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_uint`, `cursor_resolved_cursor`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 2` (from `cursor_iterator`) | 4 | [`xitdb/cursor.odin#L58-L61`](../../xitdb/cursor.odin#L58-L61) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_iterator`, `_init_btree_iter_level`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_iterator`, `_init_btree_iter_level`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 2` (from `cursor_iterator`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L690-L693`](../../xitdb/cursor.odin#L690-L693) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `cursor_iterator`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 2` (from `cursor_iterator`, `_iterator_next_internal`) | 27 | [`xitdb/cursor.odin#L695-L721`](../../xitdb/cursor.odin#L695-L721) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_iter_level`) | 21 | [`xitdb/cursor.odin#L648-L668`](../../xitdb/cursor.odin#L648-L668) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 3` (from `_init_btree_iter_level`, `_fill_slot_block_from`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `_fill_slot_block_from`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
