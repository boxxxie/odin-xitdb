# 05. `Cursor` Bytes, Stream Vtables & Nested Path Traversal

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

| # | Benchmark | Odin (`-o:speed`) | Upstream Zig | Patched Zig | Zig Speedup | Slice |
| ---: | :--- | ---: | ---: | ---: | :--- | :--- |
| 48 | `Bytes: External Bytes read_bytes_buf` | **9 ns** | 39 ns | **13 ns** | **2.98x faster** | [Slice #48](../slices/48_bytes_external_bytes_read_bytes_buf.md) |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **9 ns** | 57 ns | **19 ns** | **2.98x faster** | [Slice #50](../slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **52 ns/chunk** | 83 ns/chunk | **57 ns/chunk** | **1.45x faster** | [Slice #52](../slices/52_stream_cursor_reader_256_x_4kb_1mb.md) |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 6 ns | 28 ns | **5 ns** | **5.67x faster** *(beats Odin!)* | [Slice #53](../slices/53_stream_cursor_reader_random_seek_64b_read.md) |
| 55 | `Path: 4-level nested cursor_write_path` | **230 ns** | 1,548 ns | **530 ns** | **2.92x faster** | [Slice #55](../slices/55_path_4_level_nested_cursor_write_path.md) |
| 56 | `Path: 4-level nested cursor_read_path` | **148 ns** | 1,293 ns | **453 ns** | **2.85x faster** | [Slice #56](../slices/56_path_4_level_nested_cursor_read_path.md) |

---

## 2. What Happens Today in `lib.zig`

### A. Three Separate Reads for Format-Tagged `.bytes` (`#48` & `#50`, `4.3x–6.3x`)
In [`Cursor.readBytesObject` (`lib.zig#L3295-L3316`)](../../reference/xitdb-zig/src/lib.zig#L3295-L3316), reading a 32-byte format-tagged `.bytes` value performs three separate unbuffered `core_reader` operations:

1. `takeInt(&core_reader.interface, u64, .big)` to read `value_size` (8 bytes)
2. `core_reader.interface.readSliceAll(buffer[0..value_size])` (32 bytes)
3. `core_reader.seekTo(start_position + value_size)` + `readSliceAll(&buf)` for the 2-byte `format_tag`—even though `core_reader` is **already positioned** at `start_position + value_size`!

On unbuffered `CoreFile`, that's **3 `preadv` syscalls** for a 42-byte record; on `CoreMemory` today, it's **6 vtable dispatches**.

### B. Nested `Cursor.Reader` → `CoreMemory.Reader` Double Vtable (`#52` & `#53`, `4.67x`)
In [`Cursor.Reader.stream` (`lib.zig#L2987-L3002`)](../../reference/xitdb-zig/src/lib.zig#L2987-L3002), every unbuffered read constructs a fresh `core_reader = r.parent.db.core.reader()`, seeks to `r.start_position + r.pos`, and calls `readSliceShort(dest)`, chaining three `std.Io` vtables (`Cursor.Reader` → `Core.Reader` → `Writer.fixed`).

### C. 4-Level Nested Path Traversal (`#55` & `#56`, `6.7x–8.7x`)
Benchmarks `#55` and `#56` traverse a 4-level hierarchy (`HashMap` → `ArrayList` → `LinkedArrayList` → `SortedMap`) in one atomic `writePath` / `readPath` call. Here the gap is **entirely the sum of Guides 01–03**:
- Level 1 (`HashMap`): 2–3 unbuffered `takeInt` vtable calls
- Level 2 (`ArrayList`): 2 unbuffered `takeInt` vtable calls
- Level 3 (`LinkedArrayList`): `readBTreeNode` / `btreeGetForWrite` (**18 `takeInt` calls** on the leaf!)
- Level 4 (`SortedMap`): `readSortedNode` + `sortedPut` (**18 `takeInt` + 18 `writeInt` calls** + linear key scan!)

Once Guides 01–03 are applied, `#55` and `#56` speed up automatically without touching `readSlotPointer`!

---

## 3. What Odin Does (`xitdb/cursor.odin`)

- **Coalesced Payload + Format-Tag Read ([`xitdb/cursor.odin#L306-L329`](../../xitdb/cursor.odin#L306-L329)):** When `slot.full` is true and `buffer.len >= value_size + 2`, Odin reads `value_size + 2` contiguous bytes in one call (`combined := buffer[:value_size + 2]`), and never issues a redundant `seekTo` between `value` and `format_tag`.
- **Selective Slot Reload in `cursor_write_path` ([`xitdb/cursor.odin#L134-L145`](../../xitdb/cursor.odin#L134-L145)):** When `c.slot_ptr` is an already-initialized collection cursor inside an unfrozen transaction, Odin skips re-reading the 9-byte parent `Slot` before starting `read_slot_pointer`.

---

## 4. Idiomatic Zig Updates (~15 Lines)

### A. Drop Redundant `seekTo` & Combine Small `.bytes` Reads in `readBytesObject`

In [`Cursor.readBytesObject` (`lib.zig#L3295-L3316`)](../../reference/xitdb-zig/src/lib.zig#L3295-L3316), `format_tag` immediately follows the byte payload on disk (`lib.zig#L24-L26`), so the extra `seekTo` is unnecessary, and small payloads (`<= 246` bytes) can read `[length][payload][format_tag]` in fewer steps (especially impactful on `CoreFile`):

```zig
.bytes => {
    try core_reader.seekTo(slot_ptr.slot.value);
    const value_size = try takeInt(&core_reader.interface, u64, .big);
    if (value_size > buffer.len) return error.StreamTooLong;

    const value = buffer[0..@intCast(value_size)];
    try core_reader.interface.readSliceAll(value);

    const format_tag = if (slot_ptr.slot.full) blk: {
        // `core_reader` is already positioned immediately after `value`
        var buf: [2]u8 = undefined;
        try core_reader.interface.readSliceAll(&buf);
        break :blk buf;
    } else null;

    return .{ .value = value, .format_tag = format_tag };
},
```

### B. Zero-Copy `Cursor.Reader` on `CoreMemory`

If `db_kind == .memory` (known at `comptime` inside `Database(db_kind, HashInt)`!), `Cursor.reader()` can return a fixed `std.Io.Reader` slice straight over `self.db.core.buffer.written()[start_position .. start_position + size]` whenever `slot.tag == .bytes` (or when `slot_ptr.position != null` for `.short_bytes`):

```zig
// Inside Cursor.reader() (`lib.zig#L3370-L3385`), `.bytes` arm:
if (comptime db_kind == .memory) {
    const mem_bytes = self.db.core.buffer.written();
    if (start_position + size <= mem_bytes.len) {
        const slice = mem_bytes[@intCast(start_position)..][0..@intCast(size)];
        return .{
            .parent = self,
            .interface = .fixed(slice),
            .size = size,
            .start_position = start_position,
            .pos = size, // all `size` bytes are already in `interface.buffer[0..size]`
        };
    }
}
```

And in [`Cursor.Reader.seekTo` (`lib.zig#L2971-L2981`)](../../reference/xitdb-zig/src/lib.zig#L2971-L2981), checking `const window_start = self.pos - self.interface.end;` instead of `logical_pos` allows both forward **and backward** seeks (`try bar_reader.seekTo(0)` in `src/test.zig#L1468`) to stay inside the buffered window without invalidating `interface.end`:

```zig
pub fn seekTo(self: *Reader, offset: u64) !void {
    const logical_pos = self.logicalPos();
    const window_start = self.pos - self.interface.end;
    if (offset < window_start or offset >= self.pos) {
        self.interface.seek = 0;
        self.interface.end = 0;
        self.pos = offset;
    } else {
        const logical_delta: isize = @intCast(@as(i65, @intCast(offset)) - @as(i65, @intCast(logical_pos)));
        self.interface.seek = @intCast(@as(isize, @intCast(self.interface.seek)) + logical_delta);
    }
}
```

With this in place, `#53 Stream: Cursor_Reader random seek + 64B read` drops from `28.4 ns` to **`5.0 ns` (5.67x faster, beating Odin's `6.1 ns`)**!
