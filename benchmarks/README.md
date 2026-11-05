# xitdb Benchmarks

This directory contains the statistical performance benchmark suite for `xitdb`, measuring throughput ($\text{ops/sec}$), median/mean latency ($\text{ns/op}$), variance ($\pm\sigma$, $\text{CV}\%$, $\text{IQR}$, $\text{p95}$, $\text{p99}$, $\text{min..max}$), and resulting database byte footprint across all collection types, storage backends, and the 5-layer DSL/Datalog engine.

---

## Running the Benchmarks

Always compile benchmarks with `-o:speed` (and `-microarch:native` to enable target-specific SIMD instructions alongside runtime x86 SHA-NI detection). By default, each benchmark group executes **1 warmup pass** followed by **5 measured trials** (`--runs 5 --warmup 1`) and automatically tags results with the current Git commit SHA:

```bash
odin run benchmarks -o:speed -microarch:native
```

You can customize the number of measured trials, warmup passes, commit SHA, run ID, or append multiple runs for the same commit:

```bash
# Run 10 measured trials after 2 warmup passes
odin run benchmarks -o:speed -microarch:native -- --runs 10 --warmup 2

# Append an additional run session to odin.jsonl & history.jsonl for the current commit
odin run benchmarks -o:speed -microarch:native -- --runs 5 --append

# Disable bounds checking in hot loops for peak release numbers
odin run benchmarks -o:speed -microarch:native -no-bounds-check -- --runs 5
```

### 1v1 Comparison with Upstream Zig (`reference/xitdb-zig` & `reference/xitdb-zig-patched`)

The upstream Zig reference implementation is tracked in `reference/xitdb-zig` (and our patched fork with all 6 guide optimizations is tracked in `reference/xitdb-zig-patched`). To run the Zig benchmark suite (requires Zig `0.17.0-dev` matching `reference/xitdb-zig/build.zig.zon`):

```bash
# Run against upstream reference/xitdb-zig (default)
zig build bench -Doptimize=ReleaseFast -Dcpu=native -- --runs 5 --warmup 1

# Run against reference/xitdb-zig-patched
zig build bench -Doptimize=ReleaseFast -Dcpu=native -Dpatched=true -- --runs 5 --warmup 1
```

Or run both suites back-to-back with unified commit/run tagging and statistical significance reporting (Welch's $z$-test):

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
./benchmarks/compare_1v1.py --groups dsl --filter "Datalog|Secondary Index"
odin run benchmarks -o:speed -microarch:native -- --groups sorted_map,compaction --filter "Incremental"
```

### Multi-Run Pooling, Commit History & Regression Analysis (`history.jsonl`)

Every benchmark run writes enriched JSONL records to:
- `benchmarks/odin.jsonl` (latest Odin snapshot, or accumulated runs with `--append`)
- `benchmarks/zig.jsonl` (latest Zig snapshot, or accumulated runs with `--append`)
- `benchmarks/history.jsonl` (append-only multi-commit, multi-run history log)

Each JSONL line captures the Git commit SHA, run session ID, summary statistics, quantiles, and the raw `samples_ns` array:
```json
{"rank":1,"lang":"odin","commit":"cadcc64f08ac","run_id":"run-1793600514","name":"HAMT Hash_Map bulk put (1 tx)","ops":2000,"runs":5,"warmup":1,"total_ms":0.404,"ns_per_op":202,"mean_ns":205.20,"median_ns":202.00,"stddev_ns":8.41,"variance_ns2":70.70,"cv_pct":4.10,"min_ns":198,"max_ns":219,"iqr_ns":7.00,"p95_ns":217,"p99_ns":219,"ops_per_sec":4950495,"bytes_used":219650,"samples_ns":[219,205,202,200,198]}
```

 When multiple runs are recorded for the same `(commit, lang, name)`, `compare_1v1.py` and `update_readme.sh` automatically **pool all `samples_ns` arrays** across those runs and recompute unified variance metrics:

```bash
# List all commits, run sessions, and pooled sample counts in history.jsonl
./benchmarks/compare_1v1.py --list-commits

# Inspect individual runs, quantiles (IQR, p95, p99), and raw sample arrays for matching tests
./benchmarks/compare_1v1.py --inspect "HAMT Hash_Map"

# Compare two Git commits for statistically significant speedups or regressions (Welch's t/z test)
./benchmarks/compare_1v1.py --compare-commits <baseline_sha> <candidate_sha> --lang odin
```

`.gitattributes` configures `*.jsonl diff=jsonl`. To get human-readable `git diff` output on `.jsonl` files, configure the `jsonl` textconv driver in your local Git config:

```bash
git config diff.jsonl.textconv "jq -r '\"#\\(.rank) [\\(.commit // \"?\")] \\(.name) | \\(.ns_per_op) ± \\(.stddev_ns // 0) ns/op (CV \\(.cv_pct // 0)%, n=\\(.runs // 1)) | \\(.ops_per_sec) ops/sec\"'"
```

To regenerate the reference tables below from `benchmarks/odin.jsonl` and `benchmarks/zig.jsonl` (optionally filtering by commit prefix):

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
### 1. Latest Code-Change Impact & Affected Benchmarks (`3b3da703c200` → `2ea57460f65b`, Odin, 16 / 75 tests re-run)

- **Code Diff Inspected:** `e672ad7~1..e672ad7` · **Changed Files:** `xitdb/btree.odin`, `xitdb/compact_replicate.odin`, `xitdb/core.odin`, `xitdb/cursor.odin`
- **Modified Procedures:** `_compactor_reserve_block`, `_memory_offset_map_grow`, `btree_get_for_write`, `btree_insert`, `btree_remove`, `btree_split_left`, `btree_split_right`, `btree_split`, `core_write_all`, `cursor_iterator_linked_array_list_from_index`, `cursor_iterator_sorted_from_index`, `database_compact`, `offset_map_put`
- **Mapped Benchmark Scope:** Odin groups=`lists`, `sorted_map`, `compaction`, `hashers`, `backends` · filter=`Linked_Array_List|Heterogeneous DAG|4-level nested|Compaction|Post-compaction|Core_Buffered_File|File_Offset_Map|Sorted_Map (B+Tree) index-seek|Linked_Array_List (B-Tree) index-seek` (**16 / 75** Odin benchmarks executed; **59** unchanged benchmarks retained from `3b3da70`)

#### 1.1 Sub-100ns Fast Path (`ns`, 2 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `3b3da70` (`ns`) | Curr `2ea5746` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L956-L971) [🔍 30p](slices/21_linked_array_list_b_tree_random_get.md) | `~NOISE` | `-1.8%` | 1.02x | 55 | **54** | `1.5` | 55 ± 1.3 | 54 ± 1.2 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L973-L990) [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md) | `~NOISE` | `+7.7%` | 0.93x | 13 | **14** | `1.3` | 13 ± 0.5 | 14 ± 0.4 |

#### 1.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 9 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `3b3da70` (`ns`) | Curr `2ea5746` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) [🔍 94p](slices/20_linked_array_list_b_tree_append.md) | `~NOISE` | `-5.6%` | 1.06x | 248 | **234** | `8.1` | 247 ± 1.3 | 232 ± 4.1 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L992-L1018) [🔍 83p](slices/23_linked_array_list_b_tree_middle_insert.md) | `~NOISE` | `-5.0%` | 1.05x | 282 | **268** | `3.7` | 282 ± 4.3 | 268 ± 7.5 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1020-L1039) [🔍 84p](slices/24_linked_array_list_b_tree_middle_remove.md) | `~NOISE` | `+0.9%` | 0.99x | 338 | **341** | `0.5` | 342 ± 8.2 | 340 ± 6.0 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1041-L1066) [🔍 89p](slices/25_linked_array_list_b_tree_concat_slice.md) | `~NOISE` | `+3.9%` | 0.96x | 845 | **878** | `1.9` | 845 ± 8.3 | 916 ± 84.7 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1068-L1085) [🔍 75p](slices/26_linked_array_list_b_tree_in_place_put.md) | `~NOISE` | `+0.6%` | 0.99x | 169 | **170** | `1.1` | 169 ± 1.5 | 170 ± 2.0 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1087-L1101) [🔍 20p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | `~NOISE` | `+0.5%` | 1.00x | 411 | **413** | `0.9` | 410 ± 4.8 | 417 ± 16.2 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1256-L1271) [🔍 21p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | `~NOISE` | `+4.3%` | 0.96x | 414 | **432** | `9.1` | 414 ± 1.7 | 430 ± 3.8 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1777-L1830) [🔍 62p](slices/55_path_4_level_nested_cursor_write_path.md) | `~NOISE` | `-3.3%` | 1.03x | 244 | **236** | `0.8` | 241 ± 8.5 | 237 ± 2.6 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1832-L1853) [🔍 18p](slices/56_path_4_level_nested_cursor_read_path.md) | `~NOISE` | `+4.2%` | 0.96x | 142 | **148** | `2.3` | 142 ± 1.5 | 153 ± 10.3 |

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 5 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `3b3da70` (`µs`) | Curr `2ea5746` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) [🔍 90p](slices/41_compaction_memory_offset_map_200_1.md) | `~NOISE` | `+15.5%` | 0.87x | 1.99 | **2.30** | `2.4` | 2.06 ± 0.20 | 2.36 ± 0.19 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) [🔍 89p](slices/42_compaction_file_offset_map_200_1.md) | `~NOISE` | `+2.1%` | 0.98x | 9.43 | **9.63** | `0.8` | 9.55 ± 0.43 | 9.76 ± 0.40 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) [🔍 154p](slices/43_compaction_heterogeneous_dag_dedup.md) | `~NOISE` | `-0.2%` | 1.00x | 32.8 | **32.8** | `0.3` | 33.1 ± 2.08 | 33.4 ± 1.67 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) [🔍 43p](slices/44_replication_post_compaction_resync.md) | `~NOISE` | `+4.8%` | 0.95x | 1.46 | **1.53** | `4.0` | 1.46 ± 0.02 | 1.55 ± 0.04 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) [🔍 102p](slices/59_backend_core_buffered_file_commits.md) | `~NOISE` | `+1.5%` | 0.99x | 16.7 | **17.0** | `3.0` | 16.7 ± 0.15 | 17.0 ± 0.08 |


### 2. Odin Full Suite Results (`-o:speed -microarch:native`, Commit `2ea57460f65b`, 5 samples across 1 run(s))

> **Selective update (`2ea5746`):** Re-ran **16 / 75** affected benchmarks (marked with `↻` in `#` below; see Section 1 above for the code-change impact & progression table). Unchanged benchmarks retain their prior baseline.


#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 20 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L498-L514) [🔍 40p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **91** | 106 ± 32.6 | 30.8% | 6.1M | 11.1M | 2 | 150 | 161 | 90 | 164 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L516-L533) [🔍 33p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **57** | 65 ± 18.9 | 29.0% | 10.1M | 17.9M | 2 | 91 | 97 | 56 | 99 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L596-L612) [🔍 20p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **36** | 36 ± 0.4 | 1.2% | 27.0M | 27.8M | 0 | 37 | 37 | 36 | 37 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L769-L785) [🔍 42p](slices/13_hamt_counted_hash_set_membership_check.md) | **91** | 91 ± 1.2 | 1.3% | 10.8M | 11.1M | 1 | 93 | 93 | 90 | 93 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L830-L845) [🔍 24p](slices/15_array_list_radix_trie_random_get.md) | **46** | 46 ± 0.5 | 1.2% | 21.7M | 22.2M | 1 | 46 | 46 | 45 | 46 | 2K |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L847-L864) [🔍 21p](slices/16_array_list_radix_trie_iterator_scan.md) | **12** | 12 ± 0.0 | 0.0% | 83.3M | 83.3M | 0 | 12 | 12 | 12 | 12 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L866-L884) [🔍 67p](slices/17_array_list_radix_trie_in_place_put.md) | **96** | 95 ± 1.9 | 2.0% | 10.2M | 10.8M | 2 | 98 | 98 | 93 | 98 | 2K |
| 21 ↻ | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L956-L971) [🔍 30p](slices/21_linked_array_list_b_tree_random_get.md) | **54** | 54 ± 1.2 | 2.3% | 18.2M | 19.2M | 1 | 55 | 55 | 52 | 55 | 2K |
| 22 ↻ | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L973-L990) [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **14** | 14 ± 0.4 | 3.2% | 71.4M | 76.9M | 0 | 14 | 14 | 13 | 14 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1180-L1195) [🔍 20p](slices/31_sorted_map_b_tree_ordered_scan.md) | **13** | 13 ± 0.0 | 0.0% | 76.9M | 76.9M | 0 | 13 | 13 | 13 | 13 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1242-L1254) [🔍 29p](slices/34_sorted_map_b_tree_get_index_select.md) | **65** | 65 ± 0.8 | 1.3% | 15.2M | 15.6M | 1 | 66 | 66 | 64 | 66 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1602-L1627) [🔍 93p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **6** | 6 ± 0.0 | 0.0% | 167M | 167M | 0 | 6 | 6 | 6 | 6 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1629-L1638) [🔍 12p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **9** | 9 ± 0.0 | 0.0% | 111M | 111M | 0 | 9 | 9 | 9 | 9 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1640-L1656) [🔍 77p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **6** | 6 ± 0.0 | 0.0% | 167M | 167M | 0 | 6 | 6 | 6 | 6 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1658-L1667) [🔍 12p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **9** | 9 ± 0.0 | 0.0% | 111M | 111M | 0 | 9 | 9 | 9 | 9 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1709-L1725) [🔍 15p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **51** | 51 ± 1.0 | 2.0% | 19.2M | 20.0M | 2 | 52 | 52 | 50 | 52 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1727-L1742) [🔍 6p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **3** | 3 ± 0.0 | 0.0% | 333M | 333M | 0 | 3 | 3 | 3 | 3 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1744-L1774) [🔍 55p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **13** | 13 ± 0.5 | 4.1% | 71.4M | 76.9M | 1 | 14 | 14 | 13 | 14 | 2K |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1856-L1889) [🔍 118p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **96** | 97 ± 1.5 | 1.6% | 10.1M | 10.5M | 1 | 99 | 99 | 95 | 99 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2087-L2102) [🔍 37p](slices/63_db_re_open_trailer_checksum_verify.md) | **56** | 57 ± 1.4 | 2.5% | 16.9M | 17.9M | 2 | 59 | 59 | 56 | 59 | 5K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 36 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L471-L496) [🔍 82p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **216** | 236 ± 39.4 | 16.7% | 3.3M | 4.7M | 21 | 291 | 302 | 213 | 305 | 2K |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L535-L566) [🔍 84p](slices/04_hamt_cow_branched_moment_commits.md) | **929** | 1,002 ± 169 | 16.8% | 767K | 1.1M | 8 | 1,229 | 1,288 | 922 | 1,303 | 500 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L568-L594) [🔍 79p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **170** | 178 ± 19.8 | 11.1% | 4.9M | 6.4M | 29 | 201 | 203 | 157 | 203 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L614-L637) [🔍 82p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **197** | 203 ± 13.2 | 6.5% | 4.4M | 5.2M | 7 | 221 | 225 | 194 | 226 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L639-L663) [🔍 89p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **221** | 232 ± 24.8 | 10.7% | 3.6M | 4.6M | 5 | 266 | 274 | 219 | 276 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L665-L683) [🔍 76p](slices/09_hamt_counted_hash_map_remove.md) | **165** | 168 ± 8.9 | 5.3% | 5.6M | 6.4M | 11 | 177 | 178 | 156 | 178 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L685-L725) [🔍 79p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **180** | 188 ± 20.2 | 10.8% | 4.5M | 5.7M | 2 | 215 | 222 | 176 | 224 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L727-L747) [🔍 76p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **203** | 207 ± 7.6 | 3.7% | 4.6M | 5.0M | 10 | 216 | 217 | 199 | 217 | 500 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L749-L767) [🔍 78p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **223** | 231 ± 19.9 | 8.6% | 3.8M | 4.5M | 4 | 258 | 264 | 220 | 266 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L795-L828) [🔍 80p](slices/14_array_list_radix_trie_append.md) | **109** | 109 ± 1.5 | 1.4% | 9.0M | 9.3M | 1 | 111 | 111 | 107 | 111 | 2K |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L886-L900) [🔍 21p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **353** | 353 ± 3.9 | 1.1% | 2.8M | 2.9M | 3 | 358 | 359 | 349 | 359 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L902-L918) [🔍 66p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **699** | 701 ± 14.1 | 2.0% | 1.4M | 1.5M | 26 | 716 | 717 | 687 | 717 | 500 |
| 20 ↻ | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) [🔍 94p](slices/20_linked_array_list_b_tree_append.md) | **234** | 232 ± 4.1 | 1.8% | 4.3M | 4.4M | 3 | 235 | 235 | 225 | 235 | 2K |
| 23 ↻ | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L992-L1018) [🔍 83p](slices/23_linked_array_list_b_tree_middle_insert.md) | **268** | 268 ± 7.5 | 2.8% | 3.6M | 3.9M | 9 | 275 | 275 | 257 | 275 | 500 |
| 24 ↻ | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1020-L1039) [🔍 84p](slices/24_linked_array_list_b_tree_middle_remove.md) | **341** | 340 ± 6.0 | 1.8% | 2.9M | 3.0M | 6 | 345 | 345 | 330 | 345 | 500 |
| 25 ↻ | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1041-L1066) [🔍 89p](slices/25_linked_array_list_b_tree_concat_slice.md) | **878** | 916 ± 84.7 | 9.2% | 937K | 1.1M | 5 | 1,030 | 1,060 | 874 | 1,067 | 400 |
| 26 ↻ | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1068-L1085) [🔍 75p](slices/26_linked_array_list_b_tree_in_place_put.md) | **170** | 170 ± 2.0 | 1.2% | 5.8M | 6.0M | 2 | 172 | 173 | 168 | 173 | 2K |
| 27 ↻ | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1087-L1101) [🔍 20p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **413** | 417 ± 16.2 | 3.9% | 2.3M | 2.5M | 10 | 438 | 441 | 398 | 442 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1110-L1148) [🔍 112p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **377** | 376 ± 1.9 | 0.5% | 2.6M | 2.7M | 2 | 379 | 379 | 374 | 379 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1150-L1165) [🔍 37p](slices/29_sorted_map_b_tree_key_lookup.md) | **162** | 163 ± 1.5 | 0.9% | 6.1M | 6.2M | 1 | 165 | 165 | 161 | 165 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1167-L1178) [🔍 22p](slices/30_sorted_map_b_tree_rank_query.md) | **128** | 128 ± 1.1 | 0.9% | 7.7M | 7.9M | 0 | 130 | 130 | 127 | 130 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1197-L1212) [🔍 29p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **466** | 466 ± 1.9 | 0.4% | 2.1M | 2.2M | 1 | 468 | 468 | 463 | 468 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1214-L1240) [🔍 84p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **242** | 243 ± 2.3 | 1.0% | 4.0M | 4.1M | 1 | 246 | 247 | 241 | 247 | 1K |
| 35 ↻ | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1256-L1271) [🔍 21p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **432** | 430 ± 3.8 | 0.9% | 2.3M | 2.4M | 5 | 434 | 434 | 425 | 434 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1273-L1291) [🔍 95p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **368** | 368 ± 0.5 | 0.1% | 2.7M | 2.7M | 1 | 368 | 368 | 367 | 368 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1293-L1314) [🔍 95p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **347** | 348 ± 2.4 | 0.7% | 2.8M | 2.9M | 0 | 351 | 352 | 346 | 352 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1316-L1330) [🔍 36p](slices/38_sorted_set_b_tree_contains_lookup.md) | **149** | 148 ± 1.6 | 1.1% | 6.7M | 6.8M | 2 | 150 | 150 | 146 | 150 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1372-L1390) [🔍 42p](slices/39_replication_genesis_200_moments.md) | **104** | 103 ± 1.6 | 1.6% | 9.6M | 9.9M | 3 | 104 | 104 | 101 | 104 | 200 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1392-L1417) [🔍 93p](slices/40_replication_incremental_1_moment_delta.md) | **825** | 842 ± 44.7 | 5.3% | 1.1M | 1.2M | 14 | 903 | 917 | 813 | 921 | 100 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 99p](slices/45_hasher_sha_1_20b_hamt_put.md) | **211** | 210 ± 2.3 | 1.1% | 4.7M | 4.8M | 4 | 212 | 212 | 207 | 212 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 102p](slices/46_hasher_sha_256_32b_hamt_put.md) | **219** | 219 ± 0.5 | 0.2% | 4.5M | 4.6M | 1 | 220 | 220 | 219 | 220 | 2K |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1670-L1707) [🔍 67p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **264** | 264 ± 14.2 | 5.4% | 3.5M | 4.0M | 17 | 282 | 284 | 250 | 285 | 256 |
| 55 ↻ | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1777-L1830) [🔍 62p](slices/55_path_4_level_nested_cursor_write_path.md) | **236** | 237 ± 2.6 | 1.1% | 4.1M | 4.2M | 1 | 241 | 242 | 236 | 242 | 500 |
| 56 ↻ | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1832-L1853) [🔍 18p](slices/56_path_4_level_nested_cursor_read_path.md) | **148** | 153 ± 10.3 | 6.7% | 5.8M | 6.8M | 4 | 167 | 170 | 147 | 171 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2064-L2085) [🔍 77p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **654** | 655 ± 2.2 | 0.3% | 1.52M | 1.53M | 3 | 658 | 658 | 653 | 658 | 500 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2167-L2179) [🔍 71p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **553** | 557 ± 6.7 | 1.2% | 1.77M | 1.81M | 11 | 565 | 565 | 551 | 565 | 500 |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 19 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 41 ↻ | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) [🔍 90p](slices/41_compaction_memory_offset_map_200_1.md) | **2.30** | 2.36 ± 0.19 | 8.2% | 371K | 452K | 0.07 | 2.62 | 2.68 | 2.21 | 2.70 | 1 |
| 42 ↻ | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) [🔍 89p](slices/42_compaction_file_offset_map_200_1.md) | **9.63** | 9.76 ± 0.40 | 4.1% | 96.3K | 108K | 0.27 | 10.3 | 10.4 | 9.30 | 10.4 | 1 |
| 43 ↻ | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) [🔍 154p](slices/43_compaction_heterogeneous_dag_dedup.md) | **32.8** | 33.4 ± 1.67 | 5.0% | 27.6K | 31.3K | 1.28 | 35.7 | 36.1 | 32.0 | 36.2 | 1 |
| 44 ↻ | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) [🔍 43p](slices/44_replication_post_compaction_resync.md) | **1.53** | 1.55 ± 0.04 | 2.7% | 620K | 661K | 0.05 | 1.60 | 1.61 | 1.51 | 1.61 | 1 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1912-L1939) [🔍 101p](slices/58_backend_core_memory_commits.md) | **1.09** | 1.08 ± 0.01 | 0.6% | 917K | 931K | 0.01 | 1.09 | 1.09 | 1.07 | 1.09 | 500 |
| 59 ↻ | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) [🔍 102p](slices/59_backend_core_buffered_file_commits.md) | **17.0** | 17.0 ± 0.08 | 0.4% | 58.7K | 59.4K | 0.07 | 17.0 | 17.0 | 16.8 | 17.0 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1984-L2018) [🔍 101p](slices/60_backend_core_file_unbuffered_commits.md) | **44.6** | 44.7 ± 0.35 | 0.8% | 22.1K | 22.6K | 0.25 | 45.1 | 45.2 | 44.3 | 45.2 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2021-L2062) [🔍 96p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.03** | 1.03 ± 0.01 | 0.8% | 964K | 982K | 0.01 | 1.04 | 1.04 | 1.02 | 1.04 | 500 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2128-L2163) [🔍 99p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **4.02** | 4.01 ± 0.02 | 0.5% | 249K | 251K | 0.03 | 4.02 | 4.02 | 3.98 | 4.02 | 500 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2183-L2219) [🔍 170p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **3.98** | 3.99 ± 0.05 | 1.2% | 247K | 254K | 0.04 | 4.05 | 4.05 | 3.93 | 4.06 | 200 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2221-L2231) [🔍 139p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **1.96** | 1.96 ± 0.02 | 0.8% | 505K | 515K | 0.02 | 1.98 | 1.98 | 1.94 | 1.98 | 200 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2233-L2243) [🔍 101p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **1.60** | 1.61 ± 0.03 | 2.1% | 604K | 636K | 0.04 | 1.65 | 1.65 | 1.57 | 1.66 | 200 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2248-L2265) [🔍 158p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **273.8** | 275.6 ± 4.09 | 1.5% | 3.5K | 3.7K | 4.43 | 280.9 | 281.6 | 271.6 | 281.7 | 200 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2267-L2276) [🔍 75p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **2.24** | 2.24 ± 0.06 | 2.5% | 432K | 461K | 0.06 | 2.31 | 2.31 | 2.17 | 2.32 | 200 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2280-L2300) [🔍 123p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **13.5** | 13.8 ± 0.50 | 3.6% | 69.0K | 74.7K | 0.70 | 14.4 | 14.5 | 13.4 | 14.5 | 100 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2303-L2318) [🔍 123p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **571.2** | 577.6 ± 16.9 | 2.9% | 1.7K | 1.8K | 23.5 | 599.1 | 601.4 | 562.6 | 601.9 | 25 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2321-L2336) [🔍 123p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **26.7** | 26.8 ± 0.40 | 1.5% | 36.6K | 37.9K | 0.59 | 27.3 | 27.3 | 26.4 | 27.3 | 100 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2340-L2357) [🔍 98p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **2.99** | 3.03 ± 0.12 | 3.9% | 309K | 339K | 0.07 | 3.20 | 3.23 | 2.95 | 3.24 | 200 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2360-L2402) [🔍 185p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **7.01** | 6.98 ± 0.05 | 0.7% | 143K | 145K | 0.05 | 7.01 | 7.02 | 6.89 | 7.02 | 200 |


### 3. Zig Full Suite Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `3b3da703c200`, 5 samples across 1 run(s))

#### 3.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 10 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.zig#L882-L896) [🔍 21p](slices/16_array_list_radix_trie_iterator_scan.md) | **30** | 30 ± 1.3 | 4.4% | 32.3M | 35.7M | 2 | 31 | 31 | 28 | 31 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.zig#L1004-L1018) [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **51** | 51 ± 1.3 | 2.6% | 19.2M | 20.4M | 2 | 52 | 52 | 49 | 52 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.zig#L1206-L1219) [🔍 20p](slices/31_sorted_map_b_tree_ordered_scan.md) | **46** | 46 ± 1.1 | 2.5% | 20.8M | 22.2M | 1 | 48 | 48 | 45 | 48 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1721-L1752) [🔍 93p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **7** | 7 ± 0.0 | 0.0% | 143M | 143M | 0 | 7 | 7 | 7 | 7 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.zig#L1754-L1763) [🔍 12p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **36** | 37 ± 1.6 | 4.5% | 25.6M | 28.6M | 2 | 39 | 39 | 35 | 39 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1765-L1787) [🔍 77p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **7** | 7 ± 0.5 | 7.4% | 125M | 143M | 1 | 8 | 8 | 7 | 8 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.zig#L1789-L1798) [🔍 12p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **48** | 49 ± 2.2 | 4.4% | 18.9M | 20.8M | 1 | 52 | 53 | 48 | 53 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.zig#L1838-L1854) [🔍 15p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **77** | 76 ± 5.4 | 7.1% | 11.9M | 14.1M | 6 | 83 | 84 | 71 | 84 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.zig#L1856-L1871) [🔍 6p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **26** | 26 ± 0.5 | 2.1% | 37.0M | 38.5M | 1 | 27 | 27 | 26 | 27 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.zig#L1873-L1900) [🔍 55p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **28** | 28 ± 0.5 | 1.9% | 34.5M | 35.7M | 1 | 29 | 29 | 28 | 29 | 2K |

#### 3.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 21 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L513-L537) [🔍 82p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **758** | 753 ± 12.1 | 1.6% | 1.3M | 1.4M | 10 | 764 | 765 | 734 | 765 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.zig#L539-L555) [🔍 40p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **258** | 257 ± 1.3 | 0.5% | 3.86M | 3.91M | 2 | 259 | 259 | 256 | 259 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.zig#L557-L574) [🔍 33p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **178** | 177 ± 3.3 | 1.9% | 5.5M | 5.7M | 6 | 181 | 181 | 174 | 181 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.zig#L608-L630) [🔍 79p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **885** | 890 ± 8.1 | 0.9% | 1.11M | 1.13M | 8 | 901 | 903 | 884 | 903 | 1K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.zig#L632-L646) [🔍 20p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **141** | 140 ± 2.6 | 1.9% | 7.0M | 7.3M | 5 | 142 | 142 | 137 | 142 | 2K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.zig#L648-L670) [🔍 82p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **698** | 730 ± 77.9 | 10.7% | 1.2M | 1.4M | 7 | 835 | 862 | 691 | 869 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L672-L700) [🔍 89p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **762** | 820 ± 142 | 17.4% | 931K | 1.3M | 17 | 1,012 | 1,062 | 748 | 1,074 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.zig#L702-L721) [🔍 76p](slices/09_hamt_counted_hash_map_remove.md) | **941** | 939 ± 17.6 | 1.9% | 1.0M | 1.1M | 17 | 960 | 964 | 920 | 965 | 1K |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.zig#L786-L806) [🔍 78p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **507** | 508 ± 10.8 | 2.1% | 1.9M | 2.0M | 9 | 520 | 522 | 493 | 522 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.zig#L808-L824) [🔍 42p](slices/13_hamt_counted_hash_set_membership_check.md) | **249** | 250 ± 3.9 | 1.5% | 3.9M | 4.1M | 6 | 255 | 255 | 246 | 255 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.zig#L834-L863) [🔍 80p](slices/14_array_list_radix_trie_append.md) | **198** | 197 ± 4.2 | 2.1% | 5.0M | 5.3M | 2 | 201 | 201 | 190 | 201 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.zig#L865-L880) [🔍 24p](slices/15_array_list_radix_trie_random_get.md) | **123** | 123 ± 1.1 | 0.9% | 8.1M | 8.3M | 0 | 124 | 124 | 121 | 124 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.zig#L898-L918) [🔍 67p](slices/17_array_list_radix_trie_in_place_put.md) | **184** | 184 ± 4.7 | 2.6% | 5.2M | 5.6M | 3 | 190 | 192 | 180 | 192 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.zig#L987-L1002) [🔍 30p](slices/21_linked_array_list_b_tree_random_get.md) | **120** | 119 ± 1.6 | 1.4% | 8.3M | 8.5M | 2 | 121 | 121 | 117 | 121 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.zig#L1261-L1273) [🔍 29p](slices/34_sorted_map_b_tree_get_index_select.md) | **162** | 161 ± 1.9 | 1.2% | 6.1M | 6.3M | 0 | 163 | 163 | 158 | 163 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.zig#L1388-L1411) [🔍 42p](slices/39_replication_genesis_200_moments.md) | **851** | 872 ± 37.5 | 4.3% | 1.1M | 1.2M | 41 | 921 | 927 | 839 | 929 | 200 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.zig#L1656-L1686) [🔍 99p](slices/45_hasher_sha_1_20b_hamt_put.md) | **758** | 759 ± 1.1 | 0.1% | 1.3M | 1.3M | 2 | 760 | 760 | 758 | 760 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.zig#L1689-L1718) [🔍 102p](slices/46_hasher_sha_256_32b_hamt_put.md) | **862** | 860 ± 7.2 | 0.8% | 1.15M | 1.18M | 9 | 867 | 868 | 850 | 868 | 2K |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.zig#L1951-L1972) [🔍 18p](slices/56_path_4_level_nested_cursor_read_path.md) | **726** | 735 ± 17.8 | 2.4% | 1.3M | 1.4M | 19 | 758 | 760 | 717 | 761 | 500 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.zig#L1975-L2018) [🔍 118p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **254** | 254 ± 2.4 | 0.9% | 3.9M | 4.0M | 3 | 257 | 257 | 251 | 257 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.zig#L2265-L2279) [🔍 37p](slices/63_db_re_open_trailer_checksum_verify.md) | **239** | 243 ± 10.0 | 4.1% | 3.8M | 4.3M | 3 | 256 | 259 | 235 | 260 | 5K |

#### 3.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 32 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.zig#L576-L606) [🔍 84p](slices/04_hamt_cow_branched_moment_commits.md) | **2.18** | 2.21 ± 0.06 | 2.6% | 438K | 462K | 0.10 | 2.28 | 2.28 | 2.16 | 2.28 | 500 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.zig#L723-L761) [🔍 79p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **1.15** | 1.16 ± 0.02 | 2.0% | 835K | 876K | 0.00 | 1.19 | 1.20 | 1.14 | 1.20 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.zig#L763-L784) [🔍 76p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **2.61** | 2.61 ± 0.03 | 1.1% | 379K | 387K | 0.05 | 2.64 | 2.64 | 2.58 | 2.64 | 500 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.zig#L920-L933) [🔍 21p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **1.42** | 1.43 ± 0.05 | 3.2% | 664K | 717K | 0.04 | 1.49 | 1.50 | 1.39 | 1.51 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.zig#L935-L953) [🔍 66p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **1.30** | 1.49 ± 0.45 | 30.2% | 436K | 807K | 0.05 | 2.10 | 2.26 | 1.24 | 2.30 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.zig#L956-L985) [🔍 94p](slices/20_linked_array_list_b_tree_append.md) | **1.63** | 1.64 ± 0.02 | 1.2% | 601K | 618K | 0.03 | 1.66 | 1.66 | 1.62 | 1.66 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.zig#L1020-L1043) [🔍 83p](slices/23_linked_array_list_b_tree_middle_insert.md) | **1.99** | 1.97 ± 0.04 | 1.9% | 498K | 519K | 0.06 | 2.01 | 2.01 | 1.93 | 2.01 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.zig#L1045-L1066) [🔍 84p](slices/24_linked_array_list_b_tree_middle_remove.md) | **1.99** | 1.98 ± 0.04 | 1.8% | 496K | 518K | 0.04 | 2.02 | 2.02 | 1.93 | 2.02 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.zig#L1068-L1091) [🔍 89p](slices/25_linked_array_list_b_tree_concat_slice.md) | **18.9** | 18.8 ± 0.41 | 2.2% | 52.1K | 54.8K | 0.66 | 19.2 | 19.2 | 18.3 | 19.2 | 400 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.zig#L1093-L1112) [🔍 75p](slices/26_linked_array_list_b_tree_in_place_put.md) | **1.25** | 1.24 ± 0.02 | 1.6% | 787K | 817K | 0.03 | 1.27 | 1.27 | 1.22 | 1.27 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.zig#L1114-L1127) [🔍 20p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **2.15** | 2.16 ± 0.01 | 0.6% | 460K | 467K | 0.02 | 2.17 | 2.17 | 2.14 | 2.17 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.zig#L1136-L1174) [🔍 112p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **2.87** | 2.87 ± 0.03 | 0.9% | 345K | 352K | 0.05 | 2.90 | 2.90 | 2.84 | 2.90 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.zig#L1176-L1191) [🔍 37p](slices/29_sorted_map_b_tree_key_lookup.md) | **2.04** | 2.03 ± 0.01 | 0.7% | 489K | 497K | 0.03 | 2.04 | 2.04 | 2.01 | 2.04 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.zig#L1193-L1204) [🔍 22p](slices/30_sorted_map_b_tree_rank_query.md) | **2.00** | 1.99 ± 0.02 | 1.2% | 498K | 512K | 0.03 | 2.01 | 2.01 | 1.95 | 2.01 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.zig#L1221-L1235) [🔍 29p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **3.07** | 3.06 ± 0.02 | 0.8% | 325K | 331K | 0.01 | 3.08 | 3.08 | 3.02 | 3.08 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.zig#L1237-L1259) [🔍 84p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **3.09** | 3.10 ± 0.03 | 1.0% | 318K | 326K | 0.02 | 3.14 | 3.15 | 3.07 | 3.15 | 1K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.zig#L1275-L1289) [🔍 21p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **2.65** | 2.66 ± 0.07 | 2.5% | 364K | 386K | 0.11 | 2.74 | 2.74 | 2.59 | 2.75 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.zig#L1291-L1311) [🔍 95p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **2.44** | 2.46 ± 0.03 | 1.1% | 402K | 411K | 0.05 | 2.49 | 2.49 | 2.44 | 2.49 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.zig#L1313-L1336) [🔍 95p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **2.62** | 2.61 ± 0.03 | 1.1% | 380K | 390K | 0.04 | 2.63 | 2.63 | 2.57 | 2.63 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.zig#L1338-L1352) [🔍 36p](slices/38_sorted_set_b_tree_contains_lookup.md) | **1.87** | 1.88 ± 0.02 | 1.0% | 525K | 538K | 0.03 | 1.90 | 1.90 | 1.86 | 1.90 | 2K |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.zig#L1413-L1438) [🔍 93p](slices/40_replication_incremental_1_moment_delta.md) | **1.57** | 1.57 ± 0.01 | 0.4% | 633K | 639K | 0.01 | 1.58 | 1.58 | 1.57 | 1.58 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1440-L1458) [🔍 90p](slices/41_compaction_memory_offset_map_200_1.md) | **6.83** | 7.25 ± 2.33 | 32.2% | 89.7K | 187K | 1.71 | 10.4 | 11.0 | 5.34 | 11.2 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1460-L1514) [🔍 89p](slices/42_compaction_file_offset_map_200_1.md) | **11.3** | 12.2 ± 1.72 | 14.1% | 66.5K | 91.6K | 1.51 | 14.5 | 14.9 | 10.9 | 15.0 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.zig#L1516-L1603) [🔍 154p](slices/43_compaction_heterogeneous_dag_dedup.md) | **105.7** | 108.3 ± 10.0 | 9.2% | 8.4K | 10.2K | 18.1 | 119.3 | 119.5 | 98.2 | 119.6 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.zig#L1605-L1635) [🔍 43p](slices/44_replication_post_compaction_resync.md) | **1.67** | 1.67 ± 0.05 | 2.7% | 584K | 620K | 0.08 | 1.71 | 1.71 | 1.61 | 1.71 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.zig#L1801-L1836) [🔍 67p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **1.61** | 1.57 ± 0.07 | 4.4% | 617K | 676K | 0.12 | 1.62 | 1.62 | 1.48 | 1.62 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.zig#L1903-L1949) [🔍 62p](slices/55_path_4_level_nested_cursor_write_path.md) | **1.11** | 1.11 ± 0.01 | 0.5% | 894K | 906K | 0.00 | 1.12 | 1.12 | 1.10 | 1.12 | 500 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.zig#L2030-L2069) [🔍 101p](slices/58_backend_core_memory_commits.md) | **2.45** | 2.45 ± 0.06 | 2.3% | 397K | 421K | 0.07 | 2.51 | 2.52 | 2.37 | 2.52 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.zig#L2072-L2126) [🔍 102p](slices/59_backend_core_buffered_file_commits.md) | **17.9** | 17.9 ± 0.40 | 2.2% | 54.5K | 57.9K | 0.31 | 18.3 | 18.3 | 17.3 | 18.3 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.zig#L2129-L2178) [🔍 101p](slices/60_backend_core_file_unbuffered_commits.md) | **46.7** | 47.4 ± 1.50 | 3.2% | 20.1K | 21.7K | 1.23 | 49.4 | 49.7 | 46.0 | 49.8 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.zig#L2181-L2231) [🔍 96p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.96** | 1.93 ± 0.10 | 4.9% | 496K | 561K | 0.11 | 2.01 | 2.01 | 1.78 | 2.02 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.zig#L2233-L2263) [🔍 77p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **1.90** | 1.94 ± 0.10 | 5.3% | 471K | 537K | 0.03 | 2.08 | 2.12 | 1.86 | 2.12 | 500 |

### 4. 1v1 Statistical Comparison (Odin vs. Zig, Commit `2ea57460f65b`)

#### 4.1 Sub-100ns Fast Path (`ns`, 20 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L498-L514) ([Zig](bench_xitdb.zig#L539-L555) · [🔍 40p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md)) | **2.84x** | **91** | 258 | `10.4` ★ | 106 ± 32.6 | 30.8% | 150 | 257 ± 1.3 | 0.5% | 259 |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L516-L533) ([Zig](bench_xitdb.zig#L557-L574) · [🔍 33p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md)) | **3.12x** | **57** | 178 | `13.1` ★ | 65 ± 18.9 | 29.0% | 91 | 177 ± 3.3 | 1.9% | 181 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L596-L612) ([Zig](bench_xitdb.zig#L632-L646) · [🔍 20p](slices/06_hamt_hash_map_unordered_iterator_scan.md)) | **3.92x** | **36** | 141 | `88.2` ★ | 36 ± 0.4 | 1.2% | 37 | 140 ± 2.6 | 1.9% | 142 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L769-L785) ([Zig](bench_xitdb.zig#L808-L824) · [🔍 42p](slices/13_hamt_counted_hash_set_membership_check.md)) | **2.74x** | **91** | 249 | `87.5` ★ | 91 ± 1.2 | 1.3% | 93 | 250 ± 3.9 | 1.5% | 255 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L830-L845) ([Zig](bench_xitdb.zig#L865-L880) · [🔍 24p](slices/15_array_list_radix_trie_random_get.md)) | **2.67x** | **46** | 123 | `140.9` ★ | 46 ± 0.5 | 1.2% | 46 | 123 ± 1.1 | 0.9% | 124 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L847-L864) ([Zig](bench_xitdb.zig#L882-L896) · [🔍 21p](slices/16_array_list_radix_trie_iterator_scan.md)) | **2.50x** | **12** | 30 | `30.5` ★ | 12 ± 0.0 | 0.0% | 12 | 30 ± 1.3 | 4.4% | 31 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L866-L884) ([Zig](bench_xitdb.zig#L898-L918) · [🔍 67p](slices/17_array_list_radix_trie_in_place_put.md)) | **1.92x** | **96** | 184 | `38.9` ★ | 95 ± 1.9 | 2.0% | 98 | 184 ± 4.7 | 2.6% | 190 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L956-L971) ([Zig](bench_xitdb.zig#L987-L1002) · [🔍 30p](slices/21_linked_array_list_b_tree_random_get.md)) | **2.22x** | **54** | 120 | `71.1` ★ | 54 ± 1.2 | 2.3% | 55 | 119 ± 1.6 | 1.4% | 121 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L973-L990) ([Zig](bench_xitdb.zig#L1004-L1018) · [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md)) | **3.64x** | **14** | 51 | `60.0` ★ | 14 ± 0.4 | 3.2% | 14 | 51 ± 1.3 | 2.6% | 52 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1180-L1195) ([Zig](bench_xitdb.zig#L1206-L1219) · [🔍 20p](slices/31_sorted_map_b_tree_ordered_scan.md)) | **3.54x** | **13** | 46 | `65.5` ★ | 13 ± 0.0 | 0.0% | 13 | 46 ± 1.1 | 2.5% | 48 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1242-L1254) ([Zig](bench_xitdb.zig#L1261-L1273) · [🔍 29p](slices/34_sorted_map_b_tree_get_index_select.md)) | **2.49x** | **65** | 162 | `101.8` ★ | 65 ± 0.8 | 1.3% | 66 | 161 ± 1.9 | 1.2% | 163 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1602-L1627) ([Zig](bench_xitdb.zig#L1721-L1752) · [🔍 93p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md)) | **1.17x** | **6** | 7 | `99.0` ★ | 6 ± 0.0 | 0.0% | 6 | 7 ± 0.0 | 0.0% | 7 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1629-L1638) ([Zig](bench_xitdb.zig#L1754-L1763) · [🔍 12p](slices/48_bytes_external_bytes_read_bytes_buf.md)) | **4.00x** | **9** | 36 | `37.8` ★ | 9 ± 0.0 | 0.0% | 9 | 37 ± 1.6 | 4.5% | 39 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1640-L1656) ([Zig](bench_xitdb.zig#L1765-L1787) · [🔍 77p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md)) | **1.17x** | **6** | 7 | `5.7` ★ | 6 ± 0.0 | 0.0% | 6 | 7 ± 0.5 | 7.4% | 8 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1658-L1667) ([Zig](bench_xitdb.zig#L1789-L1798) · [🔍 12p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md)) | **5.33x** | **9** | 48 | `41.5` ★ | 9 ± 0.0 | 0.0% | 9 | 49 ± 2.2 | 4.4% | 52 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1709-L1725) ([Zig](bench_xitdb.zig#L1838-L1854) · [🔍 15p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md)) | **1.51x** | **51** | 77 | `10.2` ★ | 51 ± 1.0 | 2.0% | 52 | 76 ± 5.4 | 7.1% | 83 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1727-L1742) ([Zig](bench_xitdb.zig#L1856-L1871) · [🔍 6p](slices/53_stream_cursor_reader_random_seek_64b_read.md)) | **8.67x** | **3** | 26 | `95.5` ★ | 3 ± 0.0 | 0.0% | 3 | 26 ± 0.5 | 2.1% | 27 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1744-L1774) ([Zig](bench_xitdb.zig#L1873-L1900) · [🔍 55p](slices/54_stream_cursor_writer_random_seek_16b_patch.md)) | **2.15x** | **13** | 28 | `43.3` ★ | 13 ± 0.5 | 4.1% | 14 | 28 ± 0.5 | 1.9% | 29 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1856-L1889) ([Zig](bench_xitdb.zig#L1975-L2018) · [🔍 118p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md)) | **2.65x** | **96** | 254 | `124.3` ★ | 97 ± 1.5 | 1.6% | 99 | 254 ± 2.4 | 0.9% | 257 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2087-L2102) ([Zig](bench_xitdb.zig#L2265-L2279) · [🔍 37p](slices/63_db_re_open_trailer_checksum_verify.md)) | **4.27x** | **56** | 239 | `41.2` ★ | 57 ± 1.4 | 2.5% | 59 | 243 ± 10.0 | 4.1% | 256 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 35 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L471-L496) ([Zig](bench_xitdb.zig#L513-L537) · [🔍 82p](slices/01_hamt_hash_map_bulk_put_1_tx.md)) | **3.51x** | **216** | 758 | `28.0` ★ | 236 ± 39.4 | 16.7% | 291 | 753 ± 12.1 | 1.6% | 764 |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L535-L566) ([Zig](bench_xitdb.zig#L576-L606) · [🔍 84p](slices/04_hamt_cow_branched_moment_commits.md)) | **2.34x** | **929** | 2,177 | `15.2` ★ | 1,002 ± 169 | 16.8% | 1,229 | 2,211 ± 57.5 | 2.6% | 2,278 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L568-L594) ([Zig](bench_xitdb.zig#L608-L630) · [🔍 79p](slices/05_hamt_hash_map_remove_branch_shortening.md)) | **5.21x** | **170** | 885 | `74.5` ★ | 178 ± 19.8 | 11.1% | 201 | 890 ± 8.1 | 0.9% | 901 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L614-L637) ([Zig](bench_xitdb.zig#L648-L670) · [🔍 82p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md)) | **3.54x** | **197** | 698 | `14.9` ★ | 203 ± 13.2 | 6.5% | 221 | 730 ± 77.9 | 10.7% | 835 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L639-L663) ([Zig](bench_xitdb.zig#L672-L700) · [🔍 89p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md)) | **3.45x** | **221** | 762 | `9.1` ★ | 232 ± 24.8 | 10.7% | 266 | 820 ± 142 | 17.4% | 1,012 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L665-L683) ([Zig](bench_xitdb.zig#L702-L721) · [🔍 76p](slices/09_hamt_counted_hash_map_remove.md)) | **5.70x** | **165** | 941 | `87.2` ★ | 168 ± 8.9 | 5.3% | 177 | 939 ± 17.6 | 1.9% | 960 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L685-L725) ([Zig](bench_xitdb.zig#L723-L761) · [🔍 79p](slices/10_hamt_deep_suffix_collision_put_depth_10.md)) | **6.39x** | **180** | 1,151 | `71.1` ★ | 188 ± 20.2 | 10.8% | 215 | 1,158 ± 22.8 | 2.0% | 1,189 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L727-L747) ([Zig](bench_xitdb.zig#L763-L784) · [🔍 76p](slices/11_hamt_deep_suffix_collision_branch_collapse.md)) | **12.84x** | **203** | 2,606 | `184.2` ★ | 207 ± 7.6 | 3.7% | 216 | 2,610 ± 28.2 | 1.1% | 2,641 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L749-L767) ([Zig](bench_xitdb.zig#L786-L806) · [🔍 78p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md)) | **2.27x** | **223** | 507 | `27.4` ★ | 231 ± 19.9 | 8.6% | 258 | 508 ± 10.8 | 2.1% | 520 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L795-L828) ([Zig](bench_xitdb.zig#L834-L863) · [🔍 80p](slices/14_array_list_radix_trie_append.md)) | **1.82x** | **109** | 198 | `44.4` ★ | 109 ± 1.5 | 1.4% | 111 | 197 ± 4.2 | 2.1% | 201 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L886-L900) ([Zig](bench_xitdb.zig#L920-L933) · [🔍 21p](slices/18_array_list_radix_trie_index_seek_page_10.md)) | **4.01x** | **353** | 1,415 | `52.2` ★ | 353 ± 3.9 | 1.1% | 358 | 1,430 ± 46.0 | 3.2% | 1,493 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L902-L918) ([Zig](bench_xitdb.zig#L935-L953) · [🔍 66p](slices/19_array_list_radix_trie_depth_collapse_slice.md)) | **1.86x** | **699** | 1,302 | `3.9` ★ | 701 ± 14.1 | 2.0% | 716 | 1,492 ± 451 | 30.2% | 2,104 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) ([Zig](bench_xitdb.zig#L956-L985) · [🔍 94p](slices/20_linked_array_list_b_tree_append.md)) | **6.97x** | **234** | 1,632 | `150.8` ★ | 232 ± 4.1 | 1.8% | 235 | 1,641 ± 20.5 | 1.2% | 1,663 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L992-L1018) ([Zig](bench_xitdb.zig#L1020-L1043) · [🔍 83p](slices/23_linked_array_list_b_tree_middle_insert.md)) | **7.44x** | **268** | 1,993 | `100.7` ★ | 268 ± 7.5 | 2.8% | 275 | 1,974 ± 37.1 | 1.9% | 2,007 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1020-L1039) ([Zig](bench_xitdb.zig#L1045-L1066) · [🔍 84p](slices/24_linked_array_list_b_tree_middle_remove.md)) | **5.84x** | **341** | 1,990 | `102.6` ★ | 340 ± 6.0 | 1.8% | 345 | 1,980 ± 35.3 | 1.8% | 2,015 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1041-L1066) ([Zig](bench_xitdb.zig#L1068-L1091) · [🔍 89p](slices/25_linked_array_list_b_tree_concat_slice.md)) | **21.54x** | **878** | 18,912 | `94.6` ★ | 916 ± 84.7 | 9.2% | 1,030 | 18,801 ± 414 | 2.2% | 19,193 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1068-L1085) ([Zig](bench_xitdb.zig#L1093-L1112) · [🔍 75p](slices/26_linked_array_list_b_tree_in_place_put.md)) | **7.33x** | **170** | 1,246 | `120.9` ★ | 170 ± 2.0 | 1.2% | 172 | 1,243 ± 19.7 | 1.6% | 1,267 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1087-L1101) ([Zig](bench_xitdb.zig#L1114-L1127) · [🔍 20p](slices/27_linked_array_list_b_tree_index_seek_page_10.md)) | **5.20x** | **413** | 2,147 | `184.1` ★ | 417 ± 16.2 | 3.9% | 438 | 2,155 ± 13.5 | 0.6% | 2,171 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1110-L1148) ([Zig](bench_xitdb.zig#L1136-L1174) · [🔍 112p](slices/28_sorted_map_b_tree_out_of_order_put.md)) | **7.62x** | **377** | 2,872 | `214.8` ★ | 376 ± 1.9 | 0.5% | 379 | 2,870 ± 25.9 | 0.9% | 2,896 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1150-L1165) ([Zig](bench_xitdb.zig#L1176-L1191) · [🔍 37p](slices/29_sorted_map_b_tree_key_lookup.md)) | **12.59x** | **162** | 2,039 | `280.6` ★ | 163 ± 1.5 | 0.9% | 165 | 2,031 ± 14.8 | 0.7% | 2,043 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1167-L1178) ([Zig](bench_xitdb.zig#L1193-L1204) · [🔍 22p](slices/30_sorted_map_b_tree_rank_query.md)) | **15.63x** | **128** | 2,000 | `179.7` ★ | 128 ± 1.1 | 0.9% | 130 | 1,988 ± 23.1 | 1.2% | 2,006 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1197-L1212) ([Zig](bench_xitdb.zig#L1221-L1235) · [🔍 29p](slices/32_sorted_map_b_tree_lower_bound_page_10.md)) | **6.59x** | **466** | 3,071 | `251.0` ★ | 466 ± 1.9 | 0.4% | 468 | 3,060 ± 23.0 | 0.8% | 3,075 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1214-L1240) ([Zig](bench_xitdb.zig#L1237-L1259) · [🔍 84p](slices/33_sorted_map_b_tree_remove_rebalance.md)) | **12.76x** | **242** | 3,089 | `202.3` ★ | 243 ± 2.3 | 1.0% | 246 | 3,097 ± 31.5 | 1.0% | 3,139 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1256-L1271) ([Zig](bench_xitdb.zig#L1275-L1289) · [🔍 21p](slices/35_sorted_map_b_tree_index_seek_page_10.md)) | **6.14x** | **432** | 2,653 | `75.9` ★ | 430 ± 3.8 | 0.9% | 434 | 2,662 ± 65.6 | 2.5% | 2,738 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1273-L1291) ([Zig](bench_xitdb.zig#L1291-L1311) · [🔍 95p](slices/36_sorted_map_b_tree_in_place_overwrite.md)) | **6.64x** | **368** | 2,442 | `180.5` ★ | 368 ± 0.5 | 0.1% | 368 | 2,457 ± 25.9 | 1.1% | 2,486 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1293-L1314) ([Zig](bench_xitdb.zig#L1313-L1336) · [🔍 95p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md)) | **7.55x** | **347** | 2,619 | `180.8` ★ | 348 ± 2.4 | 0.7% | 351 | 2,605 ± 27.8 | 1.1% | 2,631 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1316-L1330) ([Zig](bench_xitdb.zig#L1338-L1352) · [🔍 36p](slices/38_sorted_set_b_tree_contains_lookup.md)) | **12.57x** | **149** | 1,873 | `210.6` ★ | 148 ± 1.6 | 1.1% | 150 | 1,877 ± 18.3 | 1.0% | 1,900 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1372-L1390) ([Zig](bench_xitdb.zig#L1388-L1411) · [🔍 42p](slices/39_replication_genesis_200_moments.md)) | **8.18x** | **104** | 851 | `45.8` ★ | 103 ± 1.6 | 1.6% | 104 | 872 ± 37.5 | 4.3% | 921 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1392-L1417) ([Zig](bench_xitdb.zig#L1413-L1438) · [🔍 93p](slices/40_replication_incremental_1_moment_delta.md)) | **1.90x** | **825** | 1,571 | `36.2` ★ | 842 ± 44.7 | 5.3% | 903 | 1,573 ± 6.3 | 0.4% | 1,581 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1578-L1599) ([Zig](bench_xitdb.zig#L1656-L1686) · [🔍 99p](slices/45_hasher_sha_1_20b_hamt_put.md)) | **3.59x** | **211** | 758 | `474.1` ★ | 210 ± 2.3 | 1.1% | 212 | 759 ± 1.1 | 0.1% | 760 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1578-L1599) ([Zig](bench_xitdb.zig#L1689-L1718) · [🔍 102p](slices/46_hasher_sha_256_32b_hamt_put.md)) | **3.94x** | **219** | 862 | `197.8` ★ | 219 ± 0.5 | 0.2% | 220 | 860 ± 7.2 | 0.8% | 867 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1670-L1707) ([Zig](bench_xitdb.zig#L1801-L1836) · [🔍 67p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md)) | **6.08x** | **264** | 1,605 | `41.0` ★ | 264 ± 14.2 | 5.4% | 282 | 1,566 ± 69.5 | 4.4% | 1,622 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1777-L1830) ([Zig](bench_xitdb.zig#L1903-L1949) · [🔍 62p](slices/55_path_4_level_nested_cursor_write_path.md)) | **4.69x** | **236** | 1,108 | `315.3` ★ | 237 ± 2.6 | 1.1% | 241 | 1,110 ± 5.6 | 0.5% | 1,117 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1832-L1853) ([Zig](bench_xitdb.zig#L1951-L1972) · [🔍 18p](slices/56_path_4_level_nested_cursor_read_path.md)) | **4.91x** | **148** | 726 | `63.4` ★ | 153 ± 10.3 | 6.7% | 167 | 735 ± 17.8 | 2.4% | 758 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2064-L2085) ([Zig](bench_xitdb.zig#L2233-L2263) · [🔍 77p](slices/62_tx_aborted_transaction_rollback_truncate.md)) | **2.91x** | **654** | 1,903 | `27.8` ★ | 655 ± 2.2 | 0.3% | 658 | 1,943 ± 104 | 5.3% | 2,084 |

#### 4.3 Multi-Microsecond Transactions & Compaction (`µs`, 8 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) ([Zig](bench_xitdb.zig#L1440-L1458) · [🔍 90p](slices/41_compaction_memory_offset_map_200_1.md)) | **2.97x** | **2.30** | 6.83 | `4.7` ★ | 2.36 ± 0.19 | 8.2% | 2.62 | 7.25 ± 2.33 | 32.2% | 10.4 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) ([Zig](bench_xitdb.zig#L1460-L1514) · [🔍 89p](slices/42_compaction_file_offset_map_200_1.md)) | **1.18x** | **9.63** | 11.3 | `3.1` ★ | 9.76 ± 0.40 | 4.1% | 10.3 | 12.2 ± 1.72 | 14.1% | 14.5 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) ([Zig](bench_xitdb.zig#L1516-L1603) · [🔍 154p](slices/43_compaction_heterogeneous_dag_dedup.md)) | **3.23x** | **32.8** | 105.7 | `16.5` ★ | 33.4 ± 1.67 | 5.0% | 35.7 | 108.3 ± 10.0 | 9.2% | 119.3 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) ([Zig](bench_xitdb.zig#L1605-L1635) · [🔍 43p](slices/44_replication_post_compaction_resync.md)) | **1.09x** | **1.53** | 1.67 | `4.2` ★ | 1.55 ± 0.04 | 2.7% | 1.60 | 1.67 ± 0.05 | 2.7% | 1.71 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1912-L1939) ([Zig](bench_xitdb.zig#L2030-L2069) · [🔍 101p](slices/58_backend_core_memory_commits.md)) | **2.26x** | **1.09** | 2.45 | `54.0` ★ | 1.08 ± 0.01 | 0.6% | 1.09 | 2.45 ± 0.06 | 2.3% | 2.51 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) ([Zig](bench_xitdb.zig#L2072-L2126) · [🔍 102p](slices/59_backend_core_buffered_file_commits.md)) | **1.05x** | **17.0** | 17.9 | `5.1` ★ | 17.0 ± 0.08 | 0.4% | 17.0 | 17.9 ± 0.40 | 2.2% | 18.3 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1984-L2018) ([Zig](bench_xitdb.zig#L2129-L2178) · [🔍 101p](slices/60_backend_core_file_unbuffered_commits.md)) | **1.05x** | **44.6** | 46.7 | `3.9` ★ | 44.7 ± 0.35 | 0.8% | 45.1 | 47.4 ± 1.50 | 3.2% | 49.4 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2021-L2062) ([Zig](bench_xitdb.zig#L2181-L2231) · [🔍 96p](slices/61_tx_mid_tx_database_freeze_cow_clone.md)) | **1.91x** | **1.03** | 1.96 | `21.1` ★ | 1.03 ± 0.01 | 0.8% | 1.04 | 1.93 ± 0.10 | 4.9% | 2.01 |

### 5. Database Storage Footprint (`bytes_used > 0`)

| # | Benchmark | Ops | Odin Size | Zig Size |
| ---: | :--- | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L471-L496) [🔍 82p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | 2K | 214.5 KB | 214.5 KB |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L535-L566) [🔍 84p](slices/04_hamt_cow_branched_moment_commits.md) | 500 | 457.7 KB | 457.7 KB |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L795-L828) [🔍 80p](slices/14_array_list_radix_trie_append.md) | 2K | 19.3 KB | 19.3 KB |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) [🔍 94p](slices/20_linked_array_list_b_tree_append.md) | 2K | 45.3 KB | 45.3 KB |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1110-L1148) [🔍 112p](slices/28_sorted_map_b_tree_out_of_order_put.md) | 2K | 115.4 KB | 115.4 KB |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1293-L1314) [🔍 95p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | 2K | 80.0 KB | 80.0 KB |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1372-L1390) [🔍 42p](slices/39_replication_genesis_200_moments.md) | 200 | 250.9 KB | 250.9 KB |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1392-L1417) [🔍 93p](slices/40_replication_incremental_1_moment_delta.md) | 100 | 132.7 KB | 132.7 KB |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) [🔍 90p](slices/41_compaction_memory_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) [🔍 89p](slices/42_compaction_file_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) [🔍 154p](slices/43_compaction_heterogeneous_dag_dedup.md) | 1 | 23.4 KB | 23.4 KB |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) [🔍 43p](slices/44_replication_post_compaction_resync.md) | 1 | 23.4 KB | 23.4 KB |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 99p](slices/45_hasher_sha_1_20b_hamt_put.md) | 2K | 224.7 KB | 224.7 KB |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 102p](slices/46_hasher_sha_256_32b_hamt_put.md) | 2K | 248.7 KB | 248.7 KB |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1670-L1707) [🔍 67p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | 256 | 1024.1 KB | 1024.1 KB |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1912-L1939) [🔍 101p](slices/58_backend_core_memory_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) [🔍 102p](slices/59_backend_core_buffered_file_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1984-L2018) [🔍 101p](slices/60_backend_core_file_unbuffered_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2128-L2163) [🔍 99p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | 500 | 231.4 KB | — |
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
