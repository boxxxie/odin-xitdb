# #8. `HAMT Counted_Hash_Map bulk put (1 tx)` — Code Slice

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [Odin Harness (`bench_xitdb.odin#L639-L663`)](../bench_xitdb.odin#L639-L663) · [Zig Harness (`bench_xitdb.zig#L672-L700`)](../bench_xitdb.zig#L672-L700)

- **Touched Library Scope:** **88** procedures across **6** `xitdb/*.odin` files (**1891** lines of library code)
- **Direct Benchmark Entry Points:** `write_counted_hash_map_init`, `hash_map_put`, `array_list_append_context`, `array_list_get_slot`, `array_list_get_cursor`, `read_counted_hash_map_init`, `counted_hash_map_count`

---

## 1. Benchmark Harness Code

### Odin (`benchmarks/bench_xitdb.odin#L639-L663`)

```odin
 639 | 	// 1g. Counted_Hash_Map bulk put + O(1) count tracking vs remove
 640 | 	counted_put_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
 641 | 		c := (^Insert_Ctx)(user_data)
 642 | 		cm := xitdb.write_counted_hash_map_init(cursor^) or_return
 643 | 		for k, idx in c.keys {
 644 | 			xitdb.hash_map_put(&cm, k, u64(idx)) or_return
 645 | 		}
 646 | 		return nil
 647 | 	}
 648 | 
 649 | 	t6 := time.now()
 650 | 	_ = xitdb.array_list_append_context(&history, xitdb.Slot{}, counted_put_cb, &ictx)
 651 | 	elapsed_cput := time.since(t6)
 652 | 
 653 | 	cm_slot, _ := xitdb.array_list_get_slot(history, -1)
 654 | 	cm_cur, _ := xitdb.array_list_get_cursor(history, -1)
 655 | 	rcm, _ := xitdb.read_counted_hash_map_init(cm_cur.?)
 656 | 	cm_cnt, _ := xitdb.counted_hash_map_count(rcm)
 657 | 	assert(cm_cnt == i64(n))
 658 | 
 659 | 	print_result(Bench_Result{
 660 | 		name    = "HAMT Counted_Hash_Map bulk put (1 tx)",
 661 | 		ops     = n,
 662 | 		elapsed = elapsed_cput,
 663 | 	})
```

<details>
<summary><strong>Zig Benchmark Harness (<code>benchmarks/bench_xitdb.zig#L672-L700</code>)</strong></summary>

```zig
 672 |     // 1g. Counted_Hash_Map bulk put + O(1) count tracking vs remove
 673 |     const CountedPutCtx = struct {
 674 |         keys: []const []const u8,
 675 | 
 676 |         pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
 677 |             const cm = try DB.CountedHashMap(.read_write).init(cursor.*);
 678 |             for (self.keys, 0..) |k, idx| {
 679 |                 const h = hashSha1(k);
 680 |                 try cm.putKey(h, .{ .bytes = k });
 681 |                 try cm.put(h, .{ .uint = @intCast(idx) });
 682 |             }
 683 |         }
 684 |     };
 685 | 
 686 |     const t6 = std.Io.Clock.awake.now(io);
 687 |     try history.appendContext(.{ .slot = .{} }, CountedPutCtx{ .keys = keys });
 688 |     const elapsed_cput = t6.untilNow(io, .awake).nanoseconds;
 689 | 
 690 |     const cm_slot = (try history.getSlot(-1)).?;
 691 |     const cm_cur = (try history.getCursor(-1)).?;
 692 |     const rcm = try DB.CountedHashMap(.read_only).init(cm_cur);
 693 |     const cm_cnt = try rcm.count();
 694 |     std.debug.assert(cm_cnt == @as(u64, @intCast(n)));
 695 | 
 696 |     try printResult(stdout, .{
 697 |         .name = "HAMT Counted_Hash_Map bulk put (1 tx)",
 698 |         .ops = n,
 699 |         .elapsed_ns = elapsed_cput,
 700 |     });
```
</details>

---

## 2. Reached `xitdb` Call Graph & File Coverage

| File | Procedure | Role / Call Depth | Lines | Source Link |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `write_counted_hash_map_init` | **Entry Point** (`depth 0`) | 14 | [`xitdb/collections.odin#L257-L270`](../../xitdb/collections.odin#L257-L270) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L417-L421`](../../xitdb/collections.odin#L417-L421) |
| `xitdb/collections.odin` | `array_list_append_context` | **Entry Point** (`depth 0`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/collections.odin` | `array_list_get_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_get_cursor` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L41-L43`](../../xitdb/collections.odin#L41-L43) |
| `xitdb/collections.odin` | `read_counted_hash_map_init` | **Entry Point** (`depth 0`) | 9 | [`xitdb/collections.odin#L247-L255`](../../xitdb/collections.odin#L247-L255) |
| `xitdb/collections.odin` | `counted_hash_map_count` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L280-L282`](../../xitdb/collections.odin#L280-L282) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 1` (from `write_counted_hash_map_init`, `read_counted_hash_map_init`, `cursor_read_path_slot`) | 11 | [`xitdb/cursor.odin#L46-L56`](../../xitdb/cursor.odin#L46-L56) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_counted_hash_map_init`, `array_list_append_context`, `hash_map_put_key_and_value`) | 57 | [`xitdb/cursor.odin#L118-L174`](../../xitdb/cursor.odin#L118-L174) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put`) | 3 | [`xitdb/database.odin#L268-L270`](../../xitdb/database.odin#L268-L270) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L409-L415`](../../xitdb/collections.odin#L409-L415) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L81-L95`](../../xitdb/cursor.odin#L81-L95) |
| `xitdb/cursor.odin` | `cursor_read_path` | `depth 1` (from `array_list_get_cursor`) | 12 | [`xitdb/cursor.odin#L68-L79`](../../xitdb/cursor.odin#L68-L79) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 1` (from `counted_hash_map_count`) | 39 | [`xitdb/cursor.odin#L394-L432`](../../xitdb/cursor.odin#L394-L432) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_resolved`, `cursor_write_path`, `cursor_check_writable`) | 6 | [`xitdb/database.odin#L416-L421`](../../xitdb/database.odin#L416-L421) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `cursor_resolved`, `read_slot_pointer`, `database_truncate`) | 8 | [`xitdb/database.odin#L370-L377`](../../xitdb/database.odin#L370-L377) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L97-L105`](../../xitdb/cursor.odin#L97-L105) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L423-L438`](../../xitdb/database.odin#L423-L438) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L107-L116`](../../xitdb/cursor.odin#L107-L116) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `cursor_read_path`) | 68 | [`xitdb/database.odin#L552-L619`](../../xitdb/database.odin#L552-L619) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L364-L368`](../../xitdb/database.odin#L364-L368) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L28-L40`](../../xitdb/cursor.odin#L28-L40) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L259-L266`](../../xitdb/database.odin#L259-L266) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `cursor_read_path_slot`, `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_count`, `database_read_root_header`, `cursor_reload_slot`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_count`, `database_read_root_header`, `_exec_path_part`) | 34 | [`xitdb/core.odin#L326-L359`](../../xitdb/core.odin#L326-L359) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 2` (from `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1076-L1084`](../../xitdb/types.odin#L1076-L1084) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `cursor_count`) | 9 | [`xitdb/types.odin#L1099-L1107`](../../xitdb/types.odin#L1099-L1107) |
| `xitdb/core.odin` | `core_read_long` | `depth 2` (from `cursor_count`, `_exec_path_part`) | 7 | [`xitdb/core.odin#L494-L500`](../../xitdb/core.odin#L494-L500) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 3` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L993-L1003`](../../xitdb/types.odin#L993-L1003) |
| `xitdb/types.odin` | `tag_validate` | `depth 3` (from `database_read_root_header`, `core_read_slot`, `read_map_slot`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L503-L515`](../../xitdb/database.odin#L503-L515) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L577-L581`](../../xitdb/core.odin#L577-L581) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L915-L917`](../../xitdb/types.odin#L915-L917) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 18 | [`xitdb/core.odin#L583-L600`](../../xitdb/core.odin#L583-L600) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L440-L460`](../../xitdb/database.odin#L440-L460) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`, `read_map_slot`) | 24 | [`xitdb/core.odin#L552-L575`](../../xitdb/core.odin#L552-L575) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L237-L244`](../../xitdb/database.odin#L237-L244) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L400-L407`](../../xitdb/database.odin#L400-L407) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L621-L1382`](../../xitdb/database.odin#L621-L1382) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1452-L1483`](../../xitdb/database.odin#L1452-L1483) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_truncate_with_header`, `database_commit_root`) | 22 | [`xitdb/core.odin#L153-L174`](../../xitdb/core.odin#L153-L174) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L502-L507`](../../xitdb/core.odin#L502-L507) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 76 | [`xitdb/core.odin#L362-L437`](../../xitdb/core.odin#L362-L437) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L462-L468`](../../xitdb/database.odin#L462-L468) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L517-L528`](../../xitdb/database.odin#L517-L528) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L491-L501`](../../xitdb/database.odin#L491-L501) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 226 | [`xitdb/hamt.odin#L15-L240`](../../xitdb/hamt.odin#L15-L240) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L345-L383`](../../xitdb/hamt.odin#L345-L383) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1069-L1074`](../../xitdb/types.odin#L1069-L1074) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1416-L1421`](../../xitdb/types.odin#L1416-L1421) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L385-L452`](../../xitdb/hamt.odin#L385-L452) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L530-L535`](../../xitdb/database.odin#L530-L535) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1397-L1450`](../../xitdb/database.odin#L1397-L1450) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1384-L1395`](../../xitdb/database.odin#L1384-L1395) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1339-L1350`](../../xitdb/types.odin#L1339-L1350) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `read_map_slot`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_encode_writeable_data`, `_try_encode_inline_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1065-L1067`](../../xitdb/types.odin#L1065-L1067) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`) | 8 | [`xitdb/core.odin#L144-L151`](../../xitdb/core.odin#L144-L151) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 36 | [`xitdb/core.odin#L288-L323`](../../xitdb/core.odin#L288-L323) |
| `xitdb/core.odin` | `core_read_i64` | `depth 3` (from `core_read_long`) | 24 | [`xitdb/core.odin#L509-L532`](../../xitdb/core.odin#L509-L532) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `root_header_from_bytes`, `core_read_slot_raw`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L319-L334`](../../xitdb/database.odin#L319-L334) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 48 | [`xitdb/core.odin#L238-L285`](../../xitdb/core.odin#L238-L285) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `read_map_slot`, `kv_pair_read_buf`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1030-L1037`](../../xitdb/types.odin#L1030-L1037) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1022-L1028`](../../xitdb/types.odin#L1022-L1028) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L409-L414`](../../xitdb/database.odin#L409-L414) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1485-L1533`](../../xitdb/database.odin#L1485-L1533) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `core_write_long`) | 17 | [`xitdb/core.odin#L534-L550`](../../xitdb/core.odin#L534-L550) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L484-L489`](../../xitdb/database.odin#L484-L489) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1408-L1413`](../../xitdb/types.odin#L1408-L1413) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1141-L1143`](../../xitdb/types.odin#L1141-L1143) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`, `read_array_list_slot`) | 13 | [`xitdb/database.odin#L470-L482`](../../xitdb/database.odin#L470-L482) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`) | 17 | [`xitdb/core.odin#L441-L457`](../../xitdb/core.odin#L441-L457) |
| `xitdb/types.odin` | `kv_pair_read_buf` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1186-L1198`](../../xitdb/types.odin#L1186-L1198) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 5` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L384-L398`](../../xitdb/database.odin#L384-L398) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1012-L1020`](../../xitdb/types.odin#L1012-L1020) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L985-L991`](../../xitdb/types.odin#L985-L991) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1200-L1226`](../../xitdb/types.odin#L1200-L1226) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf`) | 3 | [`xitdb/types.odin#L1116-L1118`](../../xitdb/types.odin#L1116-L1118) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 6` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1039-L1051`](../../xitdb/types.odin#L1039-L1051) |

---

## 3. Highlighted Library Code Slice (`xitdb/*.odin`)

> Only procedures reachable when running **`HAMT Counted_Hash_Map bulk put (1 tx)`** are included below. Lines that dispatch to another touched procedure in this slice are marked with `// <== [calls ...]`. 

### `xitdb/collections.odin` (8 procedures · 52 lines: [`L41–L43`](../../xitdb/collections.odin#L41-L43), [`L45–L47`](../../xitdb/collections.odin#L45-L47), [`L81–L88`](../../xitdb/collections.odin#L81-L88), [`L247–L255`](../../xitdb/collections.odin#L247-L255), [`L257–L270`](../../xitdb/collections.odin#L257-L270), [`L280–L282`](../../xitdb/collections.odin#L280-L282), [`L409–L415`](../../xitdb/collections.odin#L409-L415), [`L417–L421`](../../xitdb/collections.odin#L417-L421))

#### [`array_list_get_cursor`](../../xitdb/collections.odin#L41-L43) — `ENTRY POINT` (`L41–L43`)

```odin
  41 | array_list_get_cursor :: proc(a: Read_Array_List, index: i64) -> (Maybe(Read_Cursor), Error) {
  42 | 	return cursor_read_path(a.cursor, []Path_Part{Array_List_Get{index = index}})  // <== [calls cursor_read_path]
  43 | }
```

#### [`array_list_get_slot`](../../xitdb/collections.odin#L45-L47) — `ENTRY POINT` (`L45–L47`)

```odin
  45 | array_list_get_slot :: proc(a: Read_Array_List, index: i64) -> (Maybe(Slot), Error) {
  46 | 	return cursor_read_path_slot(a.cursor, []Path_Part{Array_List_Get{index = index}})  // <== [calls cursor_read_path_slot]
  47 | }
```

#### [`array_list_append_context`](../../xitdb/collections.odin#L81-L88) — `ENTRY POINT` (`L81–L88`)

```odin
  81 | array_list_append_context :: proc(a: ^Write_Array_List, data: Writeable_Data, fn: Context_Function, user_data: rawptr = nil) -> Error {
  82 | 	_, err := cursor_write_path(&a.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
  83 | 		Array_List_Append{},
  84 | 		Write_Data{data = data},
  85 | 		Context{function = fn, user_data = user_data},
  86 | 	})
  87 | 	return err
  88 | }
```

#### [`read_counted_hash_map_init`](../../xitdb/collections.odin#L247-L255) — `ENTRY POINT` (`L247–L255`)

```odin
 247 | read_counted_hash_map_init :: proc(cursor: Read_Cursor) -> (res: Read_Counted_Hash_Map, err: Error) {
 248 | 	slot_ptr := cursor_resolved(cursor) or_return  // <== [calls cursor_resolved]
 249 | 	#partial switch slot_ptr.slot.tag {
 250 | 	case .None, .Counted_Hash_Map, .Counted_Hash_Set:
 251 | 		return Read_Counted_Hash_Map{read_hash_map = Read_Hash_Map{cursor = cursor}}, nil
 252 | 	case:
 253 | 		return {}, .Unexpected_Tag
 254 | 	}
 255 | }
```

#### [`write_counted_hash_map_init`](../../xitdb/collections.odin#L257-L270) — `ENTRY POINT` (`L257–L270`)

```odin
 257 | write_counted_hash_map_init :: proc(cursor: Write_Cursor) -> (res: Write_Counted_Hash_Map, err: Error) {
 258 | 	slot_ptr := cursor_resolved(cursor.read_cursor) or_return  // <== [calls cursor_resolved]
 259 | 	#partial switch slot_ptr.slot.tag {
 260 | 	case .None, .Counted_Hash_Map, .Counted_Hash_Set:
 261 | 	case:
 262 | 		return {}, .Unexpected_Tag
 263 | 	}
 264 | 	c := cursor
 265 | 	wc := cursor_write_path(&c, []Path_Part{Hash_Map_Init{counted = true, set = false}}) or_return  // <== [calls cursor_write_path]
 266 | 	rm := Read_Hash_Map{cursor = wc.read_cursor}
 267 | 	return Write_Counted_Hash_Map{
 268 | 		write_hash_map = Write_Hash_Map{read_hash_map = rm, write_cursor = wc},
 269 | 	}, nil
 270 | }
```

#### [`counted_hash_map_count`](../../xitdb/collections.odin#L280-L282) — `ENTRY POINT` (`L280–L282`)

```odin
 280 | counted_hash_map_count :: proc(m: Read_Counted_Hash_Map) -> (res: i64, err: Error) {
 281 | 	return cursor_count(m.cursor)  // <== [calls cursor_count]
 282 | }
```

#### [`hash_map_put_key_and_value`](../../xitdb/collections.odin#L409-L415) — `DEPTH 1` (`L409–L415`)

```odin
 409 | hash_map_put_key_and_value :: proc(m: ^Write_Hash_Map, hash: []u8, key: Writeable_Data, data: Writeable_Data) -> Error {
 410 | 	_, err := cursor_write_path(&m.write_cursor, []Path_Part{  // <== [calls cursor_write_path]
 411 | 		Hash_Map_Get{target = Hash_Map_Get_KV_Pair{hash = hash}},
 412 | 		Write_KV_Data{key = key, value = data},
 413 | 	})
 414 | 	return err
 415 | }
```

#### [`hash_map_put`](../../xitdb/collections.odin#L417-L421) — `ENTRY POINT` (`L417–L421`)

```odin
 417 | hash_map_put :: proc(m: ^Write_Hash_Map, key: string, data: Writeable_Data) -> Error {
 418 | 	buf: [64]u8 = ---
 419 | 	hash := database_digest_string_buf(m.cursor.db, key, buf[:])  // <== [calls database_digest_string_buf]
 420 | 	return hash_map_put_key_and_value(m, hash, key, data)  // <== [calls hash_map_put_key_and_value]
 421 | }
```

### `xitdb/core.odin` (17 procedures · 395 lines: [`L125–L142`](../../xitdb/core.odin#L125-L142), [`L144–L151`](../../xitdb/core.odin#L144-L151), [`L153–L174`](../../xitdb/core.odin#L153-L174), [`L176–L192`](../../xitdb/core.odin#L176-L192), [`L219–L236`](../../xitdb/core.odin#L219-L236), [`L238–L285`](../../xitdb/core.odin#L238-L285), [`L288–L323`](../../xitdb/core.odin#L288-L323), [`L326–L359`](../../xitdb/core.odin#L326-L359), [`L362–L437`](../../xitdb/core.odin#L362-L437), [`L441–L457`](../../xitdb/core.odin#L441-L457), [`L494–L500`](../../xitdb/core.odin#L494-L500), [`L502–L507`](../../xitdb/core.odin#L502-L507), [`L509–L532`](../../xitdb/core.odin#L509-L532), [`L534–L550`](../../xitdb/core.odin#L534-L550), [`L552–L575`](../../xitdb/core.odin#L552-L575), [`L577–L581`](../../xitdb/core.odin#L577-L581), [`L583–L600`](../../xitdb/core.odin#L583-L600))

#### [`_buffered_write_to_file`](../../xitdb/core.odin#L125-L142) — `DEPTH 5` (`L125–L142`)

```odin
 125 | @(private)
 126 | _buffered_write_to_file :: proc(bf: ^Core_Buffered_File, pos: i64, data: []u8) -> Error {
 127 | 	cached_len := bf.file_len
 128 | 	bf.file_len = nil
 129 | 	os.seek(bf.file.file, pos, .Start) or_return
 130 | 	written := 0
 131 | 	for written < len(data) {
 132 | 		n := os.write(bf.file.file, data[written:]) or_return
 133 | 		if n == 0 {
 134 | 			return io.Error.Short_Write
 135 | 		}
 136 | 		written += n
 137 | 	}
 138 | 	if cl, ok := cached_len.?; ok {
 139 | 		bf.file_len = max(cl, pos + i64(len(data)))
 140 | 	}
 141 | 	return nil
 142 | }
```

#### [`_buffered_flush`](../../xitdb/core.odin#L144-L151) — `DEPTH 3` (`L144–L151`)

```odin
 144 | @(private)
 145 | _buffered_flush :: proc(bf: ^Core_Buffered_File) -> Error {
 146 | 	if len(bf.memory.buf) > bf.flushed_len {
 147 | 		_buffered_write_to_file(bf, bf.memory_pos + i64(bf.flushed_len), bf.memory.buf[bf.flushed_len:]) or_return  // <== [calls _buffered_write_to_file]
 148 | 		bf.flushed_len = len(bf.memory.buf)
 149 | 	}
 150 | 	return nil
 151 | }
```

#### [`core_length`](../../xitdb/core.odin#L153-L174) — `DEPTH 4` (`L153–L174`)

```odin
 153 | core_length :: proc(c: ^Core) -> (length: i64, err: Error) {
 154 | 	switch &v in c {
 155 | 	case Core_Memory:
 156 | 		return i64(len(v.buf)), nil
 157 | 	case Core_File:
 158 | 		return os.file_size(v.file)
 159 | 	case Core_Buffered_File:
 160 | 		flen: i64
 161 | 		if fl, ok := v.file_len.?; ok {
 162 | 			flen = fl
 163 | 		} else {
 164 | 			flen = os.file_size(v.file.file) or_return
 165 | 			v.file_len = flen
 166 | 		}
 167 | 		buf_size := i64(len(v.memory.buf))
 168 | 		if buf_size == 0 {
 169 | 			return flen, nil
 170 | 		}
 171 | 		return max(v.memory_pos + buf_size, flen), nil
 172 | 	}
 173 | 	return 0, .Invalid_Database
 174 | }
```

#### [`core_seek_to`](../../xitdb/core.odin#L176-L192) — `DEPTH 2` (`L176–L192`)

```odin
 176 | core_seek_to :: proc(c: ^Core, pos: i64) -> Error {
 177 | 	if pos < 0 {
 178 | 		return .Expected_Unsigned_Long
 179 | 	}
 180 | 	switch &v in c {
 181 | 	case Core_Memory:
 182 | 		v.pos = pos
 183 | 		return nil
 184 | 	case Core_File:
 185 | 		os.seek(v.file, pos, .Start) or_return
 186 | 		return nil
 187 | 	case Core_Buffered_File:
 188 | 		v.pos = pos
 189 | 		return nil
 190 | 	}
 191 | 	return .Invalid_Database
 192 | }
```

#### [`core_sync`](../../xitdb/core.odin#L219-L236) — `DEPTH 2` (`L219–L236`)

```odin
 219 | core_sync :: proc(c: ^Core) -> Error {
 220 | 	switch &v in c {
 221 | 	case Core_Memory:
 222 | 		return nil
 223 | 	case Core_File:
 224 | 		if !v.fsync {
 225 | 			return nil
 226 | 		}
 227 | 		return os.sync(v.file)
 228 | 	case Core_Buffered_File:
 229 | 		_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 230 | 		if !v.file.fsync {
 231 | 			return nil
 232 | 		}
 233 | 		return os.sync(v.file.file)
 234 | 	}
 235 | 	return .Invalid_Database
 236 | }
```

#### [`core_set_length`](../../xitdb/core.odin#L238-L285) — `DEPTH 4` (`L238–L285`)

```odin
 238 | core_set_length :: proc(c: ^Core, new_len: i64) -> Error {
 239 | 	if new_len < 0 {
 240 | 		return .Expected_Unsigned_Long
 241 | 	}
 242 | 	switch &v in c {
 243 | 	case Core_Memory:
 244 | 		if new_len > i64(len(v.buf)) {
 245 | 			return Xitdb_Error.Invalid_Offset
 246 | 		}
 247 | 		resize(&v.buf, int(new_len))
 248 | 		if v.pos > new_len {
 249 | 			v.pos = new_len
 250 | 		}
 251 | 		return nil
 252 | 	case Core_File:
 253 | 		err := os.truncate(v.file, new_len)
 254 | 		if err != nil {
 255 | 			// Read-only file handles ignore setLength just like Zig/Go xitdb.
 256 | 			return nil
 257 | 		}
 258 | 		pos := os.seek(v.file, 0, .Current) or_return
 259 | 		if pos > new_len {
 260 | 			os.seek(v.file, new_len, .Start) or_return
 261 | 		}
 262 | 		return nil
 263 | 	case Core_Buffered_File:
 264 | 		buf_size := i64(len(v.memory.buf))
 265 | 		if new_len <= v.memory_pos {
 266 | 			clear(&v.memory.buf)
 267 | 			v.flushed_len = 0
 268 | 		} else if new_len < v.memory_pos + buf_size {
 269 | 			new_buf_len := int(new_len - v.memory_pos)
 270 | 			resize(&v.memory.buf, new_buf_len)
 271 | 			if v.flushed_len > new_buf_len {
 272 | 				v.flushed_len = new_buf_len
 273 | 			}
 274 | 		}
 275 | 		v.file_len = nil
 276 | 		if err := os.truncate(v.file.file, new_len); err == nil {
 277 | 			v.file_len = new_len
 278 | 		}
 279 | 		if v.pos > new_len {
 280 | 			v.pos = new_len
 281 | 		}
 282 | 		return nil
 283 | 	}
 284 | 	return .Invalid_Database
 285 | }
```

#### [`core_read`](../../xitdb/core.odin#L288-L323) — `DEPTH 3` (`L288–L323`)

```odin
 288 | core_read :: proc(c: ^Core, p: []u8) -> (read_n: int, err: Error) {
 289 | 	if len(p) == 0 {
 290 | 		return 0, nil
 291 | 	}
 292 | 	switch &v in c {
 293 | 	case Core_Memory:
 294 | 		if v.pos >= i64(len(v.buf)) {
 295 | 			return 0, io.Error.EOF
 296 | 		}
 297 | 		avail := int(i64(len(v.buf)) - v.pos)
 298 | 		to_read := min(len(p), avail)
 299 | 		copy(p[:to_read], v.buf[int(v.pos):int(v.pos) + to_read])
 300 | 		v.pos += i64(to_read)
 301 | 		return to_read, nil
 302 | 	case Core_File:
 303 | 		return os.read(v.file, p)
 304 | 	case Core_Buffered_File:
 305 | 		buf_len := i64(len(v.memory.buf))
 306 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos < v.memory_pos + buf_len {
 307 | 			mem_off := int(v.pos - v.memory_pos)
 308 | 			size := min(len(p), int(buf_len) - mem_off)
 309 | 			copy(p[:size], v.memory.buf[mem_off:mem_off + size])
 310 | 			v.pos += i64(size)
 311 | 			return size, nil
 312 | 		}
 313 | 		os.seek(v.file.file, v.pos, .Start) or_return
 314 | 		max_size := len(p)
 315 | 		if buf_len > 0 && v.pos < v.memory_pos {
 316 | 			max_size = min(len(p), int(v.memory_pos - v.pos))
 317 | 		}
 318 | 		n, err := os.read(v.file.file, p[:max_size])
 319 | 		v.pos += i64(n)
 320 | 		return n, err
 321 | 	}
 322 | 	return 0, .Invalid_Database
 323 | }
```

#### [`core_read_exact`](../../xitdb/core.odin#L326-L359) — `DEPTH 2` (`L326–L359`)

```odin
 326 | core_read_exact :: proc(c: ^Core, p: []u8) -> Error {
 327 | 	if len(p) == 0 {
 328 | 		return nil
 329 | 	}
 330 | 	#partial switch &v in c {
 331 | 	case Core_Memory:
 332 | 		end_pos := v.pos + i64(len(p))
 333 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 334 | 			v.pos = i64(len(v.buf))
 335 | 			return Xitdb_Error.Unexpected_EOF
 336 | 		}
 337 | 		copy(p, v.buf[int(v.pos):int(end_pos)])
 338 | 		v.pos = end_pos
 339 | 		return nil
 340 | 	}
 341 | 	total := 0
 342 | 	for total < len(p) {
 343 | 		n, err := core_read(c, p[total:])  // <== [calls core_read]
 344 | 		total += n
 345 | 		if err != nil {
 346 | 			if err == io.Error.EOF {
 347 | 				if total == len(p) {
 348 | 					return nil
 349 | 				}
 350 | 				return Xitdb_Error.Unexpected_EOF
 351 | 			}
 352 | 			return err
 353 | 		}
 354 | 		if n == 0 {
 355 | 			return Xitdb_Error.Unexpected_EOF
 356 | 		}
 357 | 	}
 358 | 	return nil
 359 | }
```

#### [`core_write_all`](../../xitdb/core.odin#L362-L437) — `DEPTH 4` (`L362–L437`)

```odin
 362 | core_write_all :: proc(c: ^Core, p: []u8) -> Error {
 363 | 	if len(p) == 0 {
 364 | 		return nil
 365 | 	}
 366 | 	switch &v in c {
 367 | 	case Core_Memory:
 368 | 		old_size := int(len(v.buf))
 369 | 		end_pos := int(v.pos) + len(p)
 370 | 		if end_pos > old_size {
 371 | 			resize(&v.buf, end_pos)
 372 | 		}
 373 | 		copy(v.buf[int(v.pos):end_pos], p)
 374 | 		v.pos = i64(end_pos)
 375 | 		return nil
 376 | 	case Core_File:
 377 | 		written := 0
 378 | 		for written < len(p) {
 379 | 			n := os.write(v.file, p[written:]) or_return
 380 | 			if n == 0 {
 381 | 				return io.Error.Short_Write
 382 | 			}
 383 | 			written += n
 384 | 		}
 385 | 		return nil
 386 | 	case Core_Buffered_File:
 387 | 		n := i64(len(p))
 388 | 		if v.file_len == nil {
 389 | 			fl := os.file_size(v.file.file) or_return
 390 | 			v.file_len = fl
 391 | 		}
 392 | 		buf_size := i64(len(v.memory.buf))
 393 | 		if buf_size > 0 && v.pos + n <= v.memory_pos {
 394 | 			// Write is strictly before the buffered tail window (e.g. Root_Header at offset 20):
 395 | 			// write directly to the file without evicting the hot tail buffer.
 396 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 397 | 			v.pos += n
 398 | 			return nil
 399 | 		}
 400 | 		if buf_size == 0 {
 401 | 			v.memory_pos = v.pos
 402 | 			v.flushed_len = 0
 403 | 		} else if v.pos > v.memory_pos + buf_size ||
 404 | 		          (v.pos >= v.memory_pos && v.pos - v.memory_pos + n > v.memory_max_size) {
 405 | 			_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 406 | 			clear(&v.memory.buf)
 407 | 			v.flushed_len = 0
 408 | 			v.memory_pos = v.pos
 409 | 		}
 410 | 		buf_size = i64(len(v.memory.buf))
 411 | 		if v.pos >= v.memory_pos && v.pos - v.memory_pos + n <= v.memory_max_size {
 412 | 			rel_off := int(v.pos - v.memory_pos)
 413 | 			end_off := rel_off + len(p)
 414 | 			if end_off > len(v.memory.buf) {
 415 | 				resize(&v.memory.buf, end_off)
 416 | 			}
 417 | 			copy(v.memory.buf[rel_off:end_off], p)
 418 | 			if rel_off < v.flushed_len {
 419 | 				if end_off <= v.flushed_len {
 420 | 					_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 421 | 				} else {
 422 | 					v.flushed_len = rel_off
 423 | 				}
 424 | 			}
 425 | 		} else {
 426 | 			if v.pos < v.memory_pos + buf_size && v.pos + n > v.memory_pos {
 427 | 				_buffered_flush(&v) or_return  // <== [calls _buffered_flush]
 428 | 				clear(&v.memory.buf)
 429 | 				v.flushed_len = 0
 430 | 			}
 431 | 			_buffered_write_to_file(&v, v.pos, p) or_return  // <== [calls _buffered_write_to_file]
 432 | 		}
 433 | 		v.pos += n
 434 | 		return nil
 435 | 	}
 436 | 	return .Invalid_Database
 437 | }
```

#### [`core_slice_at`](../../xitdb/core.odin#L441-L457) — `DEPTH 5` (`L441–L457`)

```odin
 441 | core_slice_at :: #force_inline proc(c: ^Core, pos: i64, n: int) -> (slice: []u8, in_mem: bool, err: Error) {
 442 | 	#partial switch &v in c {
 443 | 	case Core_Memory:
 444 | 		p := int(pos)
 445 | 		if p < 0 || p + n > len(v.buf) {
 446 | 			return nil, true, Xitdb_Error.Unexpected_EOF
 447 | 		}
 448 | 		return v.buf[p : p + n], true, nil
 449 | 	case Core_Buffered_File:
 450 | 		buf_len := i64(len(v.memory.buf))
 451 | 		if buf_len > 0 && pos >= v.memory_pos && pos + i64(n) <= v.memory_pos + buf_len {
 452 | 			mem_off := int(pos - v.memory_pos)
 453 | 			return v.memory.buf[mem_off : mem_off + n], true, nil
 454 | 		}
 455 | 	}
 456 | 	return nil, false, nil
 457 | }
```

#### [`core_read_long`](../../xitdb/core.odin#L494-L500) — `DEPTH 2` (`L494–L500`)

```odin
 494 | core_read_long :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 495 | 	res = core_read_i64(c) or_return  // <== [calls core_read_i64]
 496 | 	if res < 0 {
 497 | 		return 0, Xitdb_Error.Expected_Unsigned_Long
 498 | 	}
 499 | 	return res, nil
 500 | }
```

#### [`core_write_long`](../../xitdb/core.odin#L502-L507) — `DEPTH 4` (`L502–L507`)

```odin
 502 | core_write_long :: #force_inline proc(c: ^Core, v: i64) -> Error {
 503 | 	if v < 0 {
 504 | 		return Xitdb_Error.Expected_Unsigned_Long
 505 | 	}
 506 | 	return core_write_i64(c, v)  // <== [calls core_write_i64]
 507 | }
```

#### [`core_read_i64`](../../xitdb/core.odin#L509-L532) — `DEPTH 3` (`L509–L532`)

```odin
 509 | core_read_i64 :: #force_inline proc(c: ^Core) -> (res: i64, err: Error) {
 510 | 	#partial switch &v in c {
 511 | 	case Core_Memory:
 512 | 		end_pos := v.pos + 8
 513 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 514 | 			v.pos = i64(len(v.buf))
 515 | 			return 0, Xitdb_Error.Unexpected_EOF
 516 | 		}
 517 | 		res = i64(endian.unchecked_get_u64be(v.buf[int(v.pos):int(end_pos)]))
 518 | 		v.pos = end_pos
 519 | 		return res, nil
 520 | 	case Core_Buffered_File:
 521 | 		buf_len := i64(len(v.memory.buf))
 522 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + 8 <= v.memory_pos + buf_len {
 523 | 			mem_off := int(v.pos - v.memory_pos)
 524 | 			res = i64(endian.unchecked_get_u64be(v.memory.buf[mem_off : mem_off + 8]))
 525 | 			v.pos += 8
 526 | 			return res, nil
 527 | 		}
 528 | 	}
 529 | 	b: [8]u8 = ---
 530 | 	core_read_exact(c, b[:]) or_return  // <== [calls core_read_exact]
 531 | 	return i64(endian.unchecked_get_u64be(b[:])), nil
 532 | }
```

#### [`core_write_i64`](../../xitdb/core.odin#L534-L550) — `DEPTH 5` (`L534–L550`)

```odin
 534 | core_write_i64 :: #force_inline proc(c: ^Core, v: i64) -> Error {
 535 | 	#partial switch &m in c {
 536 | 	case Core_Memory:
 537 | 		old_size := len(m.buf)
 538 | 		pos := int(m.pos)
 539 | 		end_pos := pos + 8
 540 | 		if end_pos > old_size {
 541 | 			resize(&m.buf, end_pos)
 542 | 		}
 543 | 		endian.unchecked_put_u64be(m.buf[pos:end_pos], u64(v))
 544 | 		m.pos = i64(end_pos)
 545 | 		return nil
 546 | 	}
 547 | 	b: [8]u8 = ---
 548 | 	endian.unchecked_put_u64be(b[:], u64(v))
 549 | 	return core_write_all(c, b[:])  // <== [calls core_write_all]
 550 | }
```

#### [`core_read_slot_raw`](../../xitdb/core.odin#L552-L575) — `DEPTH 3` (`L552–L575`)

```odin
 552 | core_read_slot_raw :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 553 | 	#partial switch &v in c {
 554 | 	case Core_Memory:
 555 | 		end_pos := v.pos + SLOT_LENGTH
 556 | 		if v.pos < 0 || end_pos > i64(len(v.buf)) {
 557 | 			v.pos = i64(len(v.buf))
 558 | 			return {}, Xitdb_Error.Unexpected_EOF
 559 | 		}
 560 | 		s = slot_from_slice_raw(v.buf[int(v.pos):int(end_pos)])  // <== [calls slot_from_slice_raw]
 561 | 		v.pos = end_pos
 562 | 		return s, nil
 563 | 	case Core_Buffered_File:
 564 | 		buf_len := i64(len(v.memory.buf))
 565 | 		if buf_len > 0 && v.pos >= v.memory_pos && v.pos + SLOT_LENGTH <= v.memory_pos + buf_len {
 566 | 			mem_off := int(v.pos - v.memory_pos)
 567 | 			s = slot_from_slice_raw(v.memory.buf[mem_off : mem_off + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
 568 | 			v.pos += SLOT_LENGTH
 569 | 			return s, nil
 570 | 		}
 571 | 	}
 572 | 	buf: [SLOT_LENGTH]u8 = ---
 573 | 	core_read_exact(c, buf[:]) or_return  // <== [calls core_read_exact]
 574 | 	return slot_from_bytes_raw(buf), nil  // <== [calls slot_from_bytes_raw]
 575 | }
```

#### [`core_read_slot`](../../xitdb/core.odin#L577-L581) — `DEPTH 3` (`L577–L581`)

```odin
 577 | core_read_slot :: #force_inline proc(c: ^Core) -> (s: Slot, err: Error) {
 578 | 	s = core_read_slot_raw(c) or_return  // <== [calls core_read_slot_raw]
 579 | 	tag_validate(s.tag) or_return  // <== [calls tag_validate]
 580 | 	return s, nil
 581 | }
```

#### [`core_write_slot`](../../xitdb/core.odin#L583-L600) — `DEPTH 3` (`L583–L600`)

```odin
 583 | core_write_slot :: #force_inline proc(c: ^Core, s: Slot) -> Error {
 584 | 	#partial switch &v in c {
 585 | 	case Core_Memory:
 586 | 		old_size := len(v.buf)
 587 | 		pos := int(v.pos)
 588 | 		end_pos := pos + SLOT_LENGTH
 589 | 		if end_pos > old_size {
 590 | 			resize(&v.buf, end_pos)
 591 | 		}
 592 | 		full_bit := u8(0x80) if s.full else u8(0)
 593 | 		v.buf[pos] = full_bit | (u8(s.tag) & 0x7f)
 594 | 		endian.unchecked_put_u64be(v.buf[pos + 1 : end_pos], u64(s.value))
 595 | 		v.pos = i64(end_pos)
 596 | 		return nil
 597 | 	}
 598 | 	buf := slot_to_bytes(s)  // <== [calls slot_to_bytes]
 599 | 	return core_write_all(c, buf[:])  // <== [calls core_write_all]
 600 | }
```

### `xitdb/cursor.odin` (8 procedures · 166 lines: [`L28–L40`](../../xitdb/cursor.odin#L28-L40), [`L46–L56`](../../xitdb/cursor.odin#L46-L56), [`L68–L79`](../../xitdb/cursor.odin#L68-L79), [`L81–L95`](../../xitdb/cursor.odin#L81-L95), [`L97–L105`](../../xitdb/cursor.odin#L97-L105), [`L107–L116`](../../xitdb/cursor.odin#L107-L116), [`L118–L174`](../../xitdb/cursor.odin#L118-L174), [`L394–L432`](../../xitdb/cursor.odin#L394-L432))

#### [`new_write_cursor`](../../xitdb/cursor.odin#L28-L40) — `DEPTH 2` (`L28–L40`)

```odin
  28 | new_write_cursor :: proc(slot_ptr: Slot_Pointer, db: ^Database) -> Write_Cursor {
  29 | 	c := Write_Cursor{
  30 | 		read_cursor = Read_Cursor{
  31 | 			slot_ptr  = slot_ptr,
  32 | 			db        = db,
  33 | 			frozen_at = 0,
  34 | 		},
  35 | 	}
  36 | 	if slot_ptr.position != nil && !is_root(slot_ptr) {  // <== [calls is_root]
  37 | 		c.transaction = db.transaction
  38 | 	}
  39 | 	return c
  40 | }
```

#### [`cursor_resolved`](../../xitdb/cursor.odin#L46-L56) — `DEPTH 1` (`L46–L56`)

```odin
  46 | cursor_resolved :: proc(c: Read_Cursor) -> (res: Slot_Pointer, err: Error) {
  47 | 	if is_root(c.slot_ptr) {  // <== [calls is_root]
  48 | 		header := database_read_root_header(c.db) or_return  // <== [calls database_read_root_header]
  49 | 		if header.file_size < ROOT_TRAILER_LENGTH {
  50 | 			return {}, .Invalid_Database
  51 | 		}
  52 | 		position := header.file_size - ROOT_TRAILER_LENGTH
  53 | 		return Slot_Pointer{position = position, slot = header.root}, nil
  54 | 	}
  55 | 	return c.slot_ptr, nil
  56 | }
```

#### [`cursor_read_path`](../../xitdb/cursor.odin#L68-L79) — `DEPTH 1` (`L68–L79`)

```odin
  68 | cursor_read_path :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Read_Cursor), err: Error) {
  69 | 	start := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  70 | 	slot_ptr: Slot_Pointer
  71 | 	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)  // <== [calls read_slot_pointer]
  72 | 	if err != nil {
  73 | 		if err == .Key_Not_Found {
  74 | 			return nil, nil
  75 | 		}
  76 | 		return nil, err
  77 | 	}
  78 | 	return Read_Cursor{slot_ptr = slot_ptr, db = c.db}, nil
  79 | }
```

#### [`cursor_read_path_slot`](../../xitdb/cursor.odin#L81-L95) — `DEPTH 1` (`L81–L95`)

```odin
  81 | cursor_read_path_slot :: proc(c: Read_Cursor, path: []Path_Part) -> (res: Maybe(Slot), err: Error) {
  82 | 	start := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
  83 | 	slot_ptr: Slot_Pointer
  84 | 	slot_ptr, err = read_slot_pointer(c.db, .Read_Only, path, 0, start, 0)  // <== [calls read_slot_pointer]
  85 | 	if err != nil {
  86 | 		if err == .Key_Not_Found {
  87 | 			return nil, nil
  88 | 		}
  89 | 		return nil, err
  90 | 	}
  91 | 	if !slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
  92 | 		return slot_ptr.slot, nil
  93 | 	}
  94 | 	return nil, nil
  95 | }
```

#### [`cursor_check_writable`](../../xitdb/cursor.odin#L97-L105) — `DEPTH 2` (`L97–L105`)

```odin
  97 | cursor_check_writable :: proc(c: ^Write_Cursor) -> Error {
  98 | 	if c.transaction != nil && c.transaction != c.db.transaction {
  99 | 		return .Expired_Transaction
 100 | 	}
 101 | 	if !is_root(c.slot_ptr) && c.transaction == nil && c.db.tx_start == nil {  // <== [calls is_root]
 102 | 		return .Expected_Tx_Start
 103 | 	}
 104 | 	return database_check_frozen_slot(c.db, c.slot_ptr)  // <== [calls database_check_frozen_slot]
 105 | }
```

#### [`cursor_reload_slot`](../../xitdb/cursor.odin#L107-L116) — `DEPTH 2` (`L107–L116`)

```odin
 107 | cursor_reload_slot :: proc(c: ^Write_Cursor) -> Error {
 108 | 	if (c.transaction != nil || c.db.tx_start != nil) && !is_root(c.slot_ptr) {  // <== [calls is_root]
 109 | 		if pos, ok := c.slot_ptr.position.?; ok {
 110 | 			core_seek_to(c.db.core, pos) or_return  // <== [calls core_seek_to]
 111 | 			slot := core_read_slot(c.db.core) or_return  // <== [calls core_read_slot]
 112 | 			c.slot_ptr = slot_pointer_with_slot(c.slot_ptr, slot)  // <== [calls slot_pointer_with_slot]
 113 | 		}
 114 | 	}
 115 | 	return nil
 116 | }
```

#### [`cursor_write_path`](../../xitdb/cursor.odin#L118-L174) — `DEPTH 1` (`L118–L174`)

```odin
 118 | cursor_write_path :: proc(c: ^Write_Cursor, path: []Path_Part) -> (res: Write_Cursor, err: Error) {
 119 | 	cursor_check_writable(c) or_return  // <== [calls cursor_check_writable]
 120 | 	if (c.db.transaction != nil || c.db.tx_start != nil) && is_root(c.slot_ptr) && len(path) > 0 {  // <== [calls is_root]
 121 | 		return {}, .Nested_Top_Level_Write
 122 | 	}
 123 | 
 124 | 	tx_stack: Transaction
 125 | 	starts_transaction := c.db.transaction == nil && is_root(c.slot_ptr)  // <== [calls is_root]
 126 | 	if starts_transaction {
 127 | 		c.db.transaction = &tx_stack
 128 | 	}
 129 | 	defer if starts_transaction {
 130 | 		c.db.transaction = nil
 131 | 	}
 132 | 
 133 | 	err = nil
 134 | 	switch c.slot_ptr.slot.tag {
 135 | 	case .Array_List, .Linked_Array_List, .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set, .Sorted_Map, .Sorted_Set:
 136 | 		is_init := false
 137 | 		if len(path) > 0 {
 138 | 			_, is_init = init_tag(path[0])  // <== [calls init_tag]
 139 | 		}
 140 | 		if is_init || (c.db.transaction != nil && (c.db.transaction.frozen_at != nil || c.frozen_at != 0)) {
 141 | 			err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 142 | 		}
 143 | 	case .None, .Index, .Bytes, .Short_Bytes, .Uint, .Int, .Float, .KV_Pair, .Sorted_KV_Pair:
 144 | 		err = cursor_reload_slot(c)  // <== [calls cursor_reload_slot]
 145 | 	}
 146 | 	slot_ptr: Slot_Pointer
 147 | 	if err == nil {
 148 | 		slot_ptr, err = read_slot_pointer(c.db, .Read_Write, path, 0, c.slot_ptr, c.frozen_at)  // <== [calls read_slot_pointer]
 149 | 	}
 150 | 	if err != nil {
 151 | 		if c.db.tx_start == nil {
 152 | 			_ = database_truncate(c.db)  // <== [calls database_truncate]
 153 | 		}
 154 | 		return {}, err
 155 | 	}
 156 | 	if c.db.tx_start == nil {
 157 | 		core_sync(c.db.core) or_return  // <== [calls core_sync]
 158 | 	}
 159 | 	ends_with_ctx := false
 160 | 	if len(path) > 0 {
 161 | 		_, ends_with_ctx = path[len(path) - 1].(Context)
 162 | 	}
 163 | 	res = new_write_cursor(slot_ptr, c.db)  // <== [calls new_write_cursor]
 164 | 	res.frozen_at = c.frozen_at
 165 | 	if ends_with_ctx {
 166 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 167 | 		cursor_reload_slot(&res) or_return  // <== [calls cursor_reload_slot]
 168 | 	} else if c.slot_ptr.position != nil && c.slot_ptr.position == slot_ptr.position {
 169 | 		c.slot_ptr = slot_ptr
 170 | 	} else if c.db.transaction == nil || c.db.transaction.frozen_at != nil || c.frozen_at != 0 || c.slot_ptr.slot.tag == .None {
 171 | 		cursor_reload_slot(c) or_return  // <== [calls cursor_reload_slot]
 172 | 	}
 173 | 	return res, nil
 174 | }
```

#### [`cursor_count`](../../xitdb/cursor.odin#L394-L432) — `DEPTH 1` (`L394–L432`)

```odin
 394 | cursor_count :: proc(c: Read_Cursor) -> (res: i64, err: Error) {
 395 | 	slot_ptr := cursor_resolved(c) or_return  // <== [calls cursor_resolved]
 396 | 	#partial switch slot_ptr.slot.tag {
 397 | 	case .None:
 398 | 		return 0, nil
 399 | 	case .Array_List:
 400 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 401 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 402 | 		core_read_exact(c.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 403 | 		header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 404 | 		return header.size, nil
 405 | 	case .Linked_Array_List, .Sorted_Map, .Sorted_Set:
 406 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 407 | 		hb: [BTREE_HEADER_LENGTH]u8
 408 | 		core_read_exact(c.db.core, hb[:]) or_return  // <== [calls core_read_exact]
 409 | 		header := btree_header_from_bytes(hb) or_return  // <== [calls btree_header_from_bytes]
 410 | 		return header.size, nil
 411 | 	case .Bytes:
 412 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 413 | 		return core_read_long(c.db.core)  // <== [calls core_read_long]
 414 | 	case .Short_Bytes:
 415 | 		buf: [8]u8
 416 | 		endian.unchecked_put_u64be(buf[:], u64(slot_ptr.slot.value))
 417 | 		total_size := 6 if slot_ptr.slot.full else 8
 418 | 		size := 0
 419 | 		for b in buf {
 420 | 			if b == 0 || size == total_size {
 421 | 				break
 422 | 			}
 423 | 			size += 1
 424 | 		}
 425 | 		return i64(size), nil
 426 | 	case .Counted_Hash_Map, .Counted_Hash_Set:
 427 | 		core_seek_to(c.db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
 428 | 		return core_read_long(c.db.core)  // <== [calls core_read_long]
 429 | 	case:
 430 | 		return 0, .Unexpected_Tag
 431 | 	}
 432 | }
```

### `xitdb/database.odin` (28 procedures · 748 lines: [`L13–L18`](../../xitdb/database.odin#L13-L18), [`L20–L25`](../../xitdb/database.odin#L20-L25), [`L237–L244`](../../xitdb/database.odin#L237-L244), [`L259–L266`](../../xitdb/database.odin#L259-L266), [`L268–L270`](../../xitdb/database.odin#L268-L270), [`L319–L334`](../../xitdb/database.odin#L319-L334), [`L343–L362`](../../xitdb/database.odin#L343-L362), [`L364–L368`](../../xitdb/database.odin#L364-L368), [`L370–L377`](../../xitdb/database.odin#L370-L377), [`L384–L398`](../../xitdb/database.odin#L384-L398), [`L400–L407`](../../xitdb/database.odin#L400-L407), [`L409–L414`](../../xitdb/database.odin#L409-L414), [`L416–L421`](../../xitdb/database.odin#L416-L421), [`L423–L438`](../../xitdb/database.odin#L423-L438), [`L440–L460`](../../xitdb/database.odin#L440-L460), [`L462–L468`](../../xitdb/database.odin#L462-L468), [`L470–L482`](../../xitdb/database.odin#L470-L482), [`L484–L489`](../../xitdb/database.odin#L484-L489), [`L491–L501`](../../xitdb/database.odin#L491-L501), [`L503–L515`](../../xitdb/database.odin#L503-L515), [`L517–L528`](../../xitdb/database.odin#L517-L528), [`L530–L535`](../../xitdb/database.odin#L530-L535), [`L552–L619`](../../xitdb/database.odin#L552-L619), [`L621–L1382`](../../xitdb/database.odin#L621-L1382), [`L1384–L1395`](../../xitdb/database.odin#L1384-L1395), [`L1397–L1450`](../../xitdb/database.odin#L1397-L1450), [`L1452–L1483`](../../xitdb/database.odin#L1452-L1483), [`L1485–L1533`](../../xitdb/database.odin#L1485-L1533))

#### [`transaction_is_root_position`](../../xitdb/database.odin#L13-L18) — `DEPTH 4` (`L13–L18`)

```odin
  13 | transaction_is_root_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  14 | 	if t == nil || pos == nil || t.root_position == nil {
  15 | 		return false
  16 | 	}
  17 | 	return pos.? == t.root_position.?
  18 | }
```

#### [`transaction_is_scratch_position`](../../xitdb/database.odin#L20-L25) — `DEPTH 4` (`L20–L25`)

```odin
  20 | transaction_is_scratch_position :: proc(t: ^Transaction, pos: Maybe(i64)) -> bool {
  21 | 	if t == nil || pos == nil || t.scratch_position == nil {
  22 | 		return false
  23 | 	}
  24 | 	return pos.? == t.scratch_position.?
  25 | }
```

#### [`_random_u64`](../../xitdb/database.odin#L237-L244) — `DEPTH 3` (`L237–L244`)

```odin
 237 | @(private)
 238 | _random_u64 :: proc() -> u64 {
 239 | 	v := rand.uint64()
 240 | 	if v == 0 {
 241 | 		v = 1
 242 | 	}
 243 | 	return v
 244 | }
```

#### [`database_digest_buf`](../../xitdb/database.odin#L259-L266) — `DEPTH 2` (`L259–L266`)

```odin
 259 | database_digest_buf :: proc(db: ^Database, data: []u8, buf: []u8) -> []u8 {
 260 | 	hsize := int(db.header.hash_size)
 261 | 	out := buf[:hsize] if hsize <= len(buf) else make([]u8, hsize, context.temp_allocator)
 262 | 	if db.hasher.hash_proc != nil {
 263 | 		db.hasher.hash_proc(data, out, db.hasher.user_data)
 264 | 	}
 265 | 	return out
 266 | }
```

#### [`database_digest_string_buf`](../../xitdb/database.odin#L268-L270) — `DEPTH 1` (`L268–L270`)

```odin
 268 | database_digest_string_buf :: proc(db: ^Database, s: string, buf: []u8) -> []u8 {
 269 | 	return database_digest_buf(db, transmute([]u8)s, buf)  // <== [calls database_digest_buf]
 270 | }
```

#### [`_database_committed_size_with_header`](../../xitdb/database.odin#L319-L334) — `DEPTH 4` (`L319–L334`)

```odin
 319 | @(private)
 320 | _database_committed_size_with_header :: proc(db: ^Database, header: Root_Header) -> (committed_size: i64, file_size: i64, err: Error) {
 321 | 	minimum_size := i64(ROOT_HEADER_END + ROOT_TRAILER_LENGTH)
 322 | 	if header.file_size < minimum_size {
 323 | 		return 0, 0, .Invalid_Database
 324 | 	}
 325 | 	file_size = core_length(db.core) or_return  // <== [calls core_length]
 326 | 	if file_size < header.file_size {
 327 | 		return 0, 0, .Truncated_Database
 328 | 	}
 329 | 	trailer := database_read_root_trailer(db, header.file_size) or_return  // <== [calls database_read_root_trailer]
 330 | 	if trailer.root != header.root {
 331 | 		return 0, 0, .Invalid_Database
 332 | 	}
 333 | 	return header.file_size, file_size, nil
 334 | }
```

#### [`_database_truncate_with_header`](../../xitdb/database.odin#L343-L362) — `DEPTH 3` (`L343–L362`)

```odin
 343 | @(private)
 344 | _database_truncate_with_header :: proc(db: ^Database, header: Root_Header) -> (final_size: i64, err: Error) {
 345 | 	committed_size, file_size := _database_committed_size_with_header(db, header) or_return  // <== [calls _database_committed_size_with_header]
 346 | 	active := db.transaction
 347 | 	if active != nil {
 348 | 		if fa, ok := active.frozen_at.?; ok && fa > committed_size {
 349 | 			if file_size > fa {
 350 | 				core_set_length(db.core, fa) or_return  // <== [calls core_set_length]
 351 | 			}
 352 | 			commit_id := _random_u64()  // <== [calls _random_u64]
 353 | 			database_commit_root(db, header.root, commit_id) or_return  // <== [calls database_commit_root]
 354 | 			core_sync(db.core) or_return  // <== [calls core_sync]
 355 | 			return core_length(db.core)  // <== [calls core_length]
 356 | 		}
 357 | 	}
 358 | 	if file_size > committed_size {
 359 | 		core_set_length(db.core, committed_size) or_return  // <== [calls core_set_length]
 360 | 	}
 361 | 	return committed_size, nil
 362 | }
```

#### [`database_truncate`](../../xitdb/database.odin#L364-L368) — `DEPTH 2` (`L364–L368`)

```odin
 364 | database_truncate :: proc(db: ^Database) -> Error {
 365 | 	header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 366 | 	_, err := _database_truncate_with_header(db, header)  // <== [calls _database_truncate_with_header]
 367 | 	return err
 368 | }
```

#### [`database_read_root_header`](../../xitdb/database.odin#L370-L377) — `DEPTH 2` (`L370–L377`)

```odin
 370 | database_read_root_header :: proc(db: ^Database) -> (res: Root_Header, err: Error) {
 371 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 372 | 	b: [ROOT_HEADER_LENGTH]u8
 373 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 374 | 	header := root_header_from_bytes(b)  // <== [calls root_header_from_bytes]
 375 | 	tag_validate(header.root.tag) or_return  // <== [calls tag_validate]
 376 | 	return header, nil
 377 | }
```

#### [`database_read_root_trailer`](../../xitdb/database.odin#L384-L398) — `DEPTH 5` (`L384–L398`)

```odin
 384 | database_read_root_trailer :: proc(db: ^Database, end: i64) -> (res: Root_Trailer, err: Error) {
 385 | 	if end < ROOT_TRAILER_LENGTH {
 386 | 		return {}, .Invalid_Database
 387 | 	}
 388 | 	trailer_pos := end - ROOT_TRAILER_LENGTH
 389 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 390 | 	b: [ROOT_TRAILER_LENGTH]u8
 391 | 	core_read_exact(db.core, b[:]) or_return  // <== [calls core_read_exact]
 392 | 	trailer := root_trailer_from_bytes(b)  // <== [calls root_trailer_from_bytes]
 393 | 	if trailer.checksum != compute_root_trailer_checksum(db.header.file_id, trailer_pos, trailer.root, trailer.commit_id) {  // <== [calls compute_root_trailer_checksum]
 394 | 		return {}, .Invalid_Database
 395 | 	}
 396 | 	tag_validate(trailer.root.tag) or_return  // <== [calls tag_validate]
 397 | 	return trailer, nil
 398 | }
```

#### [`database_commit_root`](../../xitdb/database.odin#L400-L407) — `DEPTH 3` (`L400–L407`)

```odin
 400 | database_commit_root :: proc(db: ^Database, root: Slot, commit_id: u64) -> Error {
 401 | 	trailer_pos := core_length(db.core) or_return  // <== [calls core_length]
 402 | 	core_seek_to(db.core, trailer_pos) or_return  // <== [calls core_seek_to]
 403 | 	trailer := root_trailer_to_bytes(new_root_trailer(db.header.file_id, trailer_pos, root, commit_id))  // <== [calls root_trailer_to_bytes, new_root_trailer]
 404 | 	core_write_all(db.core, trailer[:]) or_return  // <== [calls core_write_all]
 405 | 	core_sync(db.core) or_return  // <== [calls core_sync]
 406 | 	return database_write_root_header(db, root)  // <== [calls database_write_root_header]
 407 | }
```

#### [`database_write_root_header`](../../xitdb/database.odin#L409-L414) — `DEPTH 4` (`L409–L414`)

```odin
 409 | database_write_root_header :: proc(db: ^Database, root: Slot) -> Error {
 410 | 	file_size := core_length(db.core) or_return  // <== [calls core_length]
 411 | 	core_seek_to(db.core, ROOT_HEADER_START) or_return  // <== [calls core_seek_to]
 412 | 	header := root_header_to_bytes(Root_Header{file_size = file_size, root = root})  // <== [calls root_header_to_bytes]
 413 | 	return core_write_all(db.core, header[:])  // <== [calls core_write_all]
 414 | }
```

#### [`is_root`](../../xitdb/database.odin#L416-L421) — `DEPTH 2` (`L416–L421`)

```odin
 416 | is_root :: proc(slot_ptr: Slot_Pointer) -> bool {
 417 | 	if pos, ok := slot_ptr.position.?; ok {
 418 | 		return pos == ROOT_HEADER_START
 419 | 	}
 420 | 	return false
 421 | }
```

#### [`init_tag`](../../xitdb/database.odin#L423-L438) — `DEPTH 2` (`L423–L438`)

```odin
 423 | init_tag :: proc(part: Path_Part) -> (res: Tag, err: bool) {
 424 | 	#partial switch p in part {
 425 | 	case Array_List_Init:
 426 | 		return .Array_List, true
 427 | 	case Linked_Array_List_Init:
 428 | 		return .Linked_Array_List, true
 429 | 	case Hash_Map_Init:
 430 | 		if p.counted {
 431 | 			return (.Counted_Hash_Set if p.set else .Counted_Hash_Map), true
 432 | 		}
 433 | 		return (.Hash_Set if p.set else .Hash_Map), true
 434 | 	case Sorted_Map_Init:
 435 | 		return (.Sorted_Set if p.set else .Sorted_Map), true
 436 | 	}
 437 | 	return .None, false
 438 | }
```

#### [`init_part_for`](../../xitdb/database.odin#L440-L460) — `DEPTH 3` (`L440–L460`)

```odin
 440 | init_part_for :: proc(tag: Tag) -> (res: Path_Part, err: bool) {
 441 | 	#partial switch tag {
 442 | 	case .Array_List:
 443 | 		return Array_List_Init{}, true
 444 | 	case .Linked_Array_List:
 445 | 		return Linked_Array_List_Init{}, true
 446 | 	case .Hash_Map:
 447 | 		return Hash_Map_Init{counted = false, set = false}, true
 448 | 	case .Hash_Set:
 449 | 		return Hash_Map_Init{counted = false, set = true}, true
 450 | 	case .Counted_Hash_Map:
 451 | 		return Hash_Map_Init{counted = true, set = false}, true
 452 | 	case .Counted_Hash_Set:
 453 | 		return Hash_Map_Init{counted = true, set = true}, true
 454 | 	case .Sorted_Map:
 455 | 		return Sorted_Map_Init{set = false}, true
 456 | 	case .Sorted_Set:
 457 | 		return Sorted_Map_Init{set = true}, true
 458 | 	}
 459 | 	return nil, false
 460 | }
```

#### [`database_is_old`](../../xitdb/database.odin#L462-L468) — `DEPTH 4` (`L462–L468`)

```odin
 462 | database_is_old :: proc(db: ^Database, ptr, frozen_at: i64) -> (res: bool, err: Error) {
 463 | 	tx_s, ok := db.tx_start.?
 464 | 	if !ok {
 465 | 		return false, .Expected_Tx_Start
 466 | 	}
 467 | 	return ptr < max(tx_s, frozen_at), nil
 468 | }
```

#### [`database_copy_index_block_if_old`](../../xitdb/database.odin#L470-L482) — `DEPTH 5` (`L470–L482`)

```odin
 470 | database_copy_index_block_if_old :: proc(db: ^Database, ptr, frozen_at: i64) -> (res: i64, err: Error) {
 471 | 	old := database_is_old(db, ptr, frozen_at) or_return  // <== [calls database_is_old]
 472 | 	if !old {
 473 | 		return ptr, nil
 474 | 	}
 475 | 	index_block: [INDEX_BLOCK_SIZE]u8
 476 | 	core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
 477 | 	core_read_exact(db.core, index_block[:]) or_return  // <== [calls core_read_exact]
 478 | 	next_ptr := core_length(db.core) or_return  // <== [calls core_length]
 479 | 	core_seek_to(db.core, next_ptr) or_return  // <== [calls core_seek_to]
 480 | 	core_write_all(db.core, index_block[:]) or_return  // <== [calls core_write_all]
 481 | 	return next_ptr, nil
 482 | }
```

#### [`database_check_hash`](../../xitdb/database.odin#L484-L489) — `DEPTH 5` (`L484–L489`)

```odin
 484 | database_check_hash :: proc(db: ^Database, h: []u8) -> (res: []u8, err: Error) {
 485 | 	if len(h) != int(db.header.hash_size) {
 486 | 		return nil, .Invalid_Hash_Size
 487 | 	}
 488 | 	return h, nil
 489 | }
```

#### [`database_check_hash_target`](../../xitdb/database.odin#L491-L501) — `DEPTH 4` (`L491–L501`)

```odin
 491 | database_check_hash_target :: proc(db: ^Database, target: Hash_Map_Get_Target) -> (res: []u8, err: Error) {
 492 | 	switch t in target {
 493 | 	case Hash_Map_Get_Value:
 494 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 495 | 	case Hash_Map_Get_Key:
 496 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 497 | 	case Hash_Map_Get_KV_Pair:
 498 | 		return database_check_hash(db, t.hash)  // <== [calls database_check_hash]
 499 | 	}
 500 | 	return nil, .Invalid_Hash_Size
 501 | }
```

#### [`database_check_frozen_slot`](../../xitdb/database.odin#L503-L515) — `DEPTH 3` (`L503–L515`)

```odin
 503 | database_check_frozen_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer) -> Error {
 504 | 	active := db.transaction
 505 | 	if active != nil {
 506 | 		if fa, ok := active.frozen_at.?; ok {
 507 | 			if pos, pok := slot_ptr.position.?; pok {
 508 | 				if pos < fa && !transaction_is_root_position(active, slot_ptr.position) {  // <== [calls transaction_is_root_position]
 509 | 					return .Frozen_Slot
 510 | 				}
 511 | 			}
 512 | 		}
 513 | 	}
 514 | 	return nil
 515 | }
```

#### [`database_copy_collection_if_frozen`](../../xitdb/database.odin#L517-L528) — `DEPTH 4` (`L517–L528`)

```odin
 517 | database_copy_collection_if_frozen :: proc(db: ^Database, slot_ptr: Slot_Pointer, init_part: Path_Part, frozen_at: i64) -> (res: Slot_Pointer, err: Error) {
 518 | 	if db.transaction != nil {
 519 | 		fa := frozen_at
 520 | 		if tfa, ok := db.transaction.frozen_at.?; ok && tfa > fa {
 521 | 			fa = tfa
 522 | 		}
 523 | 		if fa > 0 && slot_ptr.slot.value < fa {
 524 | 			return read_slot_pointer(db, .Read_Write, []Path_Part{init_part}, 0, slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 525 | 		}
 526 | 	}
 527 | 	return slot_ptr, nil
 528 | }
```

#### [`database_kv_key_offset`](../../xitdb/database.odin#L530-L535) — `DEPTH 4` (`L530–L535`)

```odin
 530 | database_kv_key_offset :: proc(db: ^Database, tag: Tag) -> i64 {
 531 | 	if tag == .KV_Pair {
 532 | 		return i64(db.header.hash_size)
 533 | 	}
 534 | 	return 0
 535 | }
```

#### [`read_slot_pointer`](../../xitdb/database.odin#L552-L619) — `DEPTH 2` (`L552–L619`)

```odin
 552 | read_slot_pointer :: proc(
 553 | 	db: ^Database,
 554 | 	write_mode: Write_Mode,
 555 | 	path: []Path_Part,
 556 | 	path_i: int,
 557 | 	slot_ptr: Slot_Pointer,
 558 | 	frozen_at: i64,
 559 | ) -> (res: Slot_Pointer, err: Error) {
 560 | 	if path_i == len(path) {
 561 | 		if write_mode == .Read_Only && slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
 562 | 			return {}, .Key_Not_Found
 563 | 		}
 564 | 		return slot_ptr, nil
 565 | 	}
 566 | 	if write_mode == .Read_Write {
 567 | 		database_check_frozen_slot(db, slot_ptr) or_return  // <== [calls database_check_frozen_slot]
 568 | 	}
 569 | 	part := path[path_i]
 570 | 
 571 | 	// Every write that starts at the root is a transaction.
 572 | 	if is_root(slot_ptr) {  // <== [calls is_root]
 573 | 		root_header := database_read_root_header(db) or_return  // <== [calls database_read_root_header]
 574 | 		root := root_header.root
 575 | 
 576 | 		if write_mode == .Read_Only {
 577 | 			return read_slot_pointer(db, write_mode, path, path_i, Slot_Pointer{position = nil, slot = root}, frozen_at)
 578 | 		}
 579 | 
 580 | 		// Initializing an already-initialized root is free.
 581 | 		if len(path) - path_i == 1 && root.tag != .None {
 582 | 			if tag, ok := init_tag(part); ok && tag == root.tag {  // <== [calls init_tag]
 583 | 				_ = _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 584 | 				return Slot_Pointer{position = i64(ROOT_HEADER_START), slot = root}, nil
 585 | 			}
 586 | 		}
 587 | 
 588 | 		scratch_pos := _database_truncate_with_header(db, root_header) or_return  // <== [calls _database_truncate_with_header]
 589 | 		db.tx_start = scratch_pos
 590 | 		defer db.tx_start = nil
 591 | 
 592 | 		if db.transaction != nil {
 593 | 			db.transaction.root_position = scratch_pos
 594 | 			db.transaction.scratch_position = scratch_pos
 595 | 		}
 596 | 
 597 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 598 | 		core_write_slot(db.core, root) or_return  // <== [calls core_write_slot]
 599 | 		root_ptr := Slot_Pointer{position = scratch_pos, slot = root}
 600 | 
 601 | 		if init_p, ok := init_part_for(root.tag); ok {  // <== [calls init_part_for]
 602 | 			root_ptr = read_slot_pointer(db, write_mode, []Path_Part{init_p}, 0, root_ptr, frozen_at) or_return
 603 | 		}
 604 | 
 605 | 		result := read_slot_pointer(db, write_mode, path, path_i, root_ptr, frozen_at) or_return
 606 | 
 607 | 		core_seek_to(db.core, scratch_pos) or_return  // <== [calls core_seek_to]
 608 | 		next_root := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 609 | 		commit_id := _random_u64()  // <== [calls _random_u64]
 610 | 		database_commit_root(db, next_root, commit_id) or_return  // <== [calls database_commit_root]
 611 | 
 612 | 		if rpos, ok := result.position.?; ok && rpos == scratch_pos {
 613 | 			result = Slot_Pointer{position = i64(ROOT_HEADER_START), slot = next_root}
 614 | 		}
 615 | 		return result, nil
 616 | 	}
 617 | 
 618 | 	return _exec_path_part(db, part, write_mode, path, path_i, slot_ptr, frozen_at)  // <== [calls _exec_path_part]
 619 | }
```

#### [`_exec_path_part`](../../xitdb/database.odin#L621-L1382) — `DEPTH 3` (`L621–L1382`) — Active `Path_Part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Hash_Map_Init`, `Hash_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`

```odin
 621 | @(private)
 622 | _exec_path_part :: proc(
 623 | 	db: ^Database,
 624 | 	part: Path_Part,
 625 | 	write_mode: Write_Mode,
 626 | 	path: []Path_Part,
 627 | 	path_i: int,
 628 | 	slot_ptr: Slot_Pointer,
 629 | 	frozen_at: i64,
 630 | ) -> (res: Slot_Pointer, err: Error) {
 631 | 	slot_ptr := slot_ptr
 632 | 
 633 | 	switch p in part {
 634 | 	case Array_List_Init:
 635 | 		if write_mode == .Read_Only {
 636 | 			return {}, .Write_Not_Allowed
 637 | 		}
 638 | 		position, pos_ok := slot_ptr.position.?
 639 | 		if !pos_ok {
 640 | 			return {}, .Cursor_Not_Writeable
 641 | 		}
 642 | 		#partial switch slot_ptr.slot.tag {
 643 | 		case .None:
 644 | 			array_list_start := core_length(db.core) or_return  // <== [calls core_length]
 645 | 			core_seek_to(db.core, array_list_start) or_return  // <== [calls core_seek_to]
 646 | 			array_list_ptr := array_list_start + ARRAY_LIST_HEADER_LENGTH
 647 | 			al_header := array_list_header_to_bytes(Array_List_Header{ptr = array_list_ptr, size = 0})  // <== [calls array_list_header_to_bytes]
 648 | 			core_write_all(db.core, al_header[:]) or_return  // <== [calls core_write_all]
 649 | 			empty_block: [INDEX_BLOCK_SIZE]u8
 650 | 			core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
 651 | 			next_slot_ptr := Slot_Pointer{
 652 | 				position = position,
 653 | 				slot     = Slot{value = array_list_start, tag = .Array_List},
 654 | 			}
 655 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 656 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 657 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 658 | 
 659 | 		case .Array_List:
 660 | 			array_list_start := slot_ptr.slot.value
 661 | 			old := database_is_old(db, array_list_start, frozen_at) or_return  // <== [calls database_is_old]
 662 | 			if old {
 663 | 				core_seek_to(db.core, array_list_start) or_return  // <== [calls core_seek_to]
 664 | 				hb: [ARRAY_LIST_HEADER_LENGTH]u8
 665 | 				core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 666 | 				header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 667 | 				core_seek_to(db.core, header.ptr) or_return  // <== [calls core_seek_to]
 668 | 				idx_block: [INDEX_BLOCK_SIZE]u8
 669 | 				core_read_exact(db.core, idx_block[:]) or_return  // <== [calls core_read_exact]
 670 | 				new_start := core_length(db.core) or_return  // <== [calls core_length]
 671 | 				core_seek_to(db.core, new_start) or_return  // <== [calls core_seek_to]
 672 | 				next_ptr := new_start + ARRAY_LIST_HEADER_LENGTH
 673 | 				header = array_list_header_with_ptr(header, next_ptr)  // <== [calls array_list_header_with_ptr]
 674 | 				nhb := array_list_header_to_bytes(header)  // <== [calls array_list_header_to_bytes]
 675 | 				core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 676 | 				core_write_all(db.core, idx_block[:]) or_return  // <== [calls core_write_all]
 677 | 				array_list_start = new_start
 678 | 			}
 679 | 			next_slot_ptr := Slot_Pointer{
 680 | 				position = position,
 681 | 				slot     = Slot{value = array_list_start, tag = .Array_List},
 682 | 			}
 683 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
 684 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
 685 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
 686 | 
 687 | 		case:
 688 | 			return {}, .Unexpected_Tag
 689 | 		}
   ... | 	// ... [lines 690–690: untouched Path_Part arms omitted] ...
 691 | 	case Array_List_Get:
 692 | 		#partial switch slot_ptr.slot.tag {
 693 | 		case .None:
 694 | 			return {}, .Key_Not_Found
 695 | 		case .Array_List:
 696 | 		case:
 697 | 			return {}, .Unexpected_Tag
 698 | 		}
 699 | 		if write_mode == .Read_Write {
 700 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 701 | 		}
 702 | 		next_array_list_start := slot_ptr.slot.value
 703 | 		index := p.index
 704 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 705 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 706 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 707 | 		header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 708 | 		if index >= header.size || index < -header.size {
 709 | 			return {}, .Key_Not_Found
 710 | 		}
 711 | 		key := (header.size + index) if index < 0 else index
 712 | 		shift := radix_shift(header.size - 1)  // <== [calls radix_shift]
 713 | 		final_slot_ptr := read_array_list_slot(db, header.ptr, key, shift, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot]
 714 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, final_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 715–715: untouched Path_Part arms omitted] ...
 716 | 	case Array_List_Append:
 717 | 		if write_mode == .Read_Only {
 718 | 			return {}, .Write_Not_Allowed
 719 | 		}
 720 | 		if slot_ptr.slot.tag != .Array_List {
 721 | 			return {}, .Unexpected_Tag
 722 | 		}
 723 | 		slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Array_List_Init{}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
 724 | 		next_array_list_start := slot_ptr.slot.value
 725 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 726 | 		hb: [ARRAY_LIST_HEADER_LENGTH]u8
 727 | 		core_read_exact(db.core, hb[:]) or_return  // <== [calls core_read_exact]
 728 | 		orig_header := array_list_header_from_bytes(hb) or_return  // <== [calls array_list_header_from_bytes]
 729 | 		append_res := read_array_list_slot_append(db, orig_header, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot_append]
 730 | 		core_seek_to(db.core, next_array_list_start) or_return  // <== [calls core_seek_to]
 731 | 		nhb := array_list_header_to_bytes(append_res.header)  // <== [calls array_list_header_to_bytes]
 732 | 		core_write_all(db.core, nhb[:]) or_return  // <== [calls core_write_all]
 733 | 		if db.transaction != nil && transaction_is_scratch_position(db.transaction, slot_ptr.position) {  // <== [calls transaction_is_scratch_position]
 734 | 			db.transaction.root_position = append_res.slot_ptr.position
 735 | 		}
 736 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, append_res.slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 737–983: untouched Path_Part arms omitted] ...
 984 | 	case Hash_Map_Init:
 985 | 		if write_mode == .Read_Only {
 986 | 			return {}, .Write_Not_Allowed
 987 | 		}
 988 | 		tag: Tag
 989 | 		if p.counted {
 990 | 			tag = .Counted_Hash_Set if p.set else .Counted_Hash_Map
 991 | 		} else {
 992 | 			tag = .Hash_Set if p.set else .Hash_Map
 993 | 		}
 994 | 		position, pos_ok := slot_ptr.position.?
 995 | 		if !pos_ok {
 996 | 			return {}, .Cursor_Not_Writeable
 997 | 		}
 998 | 		#partial switch slot_ptr.slot.tag {
 999 | 		case .None:
1000 | 			map_start := core_length(db.core) or_return  // <== [calls core_length]
1001 | 			core_seek_to(db.core, map_start) or_return  // <== [calls core_seek_to]
1002 | 			if p.counted {
1003 | 				core_write_long(db.core, 0) or_return  // <== [calls core_write_long]
1004 | 			}
1005 | 			empty_block: [INDEX_BLOCK_SIZE]u8
1006 | 			core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
1007 | 			next_slot_ptr := Slot_Pointer{
1008 | 				position = position,
1009 | 				slot     = Slot{value = map_start, tag = tag},
1010 | 			}
1011 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1012 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1013 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1014 | 
1015 | 		case .Hash_Map, .Hash_Set, .Counted_Hash_Map, .Counted_Hash_Set:
1016 | 			if p.counted {
1017 | 				#partial switch slot_ptr.slot.tag {
1018 | 				case .Counted_Hash_Map, .Counted_Hash_Set:
1019 | 				case:
1020 | 					return {}, .Unexpected_Tag
1021 | 				}
1022 | 			} else {
1023 | 				#partial switch slot_ptr.slot.tag {
1024 | 				case .Hash_Map, .Hash_Set:
1025 | 				case:
1026 | 					return {}, .Unexpected_Tag
1027 | 				}
1028 | 			}
1029 | 			map_start := slot_ptr.slot.value
1030 | 			old := database_is_old(db, map_start, frozen_at) or_return  // <== [calls database_is_old]
1031 | 			if old {
1032 | 				core_seek_to(db.core, map_start) or_return  // <== [calls core_seek_to]
1033 | 				map_count: i64 = 0
1034 | 				if p.counted {
1035 | 					map_count = core_read_long(db.core) or_return  // <== [calls core_read_long]
1036 | 				}
1037 | 				idx_block: [INDEX_BLOCK_SIZE]u8
1038 | 				core_read_exact(db.core, idx_block[:]) or_return  // <== [calls core_read_exact]
1039 | 				new_start := core_length(db.core) or_return  // <== [calls core_length]
1040 | 				core_seek_to(db.core, new_start) or_return  // <== [calls core_seek_to]
1041 | 				if p.counted {
1042 | 					core_write_long(db.core, map_count) or_return  // <== [calls core_write_long]
1043 | 				}
1044 | 				core_write_all(db.core, idx_block[:]) or_return  // <== [calls core_write_all]
1045 | 				map_start = new_start
1046 | 			}
1047 | 			next_slot_ptr := Slot_Pointer{
1048 | 				position = position,
1049 | 				slot     = Slot{value = map_start, tag = tag},
1050 | 			}
1051 | 			core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1052 | 			core_write_slot(db.core, next_slot_ptr.slot) or_return  // <== [calls core_write_slot]
1053 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1054 | 
1055 | 		case:
1056 | 			return {}, .Unexpected_Tag
1057 | 		}
   ... | 	// ... [lines 1058–1058: untouched Path_Part arms omitted] ...
1059 | 	case Hash_Map_Get:
1060 | 		counted := false
1061 | 		#partial switch slot_ptr.slot.tag {
1062 | 		case .None:
1063 | 			return {}, .Key_Not_Found
1064 | 		case .Hash_Map, .Hash_Set:
1065 | 		case .Counted_Hash_Map, .Counted_Hash_Set:
1066 | 			counted = true
1067 | 		case:
1068 | 			return {}, .Unexpected_Tag
1069 | 		}
1070 | 		if write_mode == .Read_Write {
1071 | 			is_set := slot_ptr.slot.tag == .Hash_Set || slot_ptr.slot.tag == .Counted_Hash_Set
1072 | 			slot_ptr = database_copy_collection_if_frozen(db, slot_ptr, Hash_Map_Init{counted = counted, set = is_set}, frozen_at) or_return  // <== [calls database_copy_collection_if_frozen]
1073 | 		}
1074 | 		index_pos := (slot_ptr.slot.value + 8) if counted else slot_ptr.slot.value
1075 | 		key_hash := database_check_hash_target(db, p.target) or_return  // <== [calls database_check_hash_target]
1076 | 		res := read_map_slot(db, index_pos, key_hash, 0, write_mode, p.target, frozen_at) or_return  // <== [calls read_map_slot]
1077 | 		if write_mode == .Read_Write && counted && res.is_empty {
1078 | 			core_seek_to(db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
1079 | 			map_count := core_read_long(db.core) or_return  // <== [calls core_read_long]
1080 | 			core_seek_to(db.core, slot_ptr.slot.value) or_return  // <== [calls core_seek_to]
1081 | 			core_write_long(db.core, map_count + 1) or_return  // <== [calls core_write_long]
1082 | 		}
1083 | 		next_sp := res.slot_ptr
1084 | 		if write_mode == .Read_Write && res.is_empty && next_sp.slot.tag == .KV_Pair {
1085 | 			next_sp.slot.full = true
1086 | 		}
1087 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, next_sp, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1088–1284: untouched Path_Part arms omitted] ...
1285 | 	case Write_Data:
1286 | 		if write_mode == .Read_Only {
1287 | 			return {}, .Write_Not_Allowed
1288 | 		}
1289 | 		position, pos_ok := slot_ptr.position.?
1290 | 		if !pos_ok {
1291 | 			return {}, .Cursor_Not_Writeable
1292 | 		}
1293 | 		if p.if_empty && !slot_empty(slot_ptr.slot) {  // <== [calls slot_empty]
1294 | 			return read_slot_pointer(db, write_mode, path, path_i + 1, slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
1295 | 		}
1296 | 
1297 | 		slot := _encode_writeable_data(db, slot_ptr, p.data) or_return  // <== [calls _encode_writeable_data]
1298 | 
1299 | 		core_seek_to(db.core, position) or_return  // <== [calls core_seek_to]
1300 | 		core_write_slot(db.core, slot) or_return  // <== [calls core_write_slot]
1301 | 		next_slot_ptr := Slot_Pointer{position = slot_ptr.position, slot = slot}
1302 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, next_slot_ptr, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1303–1303: untouched Path_Part arms omitted] ...
1304 | 	case Write_KV_Data:
1305 | 		if write_mode == .Read_Only {
1306 | 			return {}, .Write_Not_Allowed
1307 | 		}
1308 | 		kv_pos := slot_ptr.slot.value
1309 | 		key_slot_pos := kv_pos + database_kv_key_offset(db, slot_ptr.slot.tag)  // <== [calls database_kv_key_offset]
1310 | 		val_slot_pos := key_slot_pos + SLOT_LENGTH
1311 | 
1312 | 		if slot_ptr.slot.full {
1313 | 			if val_slot, val_inline, val_err := _try_encode_inline_data(p.value); val_err != nil {  // <== [calls _try_encode_inline_data]
1314 | 				return {}, val_err
1315 | 			} else if val_inline {
1316 | 				if key_bytes, is_kbytes := _extract_bytes_data(p.key); is_kbytes && !bytes_is_short(key_bytes) {  // <== [calls _extract_bytes_data, bytes_is_short]
1317 | 					if key_bytes.format_tag != nil && len(key_bytes.format_tag) != 2 {
1318 | 						return {}, .Invalid_Format_Tag_Size
1319 | 					}
1320 | 					if db.tx_start == nil {
1321 | 						return {}, .Expected_Tx_Start
1322 | 					}
1323 | 					cur_len := core_length(db.core) or_return  // <== [calls core_length]
1324 | 					has_ft := key_bytes.format_tag != nil
1325 | 					key_payload_len := 8 + len(key_bytes.value) + (2 if has_ft else 0)
1326 | 					if cur_len == val_slot_pos + SLOT_LENGTH && key_payload_len <= 238 {
1327 | 						key_slot := Slot{value = cur_len, tag = .Bytes, full = has_ft}
1328 | 						combined_buf: [256]u8 = ---
1329 | 						out_kb := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1330 | 						out_vb := slot_to_bytes(val_slot)  // <== [calls slot_to_bytes]
1331 | 						copy(combined_buf[0:SLOT_LENGTH], out_kb[:])
1332 | 						copy(combined_buf[SLOT_LENGTH : SLOT_LENGTH * 2], out_vb[:])
1333 | 						endian.unchecked_put_u64be(combined_buf[18:26], u64(len(key_bytes.value)))
1334 | 						copy(combined_buf[26 : 26 + len(key_bytes.value)], key_bytes.value)
1335 | 						if has_ft {
1336 | 							copy(combined_buf[26 + len(key_bytes.value) : 18 + key_payload_len], key_bytes.format_tag)
1337 | 						}
1338 | 						core_seek_to(db.core, key_slot_pos) or_return  // <== [calls core_seek_to]
1339 | 						core_write_all(db.core, combined_buf[:18 + key_payload_len]) or_return  // <== [calls core_write_all]
1340 | 						clean_sp := Slot_Pointer{position = slot_ptr.position, slot = slot_with_full(slot_ptr.slot, false)}  // <== [calls slot_with_full]
1341 | 						return read_slot_pointer(db, write_mode, path, path_i + 1, clean_sp, frozen_at)  // <== [calls read_slot_pointer]
1342 | 					}
1343 | 				}
1344 | 			}
1345 | 			key_slot := _encode_writeable_data(db, Slot_Pointer{position = key_slot_pos, slot = Slot{}}, p.key) or_return  // <== [calls _encode_writeable_data]
1346 | 			val_slot := _encode_writeable_data(db, Slot_Pointer{position = val_slot_pos, slot = Slot{}}, p.value) or_return  // <== [calls _encode_writeable_data]
1347 | 			slots_buf: [SLOT_LENGTH * 2]u8 = ---
1348 | 			out_kb := slot_to_bytes(key_slot)  // <== [calls slot_to_bytes]
1349 | 			out_vb := slot_to_bytes(val_slot)  // <== [calls slot_to_bytes]
1350 | 			copy(slots_buf[:SLOT_LENGTH], out_kb[:])
1351 | 			copy(slots_buf[SLOT_LENGTH:], out_vb[:])
1352 | 			core_seek_to(db.core, key_slot_pos) or_return  // <== [calls core_seek_to]
1353 | 			core_write_all(db.core, slots_buf[:]) or_return  // <== [calls core_write_all]
1354 | 		} else {
1355 | 			val_slot := _encode_writeable_data(db, Slot_Pointer{position = val_slot_pos, slot = Slot{}}, p.value) or_return  // <== [calls _encode_writeable_data]
1356 | 			core_seek_to(db.core, val_slot_pos) or_return  // <== [calls core_seek_to]
1357 | 			core_write_slot(db.core, val_slot) or_return  // <== [calls core_write_slot]
1358 | 		}
1359 | 		clean_sp := Slot_Pointer{position = slot_ptr.position, slot = slot_with_full(slot_ptr.slot, false)}  // <== [calls slot_with_full]
1360 | 		return read_slot_pointer(db, write_mode, path, path_i + 1, clean_sp, frozen_at)  // <== [calls read_slot_pointer]
   ... | 	// ... [lines 1361–1361: untouched Path_Part arms omitted] ...
1362 | 	case Context:
1363 | 		if write_mode == .Read_Only {
1364 | 			return {}, .Write_Not_Allowed
1365 | 		}
1366 | 		if path_i != len(path) - 1 {
1367 | 			return {}, .Path_Part_Must_Be_At_End
1368 | 		}
1369 | 		clean_sp := slot_ptr
1370 | 		if clean_sp.slot.tag == .KV_Pair && clean_sp.slot.full {
1371 | 			clean_sp.slot.full = false
1372 | 		}
1373 | 		next_cursor := new_write_cursor(clean_sp, db)  // <== [calls new_write_cursor]
1374 | 		next_cursor.frozen_at = frozen_at
1375 | 		if p.function != nil {
1376 | 			p.function(&next_cursor, p.user_data) or_return
1377 | 		}
1378 | 		return next_cursor.slot_ptr, nil
1379 | 	}
1380 | 
1381 | 	return {}, .Unreachable
1382 | }
```

#### [`_extract_bytes_data`](../../xitdb/database.odin#L1384-L1395) — `DEPTH 4` (`L1384–L1395`)

```odin
1384 | @(private)
1385 | _extract_bytes_data :: #force_inline proc(write_data: Writeable_Data) -> (b: Bytes, ok: bool) {
1386 | 	#partial switch data in write_data {
1387 | 	case string:
1388 | 		return Bytes{value = transmute([]u8)data}, true
1389 | 	case []u8:
1390 | 		return Bytes{value = data}, true
1391 | 	case Bytes:
1392 | 		return data, true
1393 | 	}
1394 | 	return {}, false
1395 | }
```

#### [`_try_encode_inline_data`](../../xitdb/database.odin#L1397-L1450) — `DEPTH 4` (`L1397–L1450`)

```odin
1397 | @(private)
1398 | _try_encode_inline_data :: #force_inline proc(write_data: Writeable_Data) -> (slot: Slot, is_inline: bool, err: Error) {
1399 | 	switch data in write_data {
1400 | 	case nil:
1401 | 		return Slot{full = true}, true, nil
1402 | 	case Slot:
1403 | 		if data.tag == .None {
1404 | 			return slot_with_full(data, true), true, nil  // <== [calls slot_with_full]
1405 | 		}
1406 | 		return data, true, nil
1407 | 	case Uint:
1408 | 		return Slot{value = i64(data.value), tag = .Uint}, true, nil
1409 | 	case u64:
1410 | 		return Slot{value = i64(data), tag = .Uint}, true, nil
1411 | 	case Int:
1412 | 		return Slot{value = data.value, tag = .Int}, true, nil
1413 | 	case i64:
1414 | 		return Slot{value = data, tag = .Int}, true, nil
1415 | 	case Float:
1416 | 		return Slot{value = transmute(i64)data.value, tag = .Float}, true, nil
1417 | 	case f64:
1418 | 		return Slot{value = transmute(i64)data, tag = .Float}, true, nil
1419 | 	case string:
1420 | 		b := Bytes{value = transmute([]u8)data}
1421 | 		if bytes_is_short(b) {  // <== [calls bytes_is_short]
1422 | 			buf: [8]u8
1423 | 			copy(buf[:], b.value)
1424 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes}, true, nil
1425 | 		}
1426 | 		return {}, false, nil
1427 | 	case []u8:
1428 | 		b := Bytes{value = data}
1429 | 		if bytes_is_short(b) {  // <== [calls bytes_is_short]
1430 | 			buf: [8]u8
1431 | 			copy(buf[:], b.value)
1432 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes}, true, nil
1433 | 		}
1434 | 		return {}, false, nil
1435 | 	case Bytes:
1436 | 		if data.format_tag != nil && len(data.format_tag) != 2 {
1437 | 			return {}, false, .Invalid_Format_Tag_Size
1438 | 		}
1439 | 		if bytes_is_short(data) {  // <== [calls bytes_is_short]
1440 | 			buf: [8]u8
1441 | 			copy(buf[:], data.value)
1442 | 			if data.format_tag != nil {
1443 | 				copy(buf[6:8], data.format_tag)
1444 | 			}
1445 | 			return Slot{value = i64(endian.unchecked_get_u64be(buf[:])), tag = .Short_Bytes, full = data.format_tag != nil}, true, nil
1446 | 		}
1447 | 		return {}, false, nil
1448 | 	}
1449 | 	return {}, false, nil
1450 | }
```

#### [`_encode_writeable_data`](../../xitdb/database.odin#L1452-L1483) — `DEPTH 4` (`L1452–L1483`)

```odin
1452 | @(private)
1453 | _encode_writeable_data :: proc(db: ^Database, slot_ptr: Slot_Pointer, write_data: Writeable_Data) -> (slot: Slot, err: Error) {
1454 | 	switch data in write_data {
1455 | 	case nil:
1456 | 		slot = Slot{}
1457 | 	case Slot:
1458 | 		slot = data
1459 | 	case Uint:
1460 | 		slot = Slot{value = i64(data.value), tag = .Uint}
1461 | 	case u64:
1462 | 		slot = Slot{value = i64(data), tag = .Uint}
1463 | 	case Int:
1464 | 		slot = Slot{value = data.value, tag = .Int}
1465 | 	case i64:
1466 | 		slot = Slot{value = data, tag = .Int}
1467 | 	case Float:
1468 | 		slot = Slot{value = transmute(i64)data.value, tag = .Float}
1469 | 	case f64:
1470 | 		slot = Slot{value = transmute(i64)data, tag = .Float}
1471 | 	case string:
1472 | 		slot = _encode_bytes_slot(db, slot_ptr, Bytes{value = transmute([]u8)data}) or_return  // <== [calls _encode_bytes_slot]
1473 | 	case []u8:
1474 | 		slot = _encode_bytes_slot(db, slot_ptr, Bytes{value = data}) or_return  // <== [calls _encode_bytes_slot]
1475 | 	case Bytes:
1476 | 		slot = _encode_bytes_slot(db, slot_ptr, data) or_return  // <== [calls _encode_bytes_slot]
1477 | 	}
1478 | 
1479 | 	if slot.tag == .None {
1480 | 		slot = slot_with_full(slot, true)  // <== [calls slot_with_full]
1481 | 	}
1482 | 	return slot, nil
1483 | }
```

#### [`_encode_bytes_slot`](../../xitdb/database.odin#L1485-L1533) — `DEPTH 5` (`L1485–L1533`)

```odin
1485 | @(private)
1486 | _encode_bytes_slot :: proc(db: ^Database, slot_ptr: Slot_Pointer, data: Bytes) -> (res: Slot, err: Error) {
1487 | 	if data.format_tag != nil && len(data.format_tag) != 2 {
1488 | 		return {}, .Invalid_Format_Tag_Size
1489 | 	}
1490 | 	if bytes_is_short(data) {  // <== [calls bytes_is_short]
1491 | 		buf: [8]u8
1492 | 		copy(buf[:], data.value)
1493 | 		if data.format_tag != nil {
1494 | 			copy(buf[6:8], data.format_tag)
1495 | 		}
1496 | 		uval := endian.unchecked_get_u64be(buf[:])
1497 | 		return Slot{
1498 | 			value = i64(uval),
1499 | 			tag   = .Short_Bytes,
1500 | 			full  = data.format_tag != nil,
1501 | 		}, nil
1502 | 	}
1503 | 	if is_root(slot_ptr) {  // <== [calls is_root]
1504 | 		return {}, .Cursor_Not_Writeable
1505 | 	}
1506 | 	if db.tx_start == nil {
1507 | 		return {}, .Expected_Tx_Start
1508 | 	}
1509 | 	ptr_pos := core_length(db.core) or_return  // <== [calls core_length]
1510 | 	core_seek_to(db.core, ptr_pos) or_return  // <== [calls core_seek_to]
1511 | 	has_ft := data.format_tag != nil
1512 | 	total_len := 8 + len(data.value) + (2 if has_ft else 0)
1513 | 	if total_len <= 256 {
1514 | 		buf: [256]u8 = ---
1515 | 		endian.unchecked_put_u64be(buf[0:8], u64(len(data.value)))
1516 | 		copy(buf[8 : 8 + len(data.value)], data.value)
1517 | 		if has_ft {
1518 | 			copy(buf[8 + len(data.value) : total_len], data.format_tag)
1519 | 		}
1520 | 		core_write_all(db.core, buf[:total_len]) or_return  // <== [calls core_write_all]
1521 | 	} else {
1522 | 		core_write_long(db.core, i64(len(data.value))) or_return  // <== [calls core_write_long]
1523 | 		core_write_all(db.core, data.value) or_return  // <== [calls core_write_all]
1524 | 		if has_ft {
1525 | 			core_write_all(db.core, data.format_tag) or_return  // <== [calls core_write_all]
1526 | 		}
1527 | 	}
1528 | 	return Slot{
1529 | 		value = ptr_pos,
1530 | 		tag   = .Bytes,
1531 | 		full  = has_ft,
1532 | 	}, nil
1533 | }
```

### `xitdb/hamt.odin` (3 procedures · 333 lines: [`L15–L240`](../../xitdb/hamt.odin#L15-L240), [`L345–L383`](../../xitdb/hamt.odin#L345-L383), [`L385–L452`](../../xitdb/hamt.odin#L385-L452))

#### [`read_map_slot`](../../xitdb/hamt.odin#L15-L240) — `DEPTH 4` (`L15–L240`)

```odin
  15 | read_map_slot :: proc(
  16 | 	db: ^Database,
  17 | 	index_pos: i64,
  18 | 	key_hash: []u8,
  19 | 	key_offset: u8,
  20 | 	write_mode: Write_Mode,
  21 | 	target: Hash_Map_Get_Target,
  22 | 	frozen_at: i64,
  23 | ) -> (res: Hash_Map_Get_Result, err: Error) {
  24 | 	index_pos := index_pos
  25 | 	key_offset := key_offset
  26 | 	max_offset := (int(db.header.hash_size) * 8) / BIT_COUNT
  27 | 
  28 | 	for {
  29 | 		if int(key_offset) > max_offset {
  30 | 			return {}, .Key_Offset_Exceeded
  31 | 		}
  32 | 
  33 | 		i := hamt_nibble(key_hash, key_offset)  // <== [calls hamt_nibble]
  34 | 		slot_pos := index_pos + i64(SLOT_LENGTH * i)
  35 | 		core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  36 | 		slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
  37 | 		ptr := slot.value
  38 | 
  39 | 		#partial switch slot.tag {
  40 | 		case .None:
  41 | 			switch write_mode {
  42 | 			case .Read_Only:
  43 | 				return {}, .Key_Not_Found
  44 | 			case .Read_Write:
  45 | 				hash_pos := core_length(db.core) or_return  // <== [calls core_length]
  46 | 				core_seek_to(db.core, hash_pos) or_return  // <== [calls core_seek_to]
  47 | 				key_slot_pos := hash_pos + i64(db.header.hash_size)
  48 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
  49 | 				kv_pair := Key_Value_Pair{value_slot = Slot{}, key_slot = Slot{}, hash = key_hash}
  50 | 				kv_pair_write(kv_pair, db.core) or_return  // <== [calls kv_pair_write]
  51 | 
  52 | 				next_slot := Slot{value = hash_pos, tag = .KV_Pair}
  53 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  54 | 				core_write_slot(db.core, next_slot) or_return  // <== [calls core_write_slot]
  55 | 
  56 | 				next_slot_ptr: Slot_Pointer
  57 | 				switch _ in target {
  58 | 				case Hash_Map_Get_KV_Pair:
  59 | 					next_slot_ptr = Slot_Pointer{position = slot_pos, slot = next_slot}
  60 | 				case Hash_Map_Get_Key:
  61 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
  62 | 				case Hash_Map_Get_Value:
  63 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
  64 | 				}
  65 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = true}, nil
  66 | 			}
  67 | 
  68 | 		case .Index:
  69 | 			next_ptr := ptr
  70 | 			if write_mode == .Read_Write {
  71 | 				next_ptr = database_copy_index_block_if_old(db, ptr, frozen_at) or_return  // <== [calls database_copy_index_block_if_old]
  72 | 				if next_ptr != ptr {
  73 | 					core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
  74 | 					core_write_slot(db.core, Slot{value = next_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
  75 | 				}
  76 | 			}
  77 | 			index_pos = next_ptr
  78 | 			key_offset += 1
  79 | 			continue
  80 | 
  81 | 		case .KV_Pair:
  82 | 			hash_size := int(db.header.hash_size)
  83 | 			kv_len := hash_size + SLOT_LENGTH * 2
  84 | 			stack_hash: [64]u8 = ---
  85 | 			kv_pair: Key_Value_Pair
  86 | 			hash_matches: bool
  87 | 
  88 | 			if kv_slice, in_mem, slice_err := core_slice_at(db.core, ptr, kv_len); in_mem {  // <== [calls core_slice_at]
  89 | 				if slice_err != nil {
  90 | 					return {}, slice_err
  91 | 				}
  92 | 				key_slot := slot_from_slice_raw(kv_slice[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
  93 | 				tag_validate(key_slot.tag) or_return  // <== [calls tag_validate]
  94 | 				val_slot := slot_from_slice_raw(kv_slice[hash_size + SLOT_LENGTH : kv_len])  // <== [calls slot_from_slice_raw]
  95 | 				tag_validate(val_slot.tag) or_return  // <== [calls tag_validate]
  96 | 				hash_matches = bytes.equal(kv_slice[:hash_size], key_hash)
  97 | 				if hash_matches && write_mode == .Read_Only {
  98 | 					key_slot_pos := ptr + i64(hash_size)
  99 | 					value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 100 | 					next_slot_ptr: Slot_Pointer
 101 | 					switch _ in target {
 102 | 					case Hash_Map_Get_KV_Pair:
 103 | 						next_slot_ptr = Slot_Pointer{position = slot_pos, slot = slot}
 104 | 					case Hash_Map_Get_Key:
 105 | 						next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = key_slot}
 106 | 					case Hash_Map_Get_Value:
 107 | 						next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = val_slot}
 108 | 					}
 109 | 					return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 110 | 				}
 111 | 				if !hash_matches && write_mode == .Read_Only {
 112 | 					return {}, .Key_Not_Found
 113 | 				}
 114 | 				hash_buf := stack_hash[:hash_size] if hash_size <= len(stack_hash) else make([]u8, hash_size, context.temp_allocator)
 115 | 				copy(hash_buf, kv_slice[:hash_size])
 116 | 				kv_pair = Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = hash_buf}
 117 | 			} else {
 118 | 				core_seek_to(db.core, ptr) or_return  // <== [calls core_seek_to]
 119 | 				hash_buf := stack_hash[:hash_size] if hash_size <= len(stack_hash) else make([]u8, hash_size, context.temp_allocator)
 120 | 				kv_pair = kv_pair_read_buf(db.core, hash_buf) or_return  // <== [calls kv_pair_read_buf]
 121 | 				hash_matches = bytes.equal(kv_pair.hash, key_hash)
 122 | 			}
 123 | 
 124 | 			if hash_matches {
 125 | 				if write_mode == .Read_Write {
 126 | 					old := database_is_old(db, ptr, frozen_at) or_return  // <== [calls database_is_old]
 127 | 					if old {
 128 | 						hash_pos := core_length(db.core) or_return  // <== [calls core_length]
 129 | 						core_seek_to(db.core, hash_pos) or_return  // <== [calls core_seek_to]
 130 | 						key_slot_pos := hash_pos + i64(hash_size)
 131 | 						value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 132 | 						kv_pair_write(kv_pair, db.core) or_return  // <== [calls kv_pair_write]
 133 | 
 134 | 						next_slot := Slot{value = hash_pos, tag = .KV_Pair}
 135 | 						core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 136 | 						core_write_slot(db.core, next_slot) or_return  // <== [calls core_write_slot]
 137 | 
 138 | 						next_slot_ptr: Slot_Pointer
 139 | 						switch _ in target {
 140 | 						case Hash_Map_Get_KV_Pair:
 141 | 							next_slot_ptr = Slot_Pointer{position = slot_pos, slot = next_slot}
 142 | 						case Hash_Map_Get_Key:
 143 | 							next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
 144 | 						case Hash_Map_Get_Value:
 145 | 							next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
 146 | 						}
 147 | 						return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 148 | 					}
 149 | 				}
 150 | 
 151 | 				key_slot_pos := ptr + i64(hash_size)
 152 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 153 | 				next_slot_ptr: Slot_Pointer
 154 | 				switch _ in target {
 155 | 				case Hash_Map_Get_KV_Pair:
 156 | 					next_slot_ptr = Slot_Pointer{position = slot_pos, slot = slot}
 157 | 				case Hash_Map_Get_Key:
 158 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = kv_pair.key_slot}
 159 | 				case Hash_Map_Get_Value:
 160 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = kv_pair.value_slot}
 161 | 				}
 162 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = false}, nil
 163 | 			}
 164 | 
 165 | 			// Hash collision - different keys
 166 | 			switch write_mode {
 167 | 			case .Read_Only:
 168 | 				return {}, .Key_Not_Found
 169 | 			case .Read_Write:
 170 | 				diff_offset := int(key_offset) + 1
 171 | 				for diff_offset < max_offset {
 172 | 					if hamt_nibble(kv_pair.hash, u8(diff_offset)) != hamt_nibble(key_hash, u8(diff_offset)) {  // <== [calls hamt_nibble]
 173 | 						break
 174 | 					}
 175 | 					diff_offset += 1
 176 | 				}
 177 | 				if diff_offset >= max_offset {
 178 | 					return {}, .Key_Offset_Exceeded
 179 | 				}
 180 | 
 181 | 				first_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 182 | 				core_seek_to(db.core, first_index_pos) or_return  // <== [calls core_seek_to]
 183 | 				cur_index_pos := first_index_pos
 184 | 
 185 | 				for off in int(key_offset) + 1 ..< diff_offset {
 186 | 					nib := hamt_nibble(key_hash, u8(off))  // <== [calls hamt_nibble]
 187 | 					child_index_pos := cur_index_pos + INDEX_BLOCK_SIZE
 188 | 					mid_block: [INDEX_BLOCK_SIZE]u8
 189 | 					sb := slot_to_bytes(Slot{value = child_index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 190 | 					copy(mid_block[SLOT_LENGTH * nib : SLOT_LENGTH * (nib + 1)], sb[:])
 191 | 					core_write_all(db.core, mid_block[:]) or_return  // <== [calls core_write_all]
 192 | 					cur_index_pos = child_index_pos
 193 | 				}
 194 | 
 195 | 				next_i := hamt_nibble(kv_pair.hash, u8(diff_offset))  // <== [calls hamt_nibble]
 196 | 				new_i := hamt_nibble(key_hash, u8(diff_offset))  // <== [calls hamt_nibble]
 197 | 				hash_pos := cur_index_pos + INDEX_BLOCK_SIZE
 198 | 				next_slot := Slot{value = hash_pos, tag = .KV_Pair}
 199 | 				key_slot_pos := hash_pos + i64(hash_size)
 200 | 				value_slot_pos := key_slot_pos + i64(SLOT_LENGTH)
 201 | 
 202 | 				if hash_size <= 64 {
 203 | 					combined: [INDEX_BLOCK_SIZE + 64 + SLOT_LENGTH * 2]u8
 204 | 					sb_old := slot_to_bytes(slot)  // <== [calls slot_to_bytes]
 205 | 					sb_new := slot_to_bytes(next_slot)  // <== [calls slot_to_bytes]
 206 | 					copy(combined[SLOT_LENGTH * next_i : SLOT_LENGTH * (next_i + 1)], sb_old[:])
 207 | 					copy(combined[SLOT_LENGTH * new_i : SLOT_LENGTH * (new_i + 1)], sb_new[:])
 208 | 					copy(combined[INDEX_BLOCK_SIZE : INDEX_BLOCK_SIZE + hash_size], key_hash)
 209 | 					core_write_all(db.core, combined[:INDEX_BLOCK_SIZE + kv_len]) or_return  // <== [calls core_write_all]
 210 | 				} else {
 211 | 					new_block: [INDEX_BLOCK_SIZE]u8
 212 | 					sb_old := slot_to_bytes(slot)  // <== [calls slot_to_bytes]
 213 | 					sb_new := slot_to_bytes(next_slot)  // <== [calls slot_to_bytes]
 214 | 					copy(new_block[SLOT_LENGTH * next_i : SLOT_LENGTH * (next_i + 1)], sb_old[:])
 215 | 					copy(new_block[SLOT_LENGTH * new_i : SLOT_LENGTH * (new_i + 1)], sb_new[:])
 216 | 					core_write_all(db.core, new_block[:]) or_return  // <== [calls core_write_all]
 217 | 					new_kv := Key_Value_Pair{value_slot = Slot{}, key_slot = Slot{}, hash = key_hash}
 218 | 					kv_pair_write(new_kv, db.core) or_return  // <== [calls kv_pair_write]
 219 | 				}
 220 | 
 221 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 222 | 				core_write_slot(db.core, Slot{value = first_index_pos, tag = .Index}) or_return  // <== [calls core_write_slot]
 223 | 
 224 | 				next_slot_ptr: Slot_Pointer
 225 | 				switch _ in target {
 226 | 				case Hash_Map_Get_KV_Pair:
 227 | 					next_slot_ptr = Slot_Pointer{position = cur_index_pos + i64(SLOT_LENGTH * new_i), slot = next_slot}
 228 | 				case Hash_Map_Get_Key:
 229 | 					next_slot_ptr = Slot_Pointer{position = key_slot_pos, slot = Slot{}}
 230 | 				case Hash_Map_Get_Value:
 231 | 					next_slot_ptr = Slot_Pointer{position = value_slot_pos, slot = Slot{}}
 232 | 				}
 233 | 				return Hash_Map_Get_Result{slot_ptr = next_slot_ptr, is_empty = true}, nil
 234 | 			}
 235 | 
 236 | 		case:
 237 | 			return {}, .Unexpected_Tag
 238 | 		}
 239 | 	}
 240 | }
```

#### [`read_array_list_slot_append`](../../xitdb/hamt.odin#L345-L383) — `DEPTH 4` (`L345–L383`)

```odin
 345 | read_array_list_slot_append :: proc(
 346 | 	db: ^Database,
 347 | 	header: Array_List_Header,
 348 | 	write_mode: Write_Mode,
 349 | 	frozen_at: i64,
 350 | ) -> (res: Array_List_Append_Result, err: Error) {
 351 | 	index_pos := header.ptr
 352 | 	key := header.size
 353 | 
 354 | 	prev_shift := radix_shift(key - 1)  // <== [calls radix_shift]
 355 | 	next_shift := radix_shift(key)  // <== [calls radix_shift]
 356 | 
 357 | 	if prev_shift != next_shift {
 358 | 		// Root overflow
 359 | 		next_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 360 | 		core_seek_to(db.core, next_index_pos) or_return  // <== [calls core_seek_to]
 361 | 		new_block: [INDEX_BLOCK_SIZE]u8
 362 | 		sb := slot_to_bytes(Slot{value = index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 363 | 		copy(new_block[:SLOT_LENGTH], sb[:])
 364 | 		core_write_all(db.core, new_block[:]) or_return  // <== [calls core_write_all]
 365 | 		index_pos = next_index_pos
 366 | 	}
 367 | 
 368 | 	slot_ptr := read_array_list_slot(db, index_pos, key, next_shift, write_mode, frozen_at) or_return  // <== [calls read_array_list_slot]
 369 | 	pos, pos_ok := slot_ptr.position.?
 370 | 	if !pos_ok {
 371 | 		return {}, .Cursor_Not_Writeable
 372 | 	}
 373 | 	// Clear values left by a rollback or slice
 374 | 	if slot_ptr.slot != (Slot{}) {
 375 | 		slot_ptr = slot_pointer_with_slot(slot_ptr, Slot{})  // <== [calls slot_pointer_with_slot]
 376 | 		core_seek_to(db.core, pos) or_return  // <== [calls core_seek_to]
 377 | 		core_write_slot(db.core, slot_ptr.slot) or_return  // <== [calls core_write_slot]
 378 | 	}
 379 | 	return Array_List_Append_Result{
 380 | 		header   = Array_List_Header{ptr = index_pos, size = header.size + 1},
 381 | 		slot_ptr = slot_ptr,
 382 | 	}, nil
 383 | }
```

#### [`read_array_list_slot`](../../xitdb/hamt.odin#L385-L452) — `DEPTH 4` (`L385–L452`)

```odin
 385 | read_array_list_slot :: proc(
 386 | 	db: ^Database,
 387 | 	index_pos: i64,
 388 | 	key: i64,
 389 | 	shift: u8,
 390 | 	write_mode: Write_Mode,
 391 | 	frozen_at: i64,
 392 | ) -> (res: Slot_Pointer, err: Error) {
 393 | 	if shift >= MAX_BRANCH_LENGTH {
 394 | 		return {}, .Max_Shift_Exceeded
 395 | 	}
 396 | 
 397 | 	index_pos := index_pos
 398 | 	shift := shift
 399 | 	for {
 400 | 		i := (key >> (u64(shift) * BIT_COUNT)) & i64(MASK)
 401 | 		slot_pos := index_pos + i64(SLOT_LENGTH) * i
 402 | 		core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 403 | 		slot := core_read_slot_raw(db.core) or_return  // <== [calls core_read_slot_raw]
 404 | 
 405 | 		if shift == 0 {
 406 | 			return Slot_Pointer{position = slot_pos, slot = slot}, nil
 407 | 		}
 408 | 
 409 | 		ptr := slot.value
 410 | 
 411 | 		#partial switch slot.tag {
 412 | 		case .None:
 413 | 			switch write_mode {
 414 | 			case .Read_Only:
 415 | 				return {}, .Key_Not_Found
 416 | 			case .Read_Write:
 417 | 				first_index_pos := core_length(db.core) or_return  // <== [calls core_length]
 418 | 				core_seek_to(db.core, first_index_pos) or_return  // <== [calls core_seek_to]
 419 | 				cur_index_pos := first_index_pos
 420 | 				for s := shift - 1; s > 0; s -= 1 {
 421 | 					child_i := (key >> (u64(s) * BIT_COUNT)) & i64(MASK)
 422 | 					child_index_pos := cur_index_pos + INDEX_BLOCK_SIZE
 423 | 					mid_block: [INDEX_BLOCK_SIZE]u8
 424 | 					sb := slot_to_bytes(Slot{value = child_index_pos, tag = .Index})  // <== [calls slot_to_bytes]
 425 | 					copy(mid_block[int(child_i) * SLOT_LENGTH : (int(child_i) + 1) * SLOT_LENGTH], sb[:])
 426 | 					core_write_all(db.core, mid_block[:]) or_return  // <== [calls core_write_all]
 427 | 					cur_index_pos = child_index_pos
 428 | 				}
 429 | 				empty_block: [INDEX_BLOCK_SIZE]u8
 430 | 				core_write_all(db.core, empty_block[:]) or_return  // <== [calls core_write_all]
 431 | 				core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 432 | 				core_write_slot(db.core, Slot{value = first_index_pos, tag = .Index}) or_return  // <== [calls core_write_slot]
 433 | 				leaf_i := key & i64(MASK)
 434 | 				return Slot_Pointer{position = cur_index_pos + i64(SLOT_LENGTH) * leaf_i, slot = Slot{}}, nil
 435 | 			}
 436 | 		case .Index:
 437 | 			next_ptr := ptr
 438 | 			if write_mode == .Read_Write {
 439 | 				next_ptr = database_copy_index_block_if_old(db, ptr, frozen_at) or_return  // <== [calls database_copy_index_block_if_old]
 440 | 				if next_ptr != ptr {
 441 | 					core_seek_to(db.core, slot_pos) or_return  // <== [calls core_seek_to]
 442 | 					core_write_slot(db.core, Slot{value = next_ptr, tag = .Index}) or_return  // <== [calls core_write_slot]
 443 | 				}
 444 | 			}
 445 | 			index_pos = next_ptr
 446 | 			shift -= 1
 447 | 			continue
 448 | 		case:
 449 | 			return {}, .Unexpected_Tag
 450 | 		}
 451 | 	}
 452 | }
```

### `xitdb/types.odin` (24 procedures · 197 lines: [`L67–L72`](../../xitdb/types.odin#L67-L72), [`L855–L857`](../../xitdb/types.odin#L855-L857), [`L865–L869`](../../xitdb/types.odin#L865-L869), [`L871–L877`](../../xitdb/types.odin#L871-L877), [`L880–L890`](../../xitdb/types.odin#L880-L890), [`L892–L901`](../../xitdb/types.odin#L892-L901), [`L915–L917`](../../xitdb/types.odin#L915-L917), [`L985–L991`](../../xitdb/types.odin#L985-L991), [`L993–L1003`](../../xitdb/types.odin#L993-L1003), [`L1012–L1020`](../../xitdb/types.odin#L1012-L1020), [`L1022–L1028`](../../xitdb/types.odin#L1022-L1028), [`L1030–L1037`](../../xitdb/types.odin#L1030-L1037), [`L1039–L1051`](../../xitdb/types.odin#L1039-L1051), [`L1065–L1067`](../../xitdb/types.odin#L1065-L1067), [`L1069–L1074`](../../xitdb/types.odin#L1069-L1074), [`L1076–L1084`](../../xitdb/types.odin#L1076-L1084), [`L1099–L1107`](../../xitdb/types.odin#L1099-L1107), [`L1116–L1118`](../../xitdb/types.odin#L1116-L1118), [`L1141–L1143`](../../xitdb/types.odin#L1141-L1143), [`L1186–L1198`](../../xitdb/types.odin#L1186-L1198), [`L1200–L1226`](../../xitdb/types.odin#L1200-L1226), [`L1339–L1350`](../../xitdb/types.odin#L1339-L1350), [`L1408–L1413`](../../xitdb/types.odin#L1408-L1413), [`L1416–L1421`](../../xitdb/types.odin#L1416-L1421))

#### [`tag_validate`](../../xitdb/types.odin#L67-L72) — `DEPTH 3` (`L67–L72`)

```odin
  67 | tag_validate :: proc(t: Tag) -> Error {
  68 | 	if u8(t) > MAX_TAG_VALUE {
  69 | 		return .Unexpected_Tag
  70 | 	}
  71 | 	return nil
  72 | }
```

#### [`slot_empty`](../../xitdb/types.odin#L855-L857) — `DEPTH 2` (`L855–L857`)

```odin
 855 | slot_empty :: proc(s: Slot) -> bool {
 856 | 	return s.tag == .None && !s.full
 857 | }
```

#### [`slot_with_full`](../../xitdb/types.odin#L865-L869) — `DEPTH 4` (`L865–L869`)

```odin
 865 | slot_with_full :: proc(s: Slot, full: bool) -> Slot {
 866 | 	res := s
 867 | 	res.full = full
 868 | 	return res
 869 | }
```

#### [`slot_to_bytes`](../../xitdb/types.odin#L871-L877) — `DEPTH 4` (`L871–L877`)

```odin
 871 | slot_to_bytes :: #force_inline proc(s: Slot) -> [SLOT_LENGTH]u8 {
 872 | 	buf: [SLOT_LENGTH]u8 = ---
 873 | 	full_bit := u8(0x80) if s.full else u8(0)
 874 | 	buf[0] = full_bit | (u8(s.tag) & 0x7f)
 875 | 	endian.unchecked_put_u64be(buf[1:9], u64(s.value))
 876 | 	return buf
 877 | }
```

#### [`slot_from_bytes_raw`](../../xitdb/types.odin#L880-L890) — `DEPTH 4` (`L880–L890`)

```odin
 880 | slot_from_bytes_raw :: #force_inline proc(buf: [SLOT_LENGTH]u8) -> Slot {
 881 | 	b := buf
 882 | 	full := (b[0] & 0x80) != 0
 883 | 	raw_tag := b[0] & 0x7f
 884 | 	val := endian.unchecked_get_u64be(b[1:9])
 885 | 	return Slot{
 886 | 		value = i64(val),
 887 | 		tag   = Tag(raw_tag),
 888 | 		full  = full,
 889 | 	}
 890 | }
```

#### [`slot_from_slice_raw`](../../xitdb/types.odin#L892-L901) — `DEPTH 4` (`L892–L901`)

```odin
 892 | slot_from_slice_raw :: #force_inline proc(b: []u8) -> Slot #no_bounds_check {
 893 | 	full := (b[0] & 0x80) != 0
 894 | 	raw_tag := b[0] & 0x7f
 895 | 	val := endian.unchecked_get_u64be(b[1:9])
 896 | 	return Slot{
 897 | 		value = i64(val),
 898 | 		tag   = Tag(raw_tag),
 899 | 		full  = full,
 900 | 	}
 901 | }
```

#### [`slot_pointer_with_slot`](../../xitdb/types.odin#L915-L917) — `DEPTH 3` (`L915–L917`)

```odin
 915 | slot_pointer_with_slot :: proc(sp: Slot_Pointer, s: Slot) -> Slot_Pointer {
 916 | 	return Slot_Pointer{position = sp.position, slot = s}
 917 | }
```

#### [`root_header_to_bytes`](../../xitdb/types.odin#L985-L991) — `DEPTH 5` (`L985–L991`)

```odin
 985 | root_header_to_bytes :: proc(rh: Root_Header) -> [ROOT_HEADER_LENGTH]u8 {
 986 | 	buf: [ROOT_HEADER_LENGTH]u8
 987 | 	slot_bytes := slot_to_bytes(rh.root)  // <== [calls slot_to_bytes]
 988 | 	copy(buf[0:9], slot_bytes[:])
 989 | 	endian.put_u64(buf[9:17], .Big, u64(rh.file_size))
 990 | 	return buf
 991 | }
```

#### [`root_header_from_bytes`](../../xitdb/types.odin#L993-L1003) — `DEPTH 3` (`L993–L1003`)

```odin
 993 | root_header_from_bytes :: proc(buf: [ROOT_HEADER_LENGTH]u8) -> Root_Header {
 994 | 	b := buf
 995 | 	slot_buf: [SLOT_LENGTH]u8
 996 | 	copy(slot_buf[:], b[0:9])
 997 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
 998 | 	file_size, _ := endian.get_u64(b[9:17], .Big)
 999 | 	return Root_Header{
1000 | 		file_size = i64(file_size),
1001 | 		root      = root,
1002 | 	}
1003 | }
```

#### [`compute_root_trailer_checksum`](../../xitdb/types.odin#L1012-L1020) — `DEPTH 5` (`L1012–L1020`)

```odin
1012 | compute_root_trailer_checksum :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> u64 {
1013 | 	data: [33]u8
1014 | 	endian.put_u64(data[0:8], .Big, file_id)
1015 | 	endian.put_u64(data[8:16], .Big, u64(position))
1016 | 	slot_bytes := slot_to_bytes(root)  // <== [calls slot_to_bytes]
1017 | 	copy(data[16:25], slot_bytes[:])
1018 | 	endian.put_u64(data[25:33], .Big, commit_id)
1019 | 	return hash.crc64_xz(data[:])
1020 | }
```

#### [`new_root_trailer`](../../xitdb/types.odin#L1022-L1028) — `DEPTH 4` (`L1022–L1028`)

```odin
1022 | new_root_trailer :: proc(file_id: u64, position: i64, root: Slot, commit_id: u64) -> Root_Trailer {
1023 | 	return Root_Trailer{
1024 | 		checksum  = compute_root_trailer_checksum(file_id, position, root, commit_id),  // <== [calls compute_root_trailer_checksum]
1025 | 		commit_id = commit_id,
1026 | 		root      = root,
1027 | 	}
1028 | }
```

#### [`root_trailer_to_bytes`](../../xitdb/types.odin#L1030-L1037) — `DEPTH 4` (`L1030–L1037`)

```odin
1030 | root_trailer_to_bytes :: proc(rt: Root_Trailer) -> [ROOT_TRAILER_LENGTH]u8 {
1031 | 	buf: [ROOT_TRAILER_LENGTH]u8
1032 | 	slot_bytes := slot_to_bytes(rt.root)  // <== [calls slot_to_bytes]
1033 | 	copy(buf[0:9], slot_bytes[:])
1034 | 	endian.put_u64(buf[9:17], .Big, rt.commit_id)
1035 | 	endian.put_u64(buf[17:25], .Big, rt.checksum)
1036 | 	return buf
1037 | }
```

#### [`root_trailer_from_bytes`](../../xitdb/types.odin#L1039-L1051) — `DEPTH 6` (`L1039–L1051`)

```odin
1039 | root_trailer_from_bytes :: proc(buf: [ROOT_TRAILER_LENGTH]u8) -> Root_Trailer {
1040 | 	b := buf
1041 | 	slot_buf: [SLOT_LENGTH]u8
1042 | 	copy(slot_buf[:], b[0:9])
1043 | 	root := slot_from_bytes_raw(slot_buf)  // <== [calls slot_from_bytes_raw]
1044 | 	commit_id, _ := endian.get_u64(b[9:17], .Big)
1045 | 	checksum, _ := endian.get_u64(b[17:25], .Big)
1046 | 	return Root_Trailer{
1047 | 		checksum  = checksum,
1048 | 		commit_id = commit_id,
1049 | 		root      = root,
1050 | 	}
1051 | }
```

#### [`array_list_header_with_ptr`](../../xitdb/types.odin#L1065-L1067) — `DEPTH 4` (`L1065–L1067`)

```odin
1065 | array_list_header_with_ptr :: proc(h: Array_List_Header, ptr: i64) -> Array_List_Header {
1066 | 	return Array_List_Header{ptr = ptr, size = h.size}
1067 | }
```

#### [`array_list_header_to_bytes`](../../xitdb/types.odin#L1069-L1074) — `DEPTH 4` (`L1069–L1074`)

```odin
1069 | array_list_header_to_bytes :: #force_inline proc(h: Array_List_Header) -> [ARRAY_LIST_HEADER_LENGTH]u8 {
1070 | 	buf: [ARRAY_LIST_HEADER_LENGTH]u8 = ---
1071 | 	endian.unchecked_put_u64be(buf[0:8], u64(h.size))
1072 | 	endian.unchecked_put_u64be(buf[8:16], u64(h.ptr))
1073 | 	return buf
1074 | }
```

#### [`array_list_header_from_bytes`](../../xitdb/types.odin#L1076-L1084) — `DEPTH 2` (`L1076–L1084`)

```odin
1076 | array_list_header_from_bytes :: #force_inline proc(buf: [ARRAY_LIST_HEADER_LENGTH]u8) -> (res: Array_List_Header, err: Error) {
1077 | 	b := buf
1078 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1079 | 	ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1080 | 	if size < 0 || ptr < 0 {
1081 | 		return {}, .Expected_Unsigned_Long
1082 | 	}
1083 | 	return Array_List_Header{ptr = ptr, size = size}, nil
1084 | }
```

#### [`btree_header_from_bytes`](../../xitdb/types.odin#L1099-L1107) — `DEPTH 2` (`L1099–L1107`)

```odin
1099 | btree_header_from_bytes :: #force_inline proc(buf: [BTREE_HEADER_LENGTH]u8) -> (res: BTree_Header, err: Error) {
1100 | 	b := buf
1101 | 	size := i64(endian.unchecked_get_u64be(b[0:8]))
1102 | 	root_ptr := i64(endian.unchecked_get_u64be(b[8:16]))
1103 | 	if size < 0 || root_ptr < 0 {
1104 | 		return {}, .Expected_Unsigned_Long
1105 | 	}
1106 | 	return BTree_Header{root_ptr = root_ptr, size = size}, nil
1107 | }
```

#### [`kv_pair_length`](../../xitdb/types.odin#L1116-L1118) — `DEPTH 6` (`L1116–L1118`)

```odin
1116 | kv_pair_length :: proc(hash_size: int) -> int {
1117 | 	return hash_size + SLOT_LENGTH * 2
1118 | }
```

#### [`kv_pair_write`](../../xitdb/types.odin#L1141-L1143) — `DEPTH 5` (`L1141–L1143`)

```odin
1141 | kv_pair_write :: proc(kv: Key_Value_Pair, c: ^Core) -> Error {
1142 | 	return encode_kv_pair(c, .KV_Pair, kv)  // <== [calls encode_kv_pair]
1143 | }
```

#### [`kv_pair_read_buf`](../../xitdb/types.odin#L1186-L1198) — `DEPTH 5` (`L1186–L1198`)

```odin
1186 | kv_pair_read_buf :: proc(c: ^Core, hash_buf: []u8) -> (kv: Key_Value_Pair, err: Error) {
1187 | 	hash_size := len(hash_buf)
1188 | 	kv_len := kv_pair_length(hash_size)  // <== [calls kv_pair_length]
1189 | 	stack_buf: [128]u8 = ---
1190 | 	b := stack_buf[:kv_len] if kv_len <= len(stack_buf) else make([]u8, kv_len, context.temp_allocator)
1191 | 	core_read_exact(c, b) or_return  // <== [calls core_read_exact]
1192 | 	copy(hash_buf, b[:hash_size])
1193 | 	key_slot := slot_from_slice_raw(b[hash_size : hash_size + SLOT_LENGTH])  // <== [calls slot_from_slice_raw]
1194 | 	tag_validate(key_slot.tag) or_return  // <== [calls tag_validate]
1195 | 	val_slot := slot_from_slice_raw(b[hash_size + SLOT_LENGTH : hash_size + SLOT_LENGTH * 2])  // <== [calls slot_from_slice_raw]
1196 | 	tag_validate(val_slot.tag) or_return  // <== [calls tag_validate]
1197 | 	return Key_Value_Pair{value_slot = val_slot, key_slot = key_slot, hash = hash_buf}, nil
1198 | }
```

#### [`encode_kv_pair`](../../xitdb/types.odin#L1200-L1226) — `DEPTH 6` (`L1200–L1226`)

```odin
1200 | encode_kv_pair :: proc(c: ^Core, tag: Tag, kv: Key_Value_Pair) -> Error {
1201 | 	#partial switch tag {
1202 | 	case .KV_Pair:
1203 | 		kb := slot_to_bytes(kv.key_slot)  // <== [calls slot_to_bytes]
1204 | 		vb := slot_to_bytes(kv.value_slot)  // <== [calls slot_to_bytes]
1205 | 		total := len(kv.hash) + SLOT_LENGTH * 2
1206 | 		if total <= 128 {
1207 | 			buf: [128]u8 = ---
1208 | 			copy(buf[:len(kv.hash)], kv.hash)
1209 | 			copy(buf[len(kv.hash):len(kv.hash) + SLOT_LENGTH], kb[:])
1210 | 			copy(buf[len(kv.hash) + SLOT_LENGTH:total], vb[:])
1211 | 			return core_write_all(c, buf[:total])  // <== [calls core_write_all]
1212 | 		}
1213 | 		core_write_all(c, kv.hash) or_return  // <== [calls core_write_all]
1214 | 		core_write_all(c, kb[:]) or_return  // <== [calls core_write_all]
1215 | 		return core_write_all(c, vb[:])  // <== [calls core_write_all]
1216 | 	case .Sorted_KV_Pair:
1217 | 		buf: [SORTED_KEY_VALUE_LEN]u8 = ---
1218 | 		kb := slot_to_bytes(kv.key_slot)  // <== [calls slot_to_bytes]
1219 | 		vb := slot_to_bytes(kv.value_slot)  // <== [calls slot_to_bytes]
1220 | 		copy(buf[:SLOT_LENGTH], kb[:])
1221 | 		copy(buf[SLOT_LENGTH:], vb[:])
1222 | 		return core_write_all(c, buf[:])  // <== [calls core_write_all]
1223 | 	case:
1224 | 		return .Unexpected_Tag
1225 | 	}
1226 | }
```

#### [`bytes_is_short`](../../xitdb/types.odin#L1339-L1350) — `DEPTH 4` (`L1339–L1350`)

```odin
1339 | bytes_is_short :: proc(b: Bytes) -> bool {
1340 | 	total_size := 6 if b.format_tag != nil else 8
1341 | 	if len(b.value) > total_size {
1342 | 		return false
1343 | 	}
1344 | 	for ch in b.value {
1345 | 		if ch == 0 {
1346 | 			return false
1347 | 		}
1348 | 	}
1349 | 	return true
1350 | }
```

#### [`hamt_nibble`](../../xitdb/types.odin#L1408-L1413) — `DEPTH 5` (`L1408–L1413`)

```odin
1408 | hamt_nibble :: #force_inline proc(key_hash: []u8, key_offset: u8) -> int {
1409 | 	hash_size := len(key_hash)
1410 | 	byte_idx := hash_size - 1 - int(key_offset >> 1)
1411 | 	shift := (key_offset & 1) << 2
1412 | 	return int((key_hash[byte_idx] >> shift) & 0x0F)
1413 | }
```

#### [`radix_shift`](../../xitdb/types.odin#L1416-L1421) — `DEPTH 4` (`L1416–L1421`)

```odin
1416 | radix_shift :: #force_inline proc(key: i64) -> u8 {
1417 | 	if key < SLOT_COUNT {
1418 | 		return 0
1419 | 	}
1420 | 	return u8((63 - intrinsics.count_leading_zeros(u64(key))) >> 2)
1421 | }
```

