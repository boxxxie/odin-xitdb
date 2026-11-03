# #5. `HAMT Hash_Map remove & branch shortening` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 04: 16-Way HAMT Single-Pass KV & Lazy Remove**](../zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) · [Odin Harness (`bench_xitdb.odin#L568-L594`)](../bench_xitdb.odin#L568-L594) · [Zig Harness (`bench_xitdb.zig#L608-L630`)](../bench_xitdb.zig#L608-L630)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **167** | 172.6 ± 16.6 | 9.6% | 195.4 | 5,988,024 | - | **5.83x Odin** (`z = 72.5`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 973 | 985.0 ± 18.7 | 1.9% | 1,010.4 | 1,027,749 | - | Baseline |

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

### Odin ([`benchmarks/bench_xitdb.odin#L568-L594`](../bench_xitdb.odin#L568-L594))

```odin
 568 | 	// 1d. HAMT key removal & branch shortening (remove half of the keys in 1 tx)
 569 | 	remove_count := n / 2
 570 | 	Remove_Hamt_Ctx :: struct {
 571 | 		keys: []string,
 572 | 	}
 573 | 	rhctx := Remove_Hamt_Ctx{keys = keys[:remove_count]}
 574 | 
 575 | 	remove_hamt_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
 576 | 		c := (^Remove_Hamt_Ctx)(user_data)
 577 | 		m := xitdb.write_hash_map_init(cursor^) or_return
 578 | 		for k in c.keys {
 579 | 			_, err := xitdb.hash_map_remove(&m, k)
 580 | 			if err != nil do return err
 581 | 		}
 582 | 		return nil
 583 | 	}
 584 | 
 585 | 	m0_slot, _ := xitdb.array_list_get_slot(history, 0)
 586 | 	t3 := time.now()
 587 | 	_ = xitdb.array_list_append_context(&history, m0_slot.?, remove_hamt_cb, &rhctx)
 588 | 	elapsed_rem := time.since(t3)
 589 | 
 590 | 	print_result(Bench_Result{
 591 | 		name    = "HAMT Hash_Map remove & branch shortening",
 592 | 		ops     = remove_count,
 593 | 		elapsed = elapsed_rem,
 594 | 	})
```

### Zig ([`benchmarks/bench_xitdb.zig#L608-L630`](../bench_xitdb.zig#L608-L630))

```zig
 608 |     // 1d. HAMT key removal & branch shortening (remove half of the keys in 1 tx)
 609 |     const remove_count = n / 2;
 610 |     const RemoveHamtCtx = struct {
 611 |         keys: []const []const u8,
 612 | 
 613 |         pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
 614 |             const m = try DB.HashMap(.read_write).init(cursor.*);
 615 |             for (self.keys) |k| {
 616 |                 _ = try m.remove(hashSha1(k));
 617 |             }
 618 |         }
 619 |     };
 620 | 
 621 |     const m0_slot = (try history.getSlot(0)).?;
 622 |     const t3 = std.Io.Clock.awake.now(io);
 623 |     try history.appendContext(.{ .slot = m0_slot }, RemoveHamtCtx{ .keys = keys[0..remove_count] });
 624 |     const elapsed_rem = t3.untilNow(io, .awake).nanoseconds;
 625 | 
 626 |     try printResult(stdout, .{
 627 |         .name = "HAMT Hash_Map remove & branch shortening",
 628 |         .ops = remove_count,
 629 |         .elapsed_ns = elapsed_rem,
 630 |     });
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

### Reached Odin Procedures (`75` procedures across `6` files · `1516` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Remove`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L240-L245`](../../xitdb/collections.odin#L240-L245) |
| `xitdb/collections.odin` | `hash_map_remove` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L442-L446`](../../xitdb/collections.odin#L442-L446) |
| `xitdb/collections.odin` | `array_list_get_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | **Entry Point** (`depth 0`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `array_list_append_context`, `hash_map_remove_by_hash`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L230-L238`](../../xitdb/collections.odin#L230-L238) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_remove`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_remove_by_hash` | `depth 1` (from `hash_map_remove`) | 10 | [`xitdb/collections.odin#L398-L407`](../../xitdb/collections.odin#L398-L407) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L81-L95`](../../xitdb/cursor.odin#L81-L95) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `cursor_read_path_slot`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `cursor_read_path_slot`, `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_seek_to` | `depth 3` (from `cursor_reload_slot`, `read_slot_pointer`, `_exec_path_part`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`, `cursor_resolved`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_array_list_slot`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_array_list_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/core.odin` | `core_read_exact` | `depth 4` (from `_exec_path_part`, `database_read_root_header`, `core_read_slot_raw`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 4` (from `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/database.odin` | `database_check_hash` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/hamt.odin` | `remove_map_slot` | `depth 4` (from `_exec_path_part`) | 100 | [`xitdb/hamt.odin#L242-L341`](../../xitdb/hamt.odin#L242-L341) |
| `xitdb/core.odin` | `core_read_long` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1452-L1483`](../../xitdb/database.odin#L1452-L1483) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L345-L383`](../../xitdb/hamt.odin#L345-L383) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_truncate_with_header`, `database_commit_root`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `core_read_slot`, `database_read_root_header`, `database_read_root_trailer`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `core_write_slot`, `read_array_list_slot`, `read_array_list_slot_append`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `remove_map_slot`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/core.odin` | `core_read` | `depth 5` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`, `remove_map_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `remove_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `remove_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/core.odin` | `core_read_i64` | `depth 5` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1485-L1533`](../../xitdb/database.odin#L1485-L1533) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 5` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1339-L1350`](../../xitdb/types.odin#L1339-L1350) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 6` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |
