# #24. `Linked_Array_List (B-Tree) middle remove` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) · [Odin Harness (`bench_xitdb.odin#L1020-L1039`)](../bench_xitdb.odin#L1020-L1039) · [Zig Harness (`bench_xitdb.zig#L1045-L1066`)](../bench_xitdb.zig#L1045-L1066)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **338** | 342.0 ± 8.2 | 2.4% | 353.0 | 2,958,580 | - | **5.89x Odin** (`z = 101.2`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 1,990 | 1,980.2 ± 35.3 | 1.8% | 2,015.0 | 502,513 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 02: LinkedArrayList Batch Node I/O & Direct Leaf Seek**](../zig-guide/02_btree_node_batch_io_and_leaf_seek.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Read Block Serialization vs. 18–34 Per-Field `std.Io` Calls ([`xitdb/btree.odin#L8-L75`](../../xitdb/btree.odin#L8-L75) vs. [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** This is the primary driver of Odin's **4.6x–44.9x speedup** on `Linked_Array_List` (`BTREE_SLOT_COUNT = 16`: `146B` leaf, `274B` branch). Zig's `readBTreeNode` and `writeBTreeNodeAt` loop over all 16 slots (and 16 counts on branches) unconditionally, issuing **18 to 34 individual unbuffered `takeInt`/`writeInt` calls** per node even when `node.num == 2`. Odin reads the node in **one `core_read_exact` call** into a stack buffer and decodes only `0 ..< node.num` active entries.
- **O(1) Direct Leaf Slot Seek in `read_btree_slot` ([`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181)):** On `#21 Linked_Array_List random get` (**44.06x faster in Odin: 53 ns vs 2,335 ns**), when `read_btree_slot` reaches a `.Leaf`, Odin peeks the 2-byte header and reads **only the single 9-byte `Slot`** at `node_ptr + 2 + rem * 9`. Zig's [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) calls `readBTreeNode` at the leaf, executing 18 `takeInt` calls and 16 tag checks to decode all 16 slots just to return `node.values[rem]`.
- **Targeted In-Place Branch Count Patching ([`xitdb/btree.odin#L224-L260`](../../xitdb/btree.odin#L224-L260)):** When inserting into a branch node already owned by the current transaction (`btree_reusable` is true and no child split occurred), Odin patches only the 8-byte `counts[i]` (and 9-byte `children[i]` if relocated) instead of rewriting all 274 bytes.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Read/Write `BTreeNode` via a stack `[146]u8` / `[274]u8` buffer (`~25 lines` in [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** Read the node in one `reader.interface.readSliceAll` (and write in one `writer.interface.writeAll(&buf)`), decoding `0..node.num` in memory with `std.mem.readInt`. This keeps the `BTreeNode` struct and all split/join/rebalance logic 100% unchanged while eliminating 18–34 vtable/syscall dispatches per node.
- **Short-circuit `.leaf` in `readBTreeSlot` (`~8 lines` in [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042)):** Read the 2-byte `(kind, num)` header first; when `kind == .leaf`, seek directly to `node_ptr + 2 + rem * 9` and read 1 `Slot`.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L1020-L1039`](../bench_xitdb.odin#L1020-L1039))

```odin
1020 | 		remove_mid_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
1021 | 			c := (^Mid_Ctx)(user_data)
1022 | 			list := xitdb.write_linked_array_list_init(cursor^) or_return
1023 | 			for _ in 0 ..< c.ops {
1024 | 				cnt, _ := xitdb.linked_array_list_count(list)
1025 | 				xitdb.linked_array_list_remove(&list, cnt / 2) or_return
1026 | 			}
1027 | 			return nil
1028 | 		}
1029 | 
1030 | 		m1_slot, _ := xitdb.array_list_get_slot(history, 1)
1031 | 		t4 := time.now()
1032 | 		_ = xitdb.array_list_append_context(&history, m1_slot.?, remove_mid_cb, &mctx)
1033 | 		elapsed_mid_rem := time.since(t4)
1034 | 
1035 | 		print_result(Bench_Result{
1036 | 			name    = "Linked_Array_List (B-Tree) middle remove",
1037 | 			ops     = mid_ops,
1038 | 			elapsed = elapsed_mid_rem,
1039 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1045-L1066`](../bench_xitdb.zig#L1045-L1066))

```zig
1045 |         const RemoveMidCtx = struct {
1046 |             ops: usize,
1047 | 
1048 |             pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
1049 |                 const list = try DB.LinkedArrayList(.read_write).init(cursor.*);
1050 |                 for (0..self.ops) |_| {
1051 |                     const c = try list.count();
1052 |                     try list.remove(@intCast(c / 2));
1053 |                 }
1054 |             }
1055 |         };
1056 | 
1057 |         const m1_slot = (try history.getSlot(1)).?;
1058 |         const t4 = std.Io.Clock.awake.now(io);
1059 |         try history.appendContext(.{ .slot = m1_slot }, RemoveMidCtx{ .ops = mid_ops });
1060 |         const elapsed_mid_rem = t4.untilNow(io, .awake).nanoseconds;
1061 | 
1062 |         try printResult(stdout, .{
1063 |             .name = "Linked_Array_List (B-Tree) middle remove",
1064 |             .ops = mid_ops,
1065 |             .elapsed_ns = elapsed_mid_rem,
1066 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `LinkedArrayList` | 115 | Typed count-augmented B-Tree `LinkedArrayList` wrapper (`append`, `insert`, `remove`, `concat`, `slice`) | [`lib.zig#L4390-L4504`](../../reference/xitdb-zig/src/lib.zig#L4390-L4504) |
| `readSlotPointer.linked_array_list` | 222 | `PathPart` switch arms: `.linked_array_list_init`, `.linked_array_list_get`, `.linked_array_list_append`, `.linked_array_list_slice`, `.linked_array_list_concat`, `.linked_array_list_insert`, `.linked_array_list_remove` | [`lib.zig#L1049-L1270`](../../reference/xitdb-zig/src/lib.zig#L1049-L1270) |
| `readBTreeNode` | 27 | Count-augmented B-Tree 16-slot node deserializer (18–34 `takeInt` calls) | [`lib.zig#L1946-L1972`](../../reference/xitdb-zig/src/lib.zig#L1946-L1972) |
| `writeBTreeNodeAt` | 15 | Count-augmented B-Tree 16-slot node serializer (18–34 `writeInt` calls) | [`lib.zig#L1977-L1991`](../../reference/xitdb-zig/src/lib.zig#L1977-L1991) |
| `btreeWriteNode` | 7 | In-place transaction reuse check (`btreeReusable`) vs append copy | [`lib.zig#L2013-L2019`](../../reference/xitdb-zig/src/lib.zig#L2013-L2019) |
| `readBTreeSlot` | 20 | Count-augmented B-Tree rank lookup descent | [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) |
| `btreeInsert` | 108 | Count-augmented B-Tree recursive rank insertion and node split | [`lib.zig#L2047-L2154`](../../reference/xitdb-zig/src/lib.zig#L2047-L2154) |
| `btreeGetForWrite` | 29 | Count-augmented B-Tree CoW in-place slot update | [`lib.zig#L2181-L2209`](../../reference/xitdb-zig/src/lib.zig#L2181-L2209) |
| `btreeRemove` | 37 | Count-augmented B-Tree recursive rank deletion and sibling rebalance | [`lib.zig#L2215-L2251`](../../reference/xitdb-zig/src/lib.zig#L2215-L2251) |
| `btreeJoin` | 11 | Count-augmented B-Tree height-aware O(log N) tree concatenation | [`lib.zig#L2423-L2433`](../../reference/xitdb-zig/src/lib.zig#L2423-L2433) |
| `btreeSplit` | 27 | Count-augmented B-Tree O(log N) rank split for `slice` | [`lib.zig#L2451-L2477`](../../reference/xitdb-zig/src/lib.zig#L2451-L2477) |

### Reached Odin Procedures (`84` procedures across `7` files · `1716` LOC) (Active `_exec_path_part` arms: `Array_List_Init`, `Array_List_Get`, `Array_List_Append`, `Linked_Array_List_Init`, `Linked_Array_List_Remove`, `Write_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `write_linked_array_list_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L118-L123`](../../xitdb/collections.odin#L118-L123) |
| `xitdb/collections.odin` | `linked_array_list_count` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L129-L131`](../../xitdb/collections.odin#L129-L131) |
| `xitdb/collections.odin` | `linked_array_list_remove` | **Entry Point** (`depth 0`) | 4 | [`xitdb/collections.odin#L204-L207`](../../xitdb/collections.odin#L204-L207) |
| `xitdb/collections.odin` | `array_list_get_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L45-L47`](../../xitdb/collections.odin#L45-L47) |
| `xitdb/collections.odin` | `array_list_append_context` | **Entry Point** (`depth 0`) | 8 | [`xitdb/collections.odin#L81-L88`](../../xitdb/collections.odin#L81-L88) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_linked_array_list_init`, `linked_array_list_remove`, `array_list_append_context`) | 57 | [`xitdb/cursor.odin#L119-L175`](../../xitdb/cursor.odin#L119-L175) |
| `xitdb/collections.odin` | `read_linked_array_list_init` | `depth 1` (from `write_linked_array_list_init`) | 9 | [`xitdb/collections.odin#L108-L116`](../../xitdb/collections.odin#L108-L116) |
| `xitdb/cursor.odin` | `cursor_count` | `depth 1` (from `linked_array_list_count`) | 39 | [`xitdb/cursor.odin#L395-L433`](../../xitdb/cursor.odin#L395-L433) |
| `xitdb/cursor.odin` | `cursor_read_path_slot` | `depth 1` (from `array_list_get_slot`) | 15 | [`xitdb/cursor.odin#L82-L96`](../../xitdb/cursor.odin#L82-L96) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L98-L106`](../../xitdb/cursor.odin#L98-L106) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L415-L420`](../../xitdb/database.odin#L415-L420) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L422-L437`](../../xitdb/database.odin#L422-L437) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 10 | [`xitdb/cursor.odin#L108-L117`](../../xitdb/cursor.odin#L108-L117) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `cursor_read_path_slot`, `_exec_path_part`) | 68 | [`xitdb/database.odin#L551-L618`](../../xitdb/database.odin#L551-L618) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L363-L367`](../../xitdb/database.odin#L363-L367) |
| `xitdb/core.odin` | `core_sync` | `depth 2` (from `cursor_write_path`, `_database_truncate_with_header`, `database_commit_root`) | 18 | [`xitdb/core.odin#L219-L236`](../../xitdb/core.odin#L219-L236) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L29-L41`](../../xitdb/cursor.odin#L29-L41) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_linked_array_list_init`, `cursor_count`, `cursor_read_path_slot`) | 11 | [`xitdb/cursor.odin#L47-L57`](../../xitdb/cursor.odin#L47-L57) |
| `xitdb/core.odin` | `core_seek_to` | `depth 2` (from `cursor_count`, `cursor_reload_slot`, `read_slot_pointer`) | 17 | [`xitdb/core.odin#L176-L192`](../../xitdb/core.odin#L176-L192) |
| `xitdb/core.odin` | `core_read_exact` | `depth 2` (from `cursor_count`, `_exec_path_part`, `database_read_root_header`) | 34 | [`xitdb/core.odin#L327-L360`](../../xitdb/core.odin#L327-L360) |
| `xitdb/types.odin` | `array_list_header_from_bytes` | `depth 2` (from `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1082-L1090`](../../xitdb/types.odin#L1082-L1090) |
| `xitdb/types.odin` | `btree_header_from_bytes` | `depth 2` (from `cursor_count`, `_exec_path_part`) | 9 | [`xitdb/types.odin#L1105-L1113`](../../xitdb/types.odin#L1105-L1113) |
| `xitdb/core.odin` | `core_read_long` | `depth 2` (from `cursor_count`) | 7 | [`xitdb/core.odin#L484-L490`](../../xitdb/core.odin#L484-L490) |
| `xitdb/types.odin` | `slot_empty` | `depth 2` (from `cursor_read_path_slot`, `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L855-L857`](../../xitdb/types.odin#L855-L857) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L502-L514`](../../xitdb/database.odin#L502-L514) |
| `xitdb/core.odin` | `core_read_slot` | `depth 3` (from `cursor_reload_slot`, `btree_remove`, `read_array_list_slot`) | 5 | [`xitdb/core.odin#L564-L568`](../../xitdb/core.odin#L564-L568) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`, `read_array_list_slot_append`) | 3 | [`xitdb/types.odin#L921-L923`](../../xitdb/types.odin#L921-L923) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`, `cursor_resolved`) | 8 | [`xitdb/database.odin#L369-L376`](../../xitdb/database.odin#L369-L376) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L342-L361`](../../xitdb/database.odin#L342-L361) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `btree_remove`) | 15 | [`xitdb/core.odin#L570-L584`](../../xitdb/core.odin#L570-L584) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L439-L459`](../../xitdb/database.odin#L439-L459) |
| `xitdb/core.odin` | `core_read_slot_raw` | `depth 3` (from `read_slot_pointer`, `core_read_slot`) | 24 | [`xitdb/core.odin#L539-L562`](../../xitdb/core.odin#L539-L562) |
| `xitdb/database.odin` | `_random_u64` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L236-L243`](../../xitdb/database.odin#L236-L243) |
| `xitdb/database.odin` | `database_commit_root` | `depth 3` (from `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L399-L406`](../../xitdb/database.odin#L399-L406) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 762 | [`xitdb/database.odin#L620-L1381`](../../xitdb/database.odin#L620-L1381) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L516-L527`](../../xitdb/database.odin#L516-L527) |
| `xitdb/btree.odin` | `btree_new_root` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/btree.odin#L99-L101`](../../xitdb/btree.odin#L99-L101) |
| `xitdb/btree.odin` | `btree_remove` | `depth 4` (from `_exec_path_part`) | 210 | [`xitdb/btree.odin#L522-L731`](../../xitdb/btree.odin#L522-L731) |
| `xitdb/btree.odin` | `read_btree_node` | `depth 4` (from `_exec_path_part`, `btree_remove`) | 34 | [`xitdb/btree.odin#L8-L41`](../../xitdb/btree.odin#L8-L41) |
| `xitdb/btree.odin` | `btree_write_node` | `depth 4` (from `_exec_path_part`, `btree_remove`) | 7 | [`xitdb/btree.odin#L91-L97`](../../xitdb/btree.odin#L91-L97) |
| `xitdb/types.odin` | `btree_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1098-L1103`](../../xitdb/types.odin#L1098-L1103) |
| `xitdb/core.odin` | `core_write_all` | `depth 4` (from `_exec_path_part`, `core_write_slot`, `database_commit_root`) | 52 | [`xitdb/core.odin#L376-L427`](../../xitdb/core.odin#L376-L427) |
| `xitdb/btree.odin` | `write_btree_node` | `depth 4` (from `_exec_path_part`, `btree_new_root`, `btree_write_node`) | 5 | [`xitdb/btree.odin#L77-L81`](../../xitdb/btree.odin#L77-L81) |
| `xitdb/core.odin` | `core_length` | `depth 4` (from `_exec_path_part`, `_database_truncate_with_header`, `database_commit_root`) | 21 | [`xitdb/core.odin#L154-L174`](../../xitdb/core.odin#L154-L174) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `btree_reusable`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L461-L467`](../../xitdb/database.odin#L461-L467) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1451-L1482`](../../xitdb/database.odin#L1451-L1482) |
| `xitdb/types.odin` | `array_list_header_to_bytes` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/types.odin#L1075-L1080`](../../xitdb/types.odin#L1075-L1080) |
| `xitdb/types.odin` | `array_list_header_with_ptr` | `depth 4` (from `_exec_path_part`) | 3 | [`xitdb/types.odin#L1071-L1073`](../../xitdb/types.odin#L1071-L1073) |
| `xitdb/types.odin` | `radix_shift` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 6 | [`xitdb/types.odin#L1422-L1427`](../../xitdb/types.odin#L1422-L1427) |
| `xitdb/hamt.odin` | `read_array_list_slot` | `depth 4` (from `_exec_path_part`, `read_array_list_slot_append`) | 68 | [`xitdb/hamt.odin#L388-L455`](../../xitdb/hamt.odin#L388-L455) |
| `xitdb/hamt.odin` | `read_array_list_slot_append` | `depth 4` (from `_exec_path_part`) | 39 | [`xitdb/hamt.odin#L348-L386`](../../xitdb/hamt.odin#L348-L386) |
| `xitdb/database.odin` | `transaction_is_scratch_position` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L20-L25`](../../xitdb/database.odin#L20-L25) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 3` (from `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152) |
| `xitdb/core.odin` | `core_read` | `depth 3` (from `core_read_exact`) | 43 | [`xitdb/core.odin#L282-L324`](../../xitdb/core.odin#L282-L324) |
| `xitdb/core.odin` | `core_read_i64` | `depth 3` (from `core_read_long`) | 24 | [`xitdb/core.odin#L499-L522`](../../xitdb/core.odin#L499-L522) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `core_read_slot`, `database_read_root_header`, `slot_from_slice`) | 6 | [`xitdb/types.odin#L67-L72`](../../xitdb/types.odin#L67-L72) |
| `xitdb/types.odin` | `root_header_from_bytes` | `depth 4` (from `database_read_root_header`) | 11 | [`xitdb/types.odin#L999-L1009`](../../xitdb/types.odin#L999-L1009) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 16 | [`xitdb/database.odin#L318-L333`](../../xitdb/database.odin#L318-L333) |
| `xitdb/core.odin` | `core_set_length` | `depth 4` (from `_database_truncate_with_header`) | 42 | [`xitdb/core.odin#L238-L279`](../../xitdb/core.odin#L238-L279) |
| `xitdb/core.odin` | `_memory_resize` | `depth 4` (from `core_write_slot`, `core_write_all`, `core_write_i64`) | 12 | [`xitdb/core.odin#L363-L374`](../../xitdb/core.odin#L363-L374) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 4` (from `core_write_slot`, `read_array_list_slot`, `read_array_list_slot_append`) | 7 | [`xitdb/types.odin#L871-L877`](../../xitdb/types.odin#L871-L877) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw`, `slot_from_slice`) | 10 | [`xitdb/types.odin#L892-L901`](../../xitdb/types.odin#L892-L901) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw`, `root_header_from_bytes`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L880-L890`](../../xitdb/types.odin#L880-L890) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 4` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1036-L1043`](../../xitdb/types.odin#L1036-L1043) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 4` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1028-L1034`](../../xitdb/types.odin#L1028-L1034) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 4` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L408-L413`](../../xitdb/database.odin#L408-L413) |
| `xitdb/btree.odin` | `btree_reusable` | `depth 5` (from `btree_remove`, `btree_write_node`) | 7 | [`xitdb/btree.odin#L83-L89`](../../xitdb/btree.odin#L83-L89) |
| `xitdb/core.odin` | `core_write_i64` | `depth 5` (from `btree_remove`, `core_write_long`) | 14 | [`xitdb/core.odin#L524-L537`](../../xitdb/core.odin#L524-L537) |
| `xitdb/btree.odin` | `btree_drop_child` | `depth 5` (from `btree_remove`) | 7 | [`xitdb/btree.odin#L733-L739`](../../xitdb/btree.odin#L733-L739) |
| `xitdb/btree.odin` | `btree_concat_nodes` | `depth 5` (from `btree_remove`) | 13 | [`xitdb/btree.odin#L741-L753`](../../xitdb/btree.odin#L741-L753) |
| `xitdb/types.odin` | `btree_node_subtree_count` | `depth 5` (from `btree_remove`) | 10 | [`xitdb/types.odin#L1249-L1258`](../../xitdb/types.odin#L1249-L1258) |
| `xitdb/btree.odin` | `write_btree_node_at` | `depth 5` (from `btree_remove`, `btree_write_node`, `write_btree_node`) | 33 | [`xitdb/btree.odin#L43-L75`](../../xitdb/btree.odin#L43-L75) |
| `xitdb/types.odin` | `slot_from_slice` | `depth 5` (from `read_btree_node`) | 5 | [`xitdb/types.odin#L909-L913`](../../xitdb/types.odin#L909-L913) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 5` (from `core_write_all`, `_buffered_flush`) | 18 | [`xitdb/core.odin#L125-L142`](../../xitdb/core.odin#L125-L142) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1484-L1532`](../../xitdb/database.odin#L1484-L1532) |
| `xitdb/types.odin` | `slot_with_full` | `depth 5` (from `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L865-L869`](../../xitdb/types.odin#L865-L869) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_array_list_slot`) | 13 | [`xitdb/database.odin#L469-L481`](../../xitdb/database.odin#L469-L481) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 5` (from `_database_committed_size_with_header`) | 15 | [`xitdb/database.odin#L383-L397`](../../xitdb/database.odin#L383-L397) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 5` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1018-L1026`](../../xitdb/types.odin#L1018-L1026) |
| `xitdb/types.odin` | `root_header_to_bytes` | `depth 5` (from `database_write_root_header`) | 7 | [`xitdb/types.odin#L991-L997`](../../xitdb/types.odin#L991-L997) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 6` (from `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1345-L1356`](../../xitdb/types.odin#L1345-L1356) |
| `xitdb/core.odin` | `core_write_long` | `depth 6` (from `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L492-L497`](../../xitdb/core.odin#L492-L497) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 6` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1045-L1057`](../../xitdb/types.odin#L1045-L1057) |
