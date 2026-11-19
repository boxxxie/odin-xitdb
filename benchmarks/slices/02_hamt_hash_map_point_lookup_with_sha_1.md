# #2. `HAMT Hash_Map point lookup (with SHA-1)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) · [Odin Harness (`bench_xitdb.odin#L544-L560`)](../bench_xitdb.odin#L544-L560) · [Zig Harness (`bench_xitdb.zig#L539-L555`)](../bench_xitdb.zig#L539-L555)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **155** | 155.4 ± 1.5 | 1.0% | 157.4 | 6,451,613 | - | **1.94x Odin** (`z = 20.9`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 300 | 297.0 ± 15.0 | 5.1% | 314.2 | 3,333,333 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Pass Key+Value Path Traversal ([`xitdb/collections.odin#L409-L421`](../../xitdb/collections.odin#L409-L421), [`xitdb/database.odin#L1304-L1360`](../../xitdb/database.odin#L1304-L1360)):** Odin's `hash_map_put` dispatches a single path `[Hash_Map_Init, Hash_Map_Get{.KV_Pair}, Write_KV_Data]` and coalesces the `key_slot + val_slot` + external key payload write. In Zig ([`lib.zig#L3894-L3912`](../../reference/xitdb-zig/src/lib.zig#L3894-L3912)), inserting a key and value requires **two separate root-to-leaf traversals** (`m.putKey(h, ...)` followed by `m.put(h, ...)`), doubling HAMT descent, parent slot reloads, and CoW checks.
- **Iterative Multi-Level Collision Allocation ([`xitdb/hamt.odin#L170-L223`](../../xitdb/hamt.odin#L170-L223)):** When two hashes share multiple 4-bit nibbles (e.g. `#10 HAMT deep suffix-collision put (depth 10+)` — **6.58x faster in Odin**), Odin counts matching nibbles in registers and writes the chain + split block without re-reading the existing `KV_Pair` at each shared level. Zig's [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1705-L1720) writes a 144-byte zeroed block and recurses level-by-level.
- **Lazy Single-Slot Read on Removal ([`xitdb/hamt.odin#L242-L341`](../../xitdb/hamt.odin#L242-L341)):** In [`remove_map_slot`](../../xitdb/hamt.odin#L242-L341) (`#5`, `#9`, `#11` — **5.8x–13.4x faster in Odin**), Odin reads only the single 9-byte target `Slot` on the way down and only reads the 144-byte `index_block` on unwind if `key_offset > 0` and the child collapsed to `.None` or `.KV_Pair`. Zig's [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774) zero-fills and reads/validates all 16 slots (`144 bytes`) at every level before recursing—even at `key_offset == 0` where the root block never collapses.
- **Zero-Vtable `Core_Memory` + Hardware x86 SHA-NI ([`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360), [`xitdb/types.odin#L114-L530`](../../xitdb/types.odin#L114-L530)):** Odin slices `Core_Memory.buf` directly (avoiding `CoreMemory.Reader`'s `.buffer = &.{}` double-vtable dispatch on `takeInt`) and uses hardware SHA-NI when hashing keys.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Lazy sibling block read in `removeMapSlot` ([`lib.zig#L1736-L1774`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774)):** Read only the single 9-byte `Slot` at `index_pos + 9 * i` before recursing; if `key_offset == 0` or `next_slot.tag == .index`, write `next_slot` directly without reading or validating the other 15 sibling slots.
- **Add single-pass `putKeyValue` (`~20 lines` in `HashMap` & `readSlotPointer`):** Allow `HashMap(.read_write)` and `CountedHashMap(.read_write)` to write both `key_slot` and `value_slot` in one `readMapSlot(..., .kv_pair, ...)` descent (and one atomic transaction on root maps) instead of calling `putKey` + `put` separately.
- **Back `CoreMemory.reader()` with `std.Io.Reader.fixed` ([`lib.zig#L4993-L5003`](../../reference/xitdb-zig/src/lib.zig#L4993-L5003)):** Refreshing `.fixed(self.parent.buffer.written())` in `seekTo()` eliminates two indirect vtable calls on every `takeInt`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L544-L560`](../bench_xitdb.odin#L544-L560))

```odin
 544 | 	// 1b. Point lookup N keys from Moment 0 (with SHA-1 key hashing vs pre-computed digest)
 545 | 	m0_cur, _ := xitdb.array_list_get_cursor(history, 0)
 546 | 	m0, _ := xitdb.read_hash_map_init(m0_cur.?)
 547 | 
 548 | 	t1 := time.now()
 549 | 	for k, idx in keys {
 550 | 		vc, _ := xitdb.hash_map_get_cursor(m0, k)
 551 | 		v, _ := xitdb.cursor_read_uint(vc.?)
 552 | 		assert(v == u64(idx))
 553 | 	}
 554 | 	elapsed_get := time.since(t1)
 555 | 
 556 | 	print_result(Bench_Result{
 557 | 		name    = "HAMT Hash_Map point lookup (with SHA-1)",
 558 | 		ops     = n,
 559 | 		elapsed = elapsed_get,
 560 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L539-L555`](../bench_xitdb.zig#L539-L555))

```zig
 539 |     // 1b. Point lookup N keys from Moment 0 (with SHA-1 key hashing vs pre-computed digest)
 540 |     const m0_cur = (try history.getCursor(0)).?;
 541 |     const m0 = try DB.HashMap(.read_only).init(m0_cur);
 542 | 
 543 |     const t1 = std.Io.Clock.awake.now(io);
 544 |     for (keys, 0..) |k, idx| {
 545 |         const vc = (try m0.getCursor(hashSha1(k))).?;
 546 |         const v = try vc.readUint();
 547 |         std.debug.assert(v == @as(u64, @intCast(idx)));
 548 |     }
 549 |     const elapsed_get = t1.untilNow(io, .awake).nanoseconds;
 550 | 
 551 |     try printResult(stdout, .{
 552 |         .name = "HAMT Hash_Map point lookup (with SHA-1)",
 553 |         .ops = n,
 554 |         .elapsed_ns = elapsed_get,
 555 |     });
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

### Reached Odin Procedures (`46` procedures across `6` files · `959` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Hash_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_hash_map_init` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L330-L334`](../../xitdb/collections.odin#L330-L334) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L198-L207`](../../xitdb/cursor.odin#L198-L207) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `array_list_get_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L67-L78`](../../xitdb/cursor.odin#L67-L78) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `read_hash_map_init`, `cursor_read_uint`, `cursor_read_path`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 1` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L304-L306`](../../xitdb/collections.odin#L304-L306) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `read_map_slot`, `core_read_slot_at`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 4` (from `_exec_path_part`, `core_read_slot_raw_at`, `core_read_i64_at`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1091-L1099`](../../xitdb/types.odin#L1091-L1099) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1475-L1480`](../../xitdb/types.odin#L1475-L1480) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`) | 67 | [`xitdb/hamt.odin#L382-L448`](../../xitdb/hamt.odin#L382-L448) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 3` (from `database_read_root_header`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 3` (from `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/core.odin` | `core_length` | `depth 3` (from `database_read_root_header`, `read_array_list_slot`, `read_map_slot`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `read_map_slot`, `kv_pair_read_buf_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/core.odin` | `core_read_at` | `depth 5` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 5` (from `read_array_list_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `read_array_list_slot`, `read_map_slot`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `tag_validate` | `depth 5` (from `read_map_slot`, `database_read_root_trailer`, `core_read_slot_at`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/core.odin` | `_overlay_length` | `depth 4` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 4` (from `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 6` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 6` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
