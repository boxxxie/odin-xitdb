# xitdb Benchmarks

This directory contains the statistical performance benchmark suite for `xitdb`, measuring throughput (`ops/sec`), median/mean latency (`ns/op`), variance (`±σ`, `CV%`, `IQR`, `p95`, `p99`, `min..max`), and resulting database byte footprint across all collection types, storage backends, and the 5-layer DSL/Datalog engine.

---

## Running the Benchmarks

Always compile benchmarks with `-o:speed` (and `-microarch:native` to enable target-specific SIMD instructions alongside runtime x86 SHA-NI detection). The primary runner is [`hugi`](../../hugi), which builds the benchmark package, passes `--packet-out` to collect exact integer `u64` batch nanosecond samples (`HPKT\x02`), and ingests runs into `benchmarks/history.hugidb`:

```bash
# Build & run all Odin benchmarks with hugi and ingest into benchmarks/history.hugidb
hugi run benchmarks --db benchmarks/history.hugidb --extra-build-flags "-microarch:native" --runs 5 --warmup 1

# Run a single group into an in-memory CoW Core_Overlay branch (zero disk writes to history.hugidb)
hugi run benchmarks --db benchmarks/history.hugidb --overlay --groups hamt --runs 5 --warmup 1

# Run and check immediately for statistical regressions against a baseline commit
hugi run benchmarks --db benchmarks/history.hugidb --baseline-commit bab4850e4f8e --fail-on-regression

# Run the embedded LuaJIT benchmark suite via hugi
hugi run benchmarks --db benchmarks/history.hugidb --lang lua --extra-build-flags "-microarch:native" --runs 5 --warmup 1
```

You can also invoke the Odin benchmark binary directly (with `--packet-out` for `hugi ingest`, `--quiet` to suppress table stdout, or legacy JSONL output when `--packet-out` is omitted):

```bash
# Direct Odin invocation (writes benchmarks/odin.jsonl & benchmarks/history.jsonl)
odin run benchmarks -o:speed -microarch:native -- --runs 5 --warmup 1

# Emit an HPKT binary packet directly for later ingestion
odin run benchmarks -o:speed -microarch:native -- --runs 10 --warmup 2 --packet-out .tmp/odin.hpk --quiet
hugi ingest --db benchmarks/history.hugidb .tmp/odin.hpk

# Disable bounds checking in hot loops for peak release numbers
odin run benchmarks -o:speed -microarch:native -no-bounds-check -- --runs 5
```

### 1v1 Comparison with Upstream Zig (`reference/xitdb-zig` & `reference/xitdb-zig-patched`)

The upstream Zig reference implementation is tracked in `reference/xitdb-zig` (and our patched fork with all 6 guide optimizations is tracked in `reference/xitdb-zig-patched`). To run the Zig benchmark suite (requires Zig `0.17.0-dev` matching `reference/xitdb-zig/build.zig.zon`) and ingest its JSONL output into `benchmarks/history.hugidb`:

```bash
# Run against upstream reference/xitdb-zig (default)
zig build bench -Doptimize=ReleaseFast -Dcpu=native -- --runs 5 --warmup 1

# Run against reference/xitdb-zig-patched
zig build bench -Doptimize=ReleaseFast -Dcpu=native -Dpatched=true -- --runs 5 --warmup 1

# Ingest Zig (or Lua) JSONL snapshots into the hugi store and run 1v1 comparison
hugi ingest --db benchmarks/history.hugidb benchmarks/zig.jsonl
hugi compare-1v1 --db benchmarks/history.hugidb --langs odin,zig
```

Or run both Odin and Zig suites back-to-back with unified commit/run tagging and statistical significance reporting (Welch's `z`-test) using `compare_1v1.py`:

```bash
./benchmarks/compare_1v1.py --runs 5 --warmup 1
```

### Code-Change-to-Benchmark Mapping (`--plan` & `--affected`)

Before running benchmarks, `compare_1v1.py` can inspect `git diff` (down to modified files and Odin/Zig procedures in `xitdb/*.odin` and `reference/xitdb-zig/src/**`) and map code changes to only the benchmark groups and tests that could be affected—avoiding unnecessary full-suite runs and preventing cross-invocation CPU drift on untouched benchmarks:

```bash
# Dry-run: inspect git diff (working tree or commit/range) and print the execution plan
./benchmarks/compare_1v1.py --plan
./benchmarks/compare_1v1.py --plan f7c2d56

# Run ONLY the benchmarks affected by recent code changes and merge into odin.jsonl / zig.jsonl
./benchmarks/compare_1v1.py --affected
./benchmarks/compare_1v1.py --affected HEAD~1..HEAD

# Manually target specific benchmark groups (hamt,lists,sorted_map,compaction,hashers,backends,dsl) or substring filters
hugi run benchmarks --db benchmarks/history.hugidb --groups dsl --filter "Datalog|Secondary Index"
./benchmarks/compare_1v1.py --groups dsl --filter "Datalog|Secondary Index"
odin run benchmarks -o:speed -microarch:native -- --groups sorted_map,compaction --filter "Incremental"
```

### Multi-Run Pooling, Commit History & Regression Analysis (`history.hugidb`)

Benchmark history across `odin`, `zig`, and `lua` is stored in the compressed `xitdb`-backed store at `benchmarks/history.hugidb` (backfilled from `history.jsonl` and `lua.jsonl`, and compactable into cold columnar rollups):

```bash
# Backfill or ingest packets/JSONL files into history.hugidb and compact cold chunks
hugi ingest --db benchmarks/history.hugidb benchmarks/history.jsonl benchmarks/lua.jsonl
hugi compact --db benchmarks/history.hugidb --keep-hot 0

# List stored commits, languages, run counts, and sample totals
hugi history --db benchmarks/history.hugidb --limit 0

# Inspect pooled quantiles, CV%, and footprint for matching benchmarks
hugi inspect --db benchmarks/history.hugidb "HAMT Hash_Map"

# Compare two Git commits (Mann-Whitney U + Welch t-test) or compare Odin vs. Zig 1v1
hugi compare --db benchmarks/history.hugidb --commits <baseline_sha>..<candidate_sha> --lang odin
hugi compare-1v1 --db benchmarks/history.hugidb --langs odin,zig

# Export pooled longitudinal history (Arrow IPC, Parquet, JSON, JSONL, CSV, TSV, Markdown)
hugi export --db benchmarks/history.hugidb --lang all --all-commits --format jsonl --out -
```

Legacy `.jsonl` files (`benchmarks/odin.jsonl`, `benchmarks/zig.jsonl`, `benchmarks/lua.jsonl`, `benchmarks/history.jsonl`) remain supported by `compare_1v1.py` (`--list-commits`, `--inspect`, `--compare-commits`) and as fallback inputs. `.gitattributes` configures `*.jsonl diff=jsonl`; to inspect `.jsonl` diffs cleanly in Git:

```bash
git config diff.jsonl.textconv "jq -r '\"#\\(.rank) [\\(.commit // \"?\")] \\(.name) | \\(.ns_per_op) ± \\(.stddev_ns // 0) ns/op (CV \\(.cv_pct // 0)%, n=\\(.runs // 1)) | \\(.ops_per_sec) ops/sec\"'"
```

To regenerate the reference tables and code slices below (streaming from `benchmarks/history.hugidb` via `hugi export --lang all --all-commits --format jsonl --out -` when present, or falling back to `.jsonl` files; optionally filtering by commit prefix):

```bash
./benchmarks/update_readme.sh [commit_sha]
```

---

## Reference Results (`-o:speed -microarch:native`, `Core_Memory`)

> **Interactive Code Links, Per-Benchmark Slices & Idiomatic Zig Guide:**
> - Click any **benchmark title** in the tables below to jump directly to its highlighted implementation block (`#L<start>-L<end>`) in [`bench_xitdb.odin`](bench_xitdb.odin) or [`bench_xitdb.zig`](bench_xitdb.zig).
> - Click **`[🔍 <N>p]`** next to any benchmark (or browse [**Per-Benchmark Code Slices (`slices/README.md`)**](slices/README.md)) to inspect the exact `xitdb/*.odin` procedures, `lib.zig` equivalents, and architectural notes for that benchmark.
> - Read the [**Idiomatic Zig Optimization Guide (`zig-guide/README.md`)**](zig-guide/README.md) for six standalone, peer-engineering deep dives ([`01 CoreMemory`](zig-guide/01_core_memory_zero_vtable_io.md) · [`02 LinkedArrayList`](zig-guide/02_btree_node_batch_io_and_leaf_seek.md) · [`03 SortedMap`](zig-guide/03_sorted_bptree_binary_search.md) · [`04 HAMT`](zig-guide/04_hamt_single_pass_kv_and_lazy_remove.md) · [`05 Cursor & Paths`](zig-guide/05_cursor_bytes_streams_and_paths.md) · [`06 CoreBufferedFile & Compactor`](zig-guide/06_buffered_file_tail_cache_and_compaction.md)) showing how to achieve the same speedups in Zig `0.17` in ~140 net LOC without sacrificing readability or wire compatibility.

<!-- BEGIN_BENCHMARK_TABLE -->
### 1. Latest Code-Change Impact & Affected Benchmarks (`bab4850e4f8e` → `32cdc130a8b9`, Odin, 75 / 75 tests re-run)

- **Code Diff Inspected:** `bab4850~1..bab4850` · **Changed Files:** `xitdb/dsl.odin`
- **Modified Procedures:** `_diff_recursive`, `_eval_pull_spec`, `_push_step_buf`, `history_of`, `parse_selector_buf`, `parse_selector`, `parse_steps_buf`, `parse_steps`, `precompute_step_hashes`, `read_prehashed_steps_cursor`, `read_prehashed_steps_slot`, `select_cursor`, `selector_destroy_buf`, `steps_destroy_buf`, `unmarshal_into`
- **Mapped Benchmark Scope:** Odin groups=`dsl` (**75 / 75** Odin benchmarks executed; **0** unchanged benchmarks retained from `bab4850`)

#### 1.1 Sub-100ns Fast Path (`ns`, 14 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `bab4850` (`ns`) | Curr `32cdc13` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L562-L579) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | `~NOISE` | `+1.3%` | 0.99x | 91 | **92** | `0.7` | 91 ± 0.5 | 92 ± 1.7 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L642-L658) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | `~NOISE` | `+0.9%` | 1.00x | 56 | **56** | `0.6` | 58 ± 2.6 | 57 ± 1.0 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L876-L891) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | `~NOISE` | `-0.4%` | 1.00x | 73 | **73** | `0.7` | 73 ± 0.4 | 74 ± 1.5 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L893-L910) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | `~NOISE` | `-2.8%` | 1.05x | 20 | **19** | `12.3` | 20 ± 0.0 | 19 ± 0.1 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1002-L1017) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | `~NOISE` | `-1.3%` | 1.01x | 88 | **87** | `0.0` | 88 ± 0.5 | 88 ± 2.0 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1019-L1036) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | `~NOISE` | `-6.4%` | 1.05x | 22 | **21** | `26.0` | 22 ± 0.0 | 21 ± 0.1 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1226-L1241) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | `~NOISE` | `-0.0%` | 1.00x | 20 | **20** | `1.1` | 20 ± 0.0 | 20 ± 0.2 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1648-L1673) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | `~NOISE` | `-12.0%` | 1.09x | 12 | **11** | `2.5` | 13 ± 1.3 | 11 ± 0.7 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1675-L1684) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | `~NOISE` | `+4.4%` | 0.95x | 18 | **19** | `6.1` | 18 ± 0.0 | 19 ± 0.2 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1686-L1702) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | `~NOISE` | `+2.8%` | 1.00x | 11 | **11** | `0.4` | 11 ± 0.5 | 11 ± 0.0 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1704-L1713) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | `~NOISE` | `-1.0%` | 1.00x | 19 | **19** | `0.9` | 19 ± 0.0 | 20 ± 1.5 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1755-L1771) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | `~NOISE` | `-13.8%` | 1.16x | 108 | **93** | `2.5` | 109 ± 14.6 | 93 ± 0.9 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1773-L1788) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | `~NOISE` | `+3.1%` | 1.00x | 7 | **7** | `2.0` | 7 ± 0.0 | 7 ± 0.1 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1790-L1820) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | `~NOISE` | `-7.1%` | 1.08x | 41 | **38** | `3.6` | 42 ± 2.0 | 38 ± 1.3 |

#### 1.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 35 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `bab4850` (`ns`) | Curr `32cdc13` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | `~NOISE` | `-6.3%` | 1.07x | 346 | **324** | `8.7` | 347 ± 4.4 | 324 ± 4.0 |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L544-L560) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | `~NOISE` | `-0.1%` | 1.00x | 155 | **155** | `1.5` | 155 ± 1.5 | 154 ± 2.3 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L614-L640) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | `~NOISE` | `-3.6%` | 1.04x | 283 | **273** | `0.8` | 284 ± 5.1 | 313 ± 81.0 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L660-L683) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | `~NOISE` | `+1.5%` | 0.99x | 336 | **341** | `0.9` | 338 ± 7.4 | 341 ± 4.9 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L685-L709) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | `~NOISE` | `-7.7%` | 1.08x | 357 | **330** | `13.6` | 356 ± 3.8 | 330 ± 1.8 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L711-L729) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | `~NOISE` | `+2.3%` | 0.98x | 283 | **290** | `1.4` | 286 ± 7.1 | 293 ± 9.0 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L731-L771) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | `~NOISE` | `-3.2%` | 1.03x | 333 | **322** | `2.0` | 336 ± 12.6 | 323 ± 6.7 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L773-L793) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | `~NOISE` | `+3.3%` | 0.97x | 333 | **344** | `0.9` | 341 ± 12.8 | 347 ± 4.8 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L795-L813) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | `~NOISE` | `-1.3%` | 1.01x | 356 | **351** | `1.2` | 356 ± 4.7 | 353 ± 4.5 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L815-L831) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | `~NOISE` | `-2.8%` | 1.03x | 152 | **148** | `2.8` | 152 ± 2.5 | 148 ± 1.5 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) [🔍 91p](slices/14_array_list_radix_trie_append.md) | `~NOISE` | `+4.5%` | 0.96x | 165 | **172** | `1.3` | 167 ± 8.1 | 172 ± 2.3 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L912-L930) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | `~NOISE` | `+2.3%` | 0.98x | 138 | **141** | `0.5` | 140 ± 4.6 | 141 ± 1.4 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L932-L946) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | `~NOISE` | `-1.6%` | 1.02x | 576 | **567** | `4.7` | 576 ± 2.6 | 566 ± 4.0 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | `~NOISE` | `-2.3%` | 1.02x | 387 | **378** | `0.3` | 386 ± 3.1 | 392 ± 36.3 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1038-L1064) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | `~NOISE` | `+2.6%` | 0.97x | 410 | **421** | `1.4` | 416 ± 12.8 | 429 ± 14.0 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1066-L1085) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | `~NOISE` | `+1.5%` | 0.99x | 526 | **534** | `0.6` | 532 ± 10.6 | 535 ± 7.2 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1114-L1131) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | `~NOISE` | `+1.1%` | 0.99x | 260 | **263** | `1.5` | 259 ± 3.7 | 264 ± 6.1 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1133-L1147) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | `~NOISE` | `+0.5%` | 1.00x | 615 | **618** | `5.7` | 615 ± 0.5 | 618 ± 0.8 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | `~NOISE` | `-0.0%` | 1.00x | 618 | **618** | `0.2` | 618 ± 2.0 | 618 ± 2.3 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1196-L1211) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | `~NOISE` | `+0.4%` | 1.00x | 275 | **276** | `0.5` | 275 ± 2.4 | 276 ± 2.4 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1213-L1224) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | `~NOISE` | `+0.6%` | 1.00x | 225 | **226** | `1.4` | 225 ± 1.5 | 227 ± 2.0 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1243-L1258) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | `~NOISE` | `-1.2%` | 1.01x | 760 | **751** | `2.2` | 759 ± 0.9 | 753 ± 5.9 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1260-L1286) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | `~NOISE` | `-0.1%` | 1.00x | 385 | **384** | `0.7` | 385 ± 3.9 | 383 ± 3.2 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1288-L1300) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | `~NOISE` | `-2.3%` | 1.03x | 116 | **113** | `2.8` | 116 ± 1.2 | 114 ± 1.5 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1302-L1317) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | `~NOISE` | `+0.6%` | 0.99x | 558 | **561** | `2.3` | 559 ± 2.4 | 561 ± 0.5 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1319-L1337) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | `~NOISE` | `-0.2%` | 1.00x | 584 | **583** | `0.5` | 584 ± 1.8 | 586 ± 5.9 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | `~NOISE` | `+1.1%` | 0.99x | 564 | **570** | `6.7` | 563 ± 1.9 | 570 ± 1.4 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1362-L1376) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | `~NOISE` | `+0.4%` | 1.00x | 258 | **259** | `0.4` | 258 ± 1.6 | 258 ± 1.3 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) [🔍 54p](slices/39_replication_genesis_200_moments.md) | `~NOISE` | `-1.8%` | 1.02x | 775 | **761** | `1.3` | 783 ± 29.1 | 762 ± 17.9 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | `~NOISE` | `-2.6%` | 1.03x | 337 | **328** | `2.0` | 346 ± 20.5 | 327 ± 3.1 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | `~NOISE` | `-3.4%` | 1.03x | 362 | **350** | `2.1` | 369 ± 18.6 | 351 ± 6.2 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1823-L1876) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | `~NOISE` | `+3.0%` | 0.97x | 380 | **391** | `0.3` | 387 ± 19.4 | 390 ± 2.8 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1878-L1899) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | `~NOISE` | `+1.5%` | 0.98x | 252 | **256** | `0.6` | 253 ± 7.3 | 256 ± 8.0 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1902-L1935) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | `~NOISE` | `-2.6%` | 1.03x | 161 | **157** | `1.3` | 165 ± 15.2 | 156 ± 2.7 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2133-L2148) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | `~NOISE` | `-1.1%` | 1.01x | 103 | **102** | `0.7` | 104 ± 1.5 | 103 ± 2.3 |

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 26 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `bab4850` (`µs`) | Curr `32cdc13` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | `~NOISE` | `-1.7%` | 1.02x | 1.83 | **1.79** | `5.2` | 1.82 ± 0.01 | 1.79 ± 0.01 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L948-L964) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | `~NOISE` | `+0.4%` | 1.00x | 1.29 | **1.29** | `1.1` | 1.29 ± 0.02 | 1.31 ± 0.04 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1087-L1112) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | `~NOISE` | `+0.2%` | 1.00x | 1.83 | **1.83** | `0.8` | 1.83 ± 0.03 | 1.86 ± 0.06 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | `~NOISE` | `-1.1%` | 1.01x | 1.82 | **1.80** | `0.4` | 1.83 ± 0.04 | 1.82 ± 0.04 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | `~NOISE` | `-5.4%` | 1.06x | 9.95 | **9.41** | `1.8` | 9.96 ± 0.68 | 9.39 ± 0.23 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | `~NOISE` | `+2.2%` | 0.98x | 22.5 | **23.0** | `1.6` | 22.6 ± 0.75 | 25.6 ± 4.05 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | `~NOISE` | `+3.0%` | 0.97x | 72.4 | **74.6** | `0.9` | 72.7 ± 2.99 | 74.6 ± 3.53 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) [🔍 55p](slices/44_replication_post_compaction_resync.md) | `~NOISE` | `+1.3%` | 0.99x | 2.31 | **2.33** | `2.2` | 2.31 ± 0.03 | 2.34 ± 0.02 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **FASTER** | `-11.3%` | 1.13x | 2.62 | **2.32** | `3.6` | 2.54 ± 0.14 | 2.32 ± 0.01 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) [🔍 112p](slices/58_backend_core_memory_commits.md) | `~NOISE` | `-0.0%` | 1.00x | 1.90 | **1.90** | `0.2` | 1.90 ± 0.01 | 1.90 ± 0.02 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | `~NOISE` | `-0.4%` | 1.00x | 24.8 | **24.7** | `0.6` | 24.9 ± 0.11 | 25.2 ± 1.41 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | `~NOISE` | `+0.3%` | 1.00x | 71.0 | **71.2** | `1.1` | 70.8 ± 0.28 | 73.0 ± 4.53 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2067-L2108) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | `~NOISE` | `-0.5%` | 1.01x | 1.94 | **1.93** | `1.7` | 1.94 ± 0.01 | 1.92 ± 0.03 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2110-L2131) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | `~NOISE` | `-0.4%` | 1.00x | 1.07 | **1.07** | `0.9` | 1.07 ± 0.00 | 1.07 ± 0.01 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2176-L2211) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | `~NOISE` | `+1.0%` | 0.99x | 7.16 | **7.23** | `0.4` | 7.37 ± 0.50 | 7.29 ± 0.12 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2215-L2227) [🔍 84p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | `~NOISE` | `+2.1%` | 0.98x | 1.02 | **1.04** | `2.6` | 1.02 ± 0.01 | 1.04 ± 0.01 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2231-L2267) [🔍 180p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | `~NOISE` | `+1.9%` | 0.98x | 6.38 | **6.50** | `0.0` | 6.50 ± 0.20 | 6.49 ± 0.03 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2269-L2279) [🔍 152p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | `~NOISE` | `-5.0%` | 1.05x | 3.33 | **3.17** | `9.3` | 3.33 ± 0.03 | 3.16 ± 0.03 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2281-L2291) [🔍 111p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | `~NOISE` | `-2.5%` | 1.03x | 2.95 | **2.88** | `1.6` | 3.06 ± 0.26 | 2.88 ± 0.02 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2296-L2313) [🔍 155p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | `~NOISE` | `-0.7%` | 1.01x | 390.1 | **387.6** | `0.3` | 389.4 ± 1.30 | 390.4 ± 7.01 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2315-L2324) [🔍 91p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | `~NOISE` | `+3.4%` | 0.97x | 2.54 | **2.63** | `3.0` | 2.54 ± 0.04 | 2.62 ± 0.04 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2328-L2348) [🔍 135p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | `~NOISE` | `-1.4%` | 1.01x | 25.8 | **25.4** | `5.8` | 25.8 ± 0.14 | 25.4 ± 0.09 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2351-L2366) [🔍 135p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **FASTER** | `-13.7%` | 1.16x | 1098.7 | **948.6** | `7.9` | 1101.7 ± 17.3 | 965.4 ± 34.6 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2369-L2384) [🔍 135p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | `~NOISE` | `-4.3%` | 1.04x | 50.8 | **48.7** | `0.9` | 51.0 ± 0.36 | 49.8 ± 3.04 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2388-L2405) [🔍 111p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | `~NOISE` | `-3.1%` | 1.03x | 5.36 | **5.19** | `0.5` | 5.36 ± 0.10 | 5.30 ± 0.23 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2408-L2450) [🔍 199p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | `~NOISE` | `-0.9%` | 1.01x | 11.0 | **10.9** | `0.4` | 11.0 ± 0.07 | 11.0 ± 0.17 |


### 2. Odin Full Suite Results (`-o:speed -microarch:native`, Commit `32cdc130a8b9`, 5 samples across 1 run(s))

#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 14 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L562-L579) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **92** | 92 ± 1.7 | 1.9% | 10.6M | 11.1M | 2 | 94 | 94 | 90 | 94 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L642-L658) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **56** | 57 ± 1.0 | 1.7% | 17.2M | 17.9M | 1 | 58 | 58 | 56 | 58 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L876-L891) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **73** | 74 ± 1.5 | 2.0% | 13.2M | 13.7M | 2 | 75 | 76 | 73 | 76 | 2K |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L893-L910) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **19** | 19 ± 0.1 | 0.5% | 50.0M | 52.6M | 0 | 20 | 20 | 19 | 20 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1002-L1017) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **87** | 88 ± 2.0 | 2.3% | 11.0M | 11.6M | 1 | 90 | 91 | 86 | 91 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1019-L1036) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **21** | 21 ± 0.1 | 0.6% | 47.6M | 47.6M | 0 | 21 | 21 | 21 | 21 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1226-L1241) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **20** | 20 ± 0.2 | 1.1% | 50.0M | 50.0M | 0 | 20 | 20 | 20 | 20 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1648-L1673) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **11** | 11 ± 0.7 | 6.7% | 83.3M | 90.9M | 0 | 12 | 12 | 11 | 12 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1675-L1684) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **19** | 19 ± 0.2 | 1.3% | 52.6M | 55.6M | 0 | 19 | 19 | 18 | 19 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1686-L1702) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **11** | 11 ± 0.0 | 0.0% | 90.9M | 90.9M | 0 | 11 | 11 | 11 | 11 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1704-L1713) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **19** | 20 ± 1.5 | 7.4% | 45.5M | 52.6M | 1 | 22 | 22 | 19 | 22 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1755-L1771) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **93** | 93 ± 0.9 | 1.0% | 10.6M | 10.9M | 0 | 94 | 94 | 92 | 94 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1773-L1788) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **7** | 7 ± 0.1 | 2.0% | 143M | 143M | 0 | 7 | 7 | 7 | 7 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1790-L1820) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **38** | 38 ± 1.3 | 3.3% | 25.0M | 27.0M | 2 | 40 | 40 | 37 | 40 | 2K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 35 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **324** | 324 ± 4.0 | 1.2% | 3.0M | 3.1M | 7 | 328 | 328 | 319 | 328 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L544-L560) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **155** | 154 ± 2.3 | 1.5% | 6.4M | 6.6M | 4 | 156 | 156 | 151 | 156 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L614-L640) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **273** | 313 ± 81.0 | 25.9% | 2.2M | 3.7M | 21 | 424 | 451 | 271 | 457 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L660-L683) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **341** | 341 ± 4.9 | 1.4% | 2.9M | 3.0M | 2 | 348 | 349 | 336 | 349 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L685-L709) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **330** | 330 ± 1.8 | 0.5% | 3.00M | 3.05M | 1 | 332 | 333 | 328 | 333 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L711-L729) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **290** | 293 ± 9.0 | 3.1% | 3.3M | 3.5M | 11 | 304 | 305 | 283 | 305 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L731-L771) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **322** | 323 ± 6.7 | 2.1% | 3.0M | 3.2M | 9 | 331 | 332 | 315 | 332 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L773-L793) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **344** | 347 ± 4.8 | 1.4% | 2.8M | 2.9M | 8 | 353 | 353 | 343 | 353 | 500 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L795-L813) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **351** | 353 ± 4.5 | 1.3% | 2.8M | 2.9M | 4 | 359 | 359 | 348 | 360 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L815-L831) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **148** | 148 ± 1.5 | 1.0% | 6.6M | 6.8M | 0 | 150 | 151 | 147 | 151 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **172** | 172 ± 2.3 | 1.3% | 5.7M | 5.9M | 2 | 174 | 175 | 169 | 175 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L912-L930) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **141** | 141 ± 1.4 | 1.0% | 7.0M | 7.1M | 1 | 143 | 143 | 140 | 143 | 2K |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L932-L946) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **567** | 566 ± 4.0 | 0.7% | 1.75M | 1.78M | 6 | 570 | 570 | 561 | 570 | 2K |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **378** | 392 ± 36.3 | 9.3% | 2.2M | 2.7M | 7 | 441 | 453 | 371 | 456 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1038-L1064) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **421** | 429 ± 14.0 | 3.3% | 2.2M | 2.4M | 11 | 448 | 451 | 418 | 452 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1066-L1085) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **534** | 535 ± 7.2 | 1.3% | 1.8M | 1.9M | 11 | 544 | 544 | 528 | 545 | 500 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1114-L1131) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **263** | 264 ± 6.1 | 2.3% | 3.6M | 3.9M | 4 | 272 | 273 | 258 | 274 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1133-L1147) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **618** | 618 ± 0.8 | 0.1% | 1.6M | 1.6M | 1 | 619 | 619 | 617 | 619 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **618** | 618 ± 2.3 | 0.4% | 1.61M | 1.62M | 2 | 621 | 622 | 616 | 622 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1196-L1211) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **276** | 276 ± 2.4 | 0.9% | 3.6M | 3.7M | 3 | 278 | 279 | 273 | 279 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1213-L1224) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **226** | 227 ± 2.0 | 0.9% | 4.3M | 4.4M | 3 | 229 | 230 | 225 | 230 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1243-L1258) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **751** | 753 ± 5.9 | 0.8% | 1.31M | 1.34M | 2 | 762 | 763 | 749 | 764 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1260-L1286) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **384** | 383 ± 3.2 | 0.8% | 2.59M | 2.64M | 4 | 386 | 386 | 379 | 386 | 1K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1288-L1300) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **113** | 114 ± 1.5 | 1.3% | 8.6M | 8.9M | 1 | 116 | 116 | 112 | 116 | 2K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1302-L1317) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **561** | 561 ± 0.5 | 0.1% | 1.78M | 1.79M | 0 | 562 | 562 | 560 | 562 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1319-L1337) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **583** | 586 ± 5.9 | 1.0% | 1.68M | 1.72M | 3 | 594 | 596 | 582 | 596 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **570** | 570 ± 1.4 | 0.3% | 1.7M | 1.8M | 1 | 572 | 573 | 569 | 573 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1362-L1376) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **259** | 258 ± 1.3 | 0.5% | 3.86M | 3.89M | 2 | 259 | 259 | 257 | 259 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **761** | 762 ± 17.9 | 2.3% | 1.3M | 1.4M | 6 | 785 | 789 | 740 | 790 | 200 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **328** | 327 ± 3.1 | 0.9% | 3.0M | 3.1M | 3 | 330 | 330 | 322 | 330 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **350** | 351 ± 6.2 | 1.8% | 2.8M | 2.9M | 3 | 359 | 361 | 345 | 361 | 2K |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1823-L1876) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **391** | 390 ± 2.8 | 0.7% | 2.5M | 2.6M | 3 | 393 | 393 | 386 | 393 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1878-L1899) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **256** | 256 ± 8.0 | 3.1% | 3.7M | 4.0M | 2 | 266 | 268 | 247 | 269 | 500 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1902-L1935) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **157** | 156 ± 2.7 | 1.7% | 6.3M | 6.6M | 3 | 159 | 159 | 152 | 159 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2133-L2148) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **102** | 103 ± 2.3 | 2.3% | 9.5M | 10.0M | 4 | 105 | 105 | 100 | 105 | 5K |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 26 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **1.79** | 1.79 ± 0.01 | 0.4% | 556K | 562K | 0.01 | 1.80 | 1.80 | 1.78 | 1.80 | 500 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L948-L964) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **1.29** | 1.31 ± 0.04 | 3.4% | 722K | 782K | 0.04 | 1.37 | 1.38 | 1.28 | 1.39 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1087-L1112) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **1.83** | 1.86 ± 0.06 | 3.3% | 510K | 553K | 0.01 | 1.94 | 1.96 | 1.81 | 1.96 | 400 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **1.80** | 1.82 ± 0.04 | 2.4% | 527K | 558K | 0.00 | 1.88 | 1.89 | 1.79 | 1.90 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **9.41** | 9.39 ± 0.23 | 2.4% | 103K | 110K | 0.32 | 9.65 | 9.67 | 9.13 | 9.68 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **23.0** | 25.6 ± 4.05 | 15.8% | 31.6K | 44.3K | 5.18 | 30.9 | 31.5 | 22.6 | 31.6 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **74.6** | 74.6 ± 3.53 | 4.7% | 12.5K | 14.1K | 3.78 | 79.1 | 79.8 | 71.1 | 80.0 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **2.33** | 2.34 ± 0.02 | 1.0% | 421K | 432K | 0.02 | 2.37 | 2.37 | 2.31 | 2.37 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **2.32** | 2.32 ± 0.01 | 0.6% | 427K | 434K | 0.01 | 2.34 | 2.34 | 2.31 | 2.34 | 256 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) [🔍 112p](slices/58_backend_core_memory_commits.md) | **1.90** | 1.90 ± 0.02 | 1.0% | 519K | 531K | 0.02 | 1.92 | 1.93 | 1.88 | 1.93 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **24.7** | 25.2 ± 1.41 | 5.6% | 36.0K | 40.9K | 0.09 | 27.2 | 27.6 | 24.4 | 27.8 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **71.2** | 73.0 ± 4.53 | 6.2% | 12.3K | 14.2K | 0.59 | 79.2 | 80.7 | 70.5 | 81.1 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2067-L2108) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.93** | 1.92 ± 0.03 | 1.4% | 513K | 529K | 0.04 | 1.95 | 1.95 | 1.89 | 1.95 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2110-L2131) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **1.07** | 1.07 ± 0.01 | 0.7% | 926K | 944K | 0.01 | 1.08 | 1.08 | 1.06 | 1.08 | 500 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2176-L2211) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **7.23** | 7.29 ± 0.12 | 1.6% | 133K | 138K | 0.03 | 7.45 | 7.49 | 7.23 | 7.50 | 500 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2215-L2227) [🔍 84p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **1.04** | 1.04 ± 0.01 | 1.2% | 938K | 968K | 0.01 | 1.06 | 1.07 | 1.03 | 1.07 | 500 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2231-L2267) [🔍 180p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **6.50** | 6.49 ± 0.03 | 0.4% | 153K | 155K | 0.03 | 6.52 | 6.52 | 6.45 | 6.52 | 200 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2269-L2279) [🔍 152p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **3.17** | 3.16 ± 0.03 | 0.9% | 313K | 321K | 0.01 | 3.19 | 3.19 | 3.12 | 3.19 | 200 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2281-L2291) [🔍 111p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **2.88** | 2.88 ± 0.02 | 0.6% | 345K | 350K | 0.02 | 2.90 | 2.90 | 2.86 | 2.90 | 200 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2296-L2313) [🔍 155p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **387.6** | 390.4 ± 7.01 | 1.8% | 2.5K | 2.6K | 0.86 | 399.9 | 402.3 | 386.4 | 402.9 | 200 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2315-L2324) [🔍 91p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **2.63** | 2.62 ± 0.04 | 1.4% | 377K | 392K | 0.01 | 2.65 | 2.65 | 2.55 | 2.65 | 200 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2328-L2348) [🔍 135p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **25.4** | 25.4 ± 0.09 | 0.3% | 39.3K | 39.6K | 0.11 | 25.5 | 25.5 | 25.3 | 25.5 | 100 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2351-L2366) [🔍 135p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **948.6** | 965.4 ± 34.6 | 3.6% | 974 | 1.1K | 8.90 | 1013.0 | 1024.2 | 946.3 | 1027.0 | 25 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2369-L2384) [🔍 135p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **48.7** | 49.8 ± 3.04 | 6.1% | 18.1K | 20.8K | 0.57 | 53.9 | 54.9 | 48.1 | 55.2 | 100 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2388-L2405) [🔍 111p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **5.19** | 5.30 ± 0.23 | 4.3% | 176K | 194K | 0.17 | 5.62 | 5.67 | 5.15 | 5.69 | 200 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2408-L2450) [🔍 199p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **10.9** | 11.0 ± 0.17 | 1.5% | 88.4K | 91.8K | 0.02 | 11.2 | 11.3 | 10.9 | 11.3 | 200 |


### 3. Zig Full Suite Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `3c1d38d9cfcc`, 5 samples across 1 run(s))

#### 3.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 9 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.zig#L882-L896) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **36** | 36 ± 1.3 | 3.6% | 26.3M | 28.6M | 2 | 38 | 38 | 35 | 38 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.zig#L1004-L1018) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **64** | 63 ± 1.5 | 2.4% | 15.4M | 16.4M | 1 | 65 | 65 | 61 | 65 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.zig#L1206-L1219) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **55** | 56 ± 3.8 | 6.8% | 16.1M | 19.2M | 3 | 61 | 62 | 52 | 62 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1721-L1752) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **8** | 8 ± 0.5 | 7.2% | 125M | 143M | 1 | 8 | 8 | 7 | 8 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.zig#L1754-L1763) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **42** | 41 ± 2.9 | 7.0% | 22.2M | 26.3M | 4 | 45 | 45 | 38 | 45 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1765-L1787) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **8** | 9 ± 0.9 | 10.4% | 100M | 125M | 1 | 10 | 10 | 8 | 10 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.zig#L1789-L1798) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **50** | 51 ± 1.7 | 3.4% | 18.5M | 20.0M | 1 | 53 | 54 | 50 | 54 | 10K |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.zig#L1856-L1871) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **32** | 35 ± 7.1 | 19.9% | 20.8M | 31.3M | 1 | 45 | 47 | 32 | 48 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.zig#L1873-L1900) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **33** | 34 ± 2.7 | 8.0% | 26.3M | 32.3M | 2 | 37 | 38 | 31 | 38 | 2K |

#### 3.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 19 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L513-L537) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **861** | 866 ± 36.7 | 4.2% | 1.1M | 1.2M | 27 | 910 | 916 | 818 | 918 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.zig#L539-L555) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **300** | 297 ± 15.0 | 5.1% | 3.2M | 3.6M | 16 | 314 | 316 | 278 | 317 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.zig#L557-L574) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **212** | 210 ± 8.6 | 4.1% | 4.5M | 5.0M | 12 | 219 | 221 | 201 | 221 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.zig#L632-L646) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **161** | 164 ± 7.0 | 4.3% | 5.7M | 6.3M | 10 | 173 | 174 | 158 | 174 | 2K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.zig#L648-L670) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **811** | 830 ± 37.4 | 4.5% | 1.1M | 1.3M | 42 | 880 | 886 | 799 | 888 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L672-L700) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **870** | 879 ± 44.2 | 5.0% | 1.1M | 1.2M | 51 | 930 | 934 | 822 | 935 | 2K |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.zig#L786-L806) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **607** | 605 ± 22.9 | 3.8% | 1.6M | 1.7M | 38 | 631 | 633 | 581 | 633 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.zig#L808-L824) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **298** | 299 ± 14.9 | 5.0% | 3.2M | 3.5M | 26 | 316 | 317 | 284 | 317 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.zig#L834-L863) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **235** | 241 ± 9.8 | 4.1% | 3.9M | 4.3M | 12 | 253 | 255 | 232 | 255 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.zig#L865-L880) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **149** | 148 ± 5.9 | 3.9% | 6.5M | 7.1M | 10 | 154 | 154 | 141 | 154 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.zig#L898-L918) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **243** | 241 ± 10.5 | 4.3% | 4.0M | 4.4M | 13 | 251 | 252 | 226 | 252 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.zig#L987-L1002) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **145** | 146 ± 6.5 | 4.4% | 6.5M | 7.3M | 7 | 153 | 153 | 137 | 153 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.zig#L1261-L1273) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **178** | 178 ± 4.1 | 2.3% | 5.5M | 5.8M | 4 | 181 | 181 | 171 | 181 | 2K |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.zig#L1656-L1686) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **812** | 818 ± 17.9 | 2.2% | 1.2M | 1.3M | 24 | 838 | 839 | 796 | 839 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.zig#L1689-L1718) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **905** | 916 ± 25.6 | 2.8% | 1.0M | 1.1M | 14 | 951 | 958 | 897 | 960 | 2K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.zig#L1838-L1854) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **181** | 217 ± 85.7 | 39.5% | 2.7M | 5.8M | 5 | 333 | 363 | 171 | 370 | 256 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.zig#L1951-L1972) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **812** | 816 ± 33.1 | 4.1% | 1.2M | 1.3M | 3 | 856 | 864 | 773 | 866 | 500 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.zig#L1975-L2018) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **284** | 284 ± 5.2 | 1.8% | 3.4M | 3.6M | 3 | 289 | 290 | 276 | 290 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.zig#L2265-L2279) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **273** | 268 ± 13.7 | 5.1% | 3.5M | 4.0M | 23 | 281 | 282 | 252 | 282 | 5K |

#### 3.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 35 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.zig#L576-L606) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **2.60** | 2.63 ± 0.16 | 6.0% | 356K | 407K | 0.28 | 2.80 | 2.81 | 2.46 | 2.81 | 500 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.zig#L608-L630) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **1.11** | 1.11 ± 0.06 | 5.2% | 847K | 962K | 0.08 | 1.18 | 1.18 | 1.04 | 1.18 | 1K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.zig#L702-L721) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **1.22** | 1.19 ± 0.06 | 5.3% | 803K | 916K | 0.07 | 1.24 | 1.24 | 1.09 | 1.25 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.zig#L723-L761) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **1.35** | 1.36 ± 0.08 | 5.5% | 681K | 781K | 0.10 | 1.46 | 1.47 | 1.28 | 1.47 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.zig#L763-L784) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **3.08** | 3.05 ± 0.16 | 5.2% | 312K | 351K | 0.26 | 3.21 | 3.21 | 2.85 | 3.21 | 500 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.zig#L920-L933) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **1.68** | 1.69 ± 0.07 | 3.9% | 556K | 617K | 0.02 | 1.78 | 1.79 | 1.62 | 1.80 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.zig#L935-L953) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **1.59** | 1.62 ± 0.10 | 6.2% | 563K | 660K | 0.09 | 1.75 | 1.77 | 1.52 | 1.78 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.zig#L956-L985) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **2.01** | 2.01 ± 0.08 | 4.1% | 469K | 525K | 0.06 | 2.11 | 2.13 | 1.90 | 2.13 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.zig#L1020-L1043) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **2.35** | 2.38 ± 0.09 | 4.0% | 400K | 441K | 0.13 | 2.49 | 2.50 | 2.27 | 2.50 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.zig#L1045-L1066) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **2.38** | 2.40 ± 0.10 | 4.3% | 397K | 441K | 0.15 | 2.51 | 2.52 | 2.27 | 2.52 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.zig#L1068-L1091) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **22.8** | 22.9 ± 0.88 | 3.9% | 41.9K | 46.3K | 0.98 | 23.8 | 23.9 | 21.6 | 23.9 | 400 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.zig#L1093-L1112) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **1.52** | 1.51 ± 0.04 | 2.6% | 644K | 682K | 0.07 | 1.55 | 1.55 | 1.47 | 1.55 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.zig#L1114-L1127) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **2.94** | 2.90 ± 0.09 | 3.2% | 335K | 359K | 0.15 | 2.98 | 2.98 | 2.79 | 2.98 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.zig#L1136-L1174) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **3.25** | 3.32 ± 0.18 | 5.4% | 276K | 315K | 0.12 | 3.56 | 3.61 | 3.17 | 3.62 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.zig#L1176-L1191) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **2.31** | 2.31 ± 0.03 | 1.3% | 425K | 442K | 0.01 | 2.34 | 2.35 | 2.26 | 2.35 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.zig#L1193-L1204) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **2.27** | 2.30 ± 0.05 | 2.4% | 420K | 443K | 0.07 | 2.37 | 2.38 | 2.26 | 2.38 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.zig#L1221-L1235) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **3.42** | 3.42 ± 0.02 | 0.6% | 289K | 294K | 0.01 | 3.45 | 3.46 | 3.40 | 3.46 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.zig#L1237-L1259) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **3.47** | 3.47 ± 0.05 | 1.4% | 283K | 295K | 0.01 | 3.52 | 3.53 | 3.39 | 3.53 | 1K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.zig#L1275-L1289) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **2.93** | 2.92 ± 0.05 | 1.6% | 339K | 353K | 0.02 | 2.95 | 2.95 | 2.83 | 2.95 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.zig#L1291-L1311) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **2.79** | 2.76 ± 0.06 | 2.3% | 354K | 376K | 0.04 | 2.82 | 2.83 | 2.66 | 2.83 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.zig#L1313-L1336) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **2.94** | 2.92 ± 0.06 | 1.9% | 337K | 354K | 0.02 | 2.97 | 2.97 | 2.83 | 2.97 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.zig#L1338-L1352) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **2.14** | 2.14 ± 0.03 | 1.3% | 460K | 476K | 0.02 | 2.17 | 2.17 | 2.10 | 2.17 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.zig#L1388-L1411) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **1.34** | 1.31 ± 0.13 | 9.6% | 693K | 867K | 0.20 | 1.43 | 1.44 | 1.15 | 1.44 | 200 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.zig#L1413-L1438) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **1.93** | 1.97 ± 0.13 | 6.4% | 475K | 548K | 0.21 | 2.10 | 2.11 | 1.83 | 2.11 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1440-L1458) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **9.07** | 10.8 ± 2.62 | 24.3% | 69.3K | 114K | 3.81 | 14.1 | 14.4 | 8.80 | 14.4 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1460-L1514) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **21.1** | 20.5 ± 3.62 | 17.6% | 40.7K | 67.8K | 1.81 | 24.1 | 24.5 | 14.8 | 24.6 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.zig#L1516-L1603) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **130.6** | 134.3 ± 12.4 | 9.2% | 6.5K | 8.1K | 12.4 | 150.7 | 153.2 | 122.9 | 153.8 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.zig#L1605-L1635) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **2.29** | 2.29 ± 0.41 | 18.1% | 343K | 525K | 0.48 | 2.81 | 2.90 | 1.90 | 2.92 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.zig#L1801-L1836) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **1.93** | 1.99 ± 0.20 | 10.0% | 432K | 553K | 0.15 | 2.26 | 2.30 | 1.81 | 2.32 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.zig#L1903-L1949) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **1.21** | 1.21 ± 0.03 | 2.3% | 792K | 836K | 0.01 | 1.25 | 1.26 | 1.20 | 1.26 | 500 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.zig#L2030-L2069) [🔍 112p](slices/58_backend_core_memory_commits.md) | **2.74** | 2.75 ± 0.08 | 2.7% | 350K | 377K | 0.06 | 2.84 | 2.86 | 2.66 | 2.86 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.zig#L2072-L2126) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **19.6** | 19.8 ± 0.54 | 2.7% | 48.9K | 52.0K | 0.88 | 20.4 | 20.4 | 19.2 | 20.4 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.zig#L2129-L2178) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **52.9** | 52.2 ± 1.88 | 3.6% | 18.5K | 20.2K | 2.73 | 53.9 | 54.0 | 49.6 | 54.0 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.zig#L2181-L2231) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **2.17** | 2.17 ± 0.07 | 3.4% | 438K | 481K | 0.05 | 2.26 | 2.28 | 2.08 | 2.28 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.zig#L2233-L2263) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **2.17** | 2.11 ± 0.10 | 4.5% | 457K | 500K | 0.17 | 2.19 | 2.19 | 2.00 | 2.19 | 500 |

### 4. 1v1 Statistical Comparison (Odin vs. Zig, Commit `32cdc130a8b9`)

#### 4.1 Sub-100ns Fast Path (`ns`, 14 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L562-L579) ([Zig](bench_xitdb.zig#L557-L574) · [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md)) | **2.30x** | **92** | 212 | `30.0` ★ | 92 ± 1.7 | 1.9% | 94 | 210 ± 8.6 | 4.1% | 219 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L642-L658) ([Zig](bench_xitdb.zig#L632-L646) · [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md)) | **2.88x** | **56** | 161 | `33.8` ★ | 57 ± 1.0 | 1.7% | 58 | 164 ± 7.0 | 4.3% | 173 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L876-L891) ([Zig](bench_xitdb.zig#L865-L880) · [🔍 30p](slices/15_array_list_radix_trie_random_get.md)) | **2.04x** | **73** | 149 | `27.6` ★ | 74 ± 1.5 | 2.0% | 75 | 148 ± 5.9 | 3.9% | 154 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L893-L910) ([Zig](bench_xitdb.zig#L882-L896) · [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md)) | **1.89x** | **19** | 36 | `28.6` ★ | 19 ± 0.1 | 0.5% | 20 | 36 ± 1.3 | 3.6% | 38 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1002-L1017) ([Zig](bench_xitdb.zig#L987-L1002) · [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md)) | **1.67x** | **87** | 145 | `19.4` ★ | 88 ± 2.0 | 2.3% | 90 | 146 ± 6.5 | 4.4% | 153 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1019-L1036) ([Zig](bench_xitdb.zig#L1004-L1018) · [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md)) | **3.05x** | **21** | 64 | `62.9` ★ | 21 ± 0.1 | 0.6% | 21 | 63 ± 1.5 | 2.4% | 65 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1226-L1241) ([Zig](bench_xitdb.zig#L1206-L1219) · [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md)) | **2.75x** | **20** | 55 | `21.0` ★ | 20 ± 0.2 | 1.1% | 20 | 56 ± 3.8 | 6.8% | 61 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1648-L1673) ([Zig](bench_xitdb.zig#L1721-L1752) · [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md)) | 0.73x | 11 | **8** | `8.1` ★ | 11 ± 0.7 | 6.7% | 12 | 8 ± 0.5 | 7.2% | 8 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1675-L1684) ([Zig](bench_xitdb.zig#L1754-L1763) · [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md)) | **2.21x** | **19** | 42 | `17.6` ★ | 19 ± 0.2 | 1.3% | 19 | 41 ± 2.9 | 7.0% | 45 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1686-L1702) ([Zig](bench_xitdb.zig#L1765-L1787) · [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md)) | 0.73x | 11 | **8** | `6.8` ★ | 11 ± 0.0 | 0.0% | 11 | 9 ± 0.9 | 10.4% | 10 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1704-L1713) ([Zig](bench_xitdb.zig#L1789-L1798) · [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md)) | **2.63x** | **19** | 50 | `31.0` ★ | 20 ± 1.5 | 7.4% | 22 | 51 ± 1.7 | 3.4% | 53 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1755-L1771) ([Zig](bench_xitdb.zig#L1838-L1854) · [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md)) | **1.95x** | **93** | 181 | `3.2` ★ | 93 ± 0.9 | 1.0% | 94 | 217 ± 85.7 | 39.5% | 333 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1773-L1788) ([Zig](bench_xitdb.zig#L1856-L1871) · [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md)) | **4.57x** | **7** | 32 | `9.0` ★ | 7 ± 0.1 | 2.0% | 7 | 35 ± 7.1 | 19.9% | 45 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1790-L1820) ([Zig](bench_xitdb.zig#L1873-L1900) · [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md)) | 0.87x | 38 | **33** | `3.4` ★ | 38 ± 1.3 | 3.3% | 40 | 34 ± 2.7 | 8.0% | 37 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 35 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) ([Zig](bench_xitdb.zig#L513-L537) · [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md)) | **2.66x** | **324** | 861 | `32.8` ★ | 324 ± 4.0 | 1.2% | 328 | 866 ± 36.7 | 4.2% | 910 |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L544-L560) ([Zig](bench_xitdb.zig#L539-L555) · [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md)) | **1.94x** | **155** | 300 | `21.1` ★ | 154 ± 2.3 | 1.5% | 156 | 297 ± 15.0 | 5.1% | 314 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L614-L640) ([Zig](bench_xitdb.zig#L608-L630) · [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md)) | **4.06x** | **273** | 1,109 | `17.9` ★ | 313 ± 81.0 | 25.9% | 424 | 1,111 ± 58.0 | 5.2% | 1,175 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L660-L683) ([Zig](bench_xitdb.zig#L648-L670) · [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md)) | **2.38x** | **341** | 811 | `29.0` ★ | 341 ± 4.9 | 1.4% | 348 | 830 ± 37.4 | 4.5% | 880 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L685-L709) ([Zig](bench_xitdb.zig#L672-L700) · [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md)) | **2.64x** | **330** | 870 | `27.8` ★ | 330 ± 1.8 | 0.5% | 332 | 879 ± 44.2 | 5.0% | 930 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L711-L729) ([Zig](bench_xitdb.zig#L702-L721) · [🔍 83p](slices/09_hamt_counted_hash_map_remove.md)) | **4.21x** | **290** | 1,222 | `31.5` ★ | 293 ± 9.0 | 3.1% | 304 | 1,189 ± 63.1 | 5.3% | 1,241 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L731-L771) ([Zig](bench_xitdb.zig#L723-L761) · [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md)) | **4.18x** | **322** | 1,345 | `30.7` ★ | 323 ± 6.7 | 2.1% | 331 | 1,363 ± 75.5 | 5.5% | 1,456 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L773-L793) ([Zig](bench_xitdb.zig#L763-L784) · [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md)) | **8.95x** | **344** | 3,078 | `38.3` ★ | 347 ± 4.8 | 1.4% | 353 | 3,054 ± 158 | 5.2% | 3,207 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L795-L813) ([Zig](bench_xitdb.zig#L786-L806) · [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md)) | **1.73x** | **351** | 607 | `24.1` ★ | 353 ± 4.5 | 1.3% | 359 | 605 ± 22.9 | 3.8% | 631 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L815-L831) ([Zig](bench_xitdb.zig#L808-L824) · [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md)) | **2.01x** | **148** | 298 | `22.5` ★ | 148 ± 1.5 | 1.0% | 150 | 299 ± 14.9 | 5.0% | 316 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) ([Zig](bench_xitdb.zig#L834-L863) · [🔍 91p](slices/14_array_list_radix_trie_append.md)) | **1.37x** | **172** | 235 | `15.3` ★ | 172 ± 2.3 | 1.3% | 174 | 241 ± 9.8 | 4.1% | 253 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L912-L930) ([Zig](bench_xitdb.zig#L898-L918) · [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md)) | **1.72x** | **141** | 243 | `21.2` ★ | 141 ± 1.4 | 1.0% | 143 | 241 ± 10.5 | 4.3% | 251 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L932-L946) ([Zig](bench_xitdb.zig#L920-L933) · [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md)) | **2.96x** | **567** | 1,679 | `38.0` ★ | 566 ± 4.0 | 0.7% | 570 | 1,690 ± 66.0 | 3.9% | 1,776 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) ([Zig](bench_xitdb.zig#L956-L985) · [🔍 107p](slices/20_linked_array_list_b_tree_append.md)) | **5.31x** | **378** | 2,007 | `39.9` ★ | 392 ± 36.3 | 9.3% | 441 | 2,010 ± 83.2 | 4.1% | 2,111 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1038-L1064) ([Zig](bench_xitdb.zig#L1020-L1043) · [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md)) | **5.57x** | **421** | 2,347 | `45.7` ★ | 429 ± 14.0 | 3.3% | 448 | 2,379 ± 94.5 | 4.0% | 2,490 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1066-L1085) ([Zig](bench_xitdb.zig#L1045-L1066) · [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md)) | **4.45x** | **534** | 2,378 | `40.1` ★ | 535 ± 7.2 | 1.3% | 544 | 2,396 ± 104 | 4.3% | 2,512 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1114-L1131) ([Zig](bench_xitdb.zig#L1093-L1112) · [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md)) | **5.79x** | **263** | 1,524 | `69.2` ★ | 264 ± 6.1 | 2.3% | 272 | 1,514 ± 40.0 | 2.6% | 1,553 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1133-L1147) ([Zig](bench_xitdb.zig#L1114-L1127) · [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md)) | **4.75x** | **618** | 2,937 | `55.7` ★ | 618 ± 0.8 | 0.1% | 619 | 2,900 ± 91.6 | 3.2% | 2,982 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) ([Zig](bench_xitdb.zig#L1136-L1174) · [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md)) | **5.25x** | **618** | 3,247 | `33.9` ★ | 618 ± 2.3 | 0.4% | 621 | 3,321 ± 178 | 5.4% | 3,564 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1196-L1211) ([Zig](bench_xitdb.zig#L1176-L1191) · [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md)) | **8.36x** | **276** | 2,307 | `146.3` ★ | 276 ± 2.4 | 0.9% | 278 | 2,308 ± 31.0 | 1.3% | 2,343 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1213-L1224) ([Zig](bench_xitdb.zig#L1193-L1204) · [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md)) | **10.04x** | **226** | 2,270 | `84.7` ★ | 227 ± 2.0 | 0.9% | 229 | 2,303 ± 54.7 | 2.4% | 2,373 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1243-L1258) ([Zig](bench_xitdb.zig#L1221-L1235) · [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md)) | **4.55x** | **751** | 3,415 | `264.5` ★ | 753 ± 5.9 | 0.8% | 762 | 3,423 ± 21.8 | 0.6% | 3,451 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1260-L1286) ([Zig](bench_xitdb.zig#L1237-L1259) · [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md)) | **9.04x** | **384** | 3,472 | `141.6` ★ | 383 ± 3.2 | 0.8% | 386 | 3,468 ± 48.6 | 1.4% | 3,520 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1288-L1300) ([Zig](bench_xitdb.zig#L1261-L1273) · [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md)) | **1.58x** | **113** | 178 | `32.9` ★ | 114 ± 1.5 | 1.3% | 116 | 178 ± 4.1 | 2.3% | 181 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1302-L1317) ([Zig](bench_xitdb.zig#L1275-L1289) · [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md)) | **5.23x** | **561** | 2,934 | `110.4` ★ | 561 ± 0.5 | 0.1% | 562 | 2,916 ± 47.7 | 1.6% | 2,947 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1319-L1337) ([Zig](bench_xitdb.zig#L1291-L1311) · [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md)) | **4.78x** | **583** | 2,785 | `74.9` ★ | 586 ± 5.9 | 1.0% | 594 | 2,762 ± 64.7 | 2.3% | 2,819 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) ([Zig](bench_xitdb.zig#L1313-L1336) · [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md)) | **5.15x** | **570** | 2,938 | `92.5` ★ | 570 ± 1.4 | 0.3% | 572 | 2,924 ± 56.9 | 1.9% | 2,965 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1362-L1376) ([Zig](bench_xitdb.zig#L1338-L1352) · [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md)) | **8.25x** | **259** | 2,136 | `155.0` ★ | 258 ± 1.3 | 0.5% | 259 | 2,141 ± 27.1 | 1.3% | 2,171 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) ([Zig](bench_xitdb.zig#L1388-L1411) · [🔍 54p](slices/39_replication_genesis_200_moments.md)) | **1.76x** | **761** | 1,338 | `9.6` ★ | 762 ± 17.9 | 2.3% | 785 | 1,307 ± 125 | 9.6% | 1,434 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) ([Zig](bench_xitdb.zig#L1656-L1686) · [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md)) | **2.48x** | **328** | 812 | `60.5` ★ | 327 ± 3.1 | 0.9% | 330 | 818 ± 17.9 | 2.2% | 838 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) ([Zig](bench_xitdb.zig#L1689-L1718) · [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md)) | **2.59x** | **350** | 905 | `48.0` ★ | 351 ± 6.2 | 1.8% | 359 | 916 ± 25.6 | 2.8% | 951 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1823-L1876) ([Zig](bench_xitdb.zig#L1903-L1949) · [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md)) | **3.08x** | **391** | 1,205 | `66.8` ★ | 390 ± 2.8 | 0.7% | 393 | 1,215 ± 27.5 | 2.3% | 1,252 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1878-L1899) ([Zig](bench_xitdb.zig#L1951-L1972) · [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md)) | **3.17x** | **256** | 812 | `36.7` ★ | 256 ± 8.0 | 3.1% | 266 | 816 ± 33.1 | 4.1% | 856 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1902-L1935) ([Zig](bench_xitdb.zig#L1975-L2018) · [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md)) | **1.81x** | **157** | 284 | `48.7` ★ | 156 ± 2.7 | 1.7% | 159 | 284 ± 5.2 | 1.8% | 289 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2133-L2148) ([Zig](bench_xitdb.zig#L2265-L2279) · [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md)) | **2.68x** | **102** | 273 | `26.5` ★ | 103 ± 2.3 | 2.3% | 105 | 268 ± 13.7 | 5.1% | 281 |

#### 4.3 Multi-Microsecond Transactions & Compaction (`µs`, 14 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) ([Zig](bench_xitdb.zig#L576-L606) · [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md)) | **1.45x** | **1.79** | 2.60 | `11.8` ★ | 1.79 ± 0.01 | 0.4% | 1.80 | 2.63 ± 0.16 | 6.0% | 2.80 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L948-L964) ([Zig](bench_xitdb.zig#L935-L953) · [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md)) | **1.23x** | **1.29** | 1.59 | `6.2` ★ | 1.31 ± 0.04 | 3.4% | 1.37 | 1.62 ± 0.10 | 6.2% | 1.75 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1087-L1112) ([Zig](bench_xitdb.zig#L1068-L1091) · [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md)) | **12.44x** | **1.83** | 22.8 | `53.1` ★ | 1.86 ± 0.06 | 3.3% | 1.94 | 22.9 ± 0.88 | 3.9% | 23.8 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) ([Zig](bench_xitdb.zig#L1413-L1438) · [🔍 102p](slices/40_replication_incremental_1_moment_delta.md)) | **1.07x** | **1.80** | 1.93 | `2.5` ★ | 1.82 ± 0.04 | 2.4% | 1.88 | 1.97 ± 0.13 | 6.4% | 2.10 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) ([Zig](bench_xitdb.zig#L1440-L1458) · [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md)) | 0.96x | 9.41 | **9.07** | `1.2` ~ | 9.39 ± 0.23 | 2.4% | 9.65 | 10.8 ± 2.62 | 24.3% | 14.1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) ([Zig](bench_xitdb.zig#L1460-L1514) · [🔍 99p](slices/42_compaction_file_offset_map_200_1.md)) | 0.92x | 23.0 | **21.1** | `2.1` ★ | 25.6 ± 4.05 | 15.8% | 30.9 | 20.5 ± 3.62 | 17.6% | 24.1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) ([Zig](bench_xitdb.zig#L1516-L1603) · [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md)) | **1.75x** | **74.6** | 130.6 | `10.4` ★ | 74.6 ± 3.53 | 4.7% | 79.1 | 134.3 ± 12.4 | 9.2% | 150.7 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) ([Zig](bench_xitdb.zig#L1605-L1635) · [🔍 55p](slices/44_replication_post_compaction_resync.md)) | 0.98x | 2.33 | **2.29** | `0.3` ~ | 2.34 ± 0.02 | 1.0% | 2.37 | 2.29 ± 0.41 | 18.1% | 2.81 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) ([Zig](bench_xitdb.zig#L1801-L1836) · [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md)) | 0.83x | 2.32 | **1.93** | `3.8` ★ | 2.32 ± 0.01 | 0.6% | 2.34 | 1.99 ± 0.20 | 10.0% | 2.26 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) ([Zig](bench_xitdb.zig#L2030-L2069) · [🔍 112p](slices/58_backend_core_memory_commits.md)) | **1.44x** | **1.90** | 2.74 | `24.7` ★ | 1.90 ± 0.02 | 1.0% | 1.92 | 2.75 ± 0.08 | 2.7% | 2.84 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) ([Zig](bench_xitdb.zig#L2072-L2126) · [🔍 113p](slices/59_backend_core_buffered_file_commits.md)) | 0.79x | 24.7 | **19.6** | `8.1` ★ | 25.2 ± 1.41 | 5.6% | 27.2 | 19.8 ± 0.54 | 2.7% | 20.4 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) ([Zig](bench_xitdb.zig#L2129-L2178) · [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md)) | 0.74x | 71.2 | **52.9** | `9.5` ★ | 73.0 ± 4.53 | 6.2% | 79.2 | 52.2 ± 1.88 | 3.6% | 53.9 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2067-L2108) ([Zig](bench_xitdb.zig#L2181-L2231) · [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md)) | **1.13x** | **1.93** | 2.17 | `7.1` ★ | 1.92 ± 0.03 | 1.4% | 1.95 | 2.17 ± 0.07 | 3.4% | 2.26 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2110-L2131) ([Zig](bench_xitdb.zig#L2233-L2263) · [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md)) | **2.03x** | **1.07** | 2.17 | `24.3` ★ | 1.07 ± 0.01 | 0.7% | 1.08 | 2.11 ± 0.10 | 4.5% | 2.19 |

### 5. Database Storage Footprint (`bytes_used > 0`)

| # | Benchmark | Ops | Odin Size | Zig Size |
| ---: | :--- | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | 2K | 214.5 KB | 214.5 KB |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | 500 | 457.7 KB | 457.7 KB |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) [🔍 91p](slices/14_array_list_radix_trie_append.md) | 2K | 19.3 KB | 19.3 KB |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | 2K | 45.3 KB | 45.3 KB |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | 2K | 115.4 KB | 115.4 KB |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | 2K | 80.0 KB | 80.0 KB |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) [🔍 54p](slices/39_replication_genesis_200_moments.md) | 200 | 250.9 KB | 250.9 KB |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | 100 | 132.7 KB | 132.7 KB |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | 1 | 23.4 KB | 23.4 KB |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) [🔍 55p](slices/44_replication_post_compaction_resync.md) | 1 | 23.4 KB | 23.4 KB |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | 2K | 224.7 KB | 224.7 KB |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | 2K | 248.7 KB | 248.7 KB |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | 256 | 1024.1 KB | 1024.1 KB |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) [🔍 112p](slices/58_backend_core_memory_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2176-L2211) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | 500 | 231.4 KB | — |
<!-- END_BENCHMARK_TABLE -->

---

## Benchmark Workloads

The benchmark suite evaluates the core operational profiles of an immutable structural database:

### 1. HAMT Key-Value Throughput (`Hash_Map` & `Counted_Hash_Map`)
* **Batch Insert (Single Transaction)**: Inserts $N$ keys in a single moment, exercising the in-place HAMT node mutation fast path (`ptr >= tx_start`) and stack-allocated key digest buffers (`database_digest_string_buf`).
* **Historical Branching (Multi-Moment CoW)**: Commits $M$ sequential moments where each moment updates a subset of keys from the prior moment, measuring path-copying Copy-on-Write overhead and file growth per commit.
* **Point Lookups & Full Iteration**: Random key lookups via `hash_map_get_cursor` and full-tree traversal via the zero-allocation stack `Cursor_Iterator`.

### 2. Indexed & Positional Lists (`Array_List` vs. `Linked_Array_List`)
* **Sequential Append**: Compares 16-way Radix Trie (`Array_List`) append throughput against count-augmented B-Tree (`Linked_Array_List`) append throughput.
* **Random-Access Reads**: Measures $O(\log_{16} N)$ index lookup across multi-tier trees.
* **Mid-List Structural Edits (`Linked_Array_List`)**: Benchmarks arbitrary mid-list insertions (`linked_array_list_insert`), deletions (`linked_array_list_remove`), range slicing (`linked_array_list_slice`), and $O(\log N)$ B-Tree concatenation (`linked_array_list_concat`).

### 3. Ordered B+Tree Indexing (`Sorted_Map` & `Sorted_Set`)
* **Out-of-Order Key Insertion**: Inserts pseudo-randomly permuted keys into a `Sorted_Map`, exercising binary search, separator promotion, and B+Tree leaf/branch splitting.
* **Rank & Positional Index Queries**: Measures `sorted_map_rank` ($O(\log N)$ count of keys $< k$) and `sorted_map_get_index_kv_pair` ($O(\log N)$ lookup of the $i$-th sorted key).
* **Range & Prefix Scans**: Measures lower-bound seek + sequential leaf iteration via `sorted_map_iterator_from_string`.

### 4. Compaction & Incremental Replication
* **History Compaction**: Measures `database_compact` throughput and space reclamation when compacting a multi-moment database down to its latest moment using `Memory_Offset_Map` vs. `File_Offset_Map`.
* **Delta Replication**: Measures the time to compute `database_replication_start`, extract committed delta bytes, and apply them to a replica (`database_apply_replicated_bytes`).

### 5. Cryptographic Hashers (`SHA-1` vs. `SHA-256`)
* Compares hashing throughput on short keys ($\le 32\text{ B}$) and large blocks ($4\text{ KiB}$), verifying hardware x86 SHA-NI acceleration on `amd64` targets.

### 6. 5-Layer DSL & Datalog Engine (`run_dsl_benchmarks`)
* **Layer 1 & 2 (`parse_selector`, `get_uint`, `Tx` + Secondary Index)**: Measures string selector path resolution (`@-1.users["..."].age`) and Datomic-style `Tx` commits with automatic `Sorted_Map` secondary index maintenance (`tx_index_on`).
* **Layer 3 (`marshal`, `unmarshal`, `pull`)**: Measures native Odin struct tag reflection (`xitdb:"..."`) and Datomic-style `pull` subtree projections with range slicing.
* **Layer 4 (`diff_moments`, `history_of`)**: Measures $O(1)$ `Slot`-pointer subtree skipping when diffing moments where only 1 of 700 entities changed, plus temporal path lineage across moments.
* **Layer 5 (`query_datalog`)**: Measures B+Tree prefix pushdown (`starts_with`) with index nested-loop joins, grouped aggregations (`count`, `sum`, `min`, `max`), and cycle-safe BFS transitive closure (`reach` over a 32-node directed ring).

---

## Storage Backend Comparison

Benchmarks can be parameterized across the three `Core` backends to evaluate I/O trade-offs:

| Backend | Constructor | Best For |
| :--- | :--- | :--- |
| **`Core_Memory`** | `core_memory_init()` | Measuring pure data-structure CPU & memory overhead without OS syscall noise. |
| **`Core_Buffered_File`** | `core_buffered_file_open(path, 2*1024*1024, flags, fsync)` | Production file workloads—coalesces node reads/writes in a contiguous tail window before flushing on transaction sync. |
| **`Core_File`** | `core_file_open(path, flags, fsync)` | Baseline unbuffered OS file I/O comparison. |

> **Note on `fsync`:** When benchmarking raw disk throughput across thousands of tiny transactions, pass `fsync = false` to measure OS page-cache write speed, or `fsync = true` to measure hardware disk-flush latency per transaction.
