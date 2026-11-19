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
### 1. Latest Code-Change Impact & Affected Benchmarks (`3c1d38d9cfcc` → `bab4850e4f8e`, Odin, 75 / 75 tests re-run)

- **Code Diff Inspected:** `bab4850~1..bab4850` · **Changed Files:** `xitdb/dsl.odin`
- **Modified Procedures:** `_diff_recursive`, `_eval_pull_spec`, `_push_step_buf`, `history_of`, `parse_selector_buf`, `parse_selector`, `parse_steps_buf`, `parse_steps`, `precompute_step_hashes`, `read_prehashed_steps_cursor`, `read_prehashed_steps_slot`, `select_cursor`, `selector_destroy_buf`, `steps_destroy_buf`, `unmarshal_into`
- **Mapped Benchmark Scope:** Odin groups=`dsl` (**75 / 75** Odin benchmarks executed; **0** unchanged benchmarks retained from `3c1d38d`)

#### 1.1 Sub-100ns Fast Path (`ns`, 13 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `3c1d38d` (`ns`) | Curr `bab4850` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L528-L545) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **REGRESSION** | `+71.7%` | 0.58x | 53 | **91** | `19.6` | 54 ± 4.2 | 91 ± 0.5 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L608-L624) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **REGRESSION** | `+55.6%` | 0.64x | 36 | **56** | `11.5` | 36 ± 3.2 | 58 ± 2.6 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L842-L857) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **REGRESSION** | `+49.0%` | 0.67x | 49 | **73** | `33.4` | 50 ± 1.5 | 73 ± 0.4 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L859-L876) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **REGRESSION** | `+53.8%` | 0.65x | 13 | **20** | `99.0` | 13 ± 0.0 | 20 ± 0.0 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L968-L983) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **REGRESSION** | `+57.1%` | 0.64x | 56 | **88** | `6.5` | 60 ± 9.3 | 88 ± 0.5 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L985-L1002) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **REGRESSION** | `+57.1%` | 0.64x | 14 | **22** | `99.0` | 14 ± 0.0 | 22 ± 0.0 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1192-L1207) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **REGRESSION** | `+53.8%` | 0.65x | 13 | **20** | `26.9` | 13 ± 0.5 | 20 ± 0.0 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1614-L1639) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **REGRESSION** | `+71.4%` | 0.58x | 7 | **12** | `9.3` | 7 ± 0.0 | 13 ± 1.3 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1641-L1650) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **REGRESSION** | `+100.0%` | 0.50x | 9 | **18** | `10.3` | 10 ± 1.8 | 18 ± 0.0 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1652-L1668) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | `~NOISE` | `+57.1%` | 0.64x | 7 | **11** | `18.0` | 7 ± 0.0 | 11 ± 0.5 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1670-L1679) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **REGRESSION** | `+90.0%` | 0.53x | 10 | **19** | `99.0` | 10 ± 0.0 | 19 ± 0.0 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1739-L1754) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | `~NOISE` | `+75.0%` | 0.57x | 4 | **7** | `99.0` | 4 ± 0.0 | 7 ± 0.0 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1756-L1786) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **REGRESSION** | `+64.0%` | 0.61x | 25 | **41** | `16.1` | 25 ± 1.3 | 42 ± 2.0 |

#### 1.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 36 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `3c1d38d` (`ns`) | Curr `bab4850` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L483-L508) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **REGRESSION** | `+67.1%` | 0.60x | 207 | **346** | `18.1` | 208 ± 16.7 | 347 ± 4.4 |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L510-L526) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **REGRESSION** | `+63.2%` | 0.61x | 95 | **155** | `17.5` | 95 ± 7.6 | 155 ± 1.5 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L580-L606) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **REGRESSION** | `+67.5%` | 0.60x | 169 | **283** | `18.7` | 173 ± 12.3 | 284 ± 5.1 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L626-L649) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **REGRESSION** | `+68.0%` | 0.60x | 200 | **336** | `17.2` | 207 ± 15.3 | 338 ± 7.4 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L651-L675) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **REGRESSION** | `+60.8%` | 0.62x | 222 | **357** | `26.8` | 214 ± 11.2 | 356 ± 3.8 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L677-L695) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **REGRESSION** | `+58.1%` | 0.63x | 179 | **283** | `17.6` | 177 ± 11.8 | 286 ± 7.1 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L697-L737) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **REGRESSION** | `+58.6%` | 0.63x | 210 | **333** | `13.7` | 212 ± 15.8 | 336 ± 12.6 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L739-L759) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **REGRESSION** | `+66.5%` | 0.60x | 200 | **333** | `20.5` | 200 ± 8.6 | 341 ± 12.8 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L761-L779) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **REGRESSION** | `+61.1%` | 0.62x | 221 | **356** | `22.8` | 223 ± 12.2 | 356 ± 4.7 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L781-L797) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **REGRESSION** | `+60.0%` | 0.63x | 95 | **152** | `22.5` | 92 ± 5.4 | 152 ± 2.5 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L807-L840) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **REGRESSION** | `+44.7%` | 0.69x | 114 | **165** | `14.6` | 113 ± 2.0 | 167 ± 8.1 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L878-L896) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **REGRESSION** | `+40.8%` | 0.71x | 98 | **138** | `17.3` | 98 ± 2.9 | 140 ± 4.6 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L898-L912) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **REGRESSION** | `+48.8%` | 0.67x | 387 | **576** | `95.2` | 385 ± 3.6 | 576 ± 2.6 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L933-L966) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **REGRESSION** | `+52.4%` | 0.66x | 254 | **387** | `51.2` | 254 ± 4.9 | 386 ± 3.1 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1004-L1030) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **REGRESSION** | `+41.4%` | 0.71x | 290 | **410** | `21.9` | 290 ± 1.2 | 416 ± 12.8 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1032-L1051) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **REGRESSION** | `+49.9%` | 0.67x | 351 | **526** | `30.7` | 356 ± 7.2 | 532 ± 10.6 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1080-L1097) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **REGRESSION** | `+60.5%` | 0.62x | 162 | **260** | `49.7` | 162 ± 2.3 | 259 ± 3.7 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1099-L1113) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **REGRESSION** | `+53.0%` | 0.65x | 402 | **615** | `75.1` | 403 ± 6.3 | 615 ± 0.5 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1122-L1160) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **REGRESSION** | `+54.9%` | 0.65x | 399 | **618** | `211.7` | 398 ± 1.1 | 618 ± 2.0 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1162-L1177) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **REGRESSION** | `+54.5%` | 0.65x | 178 | **275** | `70.7` | 177 ± 1.9 | 275 ± 2.4 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1179-L1190) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **REGRESSION** | `+55.2%` | 0.64x | 145 | **225** | `95.2` | 145 ± 1.1 | 225 ± 1.5 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1209-L1224) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **REGRESSION** | `+52.0%` | 0.66x | 500 | **760** | `79.2` | 504 ± 7.2 | 759 ± 0.9 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1226-L1252) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **REGRESSION** | `+54.6%` | 0.65x | 249 | **385** | `45.2` | 251 ± 5.3 | 385 ± 3.9 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1254-L1266) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **REGRESSION** | `+50.6%` | 0.66x | 77 | **116** | `36.5` | 78 ± 1.9 | 116 ± 1.2 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1268-L1283) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **REGRESSION** | `+52.9%` | 0.65x | 365 | **558** | `53.7` | 367 ± 7.6 | 559 ± 2.4 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1285-L1303) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **REGRESSION** | `+56.1%` | 0.64x | 374 | **584** | `168.5` | 374 ± 2.1 | 584 ± 1.8 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1305-L1326) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **REGRESSION** | `+57.1%` | 0.64x | 359 | **564** | `151.3` | 358 ± 2.3 | 563 ± 1.9 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1328-L1342) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **REGRESSION** | `+55.4%` | 0.64x | 166 | **258** | `106.0` | 166 ± 1.1 | 258 ± 1.6 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1384-L1402) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **REGRESSION** | `+57.2%` | 0.64x | 493 | **775** | `14.6` | 505 ± 31.1 | 783 ± 29.1 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1590-L1611) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **REGRESSION** | `+59.0%` | 0.63x | 212 | **337** | `14.5` | 212 ± 1.6 | 346 ± 20.5 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1590-L1611) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **REGRESSION** | `+61.6%` | 0.62x | 224 | **362** | `17.1` | 225 ± 3.7 | 369 ± 18.6 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1721-L1737) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **REGRESSION** | `+89.5%` | 0.53x | 57 | **108** | `7.2` | 59 ± 5.5 | 109 ± 14.6 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1789-L1842) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **REGRESSION** | `+63.8%` | 0.61x | 232 | **380** | `17.0` | 234 ± 5.4 | 387 ± 19.4 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1844-L1865) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **REGRESSION** | `+65.8%` | 0.60x | 152 | **252** | `29.7` | 152 ± 2.3 | 253 ± 7.3 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1868-L1901) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **REGRESSION** | `+62.6%` | 0.61x | 99 | **161** | `9.8` | 99 ± 1.5 | 165 ± 15.2 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2099-L2114) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **REGRESSION** | `+90.7%` | 0.52x | 54 | **103** | `22.3` | 56 ± 4.5 | 104 ± 1.5 |

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 26 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `3c1d38d` (`µs`) | Curr `bab4850` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L547-L578) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **REGRESSION** | `+63.6%` | 0.61x | 1.12 | **1.83** | `13.5` | 1.15 ± 0.11 | 1.82 ± 0.01 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L914-L930) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **REGRESSION** | `+51.3%` | 0.66x | 0.85 | **1.29** | `37.2` | 0.85 ± 0.01 | 1.29 ± 0.02 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1053-L1078) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **REGRESSION** | `+50.0%` | 0.67x | 1.22 | **1.83** | `44.1` | 1.22 ± 0.01 | 1.83 ± 0.03 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1404-L1429) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **REGRESSION** | `+57.5%` | 0.63x | 1.16 | **1.82** | `19.7` | 1.18 ± 0.06 | 1.83 ± 0.04 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1431-L1449) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **REGRESSION** | `+56.9%` | 0.64x | 6.34 | **9.95** | `9.7` | 6.18 ± 0.54 | 9.96 ± 0.68 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1451-L1472) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **REGRESSION** | `+51.1%` | 0.66x | 14.9 | **22.5** | `16.2` | 15.1 ± 0.73 | 22.6 ± 0.75 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1474-L1533) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **REGRESSION** | `+58.9%` | 0.63x | 45.6 | **72.4** | `13.5` | 43.3 ± 3.86 | 72.7 ± 2.99 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1535-L1560) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **REGRESSION** | `+58.6%` | 0.63x | 1.45 | **2.31** | `42.3` | 1.44 ± 0.04 | 2.31 ± 0.03 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1682-L1719) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **REGRESSION** | `+76.1%` | 0.57x | 1.49 | **2.62** | `17.1` | 1.49 ± 0.01 | 2.54 ± 0.14 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1924-L1951) [🔍 112p](slices/58_backend_core_memory_commits.md) | **REGRESSION** | `+58.8%` | 0.63x | 1.20 | **1.90** | `15.7` | 1.24 ± 0.09 | 1.90 ± 0.01 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1954-L1993) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **REGRESSION** | `+60.9%` | 0.62x | 15.4 | **24.8** | `10.6` | 16.0 ± 1.87 | 24.9 ± 0.11 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1996-L2030) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **REGRESSION** | `+54.5%` | 0.65x | 45.9 | **71.0** | `4.9` | 48.6 ± 10.2 | 70.8 ± 0.28 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2033-L2074) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **REGRESSION** | `+48.8%` | 0.67x | 1.30 | **1.94** | `6.0` | 1.38 ± 0.21 | 1.94 ± 0.01 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2076-L2097) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **REGRESSION** | `+56.0%` | 0.64x | 0.69 | **1.07** | `7.6` | 0.71 ± 0.11 | 1.07 ± 0.00 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2140-L2175) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **REGRESSION** | `+62.2%` | 0.62x | 4.42 | **7.16** | `12.2` | 4.48 ± 0.16 | 7.37 ± 0.50 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2179-L2191) [🔍 84p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **REGRESSION** | `+52.7%` | 0.65x | 0.67 | **1.02** | `18.2` | 0.68 ± 0.04 | 1.02 ± 0.01 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2195-L2231) [🔍 180p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **REGRESSION** | `+48.0%` | 0.68x | 4.31 | **6.38** | `22.2` | 4.31 ± 0.08 | 6.50 ± 0.20 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2233-L2243) [🔍 152p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **REGRESSION** | `+62.3%` | 0.62x | 2.05 | **3.33** | `47.5` | 2.06 ± 0.05 | 3.33 ± 0.03 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2245-L2255) [🔍 111p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **REGRESSION** | `+67.7%` | 0.60x | 1.76 | **2.95** | `10.8` | 1.77 ± 0.05 | 3.06 ± 0.26 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2260-L2277) [🔍 155p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **REGRESSION** | `+34.0%` | 0.75x | 291.1 | **390.1** | `58.1` | 291.6 ± 3.53 | 389.4 ± 1.30 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2279-L2288) [🔍 91p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | `~NOISE` | `-0.3%` | 1.00x | 2.55 | **2.54** | `0.6` | 2.56 ± 0.05 | 2.54 ± 0.04 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2292-L2312) [🔍 135p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **REGRESSION** | `+53.1%` | 0.65x | 16.8 | **25.8** | `24.9` | 17.1 ± 0.77 | 25.8 ± 0.14 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2315-L2330) [🔍 135p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **REGRESSION** | `+52.7%` | 0.65x | 719.3 | **1098.7** | `32.3` | 725.5 ± 19.4 | 1101.7 ± 17.3 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2333-L2348) [🔍 135p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **REGRESSION** | `+49.2%` | 0.67x | 34.1 | **50.8** | `26.4` | 33.3 ± 1.45 | 51.0 ± 0.36 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2352-L2369) [🔍 111p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **REGRESSION** | `+51.4%` | 0.66x | 3.54 | **5.36** | `4.8` | 3.84 ± 0.71 | 5.36 ± 0.10 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2372-L2414) [🔍 199p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **REGRESSION** | `+43.1%` | 0.70x | 7.72 | **11.0** | `8.4` | 8.06 ± 0.79 | 11.0 ± 0.07 |


### 2. Odin Full Suite Results (`-o:speed -microarch:native`, Commit `bab4850e4f8e`, 5 samples across 1 run(s))

#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 13 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L528-L545) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **91** | 91 ± 0.5 | 0.6% | 10.9M | 11.0M | 1 | 92 | 92 | 91 | 92 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L608-L624) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **56** | 58 ± 2.6 | 4.5% | 16.1M | 17.9M | 2 | 61 | 62 | 56 | 62 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L842-L857) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **73** | 73 ± 0.4 | 0.6% | 13.5M | 13.7M | 0 | 74 | 74 | 73 | 74 | 2K |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L859-L876) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **20** | 20 ± 0.0 | 0.0% | 50.0M | 50.0M | 0 | 20 | 20 | 20 | 20 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L968-L983) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **88** | 88 ± 0.5 | 0.6% | 11.4M | 11.5M | 1 | 88 | 88 | 87 | 88 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L985-L1002) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **22** | 22 ± 0.0 | 0.0% | 45.5M | 45.5M | 0 | 22 | 22 | 22 | 22 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1192-L1207) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **20** | 20 ± 0.0 | 0.0% | 50.0M | 50.0M | 0 | 20 | 20 | 20 | 20 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1614-L1639) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **12** | 13 ± 1.3 | 10.6% | 66.7M | 83.3M | 0 | 14 | 15 | 12 | 15 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1641-L1650) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **18** | 18 ± 0.0 | 0.0% | 55.6M | 55.6M | 0 | 18 | 18 | 18 | 18 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1652-L1668) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **11** | 11 ± 0.5 | 4.8% | 83.3M | 90.9M | 1 | 12 | 12 | 11 | 12 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1670-L1679) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **19** | 19 ± 0.0 | 0.0% | 52.6M | 52.6M | 0 | 19 | 19 | 19 | 19 | 10K |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1739-L1754) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **7** | 7 ± 0.0 | 0.0% | 143M | 143M | 0 | 7 | 7 | 7 | 7 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1756-L1786) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **41** | 42 ± 2.0 | 4.8% | 22.2M | 25.0M | 2 | 45 | 45 | 40 | 45 | 2K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 36 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L483-L508) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **346** | 347 ± 4.4 | 1.3% | 2.8M | 2.9M | 7 | 352 | 352 | 342 | 352 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L510-L526) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **155** | 155 ± 1.5 | 1.0% | 6.3M | 6.5M | 0 | 157 | 158 | 154 | 158 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L580-L606) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **283** | 284 ± 5.1 | 1.8% | 3.4M | 3.6M | 3 | 291 | 292 | 278 | 292 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L626-L649) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **336** | 338 ± 7.4 | 2.2% | 2.9M | 3.0M | 7 | 348 | 350 | 332 | 350 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L651-L675) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **357** | 356 ± 3.8 | 1.1% | 2.8M | 2.9M | 1 | 359 | 359 | 349 | 359 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L677-L695) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **283** | 286 ± 7.1 | 2.5% | 3.4M | 3.6M | 7 | 295 | 297 | 279 | 297 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L697-L737) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **333** | 336 ± 12.6 | 3.7% | 2.8M | 3.1M | 12 | 352 | 355 | 325 | 356 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L739-L759) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **333** | 341 ± 12.8 | 3.8% | 2.8M | 3.0M | 15 | 358 | 360 | 332 | 361 | 500 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L761-L779) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **356** | 356 ± 4.7 | 1.3% | 2.7M | 2.8M | 4 | 363 | 364 | 352 | 364 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L781-L797) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **152** | 152 ± 2.5 | 1.7% | 6.5M | 6.7M | 4 | 155 | 155 | 149 | 155 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L807-L840) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **165** | 167 ± 8.1 | 4.8% | 5.5M | 6.2M | 5 | 178 | 180 | 161 | 181 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L878-L896) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **138** | 140 ± 4.6 | 3.3% | 6.8M | 7.3M | 3 | 146 | 148 | 137 | 148 | 2K |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L898-L912) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **576** | 576 ± 2.6 | 0.4% | 1.73M | 1.75M | 2 | 579 | 579 | 572 | 579 | 2K |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L933-L966) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **387** | 386 ± 3.1 | 0.8% | 2.57M | 2.62M | 2 | 389 | 389 | 381 | 389 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1004-L1030) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **410** | 416 ± 12.8 | 3.1% | 2.3M | 2.5M | 20 | 432 | 434 | 406 | 434 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1032-L1051) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **526** | 532 ± 10.6 | 2.0% | 1.8M | 1.9M | 18 | 543 | 543 | 521 | 543 | 500 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1080-L1097) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **260** | 259 ± 3.7 | 1.4% | 3.8M | 3.9M | 5 | 263 | 263 | 254 | 263 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1099-L1113) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **615** | 615 ± 0.5 | 0.1% | 1.62M | 1.63M | 1 | 616 | 616 | 615 | 616 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1122-L1160) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **618** | 618 ± 2.0 | 0.3% | 1.61M | 1.63M | 2 | 620 | 620 | 615 | 620 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1162-L1177) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **275** | 275 ± 2.4 | 0.9% | 3.6M | 3.7M | 3 | 278 | 278 | 272 | 278 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1179-L1190) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **225** | 225 ± 1.5 | 0.7% | 4.4M | 4.5M | 3 | 227 | 227 | 224 | 227 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1209-L1224) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **760** | 759 ± 0.9 | 0.1% | 1.3M | 1.3M | 1 | 760 | 760 | 758 | 760 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1226-L1252) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **385** | 385 ± 3.9 | 1.0% | 2.56M | 2.64M | 1 | 389 | 390 | 379 | 390 | 1K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1254-L1266) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **116** | 116 ± 1.2 | 1.1% | 8.5M | 8.7M | 1 | 118 | 118 | 115 | 118 | 2K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1268-L1283) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **558** | 559 ± 2.4 | 0.4% | 1.78M | 1.80M | 0 | 562 | 563 | 557 | 563 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1285-L1303) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **584** | 584 ± 1.8 | 0.3% | 1.70M | 1.72M | 1 | 587 | 587 | 582 | 587 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1305-L1326) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **564** | 563 ± 1.9 | 0.3% | 1.77M | 1.79M | 1 | 565 | 565 | 560 | 565 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1328-L1342) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **258** | 258 ± 1.6 | 0.6% | 3.8M | 3.9M | 2 | 260 | 260 | 256 | 260 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1384-L1402) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **775** | 783 ± 29.1 | 3.7% | 1.2M | 1.3M | 40 | 818 | 820 | 750 | 821 | 200 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1590-L1611) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **337** | 346 ± 20.5 | 5.9% | 2.6M | 3.0M | 5 | 374 | 380 | 334 | 382 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1590-L1611) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **362** | 369 ± 18.6 | 5.0% | 2.5M | 2.8M | 5 | 395 | 401 | 356 | 402 | 2K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1721-L1737) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **108** | 109 ± 14.6 | 13.3% | 7.5M | 10.3M | 8 | 129 | 133 | 97 | 134 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1789-L1842) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **380** | 387 ± 19.4 | 5.0% | 2.4M | 2.7M | 2 | 414 | 420 | 377 | 422 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1844-L1865) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **252** | 253 ± 7.3 | 2.9% | 3.8M | 4.0M | 3 | 263 | 265 | 248 | 266 | 500 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1868-L1901) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **161** | 165 ± 15.2 | 9.2% | 5.2M | 6.5M | 4 | 186 | 191 | 154 | 192 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2099-L2114) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **103** | 104 ± 1.5 | 1.5% | 9.4M | 9.8M | 1 | 106 | 106 | 102 | 106 | 5K |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 26 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L547-L578) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **1.83** | 1.82 ± 0.01 | 0.7% | 544K | 553K | 0.01 | 1.84 | 1.84 | 1.81 | 1.84 | 500 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L914-L930) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **1.29** | 1.29 ± 0.02 | 1.7% | 758K | 791K | 0.02 | 1.32 | 1.32 | 1.26 | 1.32 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1053-L1078) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **1.83** | 1.83 ± 0.03 | 1.7% | 532K | 555K | 0.03 | 1.87 | 1.88 | 1.80 | 1.88 | 400 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1404-L1429) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **1.82** | 1.83 ± 0.04 | 2.0% | 535K | 558K | 0.07 | 1.87 | 1.87 | 1.79 | 1.87 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1431-L1449) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **9.95** | 9.96 ± 0.68 | 6.9% | 90.4K | 107K | 0.58 | 10.9 | 11.0 | 9.34 | 11.1 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1451-L1472) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **22.5** | 22.6 ± 0.75 | 3.3% | 42.0K | 45.7K | 0.64 | 23.6 | 23.8 | 21.9 | 23.8 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1474-L1533) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **72.4** | 72.7 ± 2.99 | 4.1% | 12.9K | 14.5K | 0.75 | 76.4 | 77.1 | 68.9 | 77.2 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1535-L1560) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **2.31** | 2.31 ± 0.03 | 1.1% | 428K | 440K | 0.04 | 2.34 | 2.34 | 2.27 | 2.34 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1682-L1719) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **2.62** | 2.54 ± 0.14 | 5.4% | 375K | 422K | 0.22 | 2.66 | 2.67 | 2.37 | 2.67 | 256 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1924-L1951) [🔍 112p](slices/58_backend_core_memory_commits.md) | **1.90** | 1.90 ± 0.01 | 0.5% | 523K | 530K | 0.01 | 1.91 | 1.91 | 1.89 | 1.91 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1954-L1993) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **24.8** | 24.9 ± 0.11 | 0.4% | 40.0K | 40.4K | 0.15 | 25.0 | 25.0 | 24.8 | 25.0 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1996-L2030) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **71.0** | 70.8 ± 0.28 | 0.4% | 14.1K | 14.2K | 0.17 | 71.1 | 71.1 | 70.4 | 71.1 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2033-L2074) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.94** | 1.94 ± 0.01 | 0.6% | 512K | 519K | 0.02 | 1.95 | 1.95 | 1.93 | 1.95 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2076-L2097) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **1.07** | 1.07 ± 0.00 | 0.3% | 930K | 938K | 0.00 | 1.08 | 1.08 | 1.07 | 1.08 | 500 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2140-L2175) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **7.16** | 7.37 ± 0.50 | 6.8% | 121K | 141K | 0.02 | 8.05 | 8.23 | 7.11 | 8.27 | 500 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2179-L2191) [🔍 84p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **1.02** | 1.02 ± 0.01 | 1.4% | 955K | 990K | 0.01 | 1.04 | 1.05 | 1.01 | 1.05 | 500 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2195-L2231) [🔍 180p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **6.38** | 6.50 ± 0.20 | 3.1% | 146K | 158K | 0.17 | 6.78 | 6.82 | 6.35 | 6.83 | 200 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2233-L2243) [🔍 152p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **3.33** | 3.33 ± 0.03 | 0.9% | 296K | 303K | 0.02 | 3.37 | 3.38 | 3.30 | 3.38 | 200 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2245-L2255) [🔍 111p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **2.95** | 3.06 ± 0.26 | 8.6% | 283K | 343K | 0.08 | 3.42 | 3.51 | 2.91 | 3.53 | 200 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2260-L2277) [🔍 155p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **390.1** | 389.4 ± 1.30 | 0.3% | 2.56K | 2.58K | 1.31 | 390.3 | 390.4 | 387.3 | 390.4 | 200 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2279-L2288) [🔍 91p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **2.54** | 2.54 ± 0.04 | 1.7% | 385K | 403K | 0.05 | 2.59 | 2.59 | 2.48 | 2.60 | 200 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2292-L2312) [🔍 135p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **25.8** | 25.8 ± 0.14 | 0.6% | 38.4K | 38.9K | 0.19 | 26.0 | 26.0 | 25.7 | 26.0 | 100 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2315-L2330) [🔍 135p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **1098.7** | 1101.7 ± 17.3 | 1.6% | 889 | 923 | 26.1 | 1122.4 | 1124.1 | 1083.6 | 1124.6 | 25 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2333-L2348) [🔍 135p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **50.8** | 51.0 ± 0.36 | 0.7% | 19.4K | 19.7K | 0.14 | 51.5 | 51.6 | 50.8 | 51.6 | 100 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2352-L2369) [🔍 111p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **5.36** | 5.36 ± 0.10 | 1.9% | 183K | 191K | 0.18 | 5.46 | 5.46 | 5.25 | 5.46 | 200 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2372-L2414) [🔍 199p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **11.0** | 11.0 ± 0.07 | 0.6% | 90.0K | 91.2K | 0.12 | 11.1 | 11.1 | 11.0 | 11.1 | 200 |


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

### 4. 1v1 Statistical Comparison (Odin vs. Zig, Commit `bab4850e4f8e`)

#### 4.1 Sub-100ns Fast Path (`ns`, 13 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L528-L545) ([Zig](bench_xitdb.zig#L557-L574) · [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md)) | **2.33x** | **91** | 212 | `30.7` ★ | 91 ± 0.5 | 0.6% | 92 | 210 ± 8.6 | 4.1% | 219 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L608-L624) ([Zig](bench_xitdb.zig#L632-L646) · [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md)) | **2.88x** | **56** | 161 | `31.7` ★ | 58 ± 2.6 | 4.5% | 61 | 164 ± 7.0 | 4.3% | 173 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L842-L857) ([Zig](bench_xitdb.zig#L865-L880) · [🔍 30p](slices/15_array_list_radix_trie_random_get.md)) | **2.04x** | **73** | 149 | `28.6` ★ | 73 ± 0.4 | 0.6% | 74 | 148 ± 5.9 | 3.9% | 154 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L859-L876) ([Zig](bench_xitdb.zig#L882-L896) · [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md)) | **1.80x** | **20** | 36 | `27.8` ★ | 20 ± 0.0 | 0.0% | 20 | 36 ± 1.3 | 3.6% | 38 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L968-L983) ([Zig](bench_xitdb.zig#L987-L1002) · [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md)) | **1.65x** | **88** | 145 | `20.3` ★ | 88 ± 0.5 | 0.6% | 88 | 146 ± 6.5 | 4.4% | 153 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L985-L1002) ([Zig](bench_xitdb.zig#L1004-L1018) · [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md)) | **2.91x** | **22** | 64 | `61.0` ★ | 22 ± 0.0 | 0.0% | 22 | 63 ± 1.5 | 2.4% | 65 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1192-L1207) ([Zig](bench_xitdb.zig#L1206-L1219) · [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md)) | **2.75x** | **20** | 55 | `21.1` ★ | 20 ± 0.0 | 0.0% | 20 | 56 ± 3.8 | 6.8% | 61 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1614-L1639) ([Zig](bench_xitdb.zig#L1721-L1752) · [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md)) | 0.67x | 12 | **8** | `7.7` ★ | 13 ± 1.3 | 10.6% | 14 | 8 ± 0.5 | 7.2% | 8 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1641-L1650) ([Zig](bench_xitdb.zig#L1754-L1763) · [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md)) | **2.33x** | **18** | 42 | `18.2` ★ | 18 ± 0.0 | 0.0% | 18 | 41 ± 2.9 | 7.0% | 45 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1652-L1668) ([Zig](bench_xitdb.zig#L1765-L1787) · [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md)) | 0.73x | 11 | **8** | `6.0` ★ | 11 ± 0.5 | 4.8% | 12 | 9 ± 0.9 | 10.4% | 10 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1670-L1679) ([Zig](bench_xitdb.zig#L1789-L1798) · [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md)) | **2.63x** | **19** | 50 | `41.3` ★ | 19 ± 0.0 | 0.0% | 19 | 51 ± 1.7 | 3.4% | 53 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1739-L1754) ([Zig](bench_xitdb.zig#L1856-L1871) · [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md)) | **4.57x** | **7** | 32 | `9.0` ★ | 7 ± 0.0 | 0.0% | 7 | 35 ± 7.1 | 19.9% | 45 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1756-L1786) ([Zig](bench_xitdb.zig#L1873-L1900) · [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md)) | 0.80x | 41 | **33** | `5.6` ★ | 42 ± 2.0 | 4.8% | 45 | 34 ± 2.7 | 8.0% | 37 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 36 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L483-L508) ([Zig](bench_xitdb.zig#L513-L537) · [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md)) | **2.49x** | **346** | 861 | `31.4` ★ | 347 ± 4.4 | 1.3% | 352 | 866 ± 36.7 | 4.2% | 910 |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L510-L526) ([Zig](bench_xitdb.zig#L539-L555) · [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md)) | **1.94x** | **155** | 300 | `20.9` ★ | 155 ± 1.5 | 1.0% | 157 | 297 ± 15.0 | 5.1% | 314 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L580-L606) ([Zig](bench_xitdb.zig#L608-L630) · [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md)) | **3.92x** | **283** | 1,109 | `31.7` ★ | 284 ± 5.1 | 1.8% | 291 | 1,111 ± 58.0 | 5.2% | 1,175 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L626-L649) ([Zig](bench_xitdb.zig#L648-L670) · [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md)) | **2.41x** | **336** | 811 | `28.9` ★ | 338 ± 7.4 | 2.2% | 348 | 830 ± 37.4 | 4.5% | 880 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L651-L675) ([Zig](bench_xitdb.zig#L672-L700) · [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md)) | **2.44x** | **357** | 870 | `26.4` ★ | 356 ± 3.8 | 1.1% | 359 | 879 ± 44.2 | 5.0% | 930 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L677-L695) ([Zig](bench_xitdb.zig#L702-L721) · [🔍 83p](slices/09_hamt_counted_hash_map_remove.md)) | **4.32x** | **283** | 1,222 | `31.8` ★ | 286 ± 7.1 | 2.5% | 295 | 1,189 ± 63.1 | 5.3% | 1,241 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L697-L737) ([Zig](bench_xitdb.zig#L723-L761) · [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md)) | **4.04x** | **333** | 1,345 | `30.0` ★ | 336 ± 12.6 | 3.7% | 352 | 1,363 ± 75.5 | 5.5% | 1,456 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L739-L759) ([Zig](bench_xitdb.zig#L763-L784) · [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md)) | **9.24x** | **333** | 3,078 | `38.3` ★ | 341 ± 12.8 | 3.8% | 358 | 3,054 ± 158 | 5.2% | 3,207 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L761-L779) ([Zig](bench_xitdb.zig#L786-L806) · [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md)) | **1.71x** | **356** | 607 | `23.7` ★ | 356 ± 4.7 | 1.3% | 363 | 605 ± 22.9 | 3.8% | 631 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L781-L797) ([Zig](bench_xitdb.zig#L808-L824) · [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md)) | **1.96x** | **152** | 298 | `21.7` ★ | 152 ± 2.5 | 1.7% | 155 | 299 ± 14.9 | 5.0% | 316 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L807-L840) ([Zig](bench_xitdb.zig#L834-L863) · [🔍 91p](slices/14_array_list_radix_trie_append.md)) | **1.42x** | **165** | 235 | `13.0` ★ | 167 ± 8.1 | 4.8% | 178 | 241 ± 9.8 | 4.1% | 253 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L878-L896) ([Zig](bench_xitdb.zig#L898-L918) · [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md)) | **1.76x** | **138** | 243 | `19.8` ★ | 140 ± 4.6 | 3.3% | 146 | 241 ± 10.5 | 4.3% | 251 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L898-L912) ([Zig](bench_xitdb.zig#L920-L933) · [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md)) | **2.91x** | **576** | 1,679 | `37.7` ★ | 576 ± 2.6 | 0.4% | 579 | 1,690 ± 66.0 | 3.9% | 1,776 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L933-L966) ([Zig](bench_xitdb.zig#L956-L985) · [🔍 107p](slices/20_linked_array_list_b_tree_append.md)) | **5.19x** | **387** | 2,007 | `43.6` ★ | 386 ± 3.1 | 0.8% | 389 | 2,010 ± 83.2 | 4.1% | 2,111 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1004-L1030) ([Zig](bench_xitdb.zig#L1020-L1043) · [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md)) | **5.72x** | **410** | 2,347 | `46.0` ★ | 416 ± 12.8 | 3.1% | 432 | 2,379 ± 94.5 | 4.0% | 2,490 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1032-L1051) ([Zig](bench_xitdb.zig#L1045-L1066) · [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md)) | **4.52x** | **526** | 2,378 | `40.0` ★ | 532 ± 10.6 | 2.0% | 543 | 2,396 ± 104 | 4.3% | 2,512 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1080-L1097) ([Zig](bench_xitdb.zig#L1093-L1112) · [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md)) | **5.86x** | **260** | 1,524 | `70.0` ★ | 259 ± 3.7 | 1.4% | 263 | 1,514 ± 40.0 | 2.6% | 1,553 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1099-L1113) ([Zig](bench_xitdb.zig#L1114-L1127) · [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md)) | **4.78x** | **615** | 2,937 | `55.8` ★ | 615 ± 0.5 | 0.1% | 616 | 2,900 ± 91.6 | 3.2% | 2,982 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1122-L1160) ([Zig](bench_xitdb.zig#L1136-L1174) · [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md)) | **5.25x** | **618** | 3,247 | `33.9` ★ | 618 ± 2.0 | 0.3% | 620 | 3,321 ± 178 | 5.4% | 3,564 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1162-L1177) ([Zig](bench_xitdb.zig#L1176-L1191) · [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md)) | **8.39x** | **275** | 2,307 | `146.4` ★ | 275 ± 2.4 | 0.9% | 278 | 2,308 ± 31.0 | 1.3% | 2,343 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1179-L1190) ([Zig](bench_xitdb.zig#L1193-L1204) · [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md)) | **10.09x** | **225** | 2,270 | `84.8` ★ | 225 ± 1.5 | 0.7% | 227 | 2,303 ± 54.7 | 2.4% | 2,373 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1209-L1224) ([Zig](bench_xitdb.zig#L1221-L1235) · [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md)) | **4.49x** | **760** | 3,415 | `273.3` ★ | 759 ± 0.9 | 0.1% | 760 | 3,423 ± 21.8 | 0.6% | 3,451 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1226-L1252) ([Zig](bench_xitdb.zig#L1237-L1259) · [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md)) | **9.02x** | **385** | 3,472 | `141.3` ★ | 385 ± 3.9 | 1.0% | 389 | 3,468 ± 48.6 | 1.4% | 3,520 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1254-L1266) ([Zig](bench_xitdb.zig#L1261-L1273) · [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md)) | **1.53x** | **116** | 178 | `32.2` ★ | 116 ± 1.2 | 1.1% | 118 | 178 ± 4.1 | 2.3% | 181 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1268-L1283) ([Zig](bench_xitdb.zig#L1275-L1289) · [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md)) | **5.26x** | **558** | 2,934 | `110.4` ★ | 559 ± 2.4 | 0.4% | 562 | 2,916 ± 47.7 | 1.6% | 2,947 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1285-L1303) ([Zig](bench_xitdb.zig#L1291-L1311) · [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md)) | **4.77x** | **584** | 2,785 | `75.2` ★ | 584 ± 1.8 | 0.3% | 587 | 2,762 ± 64.7 | 2.3% | 2,819 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1305-L1326) ([Zig](bench_xitdb.zig#L1313-L1336) · [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md)) | **5.21x** | **564** | 2,938 | `92.8` ★ | 563 ± 1.9 | 0.3% | 565 | 2,924 ± 56.9 | 1.9% | 2,965 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1328-L1342) ([Zig](bench_xitdb.zig#L1338-L1352) · [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md)) | **8.28x** | **258** | 2,136 | `154.9` ★ | 258 ± 1.6 | 0.6% | 260 | 2,141 ± 27.1 | 1.3% | 2,171 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1384-L1402) ([Zig](bench_xitdb.zig#L1388-L1411) · [🔍 54p](slices/39_replication_genesis_200_moments.md)) | **1.73x** | **775** | 1,338 | `9.1` ★ | 783 ± 29.1 | 3.7% | 818 | 1,307 ± 125 | 9.6% | 1,434 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1590-L1611) ([Zig](bench_xitdb.zig#L1656-L1686) · [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md)) | **2.41x** | **337** | 812 | `38.9` ★ | 346 ± 20.5 | 5.9% | 374 | 818 ± 17.9 | 2.2% | 838 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1590-L1611) ([Zig](bench_xitdb.zig#L1689-L1718) · [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md)) | **2.50x** | **362** | 905 | `38.7` ★ | 369 ± 18.6 | 5.0% | 395 | 916 ± 25.6 | 2.8% | 951 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1721-L1737) ([Zig](bench_xitdb.zig#L1838-L1854) · [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md)) | **1.68x** | **108** | 181 | `2.8` ★ | 109 ± 14.6 | 13.3% | 129 | 217 ± 85.7 | 39.5% | 333 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1789-L1842) ([Zig](bench_xitdb.zig#L1903-L1949) · [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md)) | **3.17x** | **380** | 1,205 | `55.1` ★ | 387 ± 19.4 | 5.0% | 414 | 1,215 ± 27.5 | 2.3% | 1,252 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1844-L1865) ([Zig](bench_xitdb.zig#L1951-L1972) · [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md)) | **3.22x** | **252** | 812 | `37.1` ★ | 253 ± 7.3 | 2.9% | 263 | 816 ± 33.1 | 4.1% | 856 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1868-L1901) ([Zig](bench_xitdb.zig#L1975-L2018) · [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md)) | **1.76x** | **161** | 284 | `16.5` ★ | 165 ± 15.2 | 9.2% | 186 | 284 ± 5.2 | 1.8% | 289 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2099-L2114) ([Zig](bench_xitdb.zig#L2265-L2279) · [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md)) | **2.65x** | **103** | 273 | `26.6` ★ | 104 ± 1.5 | 1.5% | 106 | 268 ± 13.7 | 5.1% | 281 |

#### 4.3 Multi-Microsecond Transactions & Compaction (`µs`, 14 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L547-L578) ([Zig](bench_xitdb.zig#L576-L606) · [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md)) | **1.42x** | **1.83** | 2.60 | `11.3` ★ | 1.82 ± 0.01 | 0.7% | 1.84 | 2.63 ± 0.16 | 6.0% | 2.80 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L914-L930) ([Zig](bench_xitdb.zig#L935-L953) · [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md)) | **1.24x** | **1.29** | 1.59 | `7.1` ★ | 1.29 ± 0.02 | 1.7% | 1.32 | 1.62 ± 0.10 | 6.2% | 1.75 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1053-L1078) ([Zig](bench_xitdb.zig#L1068-L1091) · [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md)) | **12.46x** | **1.83** | 22.8 | `53.3` ★ | 1.83 ± 0.03 | 1.7% | 1.87 | 22.9 ± 0.88 | 3.9% | 23.8 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1404-L1429) ([Zig](bench_xitdb.zig#L1413-L1438) · [🔍 102p](slices/40_replication_incremental_1_moment_delta.md)) | **1.06x** | **1.82** | 1.93 | `2.3` ★ | 1.83 ± 0.04 | 2.0% | 1.87 | 1.97 ± 0.13 | 6.4% | 2.10 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1431-L1449) ([Zig](bench_xitdb.zig#L1440-L1458) · [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md)) | 0.91x | 9.95 | **9.07** | `0.7` ~ | 9.96 ± 0.68 | 6.9% | 10.9 | 10.8 ± 2.62 | 24.3% | 14.1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1451-L1472) ([Zig](bench_xitdb.zig#L1460-L1514) · [🔍 99p](slices/42_compaction_file_offset_map_200_1.md)) | 0.94x | 22.5 | **21.1** | `1.3` ~ | 22.6 ± 0.75 | 3.3% | 23.6 | 20.5 ± 3.62 | 17.6% | 24.1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1474-L1533) ([Zig](bench_xitdb.zig#L1516-L1603) · [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md)) | **1.80x** | **72.4** | 130.6 | `10.8` ★ | 72.7 ± 2.99 | 4.1% | 76.4 | 134.3 ± 12.4 | 9.2% | 150.7 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1535-L1560) ([Zig](bench_xitdb.zig#L1605-L1635) · [🔍 55p](slices/44_replication_post_compaction_resync.md)) | 1.00x | 2.31 | **2.29** | `0.1` ~ | 2.31 ± 0.03 | 1.1% | 2.34 | 2.29 ± 0.41 | 18.1% | 2.81 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1682-L1719) ([Zig](bench_xitdb.zig#L1801-L1836) · [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md)) | 0.74x | 2.62 | **1.93** | `5.1` ★ | 2.54 ± 0.14 | 5.4% | 2.66 | 1.99 ± 0.20 | 10.0% | 2.26 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1924-L1951) ([Zig](bench_xitdb.zig#L2030-L2069) · [🔍 112p](slices/58_backend_core_memory_commits.md)) | **1.44x** | **1.90** | 2.74 | `25.1` ★ | 1.90 ± 0.01 | 0.5% | 1.91 | 2.75 ± 0.08 | 2.7% | 2.84 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1954-L1993) ([Zig](bench_xitdb.zig#L2072-L2126) · [🔍 113p](slices/59_backend_core_buffered_file_commits.md)) | 0.79x | 24.8 | **19.6** | `20.4` ★ | 24.9 ± 0.11 | 0.4% | 25.0 | 19.8 ± 0.54 | 2.7% | 20.4 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1996-L2030) ([Zig](bench_xitdb.zig#L2129-L2178) · [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md)) | 0.75x | 71.0 | **52.9** | `21.9` ★ | 70.8 ± 0.28 | 0.4% | 71.1 | 52.2 ± 1.88 | 3.6% | 53.9 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2033-L2074) ([Zig](bench_xitdb.zig#L2181-L2231) · [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md)) | **1.12x** | **1.94** | 2.17 | `6.8` ★ | 1.94 ± 0.01 | 0.6% | 1.95 | 2.17 ± 0.07 | 3.4% | 2.26 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2076-L2097) ([Zig](bench_xitdb.zig#L2233-L2263) · [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md)) | **2.02x** | **1.07** | 2.17 | `24.3` ★ | 1.07 ± 0.00 | 0.3% | 1.08 | 2.11 ± 0.10 | 4.5% | 2.19 |

### 5. Database Storage Footprint (`bytes_used > 0`)

| # | Benchmark | Ops | Odin Size | Zig Size |
| ---: | :--- | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L483-L508) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | 2K | 214.5 KB | 214.5 KB |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L547-L578) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | 500 | 457.7 KB | 457.7 KB |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L807-L840) [🔍 91p](slices/14_array_list_radix_trie_append.md) | 2K | 19.3 KB | 19.3 KB |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L933-L966) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | 2K | 45.3 KB | 45.3 KB |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1122-L1160) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | 2K | 115.4 KB | 115.4 KB |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1305-L1326) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | 2K | 80.0 KB | 80.0 KB |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1384-L1402) [🔍 54p](slices/39_replication_genesis_200_moments.md) | 200 | 250.9 KB | 250.9 KB |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1404-L1429) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | 100 | 132.7 KB | 132.7 KB |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1431-L1449) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1451-L1472) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1474-L1533) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | 1 | 23.4 KB | 23.4 KB |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1535-L1560) [🔍 55p](slices/44_replication_post_compaction_resync.md) | 1 | 23.4 KB | 23.4 KB |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1590-L1611) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | 2K | 224.7 KB | 224.7 KB |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1590-L1611) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | 2K | 248.7 KB | 248.7 KB |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1682-L1719) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | 256 | 1024.1 KB | 1024.1 KB |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1924-L1951) [🔍 112p](slices/58_backend_core_memory_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1954-L1993) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1996-L2030) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2140-L2175) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | 500 | 231.4 KB | — |
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
