# #61. `Tx: Mid-tx database_freeze + CoW clone` — Odin vs. Zig Code Slice & Analysis

[← Back to Benchmark Suite](../README.md) · [← All Slices](README.md) · [**📘 Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) · [Odin Harness (`bench_xitdb.odin#L2067-L2108`)](../bench_xitdb.odin#L2067-L2108) · [Zig Harness (`bench_xitdb.zig#L2181-L2231`)](../bench_xitdb.zig#L2181-L2231)

## 1. 1v1 Statistical Performance Summary

| Implementation | Median (`ns/op`) | Mean ± σ (`ns/op`) | CV% | `p95` (`ns`) | Throughput (`ops/s`) | Storage Footprint | Result |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| **Odin** (`-o:speed -microarch:native`) | **1,937** | 1,939.8 ± 11.0 | 0.6% | 1,951.6 | 516,262 | - | **1.12x Odin** (`z = 6.8`) |
| **Zig** (`0.17.0 -Doptimize=ReleaseFast`) | 2,175 | 2,169.6 ± 74.8 | 3.4% | 2,261.4 | 459,770 | - | Baseline |

---

## 2. Architectural Comparison: Odin Optimizations & Idiomatic Zig Improvements

> **Deep-Dive Implementation Guide:** See [**Guide 06: CoreBufferedFile Coherency & Compaction**](../zig-guide/06_buffered_file_tail_cache_and_compaction.md) for complete side-by-side `xitdb/*.odin` vs. `lib.zig` code examples and drop-in Zig `0.17` updates.

### What Odin Does Differently (`xitdb/*.odin`)

- **Multi-Handle Coherent `Core_Buffered_File` (`#59` — 1.05x faster in Odin: `16.97 µs` vs `17.85 µs`):** Both Odin ([`xitdb/core.odin#L25-L33`](../../xitdb/core.odin#L25-L33), [`#L144-L152`](../../xitdb/core.odin#L144-L152)) and Zig ([`CoreBufferedFile`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232)) clear `memory.buf` and `file_len` in `flush()` so multiple buffered handles taking turns under an external file lock never read stale `Root_Header` or `file_len` values (`spec_buffered_file_multi_handle_alternating_commits_preserve_all_moments`). Within each transaction, Odin's direct `core_slice_at` window reads and stack-buffered node I/O avoid vtable overhead.
- **Single Trailer Validation on Open & Truncate (`#62–#63` — 2.91x–4.27x faster in Odin):** In `#63`, Zig validates the root trailer CRC-64/XZ twice back-to-back (`Database.init` line 536 `committedSize()` then `rootCursor()` line 546 `readRootSlot()`) over an unbuffered `CoreMemory.Reader`. Odin's `_database_truncate_with_header` ([`xitdb/database.odin#L343-L362`](../../xitdb/database.odin#L343-L362)) and `Core_Memory` slice reads avoid redundant header/trailer round-trips.

### Suggested Zig Improvements (`reference/xitdb-zig/src/lib.zig` — Preserving Readability & Zero Code Explosion)

- **Keep `flush()` clearing `memory.buffer` and `file_len = null` in `CoreBufferedFile` ([`lib.zig#L5226-L5231`](../../reference/xitdb-zig/src/lib.zig#L5226-L5231)):** Essential for multi-handle coherency when processes alternate commits on the same file.
- **Reuse validated root `Slot` in `Database.init` + `rootCursor()` ([`lib.zig#L535-L548`](../../reference/xitdb-zig/src/lib.zig#L535-L548)):** Avoid computing the trailer CRC-64/XZ twice when opening an existing database.

---

## 3. Benchmark Harness Code (`#L<start>-L<end>`)

### Odin ([`benchmarks/bench_xitdb.odin#L2067-L2108`](../bench_xitdb.odin#L2067-L2108))

```odin
2067 | 	// 5d. Mid-transaction `database_freeze` + CoW subtree cloning & transaction rollback truncation
2068 | 	{
2069 | 		core: xitdb.Core = xitdb.core_memory_init()
2070 | 		defer xitdb.core_destroy(&core)
2071 | 		db, _ := xitdb.database_init(&core, xitdb.sha1_hasher())
2072 | 
2073 | 		Freeze_Ctx :: struct {
2074 | 			db:    ^xitdb.Database,
2075 | 			iters: int,
2076 | 		}
2077 | 		fctx := Freeze_Ctx{db = &db, iters = commits}
2078 | 
2079 | 		freeze_cow_cb :: proc(cursor: ^xitdb.Write_Cursor, user_data: rawptr) -> xitdb.Error {
2080 | 			c := (^Freeze_Ctx)(user_data)
2081 | 			top := xitdb.write_hash_map_init(cursor^) or_return
2082 | 			base_wc := xitdb.hash_map_put_cursor(&top, "base") or_return
2083 | 			base_map := xitdb.write_hash_map_init(base_wc) or_return
2084 | 			for j in 0 ..< 16 {
2085 | 				xitdb.hash_map_put(&base_map, fmt.tprintf("k-%02d", j), u64(j)) or_return
2086 | 			}
2087 | 			base_slot := xitdb.hash_map_slot(base_map.read_hash_map) or_return
2088 | 
2089 | 			for i in 0 ..< c.iters {
2090 | 				xitdb.database_freeze(c.db) or_return
2091 | 				fork_key := fmt.tprintf("fork-%04d", i)
2092 | 				xitdb.hash_map_put(&top, fork_key, base_slot) or_return
2093 | 				fork_wc := xitdb.hash_map_put_cursor(&top, fork_key) or_return
2094 | 				fork_map := xitdb.write_hash_map_init(fork_wc) or_return
2095 | 				xitdb.hash_map_put(&fork_map, "k-00", u64(1000 + i)) or_return
2096 | 			}
2097 | 			return nil
2098 | 		}
2099 | 
2100 | 		t_fc := time.now()
2101 | 		_ = xitdb.database_run_context(&db, freeze_cow_cb, &fctx)
2102 | 		elapsed_fc := time.since(t_fc)
2103 | 
2104 | 		print_result(Bench_Result{
2105 | 			name    = "Tx: Mid-tx database_freeze + CoW clone",
2106 | 			ops     = commits,
2107 | 			elapsed = elapsed_fc,
2108 | 		})
```

### Zig ([`benchmarks/bench_xitdb.zig#L2181-L2231`](../bench_xitdb.zig#L2181-L2231))

```zig
2181 |     // 6d. Mid-transaction `database_freeze` + CoW subtree cloning & transaction rollback truncation
2182 |     {
2183 |         const DB = xitdb.Database(.memory, HashInt);
2184 |         var buffer = std.Io.Writer.Allocating.init(allocator);
2185 |         defer buffer.deinit();
2186 |         var db = try DB.init(io, .{ .buffer = &buffer, .hash_id = xitdb.HashId.fromBytes("sha1") });
2187 | 
2188 |         const FreezeCowCtx = struct {
2189 |             db: *DB,
2190 |             iters: usize,
2191 | 
2192 |             pub fn run(self: @This(), cursor: *DB.Cursor(.read_write)) !void {
2193 |                 const top = try DB.HashMap(.read_write).init(cursor.*);
2194 |                 const h_base = hashSha1("base");
2195 |                 try top.putKey(h_base, .{ .bytes = "base" });
2196 |                 const base_wc = try top.putCursor(h_base);
2197 |                 const base_map = try DB.HashMap(.read_write).init(base_wc);
2198 |                 for (0..16) |j| {
2199 |                     var kbuf: [16]u8 = undefined;
2200 |                     const k = try std.fmt.bufPrint(&kbuf, "k-{d:0>2}", .{j});
2201 |                     const hk = hashSha1(k);
2202 |                     try base_map.putKey(hk, .{ .bytes = k });
2203 |                     try base_map.put(hk, .{ .uint = @intCast(j) });
2204 |                 }
2205 |                 const base_slot = try base_map.slot();
2206 |                 const hk00 = hashSha1("k-00");
2207 | 
2208 |                 for (0..self.iters) |i| {
2209 |                     try self.db.freeze();
2210 |                     var fkbuf: [16]u8 = undefined;
2211 |                     const fork_key = try std.fmt.bufPrint(&fkbuf, "fork-{d:0>4}", .{i});
2212 |                     const h_fork = hashSha1(fork_key);
2213 |                     try top.putKey(h_fork, .{ .bytes = fork_key });
2214 |                     try top.put(h_fork, .{ .slot = base_slot });
2215 |                     const fork_wc = try top.putCursor(h_fork);
2216 |                     const fork_map = try DB.HashMap(.read_write).init(fork_wc);
2217 |                     try fork_map.putKey(hk00, .{ .bytes = "k-00" });
2218 |                     try fork_map.put(hk00, .{ .uint = @intCast(1000 + i) });
2219 |                 }
2220 |             }
2221 |         };
2222 | 
2223 |         const t_fc = std.Io.Clock.awake.now(io);
2224 |         try db.runContext(FreezeCowCtx{ .db = &db, .iters = commits });
2225 |         const elapsed_fc = t_fc.untilNow(io, .awake).nanoseconds;
2226 | 
2227 |         try printResult(stdout, .{
2228 |             .name = "Tx: Mid-tx database_freeze + CoW clone",
2229 |             .ops = commits,
2230 |             .elapsed_ns = elapsed_fc,
2231 |         });
```

---

## 4. Touched Library Code Links (Odin `xitdb/*.odin` ↔ Zig `reference/xitdb-zig/src/lib.zig`)

### Zig Reference Equivalents (`reference/xitdb-zig/src/lib.zig`)

| Zig Symbol / Section | Lines | Role in `reference/xitdb-zig/src/lib.zig` | Source Link |
| :--- | ---: | :--- | :--- |
| `Database.init` | 79 | Database initialization, header validation, `committedSize()`, and `rootCursor()` | [`lib.zig#L470-L548`](../../reference/xitdb-zig/src/lib.zig#L470-L548) |
| `CoreMemory` | 111 | In-memory `Writer.Allocating` backend with unbuffered `.buffer = &.{}` `std.Io` vtables | [`lib.zig#L4917-L5027`](../../reference/xitdb-zig/src/lib.zig#L4917-L5027) |
| `CoreBufferedFile` | 166 | Contiguous tail-buffered OS file backend (`flush` clears buffer on `sync`) | [`lib.zig#L5067-L5232`](../../reference/xitdb-zig/src/lib.zig#L5067-L5232) |
| `CoreFile` | 38 | Unbuffered OS file descriptor backend | [`lib.zig#L5029-L5066`](../../reference/xitdb-zig/src/lib.zig#L5029-L5066) |
| `freeze` | 7 | Mid-transaction `freeze()` barrier for O(1) structural CoW branching | [`lib.zig#L560-L566`](../../reference/xitdb-zig/src/lib.zig#L560-L566) |
| `commitRoot` | 26 | Transaction trailer append, `core.sync()`, and `writeRootHeader` commit sequence | [`lib.zig#L776-L801`](../../reference/xitdb-zig/src/lib.zig#L776-L801) |
| `readSlotPointer` | 733 | Central path-traversal engine & root transaction dispatcher | [`lib.zig#L859-L1591`](../../reference/xitdb-zig/src/lib.zig#L859-L1591) |

### Reached Odin Procedures (`107` procedures across `6` files · `2332` LOC) (Active `_exec_path_part` arms: `Hash_Map_Init`, `Hash_Map_Get`, `Write_Data`, `Write_KV_Data`, `Context`)

| File | Procedure | Role / Call Depth | Lines | Source Link (`#L<start>-L<end>`) |
| :--- | :--- | :--- | ---: | :--- |
| `xitdb/core.odin` | `core_memory_init` | **Entry Point** (`depth 0`) | 28 | [`xitdb/core.odin#L85-L112`](../../xitdb/core.odin#L85-L112) |
| `xitdb/core.odin` | `core_destroy` | **Entry Point** (`depth 0`) | 30 | [`xitdb/core.odin#L351-L380`](../../xitdb/core.odin#L351-L380) |
| `xitdb/database.odin` | `database_init` | **Entry Point** (`depth 0`) | 66 | [`xitdb/database.odin#L182-L247`](../../xitdb/database.odin#L182-L247) |
| `xitdb/types.odin` | `sha1_hasher` | **Entry Point** (`depth 0`) | 10 | [`xitdb/types.odin#L828-L837`](../../xitdb/types.odin#L828-L837) |
| `xitdb/collections.odin` | `write_hash_map_init` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L256-L261`](../../xitdb/collections.odin#L256-L261) |
| `xitdb/collections.odin` | `hash_map_put_cursor` | **Entry Point** (`depth 0`) | 6 | [`xitdb/collections.odin#L443-L448`](../../xitdb/collections.odin#L443-L448) |
| `xitdb/collections.odin` | `hash_map_put` | **Entry Point** (`depth 0`) | 5 | [`xitdb/collections.odin#L437-L441`](../../xitdb/collections.odin#L437-L441) |
| `xitdb/collections.odin` | `hash_map_slot` | **Entry Point** (`depth 0`) | 3 | [`xitdb/collections.odin#L288-L290`](../../xitdb/collections.odin#L288-L290) |
| `xitdb/database.odin` | `database_freeze` | **Entry Point** (`depth 0`) | 9 | [`xitdb/database.odin#L350-L358`](../../xitdb/database.odin#L350-L358) |
| `xitdb/database.odin` | `database_run_context` | **Entry Point** (`depth 0`) | 5 | [`xitdb/database.odin#L343-L347`](../../xitdb/database.odin#L343-L347) |
| `xitdb/core.odin` | `_vmem_align_page` | `depth 1` (from `core_memory_init`, `_memory_reserve`) | 8 | [`xitdb/core.odin#L76-L83`](../../xitdb/core.odin#L76-L83) |
| `xitdb/core.odin` | `_memory_destroy` | `depth 1` (from `core_destroy`, `_overlay_destroy`) | 14 | [`xitdb/core.odin#L207-L220`](../../xitdb/core.odin#L207-L220) |
| `xitdb/core.odin` | `_buffered_flush` | `depth 1` (from `core_destroy`, `core_sync`, `core_write_all`) | 9 | [`xitdb/core.odin#L401-L409`](../../xitdb/core.odin#L401-L409) |
| `xitdb/core.odin` | `_overlay_destroy` | `depth 1` (from `core_destroy`) | 11 | [`xitdb/core.odin#L222-L232`](../../xitdb/core.odin#L222-L232) |
| `xitdb/core.odin` | `core_seek_to` | `depth 1` (from `database_init`, `database_write_headers`, `database_commit_root`) | 20 | [`xitdb/core.odin#L435-L454`](../../xitdb/core.odin#L435-L454) |
| `xitdb/core.odin` | `core_length` | `depth 1` (from `database_init`, `database_freeze`, `database_read_file_size`) | 23 | [`xitdb/core.odin#L411-L433`](../../xitdb/core.odin#L411-L433) |
| `xitdb/database.odin` | `database_read_and_validate_header` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L293-L300`](../../xitdb/database.odin#L293-L300) |
| `xitdb/database.odin` | `database_read_file_size` | `depth 1` (from `database_init`) | 7 | [`xitdb/database.odin#L315-L321`](../../xitdb/database.odin#L315-L321) |
| `xitdb/database.odin` | `database_file_size_start` | `depth 1` (from `database_init`, `database_read_file_size`, `database_write_headers`) | 3 | [`xitdb/database.odin#L404-L406`](../../xitdb/database.odin#L404-L406) |
| `xitdb/core.odin` | `core_set_length` | `depth 1` (from `database_init`, `_database_truncate_with_header`) | 67 | [`xitdb/core.odin#L506-L572`](../../xitdb/core.odin#L506-L572) |
| `xitdb/database.odin` | `_random_u64` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L249-L256`](../../xitdb/database.odin#L249-L256) |
| `xitdb/database.odin` | `database_write_headers` | `depth 1` (from `database_init`) | 8 | [`xitdb/database.odin#L304-L311`](../../xitdb/database.odin#L304-L311) |
| `xitdb/database.odin` | `database_commit_root` | `depth 1` (from `database_init`, `read_slot_pointer`, `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L444-L451`](../../xitdb/database.odin#L444-L451) |
| `xitdb/core.odin` | `core_sync` | `depth 1` (from `database_init`, `database_commit_root`, `cursor_write_path`) | 20 | [`xitdb/core.odin#L485-L504`](../../xitdb/core.odin#L485-L504) |
| `xitdb/database.odin` | `database_committed_size` | `depth 1` (from `database_init`) | 4 | [`xitdb/database.odin#L370-L373`](../../xitdb/database.odin#L370-L373) |
| `xitdb/types.odin` | `sha1_sum_into` | `depth 1` (from `sha1_hasher`) | 121 | [`xitdb/types.odin#L574-L694`](../../xitdb/types.odin#L574-L694) |
| `xitdb/cursor.odin` | `cursor_write_path` | `depth 1` (from `write_hash_map_init`, `database_run_context`, `hash_map_put_key_by_hash`) | 57 | [`xitdb/cursor.odin#L116-L172`](../../xitdb/cursor.odin#L116-L172) |
| `xitdb/collections.odin` | `read_hash_map_init` | `depth 1` (from `write_hash_map_init`) | 9 | [`xitdb/collections.odin#L246-L254`](../../xitdb/collections.odin#L246-L254) |
| `xitdb/database.odin` | `database_digest_string_buf` | `depth 1` (from `hash_map_put_cursor`, `hash_map_put`) | 3 | [`xitdb/database.odin#L280-L282`](../../xitdb/database.odin#L280-L282) |
| `xitdb/collections.odin` | `hash_map_put_key_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 7 | [`xitdb/collections.odin#L404-L410`](../../xitdb/collections.odin#L404-L410) |
| `xitdb/collections.odin` | `hash_map_put_cursor_by_hash` | `depth 1` (from `hash_map_put_cursor`) | 5 | [`xitdb/collections.odin#L398-L402`](../../xitdb/collections.odin#L398-L402) |
| `xitdb/collections.odin` | `hash_map_put_key_and_value` | `depth 1` (from `hash_map_put`) | 7 | [`xitdb/collections.odin#L429-L435`](../../xitdb/collections.odin#L429-L435) |
| `xitdb/cursor.odin` | `cursor_slot` | `depth 1` (from `hash_map_slot`) | 4 | [`xitdb/cursor.odin#L62-L65`](../../xitdb/cursor.odin#L62-L65) |
| `xitdb/database.odin` | `database_root_cursor` | `depth 1` (from `database_run_context`) | 16 | [`xitdb/database.odin#L324-L339`](../../xitdb/database.odin#L324-L339) |
| `xitdb/core.odin` | `_buffered_write_to_file` | `depth 2` (from `_buffered_flush`, `core_write_all`) | 18 | [`xitdb/core.odin#L382-L399`](../../xitdb/core.odin#L382-L399) |
| `xitdb/core.odin` | `_overlay_length` | `depth 2` (from `core_length`, `_overlay_read_at`, `_overlay_slice_at`) | 4 | [`xitdb/core.odin#L257-L260`](../../xitdb/core.odin#L257-L260) |
| `xitdb/types.odin` | `header_read_at` | `depth 2` (from `database_read_and_validate_header`) | 5 | [`xitdb/types.odin#L983-L987`](../../xitdb/types.odin#L983-L987) |
| `xitdb/types.odin` | `header_validate` | `depth 2` (from `database_read_and_validate_header`) | 9 | [`xitdb/types.odin#L938-L946`](../../xitdb/types.odin#L938-L946) |
| `xitdb/core.odin` | `core_read_i64_at` | `depth 2` (from `database_read_file_size`, `database_read_root_header`, `core_read_long_at`) | 24 | [`xitdb/core.odin#L1146-L1169`](../../xitdb/core.odin#L1146-L1169) |
| `xitdb/types.odin` | `header_write` | `depth 2` (from `database_write_headers`) | 4 | [`xitdb/types.odin#L989-L992`](../../xitdb/types.odin#L989-L992) |
| `xitdb/core.odin` | `core_write_all` | `depth 2` (from `database_write_headers`, `database_commit_root`, `header_write`) | 60 | [`xitdb/core.odin#L885-L944`](../../xitdb/core.odin#L885-L944) |
| `xitdb/types.odin` | `root_trailer_to_bytes` | `depth 2` (from `database_commit_root`) | 8 | [`xitdb/types.odin#L1045-L1052`](../../xitdb/types.odin#L1045-L1052) |
| `xitdb/types.odin` | `new_root_trailer` | `depth 2` (from `database_commit_root`) | 7 | [`xitdb/types.odin#L1037-L1043`](../../xitdb/types.odin#L1037-L1043) |
| `xitdb/database.odin` | `database_write_root_header` | `depth 2` (from `database_commit_root`) | 6 | [`xitdb/database.odin#L453-L458`](../../xitdb/database.odin#L453-L458) |
| `xitdb/database.odin` | `database_read_root_header` | `depth 2` (from `database_committed_size`, `read_slot_pointer`, `database_truncate`) | 14 | [`xitdb/database.odin#L409-L422`](../../xitdb/database.odin#L409-L422) |
| `xitdb/types.odin` | `sha1_transf_hw` | `depth 2` (from `sha1_sum_into`) | 179 | [`xitdb/types.odin#L178-L356`](../../xitdb/types.odin#L178-L356) |
| `xitdb/cursor.odin` | `cursor_check_writable` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L96-L104`](../../xitdb/cursor.odin#L96-L104) |
| `xitdb/database.odin` | `is_root` | `depth 2` (from `cursor_write_path`, `cursor_check_writable`, `cursor_reload_slot`) | 6 | [`xitdb/database.odin#L460-L465`](../../xitdb/database.odin#L460-L465) |
| `xitdb/database.odin` | `init_tag` | `depth 2` (from `cursor_write_path`, `read_slot_pointer`) | 16 | [`xitdb/database.odin#L467-L482`](../../xitdb/database.odin#L467-L482) |
| `xitdb/cursor.odin` | `cursor_reload_slot` | `depth 2` (from `cursor_write_path`) | 9 | [`xitdb/cursor.odin#L106-L114`](../../xitdb/cursor.odin#L106-L114) |
| `xitdb/database.odin` | `read_slot_pointer` | `depth 2` (from `cursor_write_path`, `_exec_path_part`, `database_copy_collection_if_frozen`) | 67 | [`xitdb/database.odin#L595-L661`](../../xitdb/database.odin#L595-L661) |
| `xitdb/database.odin` | `database_truncate` | `depth 2` (from `cursor_write_path`) | 5 | [`xitdb/database.odin#L396-L400`](../../xitdb/database.odin#L396-L400) |
| `xitdb/cursor.odin` | `new_write_cursor` | `depth 2` (from `cursor_write_path`, `_exec_path_part`) | 13 | [`xitdb/cursor.odin#L30-L42`](../../xitdb/cursor.odin#L30-L42) |
| `xitdb/cursor.odin` | `cursor_resolved` | `depth 2` (from `read_hash_map_init`, `cursor_slot`) | 8 | [`xitdb/cursor.odin#L48-L55`](../../xitdb/cursor.odin#L48-L55) |
| `xitdb/database.odin` | `database_digest_buf` | `depth 2` (from `database_digest_string_buf`) | 8 | [`xitdb/database.odin#L271-L278`](../../xitdb/database.odin#L271-L278) |
| `xitdb/database.odin` | `database_read_root_slot` | `depth 2` (from `database_root_cursor`) | 4 | [`xitdb/database.odin#L424-L427`](../../xitdb/database.odin#L424-L427) |
| `xitdb/core.odin` | `core_read_exact_at` | `depth 3` (from `header_read_at`, `core_read_i64_at`, `_exec_path_part`) | 46 | [`xitdb/core.odin#L710-L755`](../../xitdb/core.odin#L710-L755) |
| `xitdb/types.odin` | `header_from_bytes` | `depth 3` (from `header_read_at`) | 15 | [`xitdb/types.odin#L961-L975`](../../xitdb/types.odin#L961-L975) |
| `xitdb/types.odin` | `header_to_bytes` | `depth 3` (from `header_write`) | 12 | [`xitdb/types.odin#L948-L959`](../../xitdb/types.odin#L948-L959) |
| `xitdb/core.odin` | `_memory_resize` | `depth 3` (from `core_write_all`, `_overlay_write_at`, `core_write_i64`) | 20 | [`xitdb/core.odin#L864-L883`](../../xitdb/core.odin#L864-L883) |
| `xitdb/core.odin` | `_overlay_write_at` | `depth 3` (from `core_write_all`) | 23 | [`xitdb/core.odin#L297-L319`](../../xitdb/core.odin#L297-L319) |
| `xitdb/types.odin` | `slot_to_bytes` | `depth 3` (from `root_trailer_to_bytes`, `_exec_path_part`, `compute_root_trailer_checksum`) | 7 | [`xitdb/types.odin#L874-L880`](../../xitdb/types.odin#L874-L880) |
| `xitdb/types.odin` | `compute_root_trailer_checksum` | `depth 3` (from `new_root_trailer`, `database_read_root_trailer`) | 9 | [`xitdb/types.odin#L1027-L1035`](../../xitdb/types.odin#L1027-L1035) |
| `xitdb/core.odin` | `core_write_i64` | `depth 3` (from `database_write_root_header`, `core_write_long`) | 14 | [`xitdb/core.odin#L1049-L1062`](../../xitdb/core.odin#L1049-L1062) |
| `xitdb/core.odin` | `core_flush` | `depth 3` (from `database_write_root_header`) | 14 | [`xitdb/core.odin#L470-L483`](../../xitdb/core.odin#L470-L483) |
| `xitdb/database.odin` | `database_read_root_trailer` | `depth 3` (from `database_read_root_header`) | 14 | [`xitdb/database.odin#L429-L442`](../../xitdb/database.odin#L429-L442) |
| `xitdb/database.odin` | `database_check_frozen_slot` | `depth 3` (from `cursor_check_writable`, `read_slot_pointer`) | 13 | [`xitdb/database.odin#L546-L558`](../../xitdb/database.odin#L546-L558) |
| `xitdb/core.odin` | `core_read_slot_at` | `depth 3` (from `cursor_reload_slot`) | 5 | [`xitdb/core.odin#L1204-L1208`](../../xitdb/core.odin#L1204-L1208) |
| `xitdb/types.odin` | `slot_pointer_with_slot` | `depth 3` (from `cursor_reload_slot`) | 3 | [`xitdb/types.odin#L924-L926`](../../xitdb/types.odin#L924-L926) |
| `xitdb/types.odin` | `slot_empty` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`) | 3 | [`xitdb/types.odin#L858-L860`](../../xitdb/types.odin#L858-L860) |
| `xitdb/database.odin` | `_database_truncate_with_header` | `depth 3` (from `read_slot_pointer`, `database_truncate`) | 20 | [`xitdb/database.odin#L375-L394`](../../xitdb/database.odin#L375-L394) |
| `xitdb/core.odin` | `core_write_slot` | `depth 3` (from `read_slot_pointer`, `_exec_path_part`, `read_map_slot`) | 15 | [`xitdb/core.odin#L1097-L1111`](../../xitdb/core.odin#L1097-L1111) |
| `xitdb/database.odin` | `init_part_for` | `depth 3` (from `read_slot_pointer`) | 21 | [`xitdb/database.odin#L484-L504`](../../xitdb/database.odin#L484-L504) |
| `xitdb/core.odin` | `core_read_slot_raw_at` | `depth 3` (from `read_slot_pointer`, `core_read_slot_at`, `read_map_slot`) | 24 | [`xitdb/core.odin#L1179-L1202`](../../xitdb/core.odin#L1179-L1202) |
| `xitdb/database.odin` | `_exec_path_part` | `depth 3` (from `read_slot_pointer`) | 743 | [`xitdb/database.odin#L663-L1405`](../../xitdb/database.odin#L663-L1405) |
| `xitdb/database.odin` | `database_copy_collection_if_frozen` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L560-L571`](../../xitdb/database.odin#L560-L571) |
| `xitdb/database.odin` | `database_check_hash_target` | `depth 4` (from `_exec_path_part`) | 11 | [`xitdb/database.odin#L534-L544`](../../xitdb/database.odin#L534-L544) |
| `xitdb/hamt.odin` | `read_map_slot` | `depth 4` (from `_exec_path_part`) | 224 | [`xitdb/hamt.odin#L15-L238`](../../xitdb/hamt.odin#L15-L238) |
| `xitdb/core.odin` | `core_read_long_at` | `depth 4` (from `_exec_path_part`) | 7 | [`xitdb/core.odin#L1171-L1177`](../../xitdb/core.odin#L1171-L1177) |
| `xitdb/core.odin` | `core_write_long` | `depth 4` (from `_exec_path_part`, `_encode_bytes_slot`) | 6 | [`xitdb/core.odin#L1015-L1020`](../../xitdb/core.odin#L1015-L1020) |
| `xitdb/database.odin` | `database_kv_key_offset` | `depth 4` (from `_exec_path_part`) | 6 | [`xitdb/database.odin#L573-L578`](../../xitdb/database.odin#L573-L578) |
| `xitdb/database.odin` | `_try_encode_inline_data` | `depth 4` (from `_exec_path_part`) | 54 | [`xitdb/database.odin#L1420-L1473`](../../xitdb/database.odin#L1420-L1473) |
| `xitdb/database.odin` | `_extract_bytes_data` | `depth 4` (from `_exec_path_part`) | 12 | [`xitdb/database.odin#L1407-L1418`](../../xitdb/database.odin#L1407-L1418) |
| `xitdb/types.odin` | `bytes_is_short` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_bytes_slot`) | 12 | [`xitdb/types.odin#L1398-L1409`](../../xitdb/types.odin#L1398-L1409) |
| `xitdb/types.odin` | `slot_with_full` | `depth 4` (from `_exec_path_part`, `_try_encode_inline_data`, `_encode_writeable_data`) | 5 | [`xitdb/types.odin#L868-L872`](../../xitdb/types.odin#L868-L872) |
| `xitdb/database.odin` | `_encode_writeable_data` | `depth 4` (from `_exec_path_part`) | 32 | [`xitdb/database.odin#L1475-L1506`](../../xitdb/database.odin#L1475-L1506) |
| `xitdb/database.odin` | `database_is_old` | `depth 4` (from `_exec_path_part`, `read_map_slot`, `database_copy_index_block_if_old`) | 7 | [`xitdb/database.odin#L506-L512`](../../xitdb/database.odin#L506-L512) |
| `xitdb/core.odin` | `core_read_at` | `depth 4` (from `core_read_exact_at`) | 47 | [`xitdb/core.odin#L661-L707`](../../xitdb/core.odin#L661-L707) |
| `xitdb/core.odin` | `_memory_reserve` | `depth 4` (from `_memory_resize`) | 29 | [`xitdb/core.odin#L834-L862`](../../xitdb/core.odin#L834-L862) |
| `xitdb/core.odin` | `_overlay_page` | `depth 4` (from `_overlay_write_at`) | 21 | [`xitdb/core.odin#L235-L255`](../../xitdb/core.odin#L235-L255) |
| `xitdb/types.odin` | `root_trailer_from_bytes` | `depth 4` (from `database_read_root_trailer`) | 13 | [`xitdb/types.odin#L1054-L1066`](../../xitdb/types.odin#L1054-L1066) |
| `xitdb/types.odin` | `tag_validate` | `depth 4` (from `database_read_root_trailer`, `core_read_slot_at`, `read_map_slot`) | 6 | [`xitdb/types.odin#L70-L75`](../../xitdb/types.odin#L70-L75) |
| `xitdb/database.odin` | `transaction_is_root_position` | `depth 4` (from `database_check_frozen_slot`) | 6 | [`xitdb/database.odin#L13-L18`](../../xitdb/database.odin#L13-L18) |
| `xitdb/database.odin` | `_database_committed_size_with_header` | `depth 4` (from `_database_truncate_with_header`) | 8 | [`xitdb/database.odin#L360-L367`](../../xitdb/database.odin#L360-L367) |
| `xitdb/types.odin` | `slot_from_slice_raw` | `depth 4` (from `core_read_slot_raw_at`, `read_map_slot`, `kv_pair_read_buf_at`) | 10 | [`xitdb/types.odin#L895-L904`](../../xitdb/types.odin#L895-L904) |
| `xitdb/types.odin` | `slot_from_bytes_raw` | `depth 4` (from `core_read_slot_raw_at`, `root_trailer_from_bytes`) | 11 | [`xitdb/types.odin#L883-L893`](../../xitdb/types.odin#L883-L893) |
| `xitdb/database.odin` | `database_check_hash` | `depth 5` (from `database_check_hash_target`) | 6 | [`xitdb/database.odin#L527-L532`](../../xitdb/database.odin#L527-L532) |
| `xitdb/types.odin` | `hamt_nibble` | `depth 5` (from `read_map_slot`) | 6 | [`xitdb/types.odin#L1467-L1472`](../../xitdb/types.odin#L1467-L1472) |
| `xitdb/types.odin` | `kv_pair_write` | `depth 5` (from `read_map_slot`) | 3 | [`xitdb/types.odin#L1156-L1158`](../../xitdb/types.odin#L1156-L1158) |
| `xitdb/database.odin` | `database_copy_index_block_if_old` | `depth 5` (from `read_map_slot`) | 12 | [`xitdb/database.odin#L514-L525`](../../xitdb/database.odin#L514-L525) |
| `xitdb/core.odin` | `core_slice_at` | `depth 5` (from `read_map_slot`, `_overlay_slice_at`) | 23 | [`xitdb/core.odin#L948-L970`](../../xitdb/core.odin#L948-L970) |
| `xitdb/types.odin` | `kv_pair_read_buf_at` | `depth 5` (from `read_map_slot`) | 13 | [`xitdb/types.odin#L1251-L1263`](../../xitdb/types.odin#L1251-L1263) |
| `xitdb/database.odin` | `_encode_bytes_slot` | `depth 5` (from `_encode_writeable_data`) | 49 | [`xitdb/database.odin#L1508-L1556`](../../xitdb/database.odin#L1508-L1556) |
| `xitdb/core.odin` | `_overlay_read_at` | `depth 5` (from `core_read_at`) | 34 | [`xitdb/core.odin#L262-L295`](../../xitdb/core.odin#L262-L295) |
| `xitdb/types.odin` | `encode_kv_pair` | `depth 6` (from `kv_pair_write`) | 27 | [`xitdb/types.odin#L1265-L1291`](../../xitdb/types.odin#L1265-L1291) |
| `xitdb/core.odin` | `_overlay_slice_at` | `depth 6` (from `core_slice_at`) | 29 | [`xitdb/core.odin#L321-L349`](../../xitdb/core.odin#L321-L349) |
| `xitdb/types.odin` | `kv_pair_length` | `depth 6` (from `kv_pair_read_buf_at`) | 3 | [`xitdb/types.odin#L1131-L1133`](../../xitdb/types.odin#L1131-L1133) |
