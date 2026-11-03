# #2. `HAMT Hash_Map point lookup (with SHA-1)` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L498-L514`)](../bench_xitdb.odin#L498-L514) · [Zig Harness (`bench_xitdb.zig#L539-L555`)](../bench_xitdb.zig#L539-L555)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **95** | 109.0 ± 31.4 | 28.8% | 151.79999999999998 | 10,526,316 | - | **2.94x Odin** (`z = 12.1`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 279 | 280.0 ± 2.3 | 0.8% | 282.8 | 3,584,229 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Pass Key+Value Path Traversal ([`xitdb/collections.odin#L409-L421`](../../xitdb/collections.odin#L409-L421), [`xitdb/database.odin#L1304-L1360`](../../xitdb/database.odin#L1304-L1360)):** Odin's `hash_map_put` dispatches a single path `[Hash_Map_Init, Hash_Map_Get{.KV_Pair}, Write_KV_Data]` and coalesces the 18-byte `key_slot + val_slot` + external key payload into one stack-buffered `core_write_all` call. In Zig ([`lib.zig#L3856-L3885`](../../reference/xitdb-zig/src/lib.zig#L3856-L3885)), inserting a key and value requires **two separate root-to-leaf traversals** (`m.putKey(h, ...)` followed by `m.put(h, ...)`), doubling HAMT descent, root header reads, and CoW checks.
- **Contiguous Multi-Level Collision Allocation ([`xitdb/hamt.odin#L140-L196`](../../xitdb/hamt.odin#L140-L196)):** When two hashes share multiple 4-bit nibbles (e.g. `#10 HAMT deep suffix-collision put (depth 10+)` — **6.58x faster in Odin**), Odin counts `common_levels` in memory and writes all `common_levels + 1` index blocks plus the new `KV_Pair` in **one contiguous `core_write_all`**. Zig's [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1705-L1720) writes a 144-byte zeroed block and recurses level-by-level, performing 2 seeks + 2 writes per collision depth.
- **Lazy Single-Slot Read on Removal ([`xitdb/hamt.odin#L242-L342`](../../xitdb/hamt.odin#L242-L342)):** In [`remove_map_slot`](../../xitdb/hamt.odin#L242-L342) (`#5`, `#9`, `#11` — **5.8x–13.4x faster in Odin**), Odin reads only the single 9-byte target `Slot` on the way down and only reads the 144-byte `index_block` on unwind if `key_offset > 0` and the child collapsed to `.None` or `.KV_Pair`. Zig's [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1728-L1811) eagerly reads and validates all 16 slots (`144 bytes`) at every level before recursing—even at `key_offset == 0` where the root block can never collapse.
- **Hardware x86 SHA-NI Acceleration ([`xitdb/types.odin#L114-L530`](../../xitdb/types.odin#L114-L530)):** Odin detects SHA-NI at runtime (`sha1_ni_available` / `sha256_ni_available`) and hashes keys directly into a stack `[32]u8` buffer without heap allocation.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Add `putKeyAndValue` / `.write_kv_data` (`~20 lines` in `HashMap` & `readSlotPointer`):** Allow `HashMap(.read_write)` to write both `key_slot` and `value_slot` in a single `readMapSlot(..., .kv_pair, ...)` descent instead of calling `putKey` + `put` separately. This immediately cuts HAMT write work in half while making caller code cleaner.
- **Defer 144-byte block read in `removeMapSlot` ([`lib.zig#L1736-L1774`](../../reference/xitdb-zig/src/lib.zig#L1736-L1774)):** Read only the single `Slot` at ` index_pos + 9 * i` before recursing; if `key_offset == 0` or `next_slot.tag == .index`, write `next_slot` directly without reading the other 15 sibling slots.
- **Zero-copy `CoreMemory.Reader` ([`lib.zig#L4920-L5004`](../../reference/xitdb-zig/src/lib.zig#L4920-L5004)):** Construct `std.Io.Reader.fixed(self.bytes.items)` over the backing slice instead of copying through a 256-byte intermediate vtable buffer on every `seekTo`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L498-L514`](../bench_xitdb.odin#L498-L514))

```odin
 498 | 	// 1b. Point lookup N keys from Moment 0 (with SHA-1 key hashing vs pre-computed digest)
 499 | 	m0_cur, _ := xitdb.array_list_get_cursor(history, 0)
 500 | 	m0, _ := xitdb.read_hash_map_init(m0_cur.?)
 501 | 
 502 | 	t1 := time.now()
 503 | 	for k, idx in keys {
 504 | 		vc, _ := xitdb.hash_map_get_cursor(m0, k)
 505 | 		v, _ := xitdb.cursor_read_uint(vc.?)
 506 | 		assert(v == u64(idx))
 507 | 	}
 508 | 	elapsed_get := time.since(t1)
 509 | 
 510 | 	print_result(Bench_Result{
 511 | 		name    = "HAMT Hash_Map point lookup (with SHA-1)",
 512 | 		ops     = n,
 513 | 		elapsed = elapsed_get,
 514 | 	})
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
| `CoreMemory` | 110 | In-memory `ArrayList(u8)` storage backend with `std.Io.Reader`/`Writer` vtable | [`lib.zig#L4918-L5027`](../../reference/xitdb-zig/src/lib.zig#L4918-L5027) |

### Reached Odin Procedures (`39` procedures across `6` files · `829` LOC) (Active `_exec_path_part` arms: `Array_List_Get`, `Hash_Map_Get`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_hash_map_init` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/collections.odin` | `hash_map_get_cursor` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L310-L314`](../../xitdb/collections.odin#L310-L314) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `array_list_get_cursor`, `hash_map_get_cursor_by_hash`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `read_hash_map_init`, `cursor_read_uint`, `cursor_read_path`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_get_cursor`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_get_cursor_by_hash` | `depth 1` (from `hash_map_get_cursor`) | 3 | [`xitdb/collections.odin#L284-L286`](../../xitdb/collections.odin#L284-L286) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_read_path`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `database_read_root_header`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `read_array_list_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `read_map_slot`, `kv_pair_read_buf`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_length` | `depth 5` (from `read_array_list_slot`, `read_map_slot`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 5` (from `read_array_list_slot`, `read_map_slot`, `encode_kv_pair`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/database.odin` | `database_is_old` | `depth 5` (from `read_map_slot`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
