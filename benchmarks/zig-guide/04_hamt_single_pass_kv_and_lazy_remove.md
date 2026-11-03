# 04. 16-Way HAMT (`HashMap` / `CountedHashMap`): Single-Pass KV Writes & Lazy Remove

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

Across all 15 HAMT benchmarks (`#1–#13`, `#45–#46`), Odin is **2.4x to 13.4x faster**, producing identical `214.5 KB` (`SHA-1`) and `248.7 KB` (`SHA-256`) database files:

| # | Benchmark | Odin (`-o:speed`) | Zig (`ReleaseFast`) | Speedup | Slice |
| ---: | :--- | ---: | ---: | :--- | :--- |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **202 ns** | 798 ns | **3.95x Odin** | [Slice #1](../slices/01_hamt_hash_map_bulk_put_1_tx.md) |
| 5 | `HAMT Hash_Map remove & branch shortening` | **167 ns** | 973 ns | **5.83x Odin** | [Slice #5](../slices/05_hamt_hash_map_remove_branch_shortening.md) |
| 9 | `HAMT Counted_Hash_Map remove` | **165 ns** | 1,019 ns | **6.18x Odin** | [Slice #9](../slices/09_hamt_counted_hash_map_remove.md) |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **193 ns** | 1,269 ns | **6.58x Odin** | [Slice #10](../slices/10_hamt_deep_suffix_collision_put_depth_10.md) |
| 11 | `HAMT deep suffix-collision branch collapse` | **211 ns** | 2,816 ns | **13.35x Odin** | [Slice #11](../slices/11_hamt_deep_suffix_collision_branch_collapse.md) |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **222 ns** | 538 ns | **2.42x Odin** | [Slice #12](../slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) |

Notice the telling contrast between `#1` (`Hash_Map bulk put`: **3.95x**) and `#12` (`Counted_Hash_Set key-only put`: **2.42x**)! `HashSet.put` traverses the HAMT **once**, whereas inserting a key + value into `HashMap` in Zig currently traverses the HAMT **twice**.

---

## 2. What Happens Today in `lib.zig`

### A. Two-Pass Root-to-Leaf Traversal for Every Key+Value Insert
In [`HashMap(.read_write)` (`lib.zig#L3894-L3912`)](../../reference/xitdb-zig/src/lib.zig#L3894-L3912), writing a key and value requires two separate `writePath` calls:

```zig
try map.putKey(hash, .{ .bytes = key });
try map.put(hash, .{ .uint = value });
```

Even inside a single `runContext` transaction:
1. `putKey` reloads `map.cursor.slot_ptr` from `core`, descends all HAMT index levels (`readMapSlot`), allocates the `KeyValuePair`, writes `key_slot`, and updates the counted header (`+1`).
2. `put` reloads `map.cursor.slot_ptr` again, **re-descends the exact same HAMT path**, reads and validates the `KeyValuePair` it just wrote (`hash + key_slot + value_slot`), checks `isOld`, and writes `value_slot`.
3. Furthermore, if `map` is a root cursor (not wrapped in `runContext`), `putKey` and `put` execute **two separate transactions and two `fsync` commits**.

### B. Eager 144-Byte Block Read & 16-Slot Decode at Every Level in `removeMapSlot` (`13.35x` gap on `#11`)
In [`removeMapSlot` (`lib.zig#L1728-L1811`)](../../reference/xitdb-zig/src/lib.zig#L1728-L1811), **before** recursing into child level `key_offset + 1`, Zig zero-fills two arrays, reads all `144 bytes` (`INDEX_BLOCK_SIZE`), and decodes/validates all 16 slots at the current level:

```zig
// reference/xitdb-zig/src/lib.zig#L1736-L1745
// read block
var slot_block: [SLOT_COUNT]Slot = @splat(.{});
try reader.seekTo(index_pos);
var index_block: [INDEX_BLOCK_SIZE]u8 = @splat(0);
try reader.interface.readSliceAll(&index_block);
var block_reader = std.Io.Reader.fixed(&index_block);
for (&slot_block) |*block_slot| {
    block_slot.* = @bitCast(try takeInt(&block_reader, SlotInt, .big));
    try block_slot.tag.validate();
}
```

Most of those 144-byte reads and 16-slot validations are wasted work:
- At `key_offset == 0` (the map's root block), a HAMT root **never collapses** into a `.kv_pair` (`lib.zig#L1769`: `if (key_offset == 0)`), so reading and validating the other 15 root slots is 100% dead work on every `remove()`.
- At intermediate branch levels (`key_offset > 0`), whenever the recursive call returns `.index` (the child branch did not collapse), the current branch **cannot** collapse either—reading its other 15 slots was unnecessary.
- If the key is not found (`error.KeyNotFound`), every level along the search path zeroed, read, and decoded 144 bytes instead of reading a single 9-byte `Slot`.

### C. Recursive Level-by-Level Writes on Multi-Nibble Collisions (`6.58x` gap on `#10`)
In [`readMapSlot` (`lib.zig#L1705-L1720`)](../../reference/xitdb-zig/src/lib.zig#L1705-L1720), when two hashes share $k$ leading nibbles, Zig writes a 144-byte zeroed block, patches the parent slot, and recurses into `readMapSlot(..., key_offset + 1)`—re-reading the zeroed block and re-reading the existing `KeyValuePair` on every shared nibble.

---

## 3. What Odin Does (`xitdb/hamt.odin` & `xitdb/database.odin`)

1. **Single-Pass `Write_KV_Data` ([`xitdb/database.odin#L1304-L1360`](../../xitdb/database.odin#L1304-L1360)):** `hash_map_put` walks `[Hash_Map_Get{.KV_Pair}, Write_KV_Data]`, writing both `key_slot` (only if newly inserted or explicitly requested) and `value_slot` in a single HAMT descent.
2. **Lazy 1-Slot Descent in `remove_map_slot` ([`xitdb/hamt.odin#L242-L341`](../../xitdb/hamt.odin#L242-L341)):** Reads only the single 9-byte slot `i` before recursing. On unwind, if `key_offset == 0` or `next_slot.tag == .Index`, it writes `next_slot` directly and returns—reading the 144-byte sibling block **only** when `key_offset > 0` and `next_slot.tag` is `.None` or `.KV_Pair`.
3. **Iterative Shared-Prefix Loop in `read_map_slot` ([`xitdb/hamt.odin#L170-L223`](../../xitdb/hamt.odin#L170-L223)):** Counts matching nibbles in registers (`for diff_offset < max_offset`) and writes the chain + split block without re-reading `kv_pair` at each depth.

---

## 4. Idiomatic Zig Update (~30 Lines)

### Step 1: Lazy Sibling Block Read in `removeMapSlot`

This self-contained refactor in [`removeMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1728-L1811) keeps the exact same collapse semantics while cutting slot reads on `remove()` by 5x–13x:

```zig
fn removeMapSlot(self: *Database(db_kind, HashInt), index_pos: u64, key_hash: HashInt, key_offset: u8, frozen_at: u64) !Slot {
    if (key_offset >= (HASH_SIZE * 8) / BIT_COUNT) return error.KeyOffsetExceeded;

    var reader = self.core.reader();
    var writer = self.core.writer();

    // 1. Read ONLY the target nibble's 9-byte slot on the way down
    const i: u4 = @intCast((key_hash >> @intCast(key_offset * BIT_COUNT)) & MASK);
    const slot_pos = index_pos + @as(u64, i) * byteSizeOf(Slot);
    try reader.seekTo(slot_pos);
    const slot: Slot = @bitCast(try takeInt(&reader.interface, SlotInt, .big));
    try slot.tag.validate();

    const next_slot: Slot = switch (slot.tag) {
        .none => return error.KeyNotFound,
        .index => try self.removeMapSlot(slot.value, key_hash, key_offset + 1, frozen_at),
        .kv_pair => blk: {
            try reader.seekTo(slot.value);
            const existing_hash = try takeInt(&reader.interface, HashInt, .big);
            if (existing_hash != key_hash) return error.KeyNotFound;
            break :blk .{};
        },
        else => return error.UnexpectedTag,
    };

    // 2. Fast unwind: root block (key_offset == 0) and non-collapsed child (.index) never collapse
    if (key_offset == 0 or next_slot.tag == .index) {
        const next_index_pos = if (key_offset == 0) index_pos else try self.copyIndexBlockIfOld(index_pos, frozen_at);
        try writer.seekTo(next_index_pos + @as(u64, i) * byteSizeOf(Slot));
        try writer.interface.writeInt(SlotInt, @bitCast(next_slot), .big);
        return .{ .value = next_index_pos, .tag = .index };
    }

    // 3. Child became .none or .kv_pair at depth > 0: check 144B block for singleton collapse
    var raw_block: [INDEX_BLOCK_SIZE]u8 = undefined;
    try reader.seekTo(index_pos);
    try reader.interface.readSliceAll(&raw_block);

    var slot_to_return: ?Slot = Slot{};
    for (0..SLOT_COUNT) |j| {
        const used_slot: Slot = if (j == i)
            next_slot
        else blk: {
            const off = j * byteSizeOf(Slot);
            const s: Slot = @bitCast(std.mem.readInt(SlotInt, raw_block[off..][0..byteSizeOf(Slot)], .big));
            try s.tag.validate();
            break :blk s;
        };
        if (used_slot.tag != .none) {
            if (slot_to_return) |sr| {
                if (sr.tag != .none) {
                    slot_to_return = null;
                    break;
                }
            }
            slot_to_return = used_slot;
        }
    }

    if (slot_to_return) |s| {
        switch (s.tag) {
            .none, .kv_pair => return s,
            else => {},
        }
    }

    const next_index_pos = try self.copyIndexBlockIfOld(index_pos, frozen_at);
    try writer.seekTo(next_index_pos + @as(u64, i) * byteSizeOf(Slot));
    try writer.interface.writeInt(SlotInt, @bitCast(next_slot), .big);
    return .{ .value = next_index_pos, .tag = .index };
}
```

### Step 2: Single-Pass `putKeyValue` on `HashMap(.read_write)`

Keeping `put` and `putKey` unchanged for callers who already pre-wrote keys, adding a `WriteKeyValue` arm to `PathPart` (or `putKeyValue(hash, key_data, value_data)` on `HashMap(.read_write)` and `CountedHashMap(.read_write)`) lets callers insert both slots in **one** HAMT traversal—and makes root-level `map.putKeyValue(...)` atomic in a single transaction:

```zig
// Ergonomic caller API (replaces `try m.putKey(h, k); try m.put(h, v);`):
pub fn putKeyValue(self: HashMap(.read_write), hash: HashInt, key: WriteableData, value: WriteableData) !void {
    _ = try self.cursor.writePath(void, &.{
        .{ .hash_map_get = .{ .kv_pair = hash } },
        .{ .write_kv = .{ .key = key, .value = value } },
    });
}
```
