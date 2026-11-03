# 01. Zero-Vtable `CoreMemory` Reads & `takeInt` Fast Path

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

This foundational overhead affects every in-memory operation in `xitdb`, and is isolated most clearly on benchmarks where algorithmic tree work is minimal:

| # | Benchmark | Odin (`-o:speed`) | Upstream Zig | Patched Zig | Zig Speedup | Slice |
| ---: | :--- | ---: | ---: | ---: | :--- | :--- |
| 15 | `Array_List (Radix Trie) random get` | **46 ns** | 138 ns | **85 ns** | **1.62x faster** | [Slice #15](../slices/15_array_list_radix_trie_random_get.md) |
| 16 | `Array_List (Radix Trie) iterator scan` | **13 ns** | 34 ns | **20 ns** | **1.67x faster** | [Slice #16](../slices/16_array_list_radix_trie_iterator_scan.md) |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **347 ns** | 1,545 ns | **925 ns** | **1.67x faster** | [Slice #18](../slices/18_array_list_radix_trie_index_seek_page_10.md) |
| 48 | `Bytes: External Bytes read_bytes_buf` | **9 ns** | 39 ns | **13 ns** | **2.98x faster** | [Slice #48](../slices/48_bytes_external_bytes_read_bytes_buf.md) |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 6 ns | 28 ns | **5 ns** | **5.67x faster** *(beats Odin!)* | [Slice #53](../slices/53_stream_cursor_reader_random_seek_64b_read.md) |
| 63 | `DB: Re-open & trailer checksum verify` | **56 ns** | 249 ns | **224 ns** | **1.11x faster** | [Slice #63](../slices/63_db_re_open_trailer_checksum_verify.md) |

---

## 2. What Happens Today in `lib.zig`

In [`reference/xitdb-zig/src/lib.zig#L4993-L5013`](../../reference/xitdb-zig/src/lib.zig#L4993-L5013), `CoreMemory.reader()` and `CoreMemory.writer()` construct `std.Io.Reader` and `std.Io.Writer` with an **empty buffer (`&.{}`)**:

```zig
// reference/xitdb-zig/src/lib.zig#L4993-L5003
pub fn reader(self: *CoreMemory) Reader {
    return .{
        .parent = self,
        .interface = .{
            .vtable = &.{ .stream = Reader.stream },
            .buffer = &.{},
            .seek = 0,
            .end = 0,
        },
    };
}
```

And every integer/slot read goes through [`takeInt`](../../reference/xitdb-zig/src/lib.zig#L5251-L5255):

```zig
// reference/xitdb-zig/src/lib.zig#L5251-L5255
fn takeInt(reader: *std.Io.Reader, comptime T: type, endian: std.builtin.Endian) !T {
    var buffer: [byteSizeOf(T)]u8 = undefined;
    try reader.readSliceAll(&buffer);
    return std.mem.readInt(T, &buffer, endian);
}
```

In Zig `0.17.0`'s `std.Io.Reader`, `readSliceAll` checks `r.buffer[r.seek..r.end]` first. Because `CoreMemory.Reader` sets `.buffer = &.{}`, that inline fast path **always misses (`0` buffered bytes)**. Consequently, reading a single 9-byte `Slot` (`u72`) executes:

1. `reader.readSliceAll(&buffer)` → `vtable.readVec` (`defaultReadVec`)
2. `vtable.stream` → [`CoreMemory.Reader.stream`](../../reference/xitdb-zig/src/lib.zig#L4930-L4941)
3. `io_w.write(slice)` → `Writer.fixed`'s `vtable.drain` to copy 9 bytes onto the stack.

Even though all bytes are already contiguous in RAM (`self.buffer.written()`), every 1-byte, 8-byte, or 9-byte read pays **two indirect function-pointer calls** that block LLVM inlining and loop vectorization.

---

## 3. What Odin Does (`xitdb/core.odin`)

In [`xitdb/core.odin#L326-L340`](../../xitdb/core.odin#L326-L340), `Core` is a tagged union (`Core_Memory | Core_File | Core_Buffered_File`), and `core_read_exact` / `core_slice_at` slice `Core_Memory.buf` directly without an intermediate stream vtable:

```odin
// xitdb/core.odin#L330-L340
#partial switch &v in c {
case Core_Memory:
    end_pos := v.pos + i64(len(p))
    if v.pos < 0 || end_pos > i64(len(v.buf)) {
        v.pos = i64(len(v.buf))
        return Xitdb_Error.Unexpected_EOF
    }
    copy(p, v.buf[int(v.pos):int(end_pos)])
    v.pos = end_pos
    return nil
}
```

---

## 4. Idiomatic Zig Update (~15 Lines, Zero API Churn)

Zig `0.17.0` already has `std.Io.Reader.fixed(slice)` built into the standard library! When `interface` is initialized with `.fixed(bytes)`, `interface.buffer` points directly to the backing slice (`end = bytes.len`), so `readSliceAll` and `takeInt` become a single inline bounds check + `@memcpy` with **zero vtable calls**.

### Important Subtlety: Safe Interleaving with `CoreMemory.Writer`

In a few places (such as [`readMapSlot`](../../reference/xitdb-zig/src/lib.zig#L1605-L1606) and [`hash_map_init`](../../reference/xitdb-zig/src/lib.zig#L1311-L1312)), `lib.zig` creates `var reader = self.core.reader()` and `var writer = self.core.writer()` in the same scope. If `writer` appends bytes and reallocates `self.buffer`, a stale slice cached inside `reader.interface.buffer` before the write would dangle if read later.

Refreshing `self.interface` from `self.parent.buffer.written()` inside `seekTo()` guarantees that any `try reader.seekTo(...)` after a write always sees the latest allocation and length:

```zig
const CoreMemory = struct {
    buffer: *std.Io.Writer.Allocating,
    max_size: ?u64,

    pub const Reader = struct {
        parent: *CoreMemory,
        interface: std.Io.Reader,
        pos: u64 = 0, // retained because `src/test.zig` asserts `reader.pos` directly

        pub fn seekTo(self: *Reader, offset: u64) !void {
            self.pos = offset;
            const bytes = self.parent.buffer.written();
            self.interface.buffer = @constCast(bytes);
            self.interface.end = bytes.len;
            self.interface.seek = @intCast(@min(offset, bytes.len));
        }
    };

    pub fn reader(self: *CoreMemory) Reader {
        return .{
            .parent = self,
            .interface = .fixed(self.buffer.written()),
        };
    }
    // ...
};
```

> **Note on `reader.pos` and `start_position`:** `src/test.zig` directly inspects `reader.pos` in unit tests (`test.zig#L154-L170`), so keeping `pos: u64 = 0` on `CoreMemory.Reader` and updating `self.pos = offset` in `seekTo()` ensures 100% test compatibility. In `Cursor` ([`lib.zig#L3245`](../../reference/xitdb-zig/src/lib.zig#L3245), [`lib.zig#L3303`](../../reference/xitdb-zig/src/lib.zig#L3303), and [`lib.zig#L3372`](../../reference/xitdb-zig/src/lib.zig#L3372)), using `slot_ptr.slot.value + byteSizeOf(u64)` after `takeInt(u64)` works uniformly across `CoreMemory`, `CoreFile`, and `CoreBufferedFile`, and lets you delete `CoreMemory.Reader.stream` completely. Also replacing `std.Io.Reader.fixed` inside `Cursor.Iter.readSlotBlock` with direct `std.mem.readInt` over the 144-byte buffer speeds up all collection iterators (`#6`, `#16`, `#22`, `#31`) by **1.52x–1.73x**.

### Maintainability & Readability Impact
- **Net LOC:** **-12 lines** (`CoreMemory.Reader.stream` is removed completely).
- **Readability:** Uses standard `std.Io.Reader.fixed` instead of a custom vtable implementation, while keeping every `var reader = self.core.reader()` call site across `lib.zig` unchanged.
