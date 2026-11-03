# #3. `HAMT Hash_Map lookup (pre-hashed digest)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) · [Odin Harness (`bench_xitdb.odin#L516-L533`)](../bench_xitdb.odin#L516-L533) · [Zig Harness (`bench_xitdb.zig#L557-L574`)](../bench_xitdb.zig#L557-L574)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **60** | 77.4 ± 27.4 | 35.4% | 112.19999999999999 | 16,666,667 | - | **3.18x Odin** (`z = 9.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 191 | 191.0 ± 1.9 | 1.0% | 193.4 | 5,235,602 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L516-L533`](../bench_xitdb.odin#L516-L533))

```odin
 516 | 	digests := make([][]u8, n, context.temp_allocator)
 517 | 	for k, idx in keys {
 518 | 		digests[idx] = xitdb.database_digest_string(&db, k, context.temp_allocator)
 519 | 	}
 520 | 
 521 | 	t1_pre := time.now()
 522 | 	for d, idx in digests {
 523 | 		vc, _ := xitdb.hash_map_get_cursor_by_hash(m0, d)
 524 | 		v, _ := xitdb.cursor_read_uint(vc.?)
 525 | 		assert(v == u64(idx))
 526 | 	}
 527 | 	elapsed_get_pre := time.since(t1_pre)
 528 | 
 529 | 	print_result(Bench_Result{
 530 | 		name    = "HAMT Hash_Map lookup (pre-hashed digest)",
 531 | 		ops     = n,
 532 | 		elapsed = elapsed_get_pre,
 533 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L557-L574`](../bench_xitdb.zig#L557-L574))

```zig
 557 |     const digests = try temp.alloc(HashInt, n);
 558 |     for (keys, 0..) |k, idx| {
 559 |         digests[idx] = hashSha1(k);
 560 |     }
 561 | 
 562 |     const t1_pre = std.Io.Clock.awake.now(io);
 563 |     for (digests, 0..) |d, idx| {
 564 |         const vc = (try m0.getCursor(d)).?;
 565 |         const v = try vc.readUint();
 566 |         std.debug.assert(v == @as(u64, @intCast(idx)));
 567 |     }
 568 |     const elapsed_get_pre = t1_pre.untilNow(io, .awake).nanoseconds;
 569 | 
 570 |     try printResult(stdout, .{
 571 |         .name = "HAMT Hash_Map lookup (pre-hashed digest)",
 572 |         .ops = n,
 573 |         .elapsed_ns = elapsed_get_pre,
 574 |     });
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

### Reached Odin Procedures (`33` procedures across `6` files · `704` LOC) (Active `_exec_path_part` arms: `Hash_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/database.odin` | `database_digest_string` | **Entry Point** (`depth 0`) | 3 | [`xitdb/database.odin#L255-L257`](../../xitdb/database.odin#L255-L257) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/database.odin` | `database_digest` | `depth 1` (from `database_digest_string`) | 7 | [`xitdb/database.odin#L247-L253`](../../xitdb/database.odin#L247-L253) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `cursor_read_uint`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `read_map_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/core.odin` | `core_read_exact` | `depth 3` (from `database_read_root_header`, `core_read_slot_raw`, `kv_pair_read_buf`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `read_map_slot`, `kv_pair_read_buf`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/core.odin` | `core_length` | `depth 5` (from `read_map_slot`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `read_map_slot`, `encode_kv_pair`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/core.odin` | `core_read` | `depth 4` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
