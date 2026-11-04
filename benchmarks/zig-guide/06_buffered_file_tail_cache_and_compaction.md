# 06. `CoreBufferedFile` Hot-Tail Retention, Re-Open Caching & Compaction

[← Back to Zig Optimization Guide](README.md) · [Per-Benchmark Slices](../slices/README.md)

## 1. Benchmark Evidence

| # | Benchmark | Odin (`-o:speed`) | Upstream Zig | Patched Zig | Zig Speedup | Slice |
| ---: | :--- | ---: | ---: | ---: | :--- | :--- |
| 59 | `Backend: Core_Buffered_File commits` | **4,579 ns** | 18,568 ns | **6,296 ns** | **2.95x faster** | [Slice #59](../slices/59_backend_core_buffered_file_commits.md) |
| 60 | `Backend: Core_File (unbuffered) commits` | **44,053 ns** | 48,505 ns | **47,654 ns** | **1.02x faster** | [Slice #60](../slices/60_backend_core_file_unbuffered_commits.md) |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **3.71 ms** | 7.59 ms | **3.96 ms** | **1.92x faster** | [Slice #41](../slices/41_compaction_memory_offset_map_200_1.md) |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **9.35 ms** | 13.71 ms | **10.26 ms** | **1.34x faster** | [Slice #42](../slices/42_compaction_file_offset_map_200_1.md) |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 126.6 ms | 110.1 ms | **84.1 ms** | **1.31x faster** *(1.51x vs Odin!)* | [Slice #43](../slices/43_compaction_heterogeneous_dag_dedup.md) |
| 63 | `DB: Re-open & trailer checksum verify` | **56 ns** | 249 ns | **224 ns** | **1.11x faster** | [Slice #63](../slices/63_db_re_open_trailer_checksum_verify.md) |

---

## 2. `CoreBufferedFile`: Multi-Handle Safety & Why `flush()` Must Clear `memory.buffer` and `file_len`

> [!CAUTION]
> **Why Retaining `memory.buffer` or `file_len` Across `flush()` Loses Commits Under Multi-Process File Locks:**
> An earlier version of this guide proposed adding `flushed_len: usize` to `CoreBufferedFile` so `flush()` would keep `memory.buffer` and `file_len` populated across transactions. **That optimization is unsafe whenever two handles take turns writing to the same file** (such as two processes coordinating under a file lock):
>
> 1. Handle 1 initializes the database and commits Transaction 1 (`0..L1`). Because `memory_pos == 0`, the 17-byte `RootHeader` at offset `20..37` is inside Handle 1's `memory.buffer`, and `Handle 1.file_len == L1`.
> 2. Handle 2 acquires the lock, reads `RootHeader` (`L1`) from disk, appends Transaction 2 at `L1..L2`, and updates `RootHeader` at offset `20` on disk to point to `L2`.
> 3. Handle 1 acquires the lock for Transaction 3. If `flush()` did not clear `Handle 1.memory.buffer` and `Handle 1.file_len`:
>    - Handle 1's `readRootHeader()` reads offset `20..37` from its own **stale `memory.buffer`** (seeing Transaction 1's root instead of Transaction 2's root!).
>    - Handle 1's `core.length()` returns its stale cached `file_len = L1` (or truncates the file back to `L1`!), **overwriting Transaction 2 at `L1`** so a fresh open sees `1 3` instead of `1 2 3`!
>
> **Required Invariant (Enforced in Both Upstream Zig and Odin [`xitdb/core.odin#L144-L152`](../../xitdb/core.odin#L144-L152)):**
> - `flush()` **must** clear `self.file_len = null` and `self.memory.buffer.clearRetainingCapacity()`.
> - `length()` and `setLength()` must never cache `file_len` outside an active write window (`file_len` is only cached while buffering uncommitted writes in `Writer.drain` / `core_write_all` and cleared on `flush()`).
> - Tested in [`spec_buffered_file_multi_handle_alternating_commits_preserve_all_moments`](../../tests/spec_xitdb.odin#L1197-L1210).


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
