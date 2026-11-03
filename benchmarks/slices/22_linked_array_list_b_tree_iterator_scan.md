# #22. `Linked_Array_List (B-Tree) iterator scan` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices & Cross-Language Guide](README.md) · [Odin Harness (`bench_xitdb.odin#L973-L990`)](../bench_xitdb.odin#L973-L990) · [Zig Harness (`bench_xitdb.zig#L1004-L1018`)](../bench_xitdb.zig#L1004-L1018)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **13** | 13.4 ± 0.5 | 4.1% | 14.0 | 76,923,077 | - | **4.62x Odin** (`z = 100.6`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 60 | 60.6 ± 0.9 | 1.5% | 61.8 | 16,666,667 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

### What Odin Does Differently (`xitdb/*.odin`)

- **Single-Read Block Serialization vs. 66 Per-Field `std.Io` Calls ([`xitdb/btree.odin#L15-L75`](../../xitdb/btree.odin#L15-L75) vs. [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** This is the primary driver of Odin's **13.0x–44.9x speedup** on `Linked_Array_List`. Zig's `readBTreeNode` and `writeBTreeNodeAt` loop over all 32 slots and 32 counts unconditionally, issuing **34 to 66 individual `takeInt`/`writeInt` calls** per node (even when `node.num == 2`). Odin reads the node in **one `core_read_exact` call** into a stack buffer and decodes only `0 ..< node.num` active entries.
- **O(1) Direct Leaf Slot Seek in `read_btree_slot` ([`xitdb/btree.odin#L101-L137`](../../xitdb/btree.odin#L101-L137)):** On `#21 Linked_Array_List random get` (**44.06x faster in Odin: 53 ns vs 2,335 ns**), when `read_btree_slot` reaches a `.Leaf`, Odin does **not** deserialize the 290-byte leaf array—it computes `position := node_ptr + BTREE_NODE_HEADER_SIZE + rem * SLOT_LENGTH` and reads only that **single 9-byte `Slot`**. Zig's [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) calls `readBTreeNode` at the leaf, executing 34 `takeInt` calls to read all 32 leaf slots just to index `node.values[rem]`.
- **Targeted In-Place Branch Count Patching ([`xitdb/btree.odin#L190-L240`](../../xitdb/btree.odin#L190-L240)):** When inserting into a node already owned by the current transaction (`btree_reusable` is true and no child split occurred), Odin patches only the 8-byte `counts[i]` (and 9-byte `children[i]` if relocated) in place instead of rewriting the entire 418-byte branch block.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Read/Write `BTreeNode` via a stack byte buffer (`~15 lines` in [`lib.zig#L1946-L1991`](../../reference/xitdb-zig/src/lib.zig#L1946-L1991)):** Read `BTREE_LEAF_BLOCK_SIZE` (290B) or `BTREE_BRANCH_BLOCK_SIZE` (418B) in a single `reader.interface.readSliceAll(&buf)` / `writer.interface.writeAll(&buf)` and loop `0..node.num` in memory using `std.mem.readInt` / `std.mem.writeInt`. This preserves 100% of the existing `BTreeNode` struct API while eliminating 95% of `std.Io` overhead.
- **Short-circuit leaf reads in `readBTreeSlot` ([`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042)):** Peek the 2-byte `(kind, num)` header; when `kind == .leaf`, seek directly to `node_ptr + 2 + rem * 9` and read 1 `Slot` (5 lines of code).

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L973-L990`](../bench_xitdb.odin#L973-L990))

```odin
 973 | 		t2 := time.now()
 974 | 		it, _ := xitdb.linked_array_list_iterator(rlist)
 975 | 		cnt := 0
 976 | 		for {
 977 | 			c_maybe, _ := xitdb.cursor_iterator_next(&it)
 978 | 			c, ok := c_maybe.?
 979 | 			if !ok do break
 980 | 			_, _ = xitdb.cursor_read_uint(c)
 981 | 			cnt += 1
 982 | 		}
 983 | 		assert(cnt == n)
 984 | 		elapsed_iter := time.since(t2)
 985 | 
 986 | 		print_result(Bench_Result{
 987 | 			name    = "Linked_Array_List (B-Tree) iterator scan",
 988 | 			ops     = n,
 989 | 			elapsed = elapsed_iter,
 990 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L1004-L1018`](../bench_xitdb.zig#L1004-L1018))

```zig
1004 |         const t2 = std.Io.Clock.awake.now(io);
1005 |         var it = try rlist.iterator();
1006 |         var cnt: usize = 0;
1007 |         while (try it.next()) |c| {
1008 |             _ = try c.readUint();
1009 |             cnt += 1;
1010 |         }
1011 |         std.debug.assert(cnt == n);
1012 |         const elapsed_iter = t2.untilNow(io, .awake).nanoseconds;
1013 | 
1014 |         try printResult(stdout, .{
1015 |             .name = "Linked_Array_List (B-Tree) iterator scan",
1016 |             .ops = n,
1017 |             .elapsed_ns = elapsed_iter,
1018 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `LinkedArrayList` | 115 | Typed count-augmented B-Tree `LinkedArrayList` wrapper (`append`, `insert`, `remove`, `concat`, `slice`) | [`lib.zig#L4390-L4504`](../../reference/xitdb-zig/src/lib.zig#L4390-L4504) |
| `readSlotPointer.linked_array_list` | 222 | `PathPart` switch arms: `.linked_array_list_init`, `.linked_array_list_get`, `.linked_array_list_append`, `.linked_array_list_slice`, `.linked_array_list_concat`, `.linked_array_list_insert`, `.linked_array_list_remove` | [`lib.zig#L1049-L1270`](../../reference/xitdb-zig/src/lib.zig#L1049-L1270) |
| `readBTreeNode` | 27 | Count-augmented B-Tree node deserializer (34–66 `takeInt` calls) | [`lib.zig#L1946-L1972`](../../reference/xitdb-zig/src/lib.zig#L1946-L1972) |
| `writeBTreeNodeAt` | 15 | Count-augmented B-Tree node serializer (34–66 `writeInt` calls) | [`lib.zig#L1977-L1991`](../../reference/xitdb-zig/src/lib.zig#L1977-L1991) |
| `readBTreeSlot` | 20 | Count-augmented B-Tree rank lookup descent | [`lib.zig#L2023-L2042`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042) |
| `btreeInsert` | 108 | Count-augmented B-Tree recursive rank insertion and node split | [`lib.zig#L2047-L2154`](../../reference/xitdb-zig/src/lib.zig#L2047-L2154) |
| `btreeGetForWrite` | 29 | Count-augmented B-Tree CoW in-place slot update | [`lib.zig#L2181-L2209`](../../reference/xitdb-zig/src/lib.zig#L2181-L2209) |
| `btreeRemove` | 37 | Count-augmented B-Tree recursive rank deletion and sibling rebalance | [`lib.zig#L2215-L2251`](../../reference/xitdb-zig/src/lib.zig#L2215-L2251) |
| `btreeJoin` | 11 | Count-augmented B-Tree height-aware O(log N) tree concatenation | [`lib.zig#L2423-L2433`](../../reference/xitdb-zig/src/lib.zig#L2423-L2433) |
| `btreeSplit` | 27 | Count-augmented B-Tree O(log N) rank split for `slice` | [`lib.zig#L2451-L2477`](../../reference/xitdb-zig/src/lib.zig#L2451-L2477) |

### Reached Odin Procedures (`21` procedures across `5` files · `329` LOC)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/collections.odin` | `linked_array_list_iterator` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L141-L143`](../../xitdb/collections.odin#L141-L143) |
| `xitdb/cursor.odin` | `cursor_iterator_next` | **Entry Point** (`depth 0`) | 22 | [`xitdb/cursor.odin#L1085-L1106`](../../xitdb/cursor.odin#L1085-L1106) |
| `xitdb/cursor.odin` | `cursor_read_uint` | **Entry Point** (`depth 0`) | 10 | [`xitdb/cursor.odin#L200-L209`](../../xitdb/cursor.odin#L200-L209) |
| `xitdb/cursor.odin` | `cursor_iterator` | `depth 1` (from `linked_array_list_iterator`) | 43 | [`xitdb/cursor.odin#L723-L765`](../../xitdb/cursor.odin#L723-L765) |
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
