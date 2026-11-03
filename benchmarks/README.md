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

### 1v1 Comparison with Upstream Zig (`reference/xitdb-zig`)

The upstream Zig reference implementation is tracked in `reference/xitdb-zig`. To run the Zig benchmark suite (requires Zig `0.17.0-dev` matching `reference/xitdb-zig/build.zig.zon`):

```bash
zig build bench -Doptimize=ReleaseFast -Dcpu=native -- --runs 5 --warmup 1
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

> **Interactive Code Links & Per-Benchmark Library Slices:**
> - Click any **benchmark title** in the tables below to jump directly to its highlighted implementation block (`#L<start>-L<end>`) in [`bench_xitdb.odin`](bench_xitdb.odin) or [`bench_xitdb.zig`](bench_xitdb.zig).
> - Click **`[🔍 <N>p]`** next to any benchmark (or browse the [**Per-Benchmark Code Slices Index (`slices/README.md`)**](slices/README.md)) to inspect the exact `xitdb/*.odin` procedures and call graph touched by that benchmark.

<!-- BEGIN_BENCHMARK_TABLE -->
### 1. Latest Code-Change Impact & Affected Benchmarks (`2d6f9a7120f3` → `40c719e2b02d`, Odin, 8 / 75 tests re-run)

- **Code Diff Inspected:** `f7c2d56~1..f7c2d56` · **Changed Files:** `xitdb/dsl.odin`
- **Modified Procedures:** `_diff_recursive`, `_eval_pattern_steps`, `_evict_stale_secondary_index_entries`, `_execute_remove_steps`, `_execute_tx_cb`, `_pull_cursor_value`, `_pull_scalar_slot`, `pull`
- **Mapped Benchmark Scope:** Odin groups=`dsl` · filter=`Cyclic|Datalog|Secondary Index|Tx Commit|diff_moments|pull` (**8 / 75** Odin benchmarks executed; **67** unchanged benchmarks retained from `2d6f9a7`)

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 8 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `2d6f9a7` (`µs`) | Curr `40c719e` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2128-L2163) [🔍 98p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | `~NOISE` | `-5.2%` | 1.06x | 4.56 | **4.32** | `0.9` | 4.71 ± 0.39 | 4.48 ± 0.37 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2233-L2243) [🔍 145p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | `~NOISE` | `+11.5%` | 0.90x | 1.53 | **1.71** | `2.7` | 1.54 ± 0.03 | 1.84 ± 0.25 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2248-L2265) [🔍 156p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | `~NOISE` | `+9.5%` | 0.91x | 261.7 | **286.6** | `11.2` | 263.4 ± 4.24 | 287.0 ± 2.01 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2280-L2300) [🔍 166p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | `~NOISE` | `-5.5%` | 1.06x | 15.4 | **14.5** | `1.3` | 15.6 ± 0.68 | 14.9 ± 0.97 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2303-L2318) [🔍 166p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **FASTER** | `-26.6%` | 1.36x | 855.4 | **628.2** | `16.1` | 842.9 ± 25.0 | 620.2 ± 18.3 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2321-L2336) [🔍 166p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | `~NOISE` | `+3.9%` | 0.96x | 27.1 | **28.2** | `1.4` | 27.7 ± 1.17 | 28.8 ± 1.43 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2340-L2357) [🔍 97p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **NEW** | `—` | — | — | **3.17** | `—` | — | 3.22 ± 0.13 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2360-L2402) [🔍 184p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **NEW** | `—` | — | — | **7.46** | `—` | — | 7.48 ± 0.13 |


### 2. Odin Full Suite Results (`-o:speed -microarch:native`, Commit `40c719e2b02d`, 5 samples across 1 run(s))

> **Selective update (`40c719e`):** Re-ran **8 / 75** affected benchmarks (marked with `↻` in `#` below; see Section 1 above for the code-change impact & progression table). Unchanged benchmarks retain their prior baseline.


#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 20 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L498-L514) [🔍 66p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **95** | 109 ± 31.4 | 28.8% | 6.1M | 10.8M | 6 | 152 | 162 | 93 | 165 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L516-L533) [🔍 58p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **60** | 77 ± 27.4 | 35.4% | 8.6M | 17.9M | 39 | 112 | 115 | 56 | 116 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L596-L612) [🔍 20p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **37** | 37 ± 0.8 | 2.3% | 26.3M | 27.8M | 1 | 38 | 38 | 36 | 38 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L769-L785) [🔍 68p](slices/13_hamt_counted_hash_set_membership_check.md) | **91** | 91 ± 1.5 | 1.7% | 10.6M | 11.1M | 0 | 93 | 94 | 90 | 94 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L830-L845) [🔍 49p](slices/15_array_list_radix_trie_random_get.md) | **46** | 46 ± 0.5 | 1.2% | 21.3M | 21.7M | 1 | 47 | 47 | 46 | 47 | 2K |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L847-L864) [🔍 21p](slices/16_array_list_radix_trie_iterator_scan.md) | **13** | 13 ± 0.5 | 4.3% | 76.9M | 83.3M | 1 | 13 | 13 | 12 | 13 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L866-L884) [🔍 66p](slices/17_array_list_radix_trie_in_place_put.md) | **89** | 89 ± 1.1 | 1.3% | 11.0M | 11.4M | 1 | 91 | 91 | 88 | 91 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L956-L971) [🔍 59p](slices/21_linked_array_list_b_tree_random_get.md) | **53** | 54 ± 0.9 | 1.7% | 18.2M | 18.9M | 1 | 55 | 55 | 53 | 55 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L973-L990) [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **13** | 13 ± 0.5 | 4.1% | 71.4M | 76.9M | 1 | 14 | 14 | 13 | 14 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1180-L1195) [🔍 20p](slices/31_sorted_map_b_tree_ordered_scan.md) | **13** | 13 ± 0.0 | 0.0% | 76.9M | 76.9M | 0 | 13 | 13 | 13 | 13 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1242-L1254) [🔍 54p](slices/34_sorted_map_b_tree_get_index_select.md) | **64** | 65 ± 1.3 | 2.0% | 14.9M | 15.6M | 1 | 67 | 67 | 64 | 67 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1602-L1627) [🔍 92p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **6** | 6 ± 0.0 | 0.0% | 167M | 167M | 0 | 6 | 6 | 6 | 6 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1629-L1638) [🔍 12p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **9** | 9 ± 0.0 | 0.0% | 111M | 111M | 0 | 9 | 9 | 9 | 9 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1640-L1656) [🔍 76p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **6** | 6 ± 0.0 | 0.0% | 167M | 167M | 0 | 6 | 6 | 6 | 6 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1658-L1667) [🔍 12p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **9** | 9 ± 0.4 | 4.9% | 100M | 111M | 0 | 10 | 10 | 9 | 10 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1709-L1725) [🔍 14p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **52** | 53 ± 0.9 | 1.7% | 18.5M | 19.2M | 1 | 54 | 54 | 52 | 54 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1727-L1742) [🔍 5p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **6** | 6 ± 0.9 | 14.0% | 125M | 167M | 0 | 8 | 8 | 6 | 8 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1744-L1774) [🔍 54p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **13** | 13 ± 0.4 | 3.4% | 71.4M | 76.9M | 0 | 14 | 14 | 13 | 14 | 2K |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1856-L1889) [🔍 117p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **97** | 97 ± 2.1 | 2.1% | 10.0M | 10.5M | 3 | 100 | 100 | 95 | 100 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2087-L2102) [🔍 36p](slices/63_db_re_open_trailer_checksum_verify.md) | **56** | 56 ± 0.5 | 1.0% | 17.5M | 17.9M | 1 | 57 | 57 | 56 | 57 | 5K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 36 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L471-L496) [🔍 81p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **202** | 241 ± 86.3 | 35.9% | 2.5M | 5.0M | 1 | 357 | 387 | 201 | 395 | 2K |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L535-L566) [🔍 83p](slices/04_hamt_cow_branched_moment_commits.md) | **923** | 1,138 ± 307 | 27.0% | 674K | 1.1M | 550 | 1,479 | 1,482 | 902 | 1,483 | 500 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L568-L594) [🔍 75p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **167** | 173 ± 16.6 | 9.6% | 5.0M | 6.2M | 12 | 195 | 200 | 161 | 201 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L614-L637) [🔍 81p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **192** | 201 ± 16.6 | 8.3% | 4.3M | 5.2M | 8 | 224 | 229 | 191 | 230 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L639-L663) [🔍 88p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **210** | 218 ± 22.8 | 10.4% | 3.9M | 4.9M | 2 | 249 | 257 | 205 | 259 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L665-L683) [🔍 72p](slices/09_hamt_counted_hash_map_remove.md) | **165** | 172 ± 11.7 | 6.8% | 5.3M | 6.2M | 17 | 187 | 188 | 162 | 188 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L685-L725) [🔍 78p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **193** | 202 ± 24.8 | 12.3% | 4.1M | 5.3M | 3 | 235 | 244 | 187 | 246 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L727-L747) [🔍 72p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **211** | 212 ± 3.8 | 1.8% | 4.6M | 4.8M | 1 | 217 | 218 | 208 | 218 | 500 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L749-L767) [🔍 77p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **222** | 236 ± 32.9 | 13.9% | 3.4M | 4.5M | 0 | 280 | 292 | 220 | 295 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L795-L828) [🔍 79p](slices/14_array_list_radix_trie_append.md) | **108** | 109 ± 0.9 | 0.8% | 9.1M | 9.3M | 1 | 110 | 110 | 108 | 110 | 2K |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L886-L900) [🔍 21p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **347** | 349 ± 6.3 | 1.8% | 2.8M | 2.9M | 9 | 357 | 358 | 343 | 358 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L902-L918) [🔍 65p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **701** | 699 ± 8.6 | 1.2% | 1.4M | 1.5M | 7 | 709 | 711 | 688 | 711 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) [🔍 92p](slices/20_linked_array_list_b_tree_append.md) | **231** | 231 ± 4.5 | 1.9% | 4.2M | 4.4M | 6 | 236 | 237 | 226 | 237 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L992-L1018) [🔍 81p](slices/23_linked_array_list_b_tree_middle_insert.md) | **258** | 258 ± 2.9 | 1.1% | 3.8M | 3.9M | 3 | 262 | 263 | 256 | 263 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1020-L1039) [🔍 82p](slices/24_linked_array_list_b_tree_middle_remove.md) | **349** | 350 ± 6.4 | 1.8% | 2.8M | 2.9M | 7 | 358 | 360 | 344 | 360 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1041-L1066) [🔍 87p](slices/25_linked_array_list_b_tree_concat_slice.md) | **807** | 812 ± 13.1 | 1.6% | 1.2M | 1.3M | 20 | 826 | 827 | 797 | 827 | 400 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1068-L1085) [🔍 73p](slices/26_linked_array_list_b_tree_in_place_put.md) | **161** | 162 ± 1.9 | 1.2% | 6.1M | 6.3M | 3 | 164 | 164 | 160 | 164 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1087-L1101) [🔍 21p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **394** | 395 ± 2.3 | 0.6% | 2.51M | 2.54M | 4 | 398 | 398 | 393 | 398 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1110-L1148) [🔍 110p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **388** | 387 ± 1.7 | 0.4% | 2.58M | 2.60M | 1 | 388 | 388 | 384 | 388 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1150-L1165) [🔍 80p](slices/29_sorted_map_b_tree_key_lookup.md) | **163** | 163 ± 1.0 | 0.6% | 6.1M | 6.2M | 2 | 164 | 164 | 162 | 164 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1167-L1178) [🔍 20p](slices/30_sorted_map_b_tree_rank_query.md) | **131** | 131 ± 0.7 | 0.5% | 7.6M | 7.7M | 0 | 132 | 132 | 130 | 132 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1197-L1212) [🔍 27p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **466** | 465 ± 1.5 | 0.3% | 2.1M | 2.2M | 1 | 467 | 467 | 463 | 467 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1214-L1240) [🔍 82p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **230** | 231 ± 2.6 | 1.1% | 4.3M | 4.4M | 4 | 234 | 234 | 228 | 234 | 1K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1256-L1271) [🔍 22p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **401** | 401 ± 1.5 | 0.4% | 2.48M | 2.51M | 1 | 403 | 403 | 399 | 403 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1273-L1291) [🔍 93p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **362** | 362 ± 1.3 | 0.4% | 2.75M | 2.78M | 2 | 363 | 363 | 360 | 363 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1293-L1314) [🔍 93p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **343** | 343 ± 2.0 | 0.6% | 2.90M | 2.93M | 4 | 345 | 345 | 341 | 345 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1316-L1330) [🔍 79p](slices/38_sorted_set_b_tree_contains_lookup.md) | **144** | 145 ± 0.9 | 0.6% | 6.8M | 6.9M | 1 | 146 | 146 | 144 | 146 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1372-L1390) [🔍 41p](slices/39_replication_genesis_200_moments.md) | **104** | 107 ± 11.2 | 10.5% | 7.9M | 10.0M | 3 | 122 | 126 | 100 | 127 | 200 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1392-L1417) [🔍 92p](slices/40_replication_incremental_1_moment_delta.md) | **743** | 752 ± 17.9 | 2.4% | 1.3M | 1.4M | 16 | 776 | 780 | 737 | 781 | 100 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 98p](slices/45_hasher_sha_1_20b_hamt_put.md) | **223** | 223 ± 2.9 | 1.3% | 4.4M | 4.6M | 2 | 225 | 225 | 218 | 225 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 101p](slices/46_hasher_sha_256_32b_hamt_put.md) | **233** | 233 ± 2.5 | 1.1% | 4.2M | 4.3M | 5 | 236 | 236 | 231 | 236 | 2K |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1670-L1707) [🔍 66p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **288** | 291 ± 9.9 | 3.4% | 3.2M | 3.5M | 1 | 305 | 308 | 285 | 309 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1777-L1830) [🔍 61p](slices/55_path_4_level_nested_cursor_write_path.md) | **230** | 231 ± 1.9 | 0.8% | 4.3M | 4.4M | 1 | 233 | 234 | 229 | 234 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1832-L1853) [🔍 41p](slices/56_path_4_level_nested_cursor_read_path.md) | **148** | 148 ± 4.2 | 2.8% | 6.6M | 7.1M | 3 | 152 | 152 | 141 | 152 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2064-L2085) [🔍 76p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **693** | 693 ± 3.5 | 0.5% | 1.4M | 1.5M | 3 | 696 | 696 | 687 | 696 | 500 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2167-L2179) [🔍 116p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **540** | 540 ± 10.9 | 2.0% | 1.8M | 1.9M | 11 | 554 | 556 | 530 | 557 | 500 |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 19 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) [🔍 89p](slices/41_compaction_memory_offset_map_200_1.md) | **3.71** | 3.89 ± 0.32 | 8.3% | 229K | 279K | 0.39 | 4.31 | 4.35 | 3.59 | 4.36 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) [🔍 88p](slices/42_compaction_file_offset_map_200_1.md) | **9.35** | 9.49 ± 0.48 | 5.1% | 97.8K | 111K | 0.43 | 10.1 | 10.2 | 8.98 | 10.2 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) [🔍 152p](slices/43_compaction_heterogeneous_dag_dedup.md) | **126.6** | 126.4 ± 4.40 | 3.5% | 7.5K | 8.2K | 3.22 | 131.9 | 132.8 | 121.3 | 133.1 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) [🔍 42p](slices/44_replication_post_compaction_resync.md) | **1.46** | 1.46 ± 0.04 | 2.5% | 661K | 703K | 0.05 | 1.51 | 1.51 | 1.42 | 1.51 | 1 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1912-L1939) [🔍 100p](slices/58_backend_core_memory_commits.md) | **1.22** | 1.22 ± 0.01 | 0.9% | 810K | 829K | 0.01 | 1.23 | 1.23 | 1.21 | 1.24 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) [🔍 101p](slices/59_backend_core_buffered_file_commits.md) | **4.58** | 4.58 ± 0.02 | 0.3% | 218K | 220K | 0.01 | 4.59 | 4.59 | 4.55 | 4.59 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1984-L2018) [🔍 100p](slices/60_backend_core_file_unbuffered_commits.md) | **44.1** | 44.1 ± 0.19 | 0.4% | 22.5K | 22.8K | 0.21 | 44.4 | 44.4 | 43.9 | 44.4 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2021-L2062) [🔍 95p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.12** | 1.11 ± 0.01 | 0.8% | 891K | 909K | 0.01 | 1.12 | 1.12 | 1.10 | 1.12 | 500 |
| 64 ↻ | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2128-L2163) [🔍 98p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **4.32** | 4.48 ± 0.37 | 8.3% | 198K | 242K | 0.42 | 4.97 | 5.03 | 4.13 | 5.04 | 500 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2183-L2219) [🔍 168p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **4.23** | 4.41 ± 0.28 | 6.4% | 211K | 240K | 0.48 | 4.73 | 4.73 | 4.16 | 4.74 | 200 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2221-L2231) [🔍 136p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **1.98** | 1.97 ± 0.03 | 1.3% | 500K | 515K | 0.04 | 2.00 | 2.00 | 1.94 | 2.00 | 200 |
| 68 ↻ | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2233-L2243) [🔍 145p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **1.71** | 1.84 ± 0.25 | 13.3% | 442K | 593K | 0.16 | 2.18 | 2.24 | 1.69 | 2.26 | 200 |
| 69 ↻ | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2248-L2265) [🔍 156p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **286.6** | 287.0 ± 2.01 | 0.7% | 3.45K | 3.51K | 2.10 | 289.4 | 289.7 | 284.5 | 289.8 | 200 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2267-L2276) [🔍 120p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **1.88** | 1.83 ± 0.09 | 4.8% | 524K | 581K | 0.14 | 1.91 | 1.91 | 1.72 | 1.91 | 200 |
| 71 ↻ | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2280-L2300) [🔍 166p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **14.5** | 14.9 ± 0.97 | 6.5% | 60.3K | 70.5K | 0.59 | 16.3 | 16.5 | 14.2 | 16.6 | 100 |
| 72 ↻ | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2303-L2318) [🔍 166p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **628.2** | 620.2 ± 18.3 | 2.9% | 1.6K | 1.7K | 32.5 | 636.1 | 636.2 | 598.2 | 636.2 | 25 |
| 73 ↻ | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2321-L2336) [🔍 166p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **28.2** | 28.8 ± 1.43 | 5.0% | 31.9K | 35.7K | 0.33 | 30.8 | 31.2 | 28.0 | 31.3 | 100 |
| 74 ↻ | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2340-L2357) [🔍 97p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **3.17** | 3.22 ± 0.13 | 4.1% | 292K | 324K | 0.14 | 3.39 | 3.42 | 3.08 | 3.42 | 200 |
| 75 ↻ | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2360-L2402) [🔍 184p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **7.46** | 7.48 ± 0.13 | 1.7% | 130K | 136K | 0.07 | 7.65 | 7.69 | 7.36 | 7.70 | 200 |


### 3. Zig Full Suite Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `40c719e2b02d`, 5 samples across 1 run(s))

#### 3.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 10 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.zig#L882-L896) [🔍 21p](slices/16_array_list_radix_trie_iterator_scan.md) | **33** | 36 ± 5.4 | 15.1% | 22.2M | 31.3M | 2 | 43 | 45 | 32 | 45 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.zig#L1004-L1018) [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **60** | 61 ± 0.9 | 1.5% | 16.1M | 16.7M | 1 | 62 | 62 | 60 | 62 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.zig#L1206-L1219) [🔍 20p](slices/31_sorted_map_b_tree_ordered_scan.md) | **53** | 54 ± 2.4 | 4.4% | 17.2M | 19.2M | 2 | 57 | 58 | 52 | 58 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1721-L1752) [🔍 92p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **9** | 9 ± 0.9 | 9.5% | 90.9M | 111M | 0 | 11 | 11 | 9 | 11 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.zig#L1754-L1763) [🔍 12p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **39** | 39 ± 1.6 | 4.1% | 24.4M | 27.0M | 2 | 41 | 41 | 37 | 41 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1765-L1787) [🔍 76p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **8** | 8 ± 1.1 | 13.4% | 100M | 143M | 0 | 10 | 10 | 7 | 10 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.zig#L1789-L1798) [🔍 12p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **57** | 57 ± 1.1 | 2.0% | 17.2M | 18.2M | 1 | 58 | 58 | 55 | 58 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.zig#L1838-L1854) [🔍 14p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **83** | 83 ± 2.1 | 2.5% | 11.9M | 12.7M | 1 | 84 | 84 | 79 | 84 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.zig#L1856-L1871) [🔍 5p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **28** | 28 ± 0.4 | 1.6% | 34.5M | 35.7M | 0 | 29 | 29 | 28 | 29 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.zig#L1873-L1900) [🔍 54p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **30** | 34 ± 7.4 | 21.4% | 21.3M | 33.3M | 5 | 45 | 47 | 30 | 47 | 2K |

#### 3.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 16 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L513-L537) [🔍 81p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **798** | 807 ± 18.0 | 2.2% | 1.2M | 1.3M | 34 | 827 | 827 | 792 | 827 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.zig#L539-L555) [🔍 66p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **279** | 280 ± 2.3 | 0.8% | 3.5M | 3.6M | 4 | 283 | 283 | 278 | 283 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.zig#L557-L574) [🔍 58p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **191** | 191 ± 1.9 | 1.0% | 5.2M | 5.3M | 1 | 193 | 194 | 189 | 194 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.zig#L608-L630) [🔍 75p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **973** | 985 ± 18.7 | 1.9% | 985K | 1.0M | 19 | 1,010 | 1,014 | 972 | 1,015 | 1K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.zig#L632-L646) [🔍 20p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **148** | 148 ± 0.5 | 0.4% | 6.76M | 6.80M | 1 | 148 | 148 | 147 | 148 | 2K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.zig#L648-L670) [🔍 81p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **762** | 761 ± 13.6 | 1.8% | 1.28M | 1.34M | 20 | 777 | 779 | 747 | 779 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L672-L700) [🔍 88p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **802** | 806 ± 11.1 | 1.4% | 1.2M | 1.3M | 9 | 822 | 824 | 798 | 825 | 2K |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.zig#L786-L806) [🔍 77p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **538** | 538 ± 6.3 | 1.2% | 1.8M | 1.9M | 5 | 545 | 546 | 529 | 546 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.zig#L808-L824) [🔍 68p](slices/13_hamt_counted_hash_set_membership_check.md) | **277** | 281 ± 10.5 | 3.7% | 3.3M | 3.6M | 3 | 296 | 299 | 275 | 300 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.zig#L834-L863) [🔍 79p](slices/14_array_list_radix_trie_append.md) | **223** | 245 ± 42.0 | 17.1% | 3.2M | 4.8M | 37 | 302 | 311 | 210 | 313 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.zig#L865-L880) [🔍 49p](slices/15_array_list_radix_trie_random_get.md) | **138** | 144 ± 17.7 | 12.3% | 5.7M | 7.6M | 7 | 168 | 174 | 131 | 175 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.zig#L898-L918) [🔍 66p](slices/17_array_list_radix_trie_in_place_put.md) | **209** | 209 ± 14.2 | 6.8% | 4.3M | 5.2M | 12 | 227 | 229 | 192 | 230 | 2K |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.zig#L1656-L1686) [🔍 98p](slices/45_hasher_sha_1_20b_hamt_put.md) | **793** | 793 ± 6.2 | 0.8% | 1.2M | 1.3M | 4 | 801 | 803 | 787 | 803 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.zig#L1689-L1718) [🔍 101p](slices/46_hasher_sha_256_32b_hamt_put.md) | **826** | 825 ± 8.2 | 1.0% | 1.20M | 1.23M | 8 | 832 | 833 | 812 | 833 | 2K |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.zig#L1975-L2018) [🔍 117p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **259** | 259 ± 1.9 | 0.7% | 3.8M | 3.9M | 2 | 262 | 262 | 257 | 262 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.zig#L2265-L2279) [🔍 36p](slices/63_db_re_open_trailer_checksum_verify.md) | **249** | 249 ± 3.9 | 1.6% | 4.0M | 4.1M | 6 | 253 | 253 | 244 | 253 | 5K |

#### 3.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 37 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.zig#L576-L606) [🔍 83p](slices/04_hamt_cow_branched_moment_commits.md) | **2.40** | 2.45 ± 0.10 | 4.3% | 381K | 419K | 0.07 | 2.59 | 2.62 | 2.38 | 2.63 | 500 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.zig#L702-L721) [🔍 72p](slices/09_hamt_counted_hash_map_remove.md) | **1.02** | 1.02 ± 0.02 | 1.5% | 954K | 993K | 0.00 | 1.04 | 1.05 | 1.01 | 1.05 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.zig#L723-L761) [🔍 78p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **1.27** | 1.28 ± 0.02 | 1.6% | 762K | 791K | 0.02 | 1.31 | 1.31 | 1.26 | 1.31 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.zig#L763-L784) [🔍 72p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **2.82** | 2.83 ± 0.03 | 1.1% | 347K | 356K | 0.03 | 2.88 | 2.88 | 2.81 | 2.88 | 500 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.zig#L920-L933) [🔍 21p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **1.55** | 1.56 ± 0.07 | 4.3% | 605K | 667K | 0.11 | 1.64 | 1.65 | 1.50 | 1.65 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.zig#L935-L953) [🔍 65p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **1.53** | 1.54 ± 0.10 | 6.2% | 595K | 696K | 0.10 | 1.66 | 1.68 | 1.44 | 1.68 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.zig#L956-L985) [🔍 92p](slices/20_linked_array_list_b_tree_append.md) | **3.01** | 2.98 ± 0.10 | 3.2% | 324K | 350K | 0.14 | 3.08 | 3.08 | 2.86 | 3.08 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.zig#L987-L1002) [🔍 59p](slices/21_linked_array_list_b_tree_random_get.md) | **2.34** | 2.29 ± 0.11 | 5.0% | 411K | 462K | 0.16 | 2.41 | 2.43 | 2.16 | 2.43 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.zig#L1020-L1043) [🔍 81p](slices/23_linked_array_list_b_tree_middle_insert.md) | **3.56** | 3.83 ± 0.39 | 10.1% | 233K | 283K | 0.68 | 4.27 | 4.28 | 3.53 | 4.28 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.zig#L1045-L1066) [🔍 82p](slices/24_linked_array_list_b_tree_middle_remove.md) | **3.58** | 3.61 ± 0.08 | 2.2% | 267K | 283K | 0.01 | 3.71 | 3.74 | 3.54 | 3.74 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.zig#L1068-L1091) [🔍 87p](slices/25_linked_array_list_b_tree_concat_slice.md) | **36.3** | 36.5 ± 0.56 | 1.5% | 26.8K | 27.9K | 0.69 | 37.2 | 37.2 | 35.9 | 37.3 | 400 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.zig#L1093-L1112) [🔍 73p](slices/26_linked_array_list_b_tree_in_place_put.md) | **2.48** | 2.46 ± 0.11 | 4.3% | 387K | 435K | 0.06 | 2.57 | 2.58 | 2.30 | 2.59 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.zig#L1114-L1127) [🔍 21p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **3.53** | 3.48 ± 0.09 | 2.6% | 282K | 300K | 0.09 | 3.55 | 3.55 | 3.33 | 3.55 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.zig#L1136-L1174) [🔍 110p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **4.51** | 4.53 ± 0.06 | 1.3% | 216K | 223K | 0.04 | 4.61 | 4.62 | 4.48 | 4.63 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.zig#L1176-L1191) [🔍 80p](slices/29_sorted_map_b_tree_key_lookup.md) | **4.24** | 4.26 ± 0.04 | 1.0% | 231K | 236K | 0.03 | 4.32 | 4.33 | 4.23 | 4.33 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.zig#L1193-L1204) [🔍 20p](slices/30_sorted_map_b_tree_rank_query.md) | **4.21** | 4.26 ± 0.12 | 2.8% | 224K | 239K | 0.08 | 4.43 | 4.46 | 4.18 | 4.47 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.zig#L1221-L1235) [🔍 27p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **5.41** | 5.37 ± 0.11 | 2.1% | 183K | 193K | 0.03 | 5.46 | 5.47 | 5.18 | 5.47 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.zig#L1237-L1259) [🔍 82p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **5.97** | 5.96 ± 0.03 | 0.5% | 167K | 169K | 0.04 | 6.00 | 6.00 | 5.92 | 6.00 | 1K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.zig#L1261-L1273) [🔍 54p](slices/34_sorted_map_b_tree_get_index_select.md) | **3.28** | 3.28 ± 0.02 | 0.8% | 301K | 308K | 0.02 | 3.31 | 3.32 | 3.25 | 3.32 | 2K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.zig#L1275-L1289) [🔍 22p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **4.39** | 4.42 ± 0.08 | 1.8% | 219K | 229K | 0.03 | 4.53 | 4.56 | 4.36 | 4.56 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.zig#L1291-L1311) [🔍 93p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **4.76** | 4.80 ± 0.09 | 2.0% | 201K | 211K | 0.03 | 4.93 | 4.96 | 4.74 | 4.97 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.zig#L1313-L1336) [🔍 93p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **4.26** | 4.26 ± 0.02 | 0.4% | 234K | 236K | 0.03 | 4.28 | 4.28 | 4.24 | 4.28 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.zig#L1338-L1352) [🔍 79p](slices/38_sorted_set_b_tree_contains_lookup.md) | **3.95** | 3.95 ± 0.01 | 0.3% | 252K | 254K | 0.01 | 3.97 | 3.97 | 3.94 | 3.97 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.zig#L1388-L1411) [🔍 41p](slices/39_replication_genesis_200_moments.md) | **1.04** | 1.15 ± 0.26 | 22.3% | 657K | 1.1M | 0.33 | 1.48 | 1.51 | 0.91 | 1.52 | 200 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.zig#L1413-L1438) [🔍 92p](slices/40_replication_incremental_1_moment_delta.md) | **1.68** | 1.72 ± 0.07 | 4.1% | 548K | 599K | 0.09 | 1.81 | 1.82 | 1.67 | 1.82 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1440-L1458) [🔍 89p](slices/41_compaction_memory_offset_map_200_1.md) | **7.59** | 8.77 ± 2.77 | 31.6% | 74.9K | 160K | 1.69 | 12.5 | 13.2 | 6.23 | 13.4 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1460-L1514) [🔍 88p](slices/42_compaction_file_offset_map_200_1.md) | **13.7** | 14.5 ± 1.93 | 13.4% | 56.3K | 77.1K | 1.10 | 17.1 | 17.6 | 13.0 | 17.8 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.zig#L1516-L1603) [🔍 152p](slices/43_compaction_heterogeneous_dag_dedup.md) | **110.1** | 112.5 ± 8.85 | 7.9% | 8.0K | 9.6K | 12.3 | 123.6 | 124.9 | 104.2 | 125.2 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.zig#L1605-L1635) [🔍 42p](slices/44_replication_post_compaction_resync.md) | **1.74** | 1.74 ± 0.04 | 2.4% | 561K | 598K | 0.03 | 1.78 | 1.78 | 1.67 | 1.78 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.zig#L1801-L1836) [🔍 66p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **1.67** | 1.69 ± 0.06 | 3.3% | 560K | 609K | 0.03 | 1.77 | 1.78 | 1.64 | 1.79 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.zig#L1903-L1949) [🔍 61p](slices/55_path_4_level_nested_cursor_write_path.md) | **1.55** | 1.57 ± 0.04 | 2.4% | 618K | 654K | 0.05 | 1.61 | 1.62 | 1.53 | 1.62 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.zig#L1951-L1972) [🔍 41p](slices/56_path_4_level_nested_cursor_read_path.md) | **1.29** | 1.29 ± 0.01 | 0.8% | 765K | 779K | 0.01 | 1.31 | 1.31 | 1.28 | 1.31 | 500 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.zig#L2030-L2069) [🔍 100p](slices/58_backend_core_memory_commits.md) | **2.53** | 2.59 ± 0.16 | 6.0% | 348K | 397K | 0.01 | 2.80 | 2.86 | 2.52 | 2.87 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.zig#L2072-L2126) [🔍 101p](slices/59_backend_core_buffered_file_commits.md) | **18.6** | 18.7 ± 0.63 | 3.4% | 50.6K | 55.0K | 0.45 | 19.6 | 19.7 | 18.2 | 19.8 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.zig#L2129-L2178) [🔍 100p](slices/60_backend_core_file_unbuffered_commits.md) | **48.5** | 48.9 ± 0.97 | 2.0% | 19.9K | 20.8K | 1.34 | 50.2 | 50.3 | 48.1 | 50.3 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.zig#L2181-L2231) [🔍 95p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.96** | 1.97 ± 0.09 | 4.4% | 480K | 531K | 0.14 | 2.07 | 2.08 | 1.89 | 2.09 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.zig#L2233-L2263) [🔍 76p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **1.93** | 1.94 ± 0.03 | 1.6% | 502K | 523K | 0.02 | 1.98 | 1.99 | 1.91 | 1.99 | 500 |

### 4. 1v1 Statistical Comparison (Odin vs. Zig, Commit `40c719e2b02d`)

#### 4.1 Sub-100ns Fast Path (`ns`, 20 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L498-L514) ([Zig](bench_xitdb.zig#L539-L555) · [🔍 66p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md)) | **2.94x** | **95** | 279 | `12.1` ★ | 109 ± 31.4 | 28.8% | 152 | 280 ± 2.3 | 0.8% | 283 |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L516-L533) ([Zig](bench_xitdb.zig#L557-L574) · [🔍 58p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md)) | **3.18x** | **60** | 191 | `9.2` ★ | 77 ± 27.4 | 35.4% | 112 | 191 ± 1.9 | 1.0% | 193 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L596-L612) ([Zig](bench_xitdb.zig#L632-L646) · [🔍 20p](slices/06_hamt_hash_map_unordered_iterator_scan.md)) | **4.00x** | **37** | 148 | `247.8` ★ | 37 ± 0.8 | 2.3% | 38 | 148 ± 0.5 | 0.4% | 148 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L769-L785) ([Zig](bench_xitdb.zig#L808-L824) · [🔍 68p](slices/13_hamt_counted_hash_set_membership_check.md)) | **3.04x** | **91** | 277 | `40.0` ★ | 91 ± 1.5 | 1.7% | 93 | 281 ± 10.5 | 3.7% | 296 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L830-L845) ([Zig](bench_xitdb.zig#L865-L880) · [🔍 49p](slices/15_array_list_radix_trie_random_get.md)) | **3.00x** | **46** | 138 | `12.4` ★ | 46 ± 0.5 | 1.2% | 47 | 144 ± 17.7 | 12.3% | 168 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L847-L864) ([Zig](bench_xitdb.zig#L882-L896) · [🔍 21p](slices/16_array_list_radix_trie_iterator_scan.md)) | **2.54x** | **13** | 33 | `9.5` ★ | 13 ± 0.5 | 4.3% | 13 | 36 ± 5.4 | 15.1% | 43 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L866-L884) ([Zig](bench_xitdb.zig#L898-L918) · [🔍 66p](slices/17_array_list_radix_trie_in_place_put.md)) | **2.35x** | **89** | 209 | `18.7` ★ | 89 ± 1.1 | 1.3% | 91 | 209 ± 14.2 | 6.8% | 227 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L956-L971) ([Zig](bench_xitdb.zig#L987-L1002) · [🔍 59p](slices/21_linked_array_list_b_tree_random_get.md)) | **44.06x** | **53** | 2,335 | `43.9` ★ | 54 ± 0.9 | 1.7% | 55 | 2,292 ± 114 | 5.0% | 2,414 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L973-L990) ([Zig](bench_xitdb.zig#L1004-L1018) · [🔍 21p](slices/22_linked_array_list_b_tree_iterator_scan.md)) | **4.62x** | **13** | 60 | `100.6` ★ | 13 ± 0.5 | 4.1% | 14 | 61 ± 0.9 | 1.5% | 62 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1180-L1195) ([Zig](bench_xitdb.zig#L1206-L1219) · [🔍 20p](slices/31_sorted_map_b_tree_ordered_scan.md)) | **4.08x** | **13** | 53 | `38.6` ★ | 13 ± 0.0 | 0.0% | 13 | 54 ± 2.4 | 4.4% | 57 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1242-L1254) ([Zig](bench_xitdb.zig#L1261-L1273) · [🔍 54p](slices/34_sorted_map_b_tree_get_index_select.md)) | **51.25x** | **64** | 3,280 | `287.8` ★ | 65 ± 1.3 | 2.0% | 67 | 3,280 ± 24.9 | 0.8% | 3,312 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1602-L1627) ([Zig](bench_xitdb.zig#L1721-L1752) · [🔍 92p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md)) | **1.50x** | **6** | 9 | `8.5` ★ | 6 ± 0.0 | 0.0% | 6 | 9 ± 0.9 | 9.5% | 11 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1629-L1638) ([Zig](bench_xitdb.zig#L1754-L1763) · [🔍 12p](slices/48_bytes_external_bytes_read_bytes_buf.md)) | **4.33x** | **9** | 39 | `42.4` ★ | 9 ± 0.0 | 0.0% | 9 | 39 ± 1.6 | 4.1% | 41 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1640-L1656) ([Zig](bench_xitdb.zig#L1765-L1787) · [🔍 76p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md)) | **1.33x** | **6** | 8 | `4.5` ★ | 6 ± 0.0 | 0.0% | 6 | 8 ± 1.1 | 13.4% | 10 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1658-L1667) ([Zig](bench_xitdb.zig#L1789-L1798) · [🔍 12p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md)) | **6.33x** | **9** | 57 | `86.5` ★ | 9 ± 0.4 | 4.9% | 10 | 57 ± 1.1 | 2.0% | 58 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1709-L1725) ([Zig](bench_xitdb.zig#L1838-L1854) · [🔍 14p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md)) | **1.60x** | **52** | 83 | `29.7` ★ | 53 ± 0.9 | 1.7% | 54 | 83 ± 2.1 | 2.5% | 84 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1727-L1742) ([Zig](bench_xitdb.zig#L1856-L1871) · [🔍 5p](slices/53_stream_cursor_reader_random_seek_64b_read.md)) | **4.67x** | **6** | 28 | `48.7` ★ | 6 ± 0.9 | 14.0% | 8 | 28 ± 0.4 | 1.6% | 29 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1744-L1774) ([Zig](bench_xitdb.zig#L1873-L1900) · [🔍 54p](slices/54_stream_cursor_writer_random_seek_16b_patch.md)) | **2.31x** | **13** | 30 | `6.4` ★ | 13 ± 0.4 | 3.4% | 14 | 34 ± 7.4 | 21.4% | 45 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1856-L1889) ([Zig](bench_xitdb.zig#L1975-L2018) · [🔍 117p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md)) | **2.67x** | **97** | 259 | `127.9` ★ | 97 ± 2.1 | 2.1% | 100 | 259 ± 1.9 | 0.7% | 262 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2087-L2102) ([Zig](bench_xitdb.zig#L2265-L2279) · [🔍 36p](slices/63_db_re_open_trailer_checksum_verify.md)) | **4.45x** | **56** | 249 | `109.5` ★ | 56 ± 0.5 | 1.0% | 57 | 249 ± 3.9 | 1.6% | 253 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 35 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L471-L496) ([Zig](bench_xitdb.zig#L513-L537) · [🔍 81p](slices/01_hamt_hash_map_bulk_put_1_tx.md)) | **3.95x** | **202** | 798 | `14.4` ★ | 241 ± 86.3 | 35.9% | 357 | 807 ± 18.0 | 2.2% | 827 |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L535-L566) ([Zig](bench_xitdb.zig#L576-L606) · [🔍 83p](slices/04_hamt_cow_branched_moment_commits.md)) | **2.59x** | **923** | 2,395 | `9.0` ★ | 1,138 ± 307 | 27.0% | 1,479 | 2,450 ± 104 | 4.3% | 2,594 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L568-L594) ([Zig](bench_xitdb.zig#L608-L630) · [🔍 75p](slices/05_hamt_hash_map_remove_branch_shortening.md)) | **5.83x** | **167** | 973 | `72.5` ★ | 173 ± 16.6 | 9.6% | 195 | 985 ± 18.7 | 1.9% | 1,010 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L614-L637) ([Zig](bench_xitdb.zig#L648-L670) · [🔍 81p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md)) | **3.97x** | **192** | 762 | `58.3` ★ | 201 ± 16.6 | 8.3% | 224 | 761 ± 13.6 | 1.8% | 777 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L639-L663) ([Zig](bench_xitdb.zig#L672-L700) · [🔍 88p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md)) | **3.82x** | **210** | 802 | `51.9` ★ | 218 ± 22.8 | 10.4% | 249 | 806 ± 11.1 | 1.4% | 822 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L665-L683) ([Zig](bench_xitdb.zig#L702-L721) · [🔍 72p](slices/09_hamt_counted_hash_map_remove.md)) | **6.18x** | **165** | 1,019 | `98.1` ★ | 172 ± 11.7 | 6.8% | 187 | 1,022 ± 15.4 | 1.5% | 1,042 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L685-L725) ([Zig](bench_xitdb.zig#L723-L761) · [🔍 78p](slices/10_hamt_deep_suffix_collision_put_depth_10.md)) | **6.58x** | **193** | 1,269 | `75.6` ★ | 202 ± 24.8 | 12.3% | 235 | 1,279 ± 19.9 | 1.6% | 1,306 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L727-L747) ([Zig](bench_xitdb.zig#L763-L784) · [🔍 72p](slices/11_hamt_deep_suffix_collision_branch_collapse.md)) | **13.35x** | **211** | 2,816 | `186.8` ★ | 212 ± 3.8 | 1.8% | 217 | 2,833 ± 31.1 | 1.1% | 2,875 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L749-L767) ([Zig](bench_xitdb.zig#L786-L806) · [🔍 77p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md)) | **2.42x** | **222** | 538 | `20.2` ★ | 236 ± 32.9 | 13.9% | 280 | 538 ± 6.3 | 1.2% | 545 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L795-L828) ([Zig](bench_xitdb.zig#L834-L863) · [🔍 79p](slices/14_array_list_radix_trie_append.md)) | **2.06x** | **108** | 223 | `7.3` ★ | 109 ± 0.9 | 0.8% | 110 | 245 ± 42.0 | 17.1% | 302 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L886-L900) ([Zig](bench_xitdb.zig#L920-L933) · [🔍 21p](slices/18_array_list_radix_trie_index_seek_page_10.md)) | **4.45x** | **347** | 1,545 | `40.3` ★ | 349 ± 6.3 | 1.8% | 357 | 1,563 ± 67.0 | 4.3% | 1,644 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L902-L918) ([Zig](bench_xitdb.zig#L935-L953) · [🔍 65p](slices/19_array_list_radix_trie_depth_collapse_slice.md)) | **2.19x** | **701** | 1,532 | `19.5` ★ | 699 ± 8.6 | 1.2% | 709 | 1,536 ± 95.8 | 6.2% | 1,658 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) ([Zig](bench_xitdb.zig#L956-L985) · [🔍 92p](slices/20_linked_array_list_b_tree_append.md)) | **13.02x** | **231** | 3,007 | `64.2` ★ | 231 ± 4.5 | 1.9% | 236 | 2,977 ± 95.6 | 3.2% | 3,075 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L992-L1018) ([Zig](bench_xitdb.zig#L1020-L1043) · [🔍 81p](slices/23_linked_array_list_b_tree_middle_insert.md)) | **13.81x** | **258** | 3,562 | `20.6` ★ | 258 ± 2.9 | 1.1% | 262 | 3,834 ± 389 | 10.1% | 4,274 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1020-L1039) ([Zig](bench_xitdb.zig#L1045-L1066) · [🔍 82p](slices/24_linked_array_list_b_tree_middle_remove.md)) | **10.27x** | **349** | 3,584 | `91.7` ★ | 350 ± 6.4 | 1.8% | 358 | 3,607 ± 79.1 | 2.2% | 3,713 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1041-L1066) ([Zig](bench_xitdb.zig#L1068-L1091) · [🔍 87p](slices/25_linked_array_list_b_tree_concat_slice.md)) | **44.93x** | **807** | 36,262 | `142.9` ★ | 812 ± 13.1 | 1.6% | 826 | 36,471 ± 558 | 1.5% | 37,171 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1068-L1085) ([Zig](bench_xitdb.zig#L1093-L1112) · [🔍 73p](slices/26_linked_array_list_b_tree_in_place_put.md)) | **15.41x** | **161** | 2,481 | `48.7` ★ | 162 ± 1.9 | 1.2% | 164 | 2,456 ± 105 | 4.3% | 2,567 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1087-L1101) ([Zig](bench_xitdb.zig#L1114-L1127) · [🔍 21p](slices/27_linked_array_list_b_tree_index_seek_page_10.md)) | **8.95x** | **394** | 3,525 | `75.9` ★ | 395 ± 2.3 | 0.6% | 398 | 3,482 ± 90.9 | 2.6% | 3,549 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1110-L1148) ([Zig](bench_xitdb.zig#L1136-L1174) · [🔍 110p](slices/28_sorted_map_b_tree_out_of_order_put.md)) | **11.63x** | **388** | 4,511 | `156.5` ★ | 387 ± 1.7 | 0.4% | 388 | 4,526 ± 59.1 | 1.3% | 4,606 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1150-L1165) ([Zig](bench_xitdb.zig#L1176-L1191) · [🔍 80p](slices/29_sorted_map_b_tree_key_lookup.md)) | **26.02x** | **163** | 4,242 | `218.5` ★ | 163 ± 1.0 | 0.6% | 164 | 4,263 ± 41.9 | 1.0% | 4,320 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1167-L1178) ([Zig](bench_xitdb.zig#L1193-L1204) · [🔍 20p](slices/30_sorted_map_b_tree_rank_query.md)) | **32.10x** | **131** | 4,205 | `76.2` ★ | 131 ± 0.7 | 0.5% | 132 | 4,261 ± 121 | 2.8% | 4,429 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1197-L1212) ([Zig](bench_xitdb.zig#L1221-L1235) · [🔍 27p](slices/32_sorted_map_b_tree_lower_bound_page_10.md)) | **11.60x** | **466** | 5,407 | `99.2` ★ | 465 ± 1.5 | 0.3% | 467 | 5,369 ± 110 | 2.1% | 5,457 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1214-L1240) ([Zig](bench_xitdb.zig#L1237-L1259) · [🔍 82p](slices/33_sorted_map_b_tree_remove_rebalance.md)) | **25.94x** | **230** | 5,966 | `409.6` ★ | 231 ± 2.6 | 1.1% | 234 | 5,964 ± 31.2 | 0.5% | 5,997 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1256-L1271) ([Zig](bench_xitdb.zig#L1275-L1289) · [🔍 22p](slices/35_sorted_map_b_tree_index_seek_page_10.md)) | **10.94x** | **401** | 4,388 | `110.0` ★ | 401 ± 1.5 | 0.4% | 403 | 4,418 ± 81.7 | 1.8% | 4,530 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1273-L1291) ([Zig](bench_xitdb.zig#L1291-L1311) · [🔍 93p](slices/36_sorted_map_b_tree_in_place_overwrite.md)) | **13.14x** | **362** | 4,757 | `105.3` ★ | 362 ± 1.3 | 0.4% | 363 | 4,800 ± 94.2 | 2.0% | 4,930 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1293-L1314) ([Zig](bench_xitdb.zig#L1313-L1336) · [🔍 93p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md)) | **12.43x** | **343** | 4,265 | `473.6` ★ | 343 ± 2.0 | 0.6% | 345 | 4,264 ± 18.4 | 0.4% | 4,281 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1316-L1330) ([Zig](bench_xitdb.zig#L1338-L1352) · [🔍 79p](slices/38_sorted_set_b_tree_contains_lookup.md)) | **27.45x** | **144** | 3,953 | `709.3` ★ | 145 ± 0.9 | 0.6% | 146 | 3,952 ± 12.0 | 0.3% | 3,967 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1372-L1390) ([Zig](bench_xitdb.zig#L1388-L1411) · [🔍 41p](slices/39_replication_genesis_200_moments.md)) | **10.04x** | **104** | 1,044 | `9.1` ★ | 107 ± 11.2 | 10.5% | 122 | 1,149 ± 256 | 22.3% | 1,478 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1392-L1417) ([Zig](bench_xitdb.zig#L1413-L1438) · [🔍 92p](slices/40_replication_incremental_1_moment_delta.md)) | **2.25x** | **743** | 1,675 | `30.0` ★ | 752 ± 17.9 | 2.4% | 776 | 1,719 ± 69.9 | 4.1% | 1,811 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1578-L1599) ([Zig](bench_xitdb.zig#L1656-L1686) · [🔍 98p](slices/45_hasher_sha_1_20b_hamt_put.md)) | **3.56x** | **223** | 793 | `187.6` ★ | 223 ± 2.9 | 1.3% | 225 | 793 ± 6.2 | 0.8% | 801 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1578-L1599) ([Zig](bench_xitdb.zig#L1689-L1718) · [🔍 101p](slices/46_hasher_sha_256_32b_hamt_put.md)) | **3.55x** | **233** | 826 | `154.6` ★ | 233 ± 2.5 | 1.1% | 236 | 825 ± 8.2 | 1.0% | 832 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1670-L1707) ([Zig](bench_xitdb.zig#L1801-L1836) · [🔍 66p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md)) | **5.81x** | **288** | 1,674 | `55.3` ★ | 291 ± 9.9 | 3.4% | 305 | 1,693 ± 55.8 | 3.3% | 1,769 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1777-L1830) ([Zig](bench_xitdb.zig#L1903-L1949) · [🔍 61p](slices/55_path_4_level_nested_cursor_write_path.md)) | **6.73x** | **230** | 1,548 | `80.5` ★ | 231 ± 1.9 | 0.8% | 233 | 1,565 ± 37.0 | 2.4% | 1,612 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1832-L1853) ([Zig](bench_xitdb.zig#L1951-L1972) · [🔍 41p](slices/56_path_4_level_nested_cursor_read_path.md)) | **8.74x** | **148** | 1,293 | `242.2` ★ | 148 ± 4.2 | 2.8% | 152 | 1,293 ± 9.7 | 0.8% | 1,305 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2064-L2085) ([Zig](bench_xitdb.zig#L2233-L2263) · [🔍 76p](slices/62_tx_aborted_transaction_rollback_truncate.md)) | **2.78x** | **693** | 1,930 | `87.6` ★ | 693 ± 3.5 | 0.5% | 696 | 1,941 ± 31.7 | 1.6% | 1,984 |

#### 4.3 Multi-Microsecond Transactions & Compaction (`µs`, 8 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) ([Zig](bench_xitdb.zig#L1440-L1458) · [🔍 89p](slices/41_compaction_memory_offset_map_200_1.md)) | **2.05x** | **3.71** | 7.59 | `3.9` ★ | 3.89 ± 0.32 | 8.3% | 4.31 | 8.77 ± 2.77 | 31.6% | 12.5 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) ([Zig](bench_xitdb.zig#L1460-L1514) · [🔍 88p](slices/42_compaction_file_offset_map_200_1.md)) | **1.47x** | **9.35** | 13.7 | `5.6` ★ | 9.49 ± 0.48 | 5.1% | 10.1 | 14.5 ± 1.93 | 13.4% | 17.1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) ([Zig](bench_xitdb.zig#L1516-L1603) · [🔍 152p](slices/43_compaction_heterogeneous_dag_dedup.md)) | 0.87x | 126.6 | **110.1** | `3.2` ★ | 126.4 ± 4.40 | 3.5% | 131.9 | 112.5 ± 8.85 | 7.9% | 123.6 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) ([Zig](bench_xitdb.zig#L1605-L1635) · [🔍 42p](slices/44_replication_post_compaction_resync.md)) | **1.19x** | **1.46** | 1.74 | `11.0` ★ | 1.46 ± 0.04 | 2.5% | 1.51 | 1.74 ± 0.04 | 2.4% | 1.78 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1912-L1939) ([Zig](bench_xitdb.zig#L2030-L2069) · [🔍 100p](slices/58_backend_core_memory_commits.md)) | **2.08x** | **1.22** | 2.53 | `19.8` ★ | 1.22 ± 0.01 | 0.9% | 1.23 | 2.59 ± 0.16 | 6.0% | 2.80 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) ([Zig](bench_xitdb.zig#L2072-L2126) · [🔍 101p](slices/59_backend_core_buffered_file_commits.md)) | **4.06x** | **4.58** | 18.6 | `50.1` ★ | 4.58 ± 0.02 | 0.3% | 4.59 | 18.7 ± 0.63 | 3.4% | 19.6 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1984-L2018) ([Zig](bench_xitdb.zig#L2129-L2178) · [🔍 100p](slices/60_backend_core_file_unbuffered_commits.md)) | **1.10x** | **44.1** | 48.5 | `10.8` ★ | 44.1 ± 0.19 | 0.4% | 44.4 | 48.9 ± 0.97 | 2.0% | 50.2 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2021-L2062) ([Zig](bench_xitdb.zig#L2181-L2231) · [🔍 95p](slices/61_tx_mid_tx_database_freeze_cow_clone.md)) | **1.75x** | **1.12** | 1.96 | `21.8` ★ | 1.11 ± 0.01 | 0.8% | 1.12 | 1.97 ± 0.09 | 4.4% | 2.07 |

### 5. Database Storage Footprint (`bytes_used > 0`)

| # | Benchmark | Ops | Odin Size | Zig Size |
| ---: | :--- | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L471-L496) [🔍 81p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | 2K | 214.5 KB | 214.5 KB |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L535-L566) [🔍 83p](slices/04_hamt_cow_branched_moment_commits.md) | 500 | 457.7 KB | 457.7 KB |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L795-L828) [🔍 79p](slices/14_array_list_radix_trie_append.md) | 2K | 19.3 KB | 19.3 KB |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L921-L954) [🔍 92p](slices/20_linked_array_list_b_tree_append.md) | 2K | 45.3 KB | 45.3 KB |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1110-L1148) [🔍 110p](slices/28_sorted_map_b_tree_out_of_order_put.md) | 2K | 115.4 KB | 115.4 KB |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1293-L1314) [🔍 93p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | 2K | 80.0 KB | 80.0 KB |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1372-L1390) [🔍 41p](slices/39_replication_genesis_200_moments.md) | 200 | 250.9 KB | 250.9 KB |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1392-L1417) [🔍 92p](slices/40_replication_incremental_1_moment_delta.md) | 100 | 132.7 KB | 132.7 KB |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1419-L1437) [🔍 89p](slices/41_compaction_memory_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1439-L1460) [🔍 88p](slices/42_compaction_file_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1462-L1521) [🔍 152p](slices/43_compaction_heterogeneous_dag_dedup.md) | 1 | 23.4 KB | 23.4 KB |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1523-L1548) [🔍 42p](slices/44_replication_post_compaction_resync.md) | 1 | 23.4 KB | 23.4 KB |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 98p](slices/45_hasher_sha_1_20b_hamt_put.md) | 2K | 224.7 KB | 224.7 KB |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1578-L1599) [🔍 101p](slices/46_hasher_sha_256_32b_hamt_put.md) | 2K | 248.7 KB | 248.7 KB |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1670-L1707) [🔍 66p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | 256 | 1024.1 KB | 1024.1 KB |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1912-L1939) [🔍 100p](slices/58_backend_core_memory_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1942-L1981) [🔍 101p](slices/59_backend_core_buffered_file_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L1984-L2018) [🔍 100p](slices/60_backend_core_file_unbuffered_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2128-L2163) [🔍 98p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | 500 | 231.4 KB | — |
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
