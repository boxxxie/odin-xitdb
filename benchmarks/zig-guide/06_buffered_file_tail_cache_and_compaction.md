# 06. `CoreBufferedFile` Hot-Tail Retention, Re-Open Caching & Compaction

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

| # | Benchmark | Odin (`-o:speed`) | Zig (`ReleaseFast`) | Speedup | Slice |
| ---: | :--- | ---: | ---: | :--- | :--- |
| 59 | `Backend: Core_Buffered_File commits` | **4,579 ns** | 18,568 ns | **4.06x Odin** | [Slice #59](../slices/59_backend_core_buffered_file_commits.md) |
| 60 | `Backend: Core_File (unbuffered) commits` | **44,053 ns** | 48,505 ns | **1.10x Odin** | [Slice #60](../slices/60_backend_core_file_unbuffered_commits.md) |
| 62 | `Tx: Aborted transaction rollback truncate` | **693 ns** | 1,930 ns | **2.78x Odin** | [Slice #62](../slices/62_tx_aborted_transaction_rollback_truncate.md) |
| 63 | `DB: Re-open & trailer checksum verify` | **56 ns** | 249 ns | **4.45x Odin** | [Slice #63](../slices/63_db_re_open_trailer_checksum_verify.md) |
| 39 | `Replication (genesis -> 200 moments)` | **104 ns/op** | 1,044 ns/op | **10.04x Odin** | [Slice #39](../slices/39_replication_genesis_200_moments.md) |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 126.6 ms | **110.1 ms** | **1.15x Zig** | [Slice #43](../slices/43_compaction_heterogeneous_dag_dedup.md) |

---

## 2. `CoreBufferedFile`: Why Commits Lose the In-Memory Window (`#59`, `4.06x`)

`CoreBufferedFile` ([`lib.zig#L5067-L5232`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232)) is already thoughtfully designed around a single contiguous window `[memory_pos, memory_pos + buffer_size)`. Within a *single* transaction, reads of newly written nodes hit `memory.buffer` (`lib.zig#L5093-L5100`).

However, trace what happens **at the end of every transaction** in [`commitRoot` (`lib.zig#L776-L790`)](../../reference/xitdb-zig/src/lib.zig#L776-L790) and [`Cursor.writePath` (`lib.zig#L3177-L3179`)](../../reference/xitdb-zig/src/lib.zig#L3177-L3179):

```zig
// 1. commitRoot (lib.zig#L787-L789):
try self.core.sync();          // -> flush() writes tx window to disk & CLEARS memory.buffer!
try self.writeRootHeader(root); // -> writes 17 bytes at offset 20 (sets memory_pos = 20!)

// 2. Cursor.writePath (lib.zig#L3177-L3179):
if (self.db.tx_start == null) {
    try self.db.core.sync();   // -> flush() writes 17B RootHeader & CLEARS memory.buffer again!
}
```

Look at [`CoreBufferedFile.flush()` (`lib.zig#L5226-L5231`)](../../reference/xitdb-zig/src/lib.zig#L5226-L5231):

```zig
pub fn flush(self: *CoreBufferedFile) !void {
    self.file_len = null;
    if (self.memory.buffer.written().len > 0) {
        try self.writeToFile(self.memory_pos, self.memory.buffer.written());
        self.memory.buffer.clearRetainingCapacity(); // <-- evicts hot tail cache!
    }
}
```

Because `flush()` calls `clearRetainingCapacity()` and resets `file_len = null`:
1. At the start of Transaction $N+1$, `memory.buffer` is **completely empty**.
2. Every read of data committed in Transaction $N$ (`readRootHeader`, `readRootTrailer`, `ArrayList` header + index block, `HashMap` root block, and `KeyValuePair`s) misses `memory.buffer` and falls into `r.parent.file.reader()` (`lib.zig#L5103`), which has `.buffer = &.{}`—issuing **~15–20 unbuffered `preadv` syscalls** plus an `fstat` (`file.length()`) on every commit!

### What Odin Does (`xitdb/core.odin#L25-L33`, `#L145-L151`, `#L393-L425`)

Odin adds **one integer field** to `Core_Buffered_File`: `flushed_len: usize`.
1. When `flush()` runs, it writes only the newly appended dirty suffix `memory.buf[flushed_len..]` to disk and advances `flushed_len = len(memory.buf)`—**keeping the committed tail window resident in `memory.buf`** as a read cache until the window reaches `memory_max_size`!
2. When `writeRootHeader` writes 17 bytes at offset `20` (`w.pos + n <= memory_pos`, strictly before the tail window), it calls `writeToFile(20, buf)` directly **without resetting `memory_pos` to 20 or evicting the hot tail buffer**.

### Idiomatic Zig Update (~18 Lines in `CoreBufferedFile`)

```zig
const CoreBufferedFile = struct {
    memory: CoreMemory,
    memory_max_size: u64,
    memory_pos: u64 = 0,
    flushed_len: usize = 0, // bytes in `memory.buffer.written()[0..flushed_len]` already on disk
    file: CoreFile,
    file_len: ?u64 = null,
```

1. **In `flush()` (`lib.zig#L5226-L5231`):** Write only the un-flushed tail `[flushed_len..]`, keep the clean bytes in `memory.buffer` for subsequent reads, and only clear `file_len` when external writers could run (or update `file_len = @max(fl, memory_pos + written.len)`):
   ```zig
   pub fn flush(self: *CoreBufferedFile) !void {
       const written = self.memory.buffer.written();
       if (written.len > self.flushed_len) {
           try self.writeToFile(self.memory_pos + self.flushed_len, written[self.flushed_len..]);
           self.flushed_len = written.len;
       }
       self.file_len = null;
   }
   ```
2. **In `Writer.drain()` (`lib.zig#L5139-L5166`):**
   - If `buffer_size > 0 and w.pos + n <= parent.memory_pos` (such as updating the 17-byte `RootHeader` at offset `20`), write directly via `parent.writeToFile(w.pos, buf)` without evicting `[memory_pos, memory_pos + buffer_size)`.
   - When sliding to a new window (`w.pos > parent.memory_pos + buffer_size` or exceeding `memory_max_size`), call `try parent.flush()`, `parent.memory.buffer.clearRetainingCapacity()`, `parent.flushed_len = 0`, `parent.memory_pos = w.pos`.
   - If an in-window write overwrites bytes below `flushed_len` (rare), set `parent.flushed_len = @min(parent.flushed_len, @as(usize, @intCast(w.pos - parent.memory_pos)))`.
3. **In `setLength()` (`lib.zig#L5207-L5219`):** Clamp `self.flushed_len = @min(self.flushed_len, self.memory.buffer.written().len)` after shrinking.

Crash-safety is 100% unchanged (`commitRoot`'s `sync()` still writes every dirty byte to the OS before updating `RootHeader`), while ~90% of `preadv` syscalls across consecutive transactions disappear!

---

## 3. Double Trailer Checksum on `Database.init` + `rootCursor` (`#63`, `4.45x`)

When opening an existing database ([`lib.zig#L535-L547`](../../reference/xitdb-zig/src/lib.zig#L535-L547)):
1. `Database.init` calls `_ = try self.committedSize()` → `readRootHeader()` → `readRootTrailer()` (computing CRC-64/XZ).
2. Immediately afterward, `db.rootCursor()` calls `self.readRootSlot()` → `readRootHeader()` → `readRootTrailer()` (computing the exact same CRC-64/XZ a second time).

Because `Database.init` (`lib.zig#L536`) already reads the root header and trailer to validate `committedSize()`, storing that validated `Slot` (or returning `readRootHeader()` from `init`) lets an immediate `rootCursor()` reuse it without reading the header/trailer and running CRC-64/XZ a second time (while still preserving `rc.slot_ptr.slot.tag` for callers that inspect it before running an operation).

---

## 4. Why Zig Wins `#43 Compaction (Heterogeneous DAG + dedup)` by 1.15x

On `#43` (compacting a multi-collection DAG with shared subtrees across `CountedHashMap`, `ArrayList`, `LinkedArrayList`, and `SortedMap`), **Zig beats Odin (`110.1 ms` vs `126.6 ms`, identical `23.4 KB` output)**!

- **Why Zig wins here:** Every slot visited by [`Compactor.remapSlot` (`lib.zig#L4544-L4558`)](../../reference/xitdb-zig/src/lib.zig#L4544-L4558) queries `offset_map.get(source_offset)`. Zig's `std.AutoHashMap(u64, u64)` uses a 1-byte-metadata SIMD SwissTable layout (`@Vector` group probing), which has lower cache-miss and probe overhead under high-churn `u64 -> u64` lookups than Odin's general-purpose `map[i64]i64`.
- **Bonus:** Notice in [`Compactor.populateBTreeLeaf` / `populateBTreeBranch` (`lib.zig#L4714-L4764`)](../../reference/xitdb-zig/src/lib.zig#L4714-L4764) and [`populateSortedMapBranch` (`lib.zig#L4876-L4911`)](../../reference/xitdb-zig/src/lib.zig#L4876-L4911) that `Compactor` *already* reads node bodies via `readSliceAll` + `std.Io.Reader.fixed`, and only uses per-slot `writeInt` loops on the output side (`for (children) |s| try writer.interface.writeInt(...)`) and visits all `16` slots instead of `0..header.num`. Changing those output loops to a stack buffer + `0..header.num` will make Zig's compactor **even faster**!
