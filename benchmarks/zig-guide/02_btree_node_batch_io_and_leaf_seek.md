# 02. `LinkedArrayList` (Count-Augmented B-Tree): Batch Node I/O & Direct Leaf Seek

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

`LinkedArrayList` (`#20–#27`) shows some of the largest speedups in the suite (**4.6x to 44.9x**), with identical `45.3 KB` database footprints:

| # | Benchmark | Odin (`-o:speed`) | Zig (`ReleaseFast`) | Speedup | Slice |
| ---: | :--- | ---: | ---: | :--- | :--- |
| 20 | `Linked_Array_List (B-Tree) append` | **231 ns** | 3,007 ns | **13.02x Odin** | [Slice #20](../slices/20_linked_array_list_b_tree_append.md) |
| 21 | `Linked_Array_List (B-Tree) random get` | **53 ns** | 2,335 ns | **44.06x Odin** | [Slice #21](../slices/21_linked_array_list_b_tree_random_get.md) |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **258 ns** | 3,562 ns | **13.81x Odin** | [Slice #23](../slices/23_linked_array_list_b_tree_middle_insert.md) |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **349 ns** | 3,584 ns | **10.27x Odin** | [Slice #24](../slices/24_linked_array_list_b_tree_middle_remove.md) |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **807 ns** | 36,262 ns | **44.93x Odin** | [Slice #25](../slices/25_linked_array_list_b_tree_concat_slice.md) |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **161 ns** | 2,481 ns | **15.41x Odin** | [Slice #26](../slices/26_linked_array_list_b_tree_in_place_put.md) |

---

## 2. What Happens Today in `lib.zig`

In `lib.zig`, `BTREE_SLOT_COUNT` is `16` ([`lib.zig#L296`](../../reference/xitdb-zig/src/lib.zig#L296)), giving fixed node sizes of **146 bytes** (`BTREE_LEAF_BLOCK_SIZE = 2 + 16 * 9`) and **274 bytes** (`BTREE_BRANCH_BLOCK_SIZE = 2 + 16 * 9 + 16 * 8`).

Two bottlenecks dominate `LinkedArrayList`:

### A. 18 to 34 Per-Field `takeInt` / `writeInt` Calls per Node
In [`readBTreeNode`](../../reference/xitdb-zig/src/lib.zig#L1946-L1972) and [`writeBTreeNodeAt`](../../reference/xitdb-zig/src/lib.zig#L1977-L1991), every slot and count is read or written individually through `std.Io`, looping over all 16 entries even when `node.num == 2`:

```zig
// reference/xitdb-zig/src/lib.zig#L1946-L1991
fn readBTreeNode(self: *Database(db_kind, HashInt), ptr: u64) !BTreeNode {
    var reader = self.core.reader();
    try reader.seekTo(ptr);
    const kind_int = try takeInt(&reader.interface, u8, .big);
    ...
    const num = try takeInt(&reader.interface, u8, .big);
    var node = BTreeNode{ .kind = kind, .num = num };
    switch (kind) {
        .leaf => for (&node.values) |*s| { // <-- 16 virtual calls (even if num == 1)
            s.* = @bitCast(try takeInt(&reader.interface, SlotInt, .big));
            try s.tag.validate();
        },
        .branch => {
            for (&node.children) |*s| { ... } // <-- 16 virtual calls
            for (&node.counts) |*c| c.* = try takeInt(&reader.interface, u64, .big); // <-- 16 virtual calls
        },
    }
    return node;
}
```

On unbuffered `CoreFile`, `writeBTreeNodeAt` issues **34 separate `pwritev` syscalls** to write a single 274-byte branch node! On `CoreMemory`, it executes 34 `drain` vtable calls + 34 capacity checks.

### B. Full Leaf Deserialization in `readBTreeSlot` (`44.06x` gap on `#21`)
In [`readBTreeSlot`](../../reference/xitdb-zig/src/lib.zig#L2023-L2042), every level of a random `get(index)` calls `readBTreeNode(node_ptr)`. At a `.leaf`, it executes 18 `takeInt` calls and 16 enum tag validations to deserialize all 146 bytes just to return `node.values[rem]`:

```zig
// reference/xitdb-zig/src/lib.zig#L2023-L2042
fn readBTreeSlot(self: *Database(db_kind, HashInt), root_ptr: u64, rank: u64) !SlotPointer {
    var node_ptr = root_ptr;
    var rem = rank;
    while (true) {
        const node = try self.readBTreeNode(node_ptr); // <-- decodes all 16 slots at leaf!
        switch (node.kind) {
            .leaf => return .{
                .position = node_ptr + BTREE_NODE_HEADER_SIZE + rem * byteSizeOf(Slot),
                .slot = node.values[@intCast(rem)],
            },
            ...
```

---

## 3. What Odin Does (`xitdb/btree.odin`)

1. **Single-Read / Single-Write Stack Buffers ([`xitdb/btree.odin#L8-L75`](../../xitdb/btree.odin#L8-L75)):** `read_btree_node` reads the header and active body in **one** `core_read_exact` call and decodes only `0 ..< num` entries from stack memory. `write_btree_node_at` formats a zero-initialized stack `[146]u8` or `[274]u8` buffer and calls `core_write_all` **once**.
2. **Direct 9-Byte Leaf Slot Seek ([`xitdb/btree.odin#L103-L181`](../../xitdb/btree.odin#L103-L181)):** `read_btree_slot` peeks the 2-byte `(kind, num)` header; when `kind == .Leaf`, it seeks directly to `node_ptr + 2 + rem * 9` and reads **one** `Slot`.
3. **In-Place Branch Count Patching ([`xitdb/btree.odin#L224-L260`](../../xitdb/btree.odin#L224-L260)):** When `btree_insert` descends through a branch node already created in the current transaction (`btree_reusable` is true) and the child does not split, Odin patches only the single 8-byte `counts[i]` (and 9-byte `children[i]` if relocated) instead of rewriting all 274 bytes.

---

## 4. Idiomatic Zig Update (~35 Lines, `BTreeNode` Struct Unchanged)

### Step 1: Stack-Buffered `readBTreeNode` and `writeBTreeNodeAt`

Keeping `BTreeNode` identical means `btreeInsert`, `btreeRemove`, `btreeJoin`, and `btreeSplit` require **zero changes** while getting an immediate ~10x–40x speedup:

```zig
fn readBTreeNode(self: *Database(db_kind, HashInt), ptr: u64) !BTreeNode {
    var reader = self.core.reader();
    try reader.seekTo(ptr);

    var hdr: [BTREE_NODE_HEADER_SIZE]u8 = undefined;
    try reader.interface.readSliceAll(&hdr);
    const kind = std.enums.fromInt(BTreeNodeKind, hdr[0]) orelse return error.InvalidBTreeNodeKind;
    const num = hdr[1];
    if (num > BTREE_SLOT_COUNT) return error.InvalidBTreeNode;

    var node = BTreeNode{ .kind = kind, .num = num };
    switch (kind) {
        .leaf => {
            var body: [BTREE_SLOT_COUNT * byteSizeOf(Slot)]u8 = undefined;
            const active_bytes = @as(usize, num) * byteSizeOf(Slot);
            try reader.interface.readSliceAll(body[0..active_bytes]);
            for (0..num) |i| {
                const off = i * byteSizeOf(Slot);
                const s: Slot = @bitCast(std.mem.readInt(SlotInt, body[off..][0..byteSizeOf(Slot)], .big));
                try s.tag.validate();
                node.values[i] = s;
            }
        },
        .branch => {
            const slots_len = BTREE_SLOT_COUNT * byteSizeOf(Slot);
            var body: [slots_len + BTREE_SLOT_COUNT * byteSizeOf(u64)]u8 = undefined;
            try reader.interface.readSliceAll(body[0 .. slots_len + @as(usize, num) * byteSizeOf(u64)]);
            for (0..num) |i| {
                const off = i * byteSizeOf(Slot);
                const s: Slot = @bitCast(std.mem.readInt(SlotInt, body[off..][0..byteSizeOf(Slot)], .big));
                try s.tag.validate();
                node.children[i] = s;
            }
            for (0..num) |i| {
                const off = slots_len + i * byteSizeOf(u64);
                node.counts[i] = std.mem.readInt(u64, body[off..][0..byteSizeOf(u64)], .big);
            }
        },
    }
    return node;
}

fn writeBTreeNodeAt(self: *Database(db_kind, HashInt), node: BTreeNode, ptr: u64) !void {
    var writer = self.core.writer();
    try writer.seekTo(ptr);
    switch (node.kind) {
        .leaf => {
            var buf: [BTREE_LEAF_BLOCK_SIZE]u8 = @splat(0);
            buf[0] = @intFromEnum(node.kind);
            buf[1] = node.num;
            for (0..node.num) |i| {
                const off = BTREE_NODE_HEADER_SIZE + i * byteSizeOf(Slot);
                std.mem.writeInt(SlotInt, buf[off..][0..byteSizeOf(Slot)], @bitCast(node.values[i]), .big);
            }
            try writer.interface.writeAll(&buf);
        },
        .branch => {
            var buf: [BTREE_BRANCH_BLOCK_SIZE]u8 = @splat(0);
            buf[0] = @intFromEnum(node.kind);
            buf[1] = node.num;
            for (0..node.num) |i| {
                const off = BTREE_NODE_HEADER_SIZE + i * byteSizeOf(Slot);
                std.mem.writeInt(SlotInt, buf[off..][0..byteSizeOf(Slot)], @bitCast(node.children[i]), .big);
            }
            const counts_base = BTREE_NODE_HEADER_SIZE + BTREE_SLOT_COUNT * byteSizeOf(Slot);
            for (0..node.num) |i| {
                const off = counts_base + i * byteSizeOf(u64);
                std.mem.writeInt(u64, buf[off..][0..byteSizeOf(u64)], node.counts[i], .big);
            }
            try writer.interface.writeAll(&buf);
        },
    }
}
```

### Step 2: Direct Leaf Slot Seek in `readBTreeSlot`

```zig
fn readBTreeSlot(self: *Database(db_kind, HashInt), root_ptr: u64, rank: u64) !SlotPointer {
    var reader = self.core.reader();
    var node_ptr = root_ptr;
    var rem = rank;
    while (true) {
        try reader.seekTo(node_ptr);
        var hdr: [BTREE_NODE_HEADER_SIZE]u8 = undefined;
        try reader.interface.readSliceAll(&hdr);
        const kind = std.enums.fromInt(BTreeNodeKind, hdr[0]) orelse return error.InvalidBTreeNodeKind;
        const num = hdr[1];
        if (num > BTREE_SLOT_COUNT) return error.InvalidBTreeNode;

        if (kind == .leaf) {
            const pos = node_ptr + BTREE_NODE_HEADER_SIZE + rem * byteSizeOf(Slot);
            try reader.seekTo(pos);
            const slot: Slot = @bitCast(try takeInt(&reader.interface, SlotInt, .big));
            try slot.tag.validate();
            return .{ .position = pos, .slot = slot };
        }

        // Branch: read only the active `num` u64 subtree counts, then read the single chosen child slot
        const counts_pos = node_ptr + BTREE_NODE_HEADER_SIZE + BTREE_SLOT_COUNT * byteSizeOf(Slot);
        try reader.seekTo(counts_pos);
        var counts_buf: [BTREE_SLOT_COUNT * byteSizeOf(u64)]u8 = undefined;
        try reader.interface.readSliceAll(counts_buf[0 .. @as(usize, num) * byteSizeOf(u64)]);

        var i: usize = 0;
        while (i + 1 < num) : (i += 1) {
            const cnt = std.mem.readInt(u64, counts_buf[i * 8 ..][0..8], .big);
            if (rem < cnt) break;
            rem -= cnt;
        }
        try reader.seekTo(node_ptr + BTREE_NODE_HEADER_SIZE + i * byteSizeOf(Slot));
        const child: Slot = @bitCast(try takeInt(&reader.interface, SlotInt, .big));
        try child.tag.validate();
        node_ptr = child.value;
    }
}
```

### Maintainability & Readability Impact
- Every tree balancing invariant (`btreeSplit`, `btreeJoin`, `btreeRebalanceOrMerge`) continues to work on the exact same value-type `BTreeNode` struct—zero pointer-casting or raw byte arithmetic leaks into tree logic.
- Note on unused trailing slots: `writeBTreeNodeAt` initializes `buf` with `@splat(0)`, preserving the exact zero-padded wire representation for slots `node.num .. 16`. (If strict validation of unused slots on corrupt files is desired, a fast `@memset`/`std.mem.allEqual` check on the trailing bytes can be kept at near-zero cost.)
