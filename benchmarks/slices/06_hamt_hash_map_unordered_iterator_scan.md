# #6. `HAMT Hash_Map unordered iterator scan` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) · [Odin Harness (`bench_xitdb.odin#L596-L612`)](../bench_xitdb.odin#L596-L612) · [Zig Harness (`bench_xitdb.zig#L632-L646`)](../bench_xitdb.zig#L632-L646)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **36** | 36.2 ± 0.4 | 1.2% | 36.8 | 27,777,778 | - | **3.92x Odin** (`z = 88.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 141 | 139.8 ± 2.6 | 1.9% | 142.0 | 7,092,199 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Pass Key+Value Path Traversal ([`xitdb/collections.odin#L409-L421`](../../xitdb/collections.odin#L409-L421), [`xitdb/database.odin#L1304-L1360`](../../xitdb/database.odin#L1304-L1360)):** Odin's `hash_map_put` dispatches a single path `[Hash_Map_Init, Hash_Map_Get{.KV_Pair}, Write_KV_Data]` and coalesces the `key_slot + val_slot` + external key payload write. In Zig ([`lib.zig#L3894-L3912`](../../reference/xitdb-zig/src/lib.zig#L3894-L3912)), inserting a key and value requires **two separate root-to-leaf traversals** (`m.putKey(h, ...)` followed by `m.put(h, ...)`), doubling HAMT descent, parent slot reloads, and CoW checks.
- **Iterative Multi-Level Collision Allocation ([`xitdb/hamt.odin#L170-L223`](../../xitdb/hamt.odin#L170-L223)):** When two hashes share multiple 4-bit nibbles (e.g. `#10 HAMT deep suffix-collision put (depth 10+)` — **6.58x faster in Odin**), Odin counts matching nibbles in registers and writes the chain + split block without re-reading the existing `KV_Pair` at each shared level. Zig's [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1705-L1720) writes a 144-byte zeroed block and recurses level-by-level.
- **Lazy Single-Slot Read on Removal ([`xitdb/hamt.odin#L242-L341`](../../xitdb/hamt.odin#L242-L341)):** In [`remove_map_slot`](../../xitdb/hamt.odin#L242-L341) (`#5`, `#9`, `#11` — **5.8x–13.4x faster in Odin**), Odin reads only the single 9-byte target `Slot` on the way down and only reads the 144-byte `index_block` on unwind if `key_offset > 0` and the child collapsed to `.None` or `.KV_Pair`. Zig's [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774) zero-fills and reads/validates all 16 slots (`144 bytes`) at every level before recursing—even at `key_offset == 0` where the root block never collapses.
- **Zero-Vtable `Core_Memory` + Hardware x86 SHA-NI ([`xitdb/core.odin#L326-L340`](../../xitdb/core.odin#L326-L340), [`xitdb/types.odin#L114-L530`](../../xitdb/types.odin#L114-L530)):** Odin slices `Core_Memory.buf` directly (avoiding `CoreMemory.Reader`'s `.buffer = &.{}` double-vtable dispatch on `takeInt`) and uses hardware SHA-NI when hashing keys.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Lazy sibling block read in `removeMapSlot` ([`lib.zig#L1736-L1774`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774)):** Read only the single 9-byte `Slot` at `index_pos + 9 * i` before recursing; if `key_offset == 0` or `next_slot.tag == .index`, write `next_slot` directly without reading or validating the other 15 sibling slots.
- **Add single-pass `putKeyValue` (`~20 lines` in `HashMap` & `readSlotPointer`):** Allow `HashMap(.read_write)` and `CountedHashMap(.read_write)` to write both `key_slot` and `value_slot` in one `readMapSlot(..., .kv_pair, ...)` descent (and one atomic transaction on root maps) instead of calling `putKey` + `put` separately.
- **Back `CoreMemory.reader()` with `std.Io.Reader.fixed` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Refreshing `.fixed(self.parent.buffer.written())` in `seekTo()` eliminates two indirect vtable calls on every `takeInt`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L596-L612`](../bench_xitdb.odin#L596-L612))

```odin
 596 | 	// 1e. HAMT unordered full-tree iterator scan
 597 | 	t4 := time.now()
 598 | 	hit, _ := xitdb.hash_map_iterator(m0)
 599 | 	hcnt := 0
 600 | 	for {
 601 | 		c_maybe, _ := xitdb.cursor_iterator_next(&hit)
 602 | 		if c_maybe == nil do break
 603 | 		hcnt += 1
 604 | 	}
 605 | 	assert(hcnt == n)
 606 | 	elapsed_hiter := time.since(t4)
 607 | 
 608 | 	print_result(Bench_Result{
 609 | 		name    = "HAMT Hash_Map unordered iterator scan",
 610 | 		ops     = n,
 611 | 		elapsed = elapsed_hiter,
 612 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L632-L646`](../bench_xitdb.zig#L632-L646))

```zig
 632 |     // 1e. HAMT unordered full-tree iterator scan
 633 |     const t4 = std.Io.Clock.awake.now(io);
 634 |     var hit = try m0.iterator();
 635 |     var hcnt: usize = 0;
 636 |     while (try hit.next()) |_| {
 637 |         hcnt += 1;
 638 |     }
 639 |     std.debug.assert(hcnt == n);
 640 |     const elapsed_hiter = t4.untilNow(io, .awake).nanoseconds;
 641 | 
 642 |     try printResult(stdout, .{
 643 |         .name = "HAMT Hash_Map unordered iterator scan",
 644 |         .ops = n,
 645 |         .elapsed_ns = elapsed_hiter,
 646 |     });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `HashMap` | 96 | Typed `HashMap(.read_only/.read_write)` wrapper (`put`, `putKey`, `getCursor`, `remove`) | [`lib.zig#L3835-L3930`](../../reference/xitdb-zig/src/lib.zig#L3835-L3930) |
| `CountedHashMap` | 73 | Typed `CountedHashMap` wrapper with 8-byte count header | [`lib.zig#L3932-L4004`](../../reference/xitdb-zig/src/lib.zig#L3932-L4004) |
| `CountedHashSet` | 53 | Typed `CountedHashSet` wrapper | [`lib.zig#L4071-L4123`](../../reference/xitdb-zig/src/lib.zig#L4071-L4123) |
| `readSlotPointer.hash_map` | 128 | `PathPart` switch arms: `.hash_map_init`, `.hash_map_get`, `.hash_map_remove` | [`lib.zig#L1271-L1398`](../../reference/xitdb-zig/src/lib.zig#L1271-L1398) |
| `readMapSlot` | 127 | 16-way HAMT recursive slot lookup, insertion, and hash-collision split | [`lib.zig#L1600-L1726`](../../reference/xitdb-zig/src/lib.zig#L1600-L1726) |
| `removeMapSlot` | 84 | 16-way HAMT recursive slot removal and singleton branch collapse | [`lib.zig#L1728-L1811`](../../reference/xitdb-zig/src/lib.zig#L1728-L1811) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |

### Reached Odin Procedures (`20` procedures across `5` files · `314` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `hash_map_iterator` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L276-L278`](../../xitdb/collections.odin#L276-L278) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1069-L1090`](../../xitdb/cursor.odin#L1069-L1090) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 1` (from `hash_map_iterator`) | 43 | [`xitdb/cursor.odin#L713-L755`](../../xitdb/cursor.odin#L713-L755) |
| `xitdb/cursor.odin` | `_iterator_next_internal` | `depth 1` (from `cursor_iterator_next`) | 34 | [`xitdb/cursor.odin#L1034-L1067`](../../xitdb/cursor.odin#L1034-L1067) |
| `xitdb/cursor.odin` | `cursor_resolved_cursor` | `depth 2` (from `cursor_iterator`) | 4 | [`xitdb/cursor.odin#L59-L62`](../../xitdb/cursor.odin#L59-L62) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_iterator`, `_init_btree_iter_level`, `_fill_slot_block_from`) | 17 | [`xitdb/core.odin#L175-L191`](../../xitdb/core.odin#L175-L191) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_iterator`, `_init_btree_iter_level`, `_fill_slot_block_from`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 2` (from `cursor_iterator`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/cursor.odin` | `_init_iter_level` | `depth 2` (from `cursor_iterator`, `_iterator_next_internal`) | 4 | [`xitdb/cursor.odin#L692-L695`](../../xitdb/cursor.odin#L692-L695) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `cursor_iterator`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/cursor.odin` | `_init_btree_iter_level` | `depth 2` (from `cursor_iterator`, `_iterator_next_internal`) | 15 | [`xitdb/cursor.odin#L697-L711`](../../xitdb/cursor.odin#L697-L711) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `_iterator_next_internal`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 3` (from `cursor_resolved_cursor`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L281-L323`](../../xitdb/core.odin#L281-L323) |
| `xitdb/cursor.odin` | `_fill_slot_block_from` | `depth 3` (from `_init_iter_level`, `_init_btree_iter_level`) | 21 | [`xitdb/cursor.odin#L670-L690`](../../xitdb/cursor.odin#L670-L690) |
| `xitdb/database.odin` | `is_root` | `depth 4` (from `cursor_resolved`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 4` (from `cursor_resolved`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `_fill_slot_block_from`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `_fill_slot_block_from`, `database_read_root_header`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 5` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
