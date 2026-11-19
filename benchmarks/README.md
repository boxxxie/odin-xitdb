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
### 1. Latest Code-Change Impact & Affected Benchmarks (`32cdc130a8b9` → `8332eda00de6`, Odin, 75 / 75 tests re-run)

- **Code Diff Inspected:** `bab4850~1..bab4850` · **Changed Files:** `xitdb/dsl.odin`
- **Modified Procedures:** `_diff_recursive`, `_eval_pull_spec`, `_push_step_buf`, `history_of`, `parse_selector_buf`, `parse_selector`, `parse_steps_buf`, `parse_steps`, `precompute_step_hashes`, `read_prehashed_steps_cursor`, `read_prehashed_steps_slot`, `select_cursor`, `selector_destroy_buf`, `steps_destroy_buf`, `unmarshal_into`
- **Mapped Benchmark Scope:** Odin groups=`dsl` (**75 / 75** Odin benchmarks executed; **0** unchanged benchmarks retained from `32cdc13`)

#### 1.1 Sub-100ns Fast Path (`ns`, 20 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `32cdc13` (`ns`) | Curr `8332eda` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L544-L560) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **FASTER** | `-43.0%` | 1.76x | 155 | **88** | `22.2` | 154 ± 2.3 | 91 ± 6.9 |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L562-L579) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **FASTER** | `-42.1%` | 1.74x | 92 | **53** | `41.6` | 92 ± 1.7 | 54 ± 1.3 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L642-L658) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **FASTER** | `-40.3%` | 1.65x | 56 | **34** | `42.6` | 57 ± 1.0 | 34 ± 0.8 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L815-L831) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **FASTER** | `-40.1%` | 1.66x | 148 | **89** | `74.0` | 148 ± 1.5 | 89 ± 1.1 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L876-L891) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **FASTER** | `-40.6%` | 1.70x | 73 | **43** | `44.0` | 74 ± 1.5 | 43 ± 0.5 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L893-L910) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **FASTER** | `-40.0%` | 1.58x | 19 | **12** | `145.0` | 19 ± 0.1 | 12 ± 0.1 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L912-L930) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **FASTER** | `-37.1%` | 1.58x | 141 | **89** | `71.6` | 141 ± 1.4 | 89 ± 1.0 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1002-L1017) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **FASTER** | `-40.5%` | 1.67x | 87 | **52** | `39.1` | 88 ± 2.0 | 52 ± 0.6 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1019-L1036) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **FASTER** | `-40.5%` | 1.75x | 21 | **12** | `144.0` | 21 ± 0.1 | 12 ± 0.1 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1226-L1241) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **FASTER** | `-40.1%` | 1.67x | 20 | **12** | `77.9` | 20 ± 0.2 | 12 ± 0.1 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1288-L1300) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **FASTER** | `-37.9%` | 1.61x | 113 | **70** | `63.9` | 114 ± 1.5 | 70 ± 0.5 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1648-L1673) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | `~NOISE` | `-40.9%` | 1.83x | 11 | **6** | `14.2` | 11 ± 0.7 | 6 ± 0.0 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1675-L1684) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **FASTER** | `-41.7%` | 1.73x | 19 | **11** | `57.3` | 19 ± 0.2 | 11 ± 0.2 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1686-L1702) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | `~NOISE` | `-40.6%` | 1.57x | 11 | **7** | `429.2` | 11 ± 0.0 | 7 ± 0.0 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1704-L1713) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **FASTER** | `-40.6%` | 1.73x | 19 | **11** | `12.7` | 20 ± 1.5 | 11 ± 0.2 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1755-L1771) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **FASTER** | `-43.0%` | 1.75x | 93 | **53** | `71.1` | 93 ± 0.9 | 54 ± 1.0 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1773-L1788) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | `~NOISE` | `-40.0%` | 1.75x | 7 | **4** | `42.7` | 7 ± 0.1 | 4 ± 0.0 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1790-L1820) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **FASTER** | `-39.8%` | 1.65x | 38 | **23** | `10.3` | 38 ± 1.3 | 24 ± 3.3 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1902-L1935) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **FASTER** | `-41.9%` | 1.73x | 157 | **91** | `29.4` | 156 ± 2.7 | 93 ± 4.8 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2133-L2148) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **FASTER** | `-41.4%` | 1.70x | 102 | **60** | `37.1` | 103 ± 2.3 | 59 ± 1.5 |

#### 1.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 32 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `32cdc13` (`ns`) | Curr `8332eda` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **FASTER** | `-39.6%` | 1.65x | 324 | **196** | `66.9` | 324 ± 4.0 | 196 ± 1.9 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L614-L640) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **FASTER** | `-37.8%` | 1.61x | 273 | **170** | `4.0` | 313 ± 81.0 | 168 ± 4.6 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L660-L683) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **FASTER** | `-43.2%` | 1.76x | 341 | **194** | `8.5` | 341 ± 4.9 | 209 ± 40.6 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L685-L709) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **FASTER** | `-39.9%` | 1.67x | 330 | **198** | `4.8` | 330 ± 1.8 | 221 ± 60.1 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L711-L729) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **FASTER** | `-42.0%` | 1.73x | 290 | **168** | `5.5` | 293 ± 9.0 | 185 ± 51.0 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L731-L771) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **FASTER** | `-41.1%` | 1.69x | 322 | **190** | `5.6` | 323 ± 6.7 | 209 ± 52.9 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L773-L793) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **FASTER** | `-42.5%` | 1.74x | 344 | **198** | `7.8` | 347 ± 4.8 | 215 ± 44.5 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L795-L813) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **FASTER** | `-39.3%` | 1.65x | 351 | **213** | `47.7` | 353 ± 4.5 | 211 ± 5.8 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **FASTER** | `-39.7%` | 1.65x | 172 | **104** | `51.2` | 172 ± 2.3 | 104 ± 2.3 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L932-L946) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **FASTER** | `-39.3%` | 1.65x | 567 | **344** | `97.1` | 566 ± 4.0 | 343 ± 3.8 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L948-L964) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **FASTER** | `-43.2%` | 1.76x | 1,294 | **735** | `28.9` | 1,311 ± 44.3 | 732 ± 7.6 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **FASTER** | `-40.3%` | 1.67x | 378 | **226** | `10.2` | 392 ± 36.3 | 226 ± 2.2 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1038-L1064) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **FASTER** | `-40.3%` | 1.68x | 421 | **251** | `27.1` | 429 ± 14.0 | 251 ± 5.0 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1066-L1085) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **FASTER** | `-40.6%` | 1.68x | 534 | **317** | `59.7` | 535 ± 7.2 | 318 ± 4.6 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1114-L1131) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **FASTER** | `-39.7%` | 1.66x | 263 | **158** | `35.8` | 264 ± 6.1 | 157 ± 3.0 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1133-L1147) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **FASTER** | `-40.9%` | 1.69x | 618 | **365** | `161.9` | 618 ± 0.8 | 365 ± 4.0 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **FASTER** | `-39.8%` | 1.66x | 618 | **372** | `165.6` | 618 ± 2.3 | 373 ± 2.8 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1196-L1211) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **FASTER** | `-40.1%` | 1.67x | 276 | **165** | `63.9` | 276 ± 2.4 | 166 ± 3.5 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1213-L1224) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **FASTER** | `-39.4%` | 1.65x | 226 | **137** | `86.7` | 227 ± 2.0 | 137 ± 1.3 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1243-L1258) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **FASTER** | `-38.7%` | 1.63x | 751 | **460** | `95.3` | 753 ± 5.9 | 460 ± 4.1 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1260-L1286) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **FASTER** | `-39.7%` | 1.66x | 384 | **232** | `89.4` | 383 ± 3.2 | 232 ± 2.3 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1302-L1317) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **FASTER** | `-40.4%` | 1.67x | 561 | **335** | `167.0` | 561 ± 0.5 | 334 ± 3.6 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1319-L1337) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **FASTER** | `-40.6%` | 1.68x | 583 | **346** | `86.6` | 586 ± 5.9 | 346 ± 2.4 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **FASTER** | `-42.5%` | 1.74x | 570 | **328** | `159.9` | 570 ± 1.4 | 328 ± 3.6 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1362-L1376) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **FASTER** | `-39.1%` | 1.64x | 259 | **158** | `112.6` | 258 ± 1.3 | 158 ± 1.8 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **FASTER** | `-42.3%` | 1.73x | 761 | **439** | `32.1` | 762 ± 17.9 | 447 ± 15.1 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **FASTER** | `-36.9%` | 1.58x | 328 | **207** | `79.9` | 327 ± 3.1 | 207 ± 1.6 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **FASTER** | `-38.7%` | 1.64x | 350 | **214** | `43.0` | 351 ± 6.2 | 215 ± 3.9 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1823-L1876) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **FASTER** | `-44.3%` | 1.79x | 391 | **218** | `72.2` | 390 ± 2.8 | 220 ± 5.3 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1878-L1899) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **FASTER** | `-42.0%` | 1.73x | 256 | **148** | `29.3` | 256 ± 8.0 | 148 ± 2.4 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2110-L2131) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **FASTER** | `-44.5%` | 1.80x | 1,069 | **593** | `71.5` | 1,068 ± 7.8 | 601 ± 14.7 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2215-L2227) [🔍 84p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **FASTER** | `-41.7%` | 1.72x | 1,042 | **607** | `59.9` | 1,045 ± 12.8 | 609 ± 11.9 |

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 23 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `32cdc13` (`µs`) | Curr `8332eda` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **FASTER** | `-41.8%` | 1.72x | 1.79 | **1.04** | `141.5` | 1.79 ± 0.01 | 1.05 ± 0.01 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1087-L1112) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **FASTER** | `-42.3%` | 1.73x | 1.83 | **1.06** | `28.8` | 1.86 ± 0.06 | 1.06 ± 0.01 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **FASTER** | `-41.6%` | 1.71x | 1.80 | **1.05** | `39.3` | 1.82 ± 0.04 | 1.05 ± 0.01 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **FASTER** | `-35.9%` | 1.56x | 9.41 | **6.03** | `2.6` | 9.39 ± 0.23 | 7.26 ± 2.13 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **FASTER** | `-43.7%` | 1.77x | 23.0 | **13.0** | `6.5` | 25.6 ± 4.05 | 13.4 ± 1.30 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **FASTER** | `-46.0%` | 1.85x | 74.6 | **40.3** | `18.7` | 74.6 ± 3.53 | 41.2 ± 2.22 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **FASTER** | `-42.0%` | 1.73x | 2.33 | **1.35** | `5.8` | 2.34 ± 0.02 | 1.49 ± 0.39 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **FASTER** | `-40.6%` | 1.68x | 2.32 | **1.38** | `101.6` | 2.32 ± 0.01 | 1.37 ± 0.02 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) [🔍 112p](slices/58_backend_core_memory_commits.md) | **FASTER** | `-42.7%` | 1.75x | 1.90 | **1.09** | `66.5` | 1.90 ± 0.02 | 1.10 ± 0.02 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **FASTER** | `-41.9%` | 1.72x | 24.7 | **14.4** | `17.0` | 25.2 ± 1.41 | 14.4 ± 0.27 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **FASTER** | `-41.7%` | 1.72x | 71.2 | **41.5** | `15.6` | 73.0 ± 4.53 | 41.4 ± 0.48 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2067-L2108) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **FASTER** | `-42.5%` | 1.74x | 1.93 | **1.11** | `45.4` | 1.92 ± 0.03 | 1.11 ± 0.03 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2176-L2211) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **FASTER** | `-42.0%` | 1.72x | 7.23 | **4.20** | `52.4` | 7.29 ± 0.12 | 4.21 ± 0.07 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2231-L2267) [🔍 180p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **FASTER** | `-40.6%` | 1.68x | 6.50 | **3.86** | `15.1` | 6.49 ± 0.03 | 4.03 ± 0.43 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2269-L2279) [🔍 152p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **FASTER** | `-40.3%` | 1.68x | 3.17 | **1.89** | `51.7` | 3.16 ± 0.03 | 1.92 ± 0.06 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2281-L2291) [🔍 111p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **FASTER** | `-41.2%` | 1.70x | 2.88 | **1.69** | `68.3` | 2.88 ± 0.02 | 1.70 ± 0.04 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2296-L2313) [🔍 155p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **FASTER** | `-40.2%` | 1.67x | 387.6 | **231.8** | `48.8` | 390.4 ± 7.01 | 232.4 ± 2.10 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2315-L2324) [🔍 91p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **FASTER** | `-39.8%` | 1.66x | 2.63 | **1.58** | `39.5` | 2.62 ± 0.04 | 1.57 ± 0.05 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2328-L2348) [🔍 135p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **FASTER** | `-39.9%` | 1.66x | 25.4 | **15.3** | `96.7` | 25.4 ± 0.09 | 15.4 ± 0.25 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2351-L2366) [🔍 135p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **FASTER** | `-30.4%` | 1.44x | 948.6 | **660.2** | `18.3` | 965.4 ± 34.6 | 666.7 ± 13.6 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2369-L2384) [🔍 135p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **FASTER** | `-41.0%` | 1.69x | 48.7 | **28.7** | `15.3` | 49.8 ± 3.04 | 28.7 ± 0.46 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2388-L2405) [🔍 111p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **FASTER** | `-40.7%` | 1.69x | 5.19 | **3.08** | `21.5` | 5.30 ± 0.23 | 3.08 ± 0.03 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2408-L2450) [🔍 199p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **FASTER** | `-40.9%` | 1.69x | 10.9 | **6.46** | `57.1` | 11.0 ± 0.17 | 6.48 ± 0.06 |


### 2. Odin Full Suite Results (`-o:speed -microarch:native`, Commit `8332eda00de6`, 7 samples across 1 run(s))

#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 20 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L544-L560) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **88** | 91 ± 6.9 | 7.7% | 9.4M | 11.5M | 0 | 101 | 105 | 87 | 106 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L562-L579) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **53** | 54 ± 1.3 | 2.5% | 17.9M | 18.9M | 1 | 56 | 56 | 53 | 56 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L642-L658) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **34** | 34 ± 0.8 | 2.5% | 27.8M | 29.4M | 0 | 35 | 36 | 34 | 36 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L815-L831) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **89** | 89 ± 1.1 | 1.3% | 11.1M | 11.5M | 1 | 90 | 90 | 87 | 90 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L876-L891) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **43** | 43 ± 0.5 | 1.2% | 22.7M | 23.8M | 0 | 44 | 44 | 42 | 44 | 2K |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L893-L910) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **12** | 12 ± 0.1 | 0.7% | 83.3M | 90.9M | 0 | 12 | 12 | 11 | 12 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L912-L930) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **89** | 89 ± 1.0 | 1.1% | 11.1M | 11.4M | 2 | 90 | 90 | 88 | 90 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1002-L1017) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **52** | 52 ± 0.6 | 1.2% | 19.2M | 19.6M | 1 | 52 | 52 | 51 | 52 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1019-L1036) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **12** | 12 ± 0.1 | 0.5% | 83.3M | 83.3M | 0 | 12 | 12 | 12 | 12 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1226-L1241) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **12** | 12 ± 0.1 | 0.8% | 83.3M | 83.3M | 0 | 12 | 12 | 12 | 12 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1288-L1300) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **70** | 70 ± 0.5 | 0.7% | 14.1M | 14.3M | 1 | 71 | 71 | 70 | 71 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1648-L1673) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **6** | 6 ± 0.0 | 0.5% | 167M | 167M | 0 | 6 | 6 | 6 | 6 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1675-L1684) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **11** | 11 ± 0.2 | 1.8% | 90.9M | 90.9M | 0 | 11 | 11 | 11 | 11 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1686-L1702) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **7** | 7 ± 0.0 | 0.4% | 143M | 143M | 0 | 7 | 7 | 7 | 7 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1704-L1713) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **11** | 11 ± 0.2 | 1.7% | 83.3M | 90.9M | 0 | 12 | 12 | 11 | 12 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1755-L1771) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **53** | 54 ± 1.0 | 1.8% | 18.2M | 19.2M | 1 | 55 | 55 | 52 | 55 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1773-L1788) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **4** | 4 ± 0.0 | 1.1% | 250M | 250M | 0 | 4 | 4 | 4 | 4 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1790-L1820) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **23** | 24 ± 3.3 | 13.5% | 32.3M | 45.5M | 3 | 29 | 30 | 22 | 31 | 2K |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1902-L1935) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **91** | 93 ± 4.8 | 5.1% | 9.7M | 11.2M | 3 | 100 | 102 | 89 | 103 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2133-L2148) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **60** | 59 ± 1.5 | 2.5% | 16.4M | 17.5M | 2 | 61 | 61 | 57 | 61 | 5K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 32 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **196** | 196 ± 1.9 | 0.9% | 5.0M | 5.2M | 2 | 198 | 199 | 194 | 199 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L614-L640) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **170** | 168 ± 4.6 | 2.7% | 5.8M | 6.2M | 6 | 172 | 173 | 161 | 173 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L660-L683) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **194** | 209 ± 40.6 | 19.4% | 3.3M | 5.2M | 2 | 270 | 295 | 193 | 301 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L685-L709) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **198** | 221 ± 60.1 | 27.2% | 2.8M | 5.1M | 2 | 310 | 347 | 195 | 357 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L711-L729) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **168** | 185 ± 51.0 | 27.6% | 3.3M | 6.2M | 4 | 261 | 293 | 161 | 300 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L731-L771) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **190** | 209 ± 52.9 | 25.3% | 3.0M | 5.5M | 7 | 290 | 320 | 181 | 328 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L773-L793) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **198** | 215 ± 44.5 | 20.7% | 3.2M | 5.1M | 6 | 283 | 309 | 196 | 316 | 500 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L795-L813) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **213** | 211 ± 5.8 | 2.7% | 4.6M | 4.9M | 7 | 218 | 219 | 203 | 219 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **104** | 104 ± 2.3 | 2.2% | 9.3M | 9.9M | 2 | 107 | 108 | 101 | 108 | 2K |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L932-L946) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **344** | 343 ± 3.8 | 1.1% | 2.9M | 3.0M | 4 | 346 | 346 | 336 | 347 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L948-L964) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **735** | 732 ± 7.6 | 1.0% | 1.3M | 1.4M | 7 | 741 | 742 | 721 | 743 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **226** | 226 ± 2.2 | 1.0% | 4.4M | 4.5M | 3 | 229 | 229 | 223 | 229 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1038-L1064) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **251** | 251 ± 5.0 | 2.0% | 3.8M | 4.1M | 4 | 259 | 261 | 246 | 261 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1066-L1085) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **317** | 318 ± 4.6 | 1.4% | 3.1M | 3.2M | 2 | 324 | 327 | 313 | 327 | 500 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1114-L1131) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **158** | 157 ± 3.0 | 1.9% | 6.3M | 6.5M | 4 | 160 | 160 | 153 | 160 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1133-L1147) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **365** | 365 ± 4.0 | 1.1% | 2.7M | 2.8M | 5 | 369 | 369 | 358 | 369 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **372** | 373 ± 2.8 | 0.8% | 2.65M | 2.71M | 3 | 376 | 377 | 369 | 377 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1196-L1211) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **165** | 166 ± 3.5 | 2.1% | 5.8M | 6.2M | 3 | 172 | 173 | 162 | 173 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1213-L1224) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **137** | 137 ± 1.3 | 1.0% | 7.2M | 7.4M | 2 | 139 | 139 | 135 | 139 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1243-L1258) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **460** | 460 ± 4.1 | 0.9% | 2.1M | 2.2M | 4 | 465 | 466 | 453 | 466 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1260-L1286) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **232** | 232 ± 2.3 | 1.0% | 4.2M | 4.3M | 3 | 236 | 236 | 230 | 236 | 1K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1302-L1317) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **335** | 334 ± 3.6 | 1.1% | 3.0M | 3.1M | 4 | 337 | 338 | 327 | 338 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1319-L1337) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **346** | 346 ± 2.4 | 0.7% | 2.86M | 2.91M | 3 | 349 | 350 | 344 | 350 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **328** | 328 ± 3.6 | 1.1% | 3.0M | 3.1M | 4 | 332 | 333 | 322 | 333 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1362-L1376) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **158** | 158 ± 1.8 | 1.1% | 6.3M | 6.5M | 2 | 160 | 160 | 155 | 160 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **439** | 447 ± 15.1 | 3.4% | 2.1M | 2.3M | 16 | 470 | 471 | 436 | 471 | 200 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **207** | 207 ± 1.6 | 0.8% | 4.8M | 4.9M | 3 | 209 | 209 | 205 | 209 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **214** | 215 ± 3.9 | 1.8% | 4.5M | 4.8M | 5 | 220 | 221 | 209 | 221 | 2K |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1823-L1876) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **218** | 220 ± 5.3 | 2.4% | 4.4M | 4.7M | 6 | 228 | 228 | 215 | 229 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1878-L1899) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **148** | 148 ± 2.4 | 1.6% | 6.6M | 6.9M | 3 | 151 | 151 | 144 | 151 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2110-L2131) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **593** | 601 ± 14.7 | 2.4% | 1.6M | 1.7M | 22 | 620 | 622 | 585 | 623 | 500 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2215-L2227) [🔍 84p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **607** | 609 ± 11.9 | 2.0% | 1.6M | 1.7M | 7 | 627 | 632 | 598 | 634 | 500 |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 23 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **1.04** | 1.05 ± 0.01 | 1.0% | 942K | 970K | 0.01 | 1.06 | 1.06 | 1.03 | 1.06 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1087-L1112) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **1.06** | 1.06 ± 0.01 | 1.1% | 924K | 955K | 0.01 | 1.08 | 1.08 | 1.05 | 1.08 | 400 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **1.05** | 1.05 ± 0.01 | 1.0% | 939K | 967K | 0.01 | 1.06 | 1.07 | 1.03 | 1.07 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **6.03** | 7.26 ± 2.13 | 29.3% | 95.3K | 198K | 2.71 | 10.3 | 10.5 | 5.06 | 10.5 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **13.0** | 13.4 ± 1.30 | 9.7% | 62.3K | 81.5K | 0.96 | 15.4 | 15.9 | 12.3 | 16.1 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **40.3** | 41.2 ± 2.22 | 5.4% | 21.8K | 25.3K | 1.44 | 44.7 | 45.6 | 39.5 | 45.9 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **1.35** | 1.49 ± 0.39 | 26.4% | 421K | 762K | 0.04 | 2.07 | 2.31 | 1.31 | 2.38 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **1.38** | 1.37 ± 0.02 | 1.3% | 716K | 746K | 0.02 | 1.39 | 1.40 | 1.34 | 1.40 | 256 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) [🔍 112p](slices/58_backend_core_memory_commits.md) | **1.09** | 1.10 ± 0.02 | 2.1% | 888K | 932K | 0.04 | 1.13 | 1.13 | 1.07 | 1.13 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **14.4** | 14.4 ± 0.27 | 1.9% | 67.5K | 71.0K | 0.39 | 14.8 | 14.8 | 14.1 | 14.8 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **41.5** | 41.4 ± 0.48 | 1.2% | 23.7K | 24.5K | 0.66 | 42.1 | 42.2 | 40.9 | 42.2 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2067-L2108) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.11** | 1.11 ± 0.03 | 3.1% | 854K | 925K | 0.05 | 1.16 | 1.17 | 1.08 | 1.17 | 500 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2176-L2211) [🔍 112p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **4.20** | 4.21 ± 0.07 | 1.8% | 229K | 243K | 0.03 | 4.32 | 4.36 | 4.12 | 4.36 | 500 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2231-L2267) [🔍 180p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **3.86** | 4.03 ± 0.43 | 10.7% | 200K | 263K | 0.11 | 4.69 | 4.93 | 3.80 | 4.99 | 200 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2269-L2279) [🔍 152p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **1.89** | 1.92 ± 0.06 | 2.9% | 495K | 534K | 0.06 | 2.00 | 2.02 | 1.87 | 2.02 | 200 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2281-L2291) [🔍 111p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **1.69** | 1.70 ± 0.04 | 2.4% | 560K | 599K | 0.04 | 1.77 | 1.78 | 1.67 | 1.79 | 200 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2296-L2313) [🔍 155p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **231.8** | 232.4 ± 2.10 | 0.9% | 4.2K | 4.3K | 3.03 | 235.2 | 235.3 | 230.0 | 235.4 | 200 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2315-L2324) [🔍 91p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **1.58** | 1.57 ± 0.05 | 3.5% | 610K | 680K | 0.05 | 1.63 | 1.64 | 1.47 | 1.64 | 200 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2328-L2348) [🔍 135p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **15.3** | 15.4 ± 0.25 | 1.7% | 63.1K | 66.2K | 0.24 | 15.8 | 15.8 | 15.1 | 15.8 | 100 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2351-L2366) [🔍 135p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **660.2** | 666.7 ± 13.6 | 2.0% | 1.4K | 1.5K | 9.21 | 688.6 | 693.6 | 658.3 | 694.8 | 25 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2369-L2384) [🔍 135p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **28.7** | 28.7 ± 0.46 | 1.6% | 34.0K | 35.5K | 0.54 | 29.3 | 29.4 | 28.1 | 29.4 | 100 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2388-L2405) [🔍 111p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **3.08** | 3.08 ± 0.03 | 1.1% | 319K | 329K | 0.06 | 3.12 | 3.13 | 3.04 | 3.13 | 200 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2408-L2450) [🔍 199p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **6.46** | 6.48 ± 0.06 | 1.0% | 151K | 156K | 0.04 | 6.58 | 6.61 | 6.42 | 6.62 | 200 |


### 3. Zig Full Suite Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `8332eda00de6`, 7 samples across 1 run(s))

#### 3.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 10 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.zig#L882-L896) [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md) | **29** | 29 ± 0.7 | 2.4% | 33.3M | 35.7M | 1 | 30 | 30 | 28 | 30 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.zig#L1004-L1018) [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **55** | 56 ± 1.4 | 2.5% | 17.2M | 18.5M | 1 | 58 | 58 | 54 | 58 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.zig#L1206-L1219) [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md) | **48** | 47 ± 1.6 | 3.5% | 20.4M | 22.2M | 3 | 49 | 49 | 45 | 49 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1721-L1752) [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **8** | 8 ± 0.0 | 0.0% | 125M | 125M | 0 | 8 | 8 | 8 | 8 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.zig#L1754-L1763) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **34** | 34 ± 0.4 | 1.1% | 29.4M | 30.3M | 0 | 34 | 34 | 33 | 34 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1765-L1787) [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **7** | 7 ± 0.0 | 0.0% | 143M | 143M | 0 | 7 | 7 | 7 | 7 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.zig#L1789-L1798) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **47** | 47 ± 0.7 | 1.5% | 20.8M | 21.7M | 1 | 48 | 48 | 46 | 48 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.zig#L1838-L1854) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **71** | 70 ± 1.5 | 2.1% | 13.9M | 14.7M | 2 | 72 | 72 | 68 | 72 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.zig#L1856-L1871) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **27** | 27 ± 0.8 | 2.8% | 34.5M | 37.0M | 0 | 28 | 29 | 27 | 29 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.zig#L1873-L1900) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **26** | 26 ± 1.5 | 5.7% | 34.5M | 40.0M | 2 | 29 | 29 | 25 | 29 | 2K |

#### 3.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 20 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L513-L537) [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **758** | 761 ± 18.9 | 2.5% | 1.3M | 1.4M | 23 | 788 | 794 | 740 | 795 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.zig#L539-L555) [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **262** | 261 ± 3.7 | 1.4% | 3.8M | 4.0M | 2 | 264 | 265 | 253 | 265 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.zig#L557-L574) [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **180** | 182 ± 9.0 | 5.0% | 5.0M | 5.8M | 7 | 195 | 199 | 173 | 200 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.zig#L608-L630) [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **942** | 942 ± 6.1 | 0.7% | 1.05M | 1.07M | 8 | 949 | 949 | 932 | 949 | 1K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.zig#L632-L646) [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **139** | 139 ± 2.4 | 1.7% | 6.9M | 7.3M | 2 | 143 | 144 | 137 | 144 | 2K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.zig#L648-L670) [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **705** | 706 ± 5.5 | 0.8% | 1.40M | 1.43M | 7 | 713 | 714 | 698 | 714 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L672-L700) [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **762** | 763 ± 8.6 | 1.1% | 1.29M | 1.33M | 7 | 775 | 777 | 750 | 778 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.zig#L702-L721) [🔍 83p](slices/09_hamt_counted_hash_map_remove.md) | **976** | 972 ± 12.5 | 1.3% | 1.0M | 1.1M | 13 | 985 | 986 | 950 | 986 | 1K |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.zig#L786-L806) [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **498** | 501 ± 6.1 | 1.2% | 1.97M | 2.03M | 9 | 508 | 508 | 492 | 508 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.zig#L808-L824) [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md) | **262** | 261 ± 6.8 | 2.6% | 3.7M | 4.0M | 13 | 268 | 268 | 253 | 268 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.zig#L834-L863) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **196** | 212 ± 43.5 | 20.6% | 3.2M | 5.3M | 7 | 278 | 304 | 189 | 310 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.zig#L865-L880) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **121** | 132 ± 31.2 | 23.7% | 5.0M | 8.5M | 5 | 179 | 197 | 117 | 202 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.zig#L898-L918) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **182** | 184 ± 8.0 | 4.3% | 5.0M | 5.7M | 4 | 196 | 200 | 176 | 201 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.zig#L987-L1002) [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md) | **118** | 118 ± 2.4 | 2.0% | 8.2M | 8.7M | 3 | 121 | 122 | 115 | 122 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.zig#L1261-L1273) [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md) | **169** | 169 ± 1.4 | 0.8% | 5.9M | 6.0M | 2 | 170 | 170 | 166 | 170 | 2K |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.zig#L1656-L1686) [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md) | **768** | 763 ± 16.5 | 2.2% | 1.27M | 1.35M | 25 | 783 | 785 | 743 | 786 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.zig#L1689-L1718) [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md) | **832** | 834 ± 5.5 | 0.7% | 1.18M | 1.20M | 3 | 843 | 845 | 830 | 846 | 2K |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.zig#L1951-L1972) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **746** | 749 ± 10.3 | 1.4% | 1.3M | 1.4M | 14 | 761 | 762 | 734 | 762 | 500 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.zig#L1975-L2018) [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **253** | 255 ± 5.8 | 2.3% | 3.8M | 4.0M | 7 | 263 | 265 | 248 | 265 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.zig#L2265-L2279) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **269** | 269 ± 5.6 | 2.1% | 3.6M | 3.8M | 5 | 277 | 278 | 260 | 278 | 5K |

#### 3.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 33 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.zig#L576-L606) [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md) | **2.24** | 2.30 ± 0.15 | 6.7% | 381K | 460K | 0.07 | 2.55 | 2.61 | 2.17 | 2.63 | 500 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.zig#L723-L761) [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **1.22** | 1.21 ± 0.01 | 0.7% | 820K | 837K | 0.01 | 1.22 | 1.22 | 1.20 | 1.22 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.zig#L763-L784) [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **2.75** | 2.76 ± 0.03 | 1.1% | 357K | 368K | 0.04 | 2.80 | 2.80 | 2.72 | 2.80 | 500 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.zig#L920-L933) [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **1.42** | 1.44 ± 0.05 | 3.6% | 643K | 713K | 0.03 | 1.52 | 1.55 | 1.40 | 1.56 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.zig#L935-L953) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **1.36** | 1.38 ± 0.06 | 4.3% | 672K | 756K | 0.05 | 1.47 | 1.49 | 1.32 | 1.49 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.zig#L956-L985) [🔍 107p](slices/20_linked_array_list_b_tree_append.md) | **1.67** | 1.67 ± 0.02 | 1.3% | 587K | 611K | 0.03 | 1.70 | 1.70 | 1.64 | 1.70 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.zig#L1020-L1043) [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md) | **2.00** | 2.02 ± 0.08 | 3.8% | 457K | 508K | 0.03 | 2.13 | 2.18 | 1.97 | 2.19 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.zig#L1045-L1066) [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md) | **2.02** | 2.01 ± 0.03 | 1.6% | 485K | 509K | 0.03 | 2.05 | 2.06 | 1.96 | 2.06 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.zig#L1068-L1091) [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md) | **18.8** | 18.9 ± 0.32 | 1.7% | 51.8K | 54.3K | 0.44 | 19.3 | 19.3 | 18.4 | 19.3 | 400 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.zig#L1093-L1112) [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md) | **1.21** | 1.22 ± 0.01 | 1.0% | 805K | 828K | 0.01 | 1.23 | 1.24 | 1.21 | 1.24 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.zig#L1114-L1127) [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **2.15** | 2.25 ± 0.26 | 11.4% | 354K | 475K | 0.06 | 2.63 | 2.78 | 2.11 | 2.82 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.zig#L1136-L1174) [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **2.88** | 2.89 ± 0.02 | 0.8% | 341K | 348K | 0.02 | 2.93 | 2.93 | 2.87 | 2.93 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.zig#L1176-L1191) [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md) | **2.03** | 2.03 ± 0.02 | 0.9% | 486K | 499K | 0.03 | 2.06 | 2.06 | 2.01 | 2.06 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.zig#L1193-L1204) [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md) | **2.04** | 2.03 ± 0.03 | 1.3% | 483K | 501K | 0.03 | 2.06 | 2.07 | 2.00 | 2.07 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.zig#L1221-L1235) [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **3.03** | 3.05 ± 0.04 | 1.2% | 323K | 332K | 0.06 | 3.09 | 3.09 | 3.01 | 3.09 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.zig#L1237-L1259) [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **3.13** | 3.14 ± 0.02 | 0.6% | 315K | 320K | 0.02 | 3.16 | 3.17 | 3.12 | 3.17 | 1K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.zig#L1275-L1289) [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **2.63** | 2.63 ± 0.03 | 1.0% | 373K | 384K | 0.02 | 2.67 | 2.68 | 2.60 | 2.68 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.zig#L1291-L1311) [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **2.47** | 2.48 ± 0.02 | 0.8% | 399K | 408K | 0.02 | 2.50 | 2.51 | 2.45 | 2.51 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.zig#L1313-L1336) [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **2.64** | 2.64 ± 0.02 | 0.8% | 373K | 383K | 0.02 | 2.67 | 2.68 | 2.61 | 2.68 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.zig#L1338-L1352) [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md) | **1.89** | 1.90 ± 0.02 | 1.2% | 516K | 531K | 0.03 | 1.94 | 1.94 | 1.89 | 1.94 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.zig#L1388-L1411) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **1.02** | 1.05 ± 0.08 | 7.3% | 845K | 1.0M | 0.08 | 1.16 | 1.18 | 0.98 | 1.18 | 200 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.zig#L1413-L1438) [🔍 102p](slices/40_replication_incremental_1_moment_delta.md) | **1.66** | 1.67 ± 0.03 | 2.0% | 584K | 613K | 0.05 | 1.71 | 1.71 | 1.63 | 1.71 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1440-L1458) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **5.58** | 5.75 ± 0.76 | 13.2% | 135K | 189K | 0.31 | 6.90 | 7.32 | 5.30 | 7.42 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1460-L1514) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **13.5** | 15.0 ± 5.43 | 36.3% | 38.5K | 103K | 4.55 | 23.0 | 25.4 | 9.70 | 26.0 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.zig#L1516-L1603) [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md) | **129.6** | 129.8 ± 15.1 | 11.6% | 6.6K | 9.2K | 21.9 | 148.4 | 150.3 | 109.0 | 150.7 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.zig#L1605-L1635) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **1.77** | 1.77 ± 0.02 | 1.2% | 554K | 570K | 0.04 | 1.80 | 1.80 | 1.75 | 1.80 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.zig#L1801-L1836) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **1.51** | 1.51 ± 0.08 | 5.3% | 609K | 697K | 0.10 | 1.63 | 1.64 | 1.43 | 1.64 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.zig#L1903-L1949) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **1.11** | 1.11 ± 0.01 | 1.1% | 887K | 914K | 0.02 | 1.13 | 1.13 | 1.09 | 1.13 | 500 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.zig#L2030-L2069) [🔍 112p](slices/58_backend_core_memory_commits.md) | **2.42** | 2.45 ± 0.06 | 2.5% | 390K | 416K | 0.07 | 2.54 | 2.56 | 2.40 | 2.56 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.zig#L2072-L2126) [🔍 113p](slices/59_backend_core_buffered_file_commits.md) | **17.8** | 17.8 ± 0.14 | 0.8% | 55.7K | 56.9K | 0.16 | 17.9 | 18.0 | 17.6 | 18.0 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.zig#L2129-L2178) [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md) | **46.9** | 47.0 ± 0.40 | 0.9% | 20.9K | 21.5K | 0.30 | 47.6 | 47.8 | 46.6 | 47.8 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.zig#L2181-L2231) [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.82** | 1.81 ± 0.02 | 1.3% | 542K | 562K | 0.02 | 1.84 | 1.84 | 1.78 | 1.84 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.zig#L2233-L2263) [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **1.94** | 1.95 ± 0.02 | 0.9% | 505K | 518K | 0.03 | 1.97 | 1.98 | 1.93 | 1.98 | 500 |

### 4. 1v1 Statistical Comparison (Odin vs. Zig, Commit `8332eda00de6`)

#### 4.1 Sub-100ns Fast Path (`ns`, 20 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L544-L560) ([Zig](bench_xitdb.zig#L539-L555) · [🔍 46p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md)) | **2.98x** | **88** | 262 | `57.1` ★ | 91 ± 6.9 | 7.7% | 101 | 261 ± 3.7 | 1.4% | 264 |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L562-L579) ([Zig](bench_xitdb.zig#L557-L574) · [🔍 39p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md)) | **3.40x** | **53** | 180 | `37.2` ★ | 54 ± 1.3 | 2.5% | 56 | 182 ± 9.0 | 5.0% | 195 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L642-L658) ([Zig](bench_xitdb.zig#L632-L646) · [🔍 31p](slices/06_hamt_hash_map_unordered_iterator_scan.md)) | **4.09x** | **34** | 139 | `108.9` ★ | 34 ± 0.8 | 2.5% | 35 | 139 ± 2.4 | 1.7% | 143 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L815-L831) ([Zig](bench_xitdb.zig#L808-L824) · [🔍 49p](slices/13_hamt_counted_hash_set_membership_check.md)) | **2.94x** | **89** | 262 | `66.2` ★ | 89 ± 1.1 | 1.3% | 90 | 261 ± 6.8 | 2.6% | 268 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L876-L891) ([Zig](bench_xitdb.zig#L865-L880) · [🔍 30p](slices/15_array_list_radix_trie_random_get.md)) | **2.81x** | **43** | 121 | `7.5` ★ | 43 ± 0.5 | 1.2% | 44 | 132 ± 31.2 | 23.7% | 179 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L893-L910) ([Zig](bench_xitdb.zig#L882-L896) · [🔍 32p](slices/16_array_list_radix_trie_iterator_scan.md)) | **2.42x** | **12** | 29 | `66.8` ★ | 12 ± 0.1 | 0.7% | 12 | 29 ± 0.7 | 2.4% | 30 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L912-L930) ([Zig](bench_xitdb.zig#L898-L918) · [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md)) | **2.04x** | **89** | 182 | `31.4` ★ | 89 ± 1.0 | 1.1% | 90 | 184 ± 8.0 | 4.3% | 196 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1002-L1017) ([Zig](bench_xitdb.zig#L987-L1002) · [🔍 37p](slices/21_linked_array_list_b_tree_random_get.md)) | **2.27x** | **52** | 118 | `72.2` ★ | 52 ± 0.6 | 1.2% | 52 | 118 ± 2.4 | 2.0% | 121 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1019-L1036) ([Zig](bench_xitdb.zig#L1004-L1018) · [🔍 32p](slices/22_linked_array_list_b_tree_iterator_scan.md)) | **4.58x** | **12** | 55 | `81.9` ★ | 12 ± 0.1 | 0.5% | 12 | 56 ± 1.4 | 2.5% | 58 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1226-L1241) ([Zig](bench_xitdb.zig#L1206-L1219) · [🔍 31p](slices/31_sorted_map_b_tree_ordered_scan.md)) | **4.00x** | **12** | 48 | `56.6` ★ | 12 ± 0.1 | 0.8% | 12 | 47 ± 1.6 | 3.5% | 49 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1288-L1300) ([Zig](bench_xitdb.zig#L1261-L1273) · [🔍 37p](slices/34_sorted_map_b_tree_get_index_select.md)) | **2.41x** | **70** | 169 | `174.4` ★ | 70 ± 0.5 | 0.7% | 71 | 169 ± 1.4 | 0.8% | 170 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1648-L1673) ([Zig](bench_xitdb.zig#L1721-L1752) · [🔍 104p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md)) | **1.33x** | **6** | 8 | `135.2` ★ | 6 ± 0.0 | 0.5% | 6 | 8 ± 0.0 | 0.0% | 8 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1675-L1684) ([Zig](bench_xitdb.zig#L1754-L1763) · [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md)) | **3.09x** | **11** | 34 | `141.9` ★ | 11 ± 0.2 | 1.8% | 11 | 34 ± 0.4 | 1.1% | 34 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1686-L1702) ([Zig](bench_xitdb.zig#L1765-L1787) · [🔍 84p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md)) | **1.00x** | **7** | 7 | `28.0` ★ | 7 ± 0.0 | 0.4% | 7 | 7 ± 0.0 | 0.0% | 7 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1704-L1713) ([Zig](bench_xitdb.zig#L1789-L1798) · [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md)) | **4.27x** | **11** | 47 | `132.5` ★ | 11 ± 0.2 | 1.7% | 12 | 47 ± 0.7 | 1.5% | 48 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L1755-L1771) ([Zig](bench_xitdb.zig#L1838-L1854) · [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md)) | **1.34x** | **53** | 71 | `25.0` ★ | 54 ± 1.0 | 1.8% | 55 | 70 ± 1.5 | 2.1% | 72 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L1773-L1788) ([Zig](bench_xitdb.zig#L1856-L1871) · [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md)) | **6.75x** | **4** | 27 | `80.2` ★ | 4 ± 0.0 | 1.1% | 4 | 27 ± 0.8 | 2.8% | 28 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L1790-L1820) ([Zig](bench_xitdb.zig#L1873-L1900) · [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md)) | **1.13x** | **23** | 26 | `1.6` ~ | 24 ± 3.3 | 13.5% | 29 | 26 ± 1.5 | 5.7% | 29 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L1902-L1935) ([Zig](bench_xitdb.zig#L1975-L2018) · [🔍 130p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md)) | **2.78x** | **91** | 253 | `57.2` ★ | 93 ± 4.8 | 5.1% | 100 | 255 ± 5.8 | 2.3% | 263 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2133-L2148) ([Zig](bench_xitdb.zig#L2265-L2279) · [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md)) | **4.48x** | **60** | 269 | `95.8` ★ | 59 ± 1.5 | 2.5% | 61 | 269 ± 5.6 | 2.1% | 277 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 31 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L517-L542) ([Zig](bench_xitdb.zig#L513-L537) · [🔍 89p](slices/01_hamt_hash_map_bulk_put_1_tx.md)) | **3.87x** | **196** | 758 | `78.7` ★ | 196 ± 1.9 | 0.9% | 198 | 761 ± 18.9 | 2.5% | 788 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L614-L640) ([Zig](bench_xitdb.zig#L608-L630) · [🔍 86p](slices/05_hamt_hash_map_remove_branch_shortening.md)) | **5.54x** | **170** | 942 | `267.3` ★ | 168 ± 4.6 | 2.7% | 172 | 942 ± 6.1 | 0.7% | 949 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L660-L683) ([Zig](bench_xitdb.zig#L648-L670) · [🔍 89p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md)) | **3.63x** | **194** | 705 | `32.1` ★ | 209 ± 40.6 | 19.4% | 270 | 706 ± 5.5 | 0.8% | 713 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L685-L709) ([Zig](bench_xitdb.zig#L672-L700) · [🔍 97p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md)) | **3.85x** | **198** | 762 | `23.6` ★ | 221 ± 60.1 | 27.2% | 310 | 763 ± 8.6 | 1.1% | 775 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L711-L729) ([Zig](bench_xitdb.zig#L702-L721) · [🔍 83p](slices/09_hamt_counted_hash_map_remove.md)) | **5.81x** | **168** | 976 | `39.6` ★ | 185 ± 51.0 | 27.6% | 261 | 972 ± 12.5 | 1.3% | 985 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L731-L771) ([Zig](bench_xitdb.zig#L723-L761) · [🔍 86p](slices/10_hamt_deep_suffix_collision_put_depth_10.md)) | **6.40x** | **190** | 1,216 | `49.5` ★ | 209 ± 52.9 | 25.3% | 290 | 1,211 ± 9.0 | 0.7% | 1,219 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L773-L793) ([Zig](bench_xitdb.zig#L763-L784) · [🔍 83p](slices/11_hamt_deep_suffix_collision_branch_collapse.md)) | **13.89x** | **198** | 2,751 | `126.2` ★ | 215 ± 44.5 | 20.7% | 283 | 2,761 ± 29.4 | 1.1% | 2,796 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L795-L813) ([Zig](bench_xitdb.zig#L786-L806) · [🔍 85p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md)) | **2.34x** | **213** | 498 | `90.9` ★ | 211 ± 5.8 | 2.7% | 218 | 501 ± 6.1 | 1.2% | 508 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L841-L874) ([Zig](bench_xitdb.zig#L834-L863) · [🔍 91p](slices/14_array_list_radix_trie_append.md)) | **1.88x** | **104** | 196 | `6.5` ★ | 104 ± 2.3 | 2.2% | 107 | 212 ± 43.5 | 20.6% | 278 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L932-L946) ([Zig](bench_xitdb.zig#L920-L933) · [🔍 32p](slices/18_array_list_radix_trie_index_seek_page_10.md)) | **4.13x** | **344** | 1,422 | `55.8` ★ | 343 ± 3.8 | 1.1% | 346 | 1,442 ± 52.0 | 3.6% | 1,523 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L948-L964) ([Zig](bench_xitdb.zig#L935-L953) · [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md)) | **1.85x** | **735** | 1,360 | `28.9` ★ | 732 ± 7.6 | 1.0% | 741 | 1,382 ± 59.0 | 4.3% | 1,473 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L967-L1000) ([Zig](bench_xitdb.zig#L956-L985) · [🔍 107p](slices/20_linked_array_list_b_tree_append.md)) | **7.38x** | **226** | 1,669 | `174.9` ★ | 226 ± 2.2 | 1.0% | 229 | 1,668 ± 21.7 | 1.3% | 1,697 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1038-L1064) ([Zig](bench_xitdb.zig#L1020-L1043) · [🔍 92p](slices/23_linked_array_list_b_tree_middle_insert.md)) | **7.96x** | **251** | 1,997 | `60.7` ★ | 251 ± 5.0 | 2.0% | 259 | 2,019 ± 76.8 | 3.8% | 2,135 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1066-L1085) ([Zig](bench_xitdb.zig#L1045-L1066) · [🔍 93p](slices/24_linked_array_list_b_tree_middle_remove.md)) | **6.36x** | **317** | 2,017 | `138.0` ★ | 318 ± 4.6 | 1.4% | 324 | 2,009 ± 32.1 | 1.6% | 2,052 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1114-L1131) ([Zig](bench_xitdb.zig#L1093-L1112) · [🔍 83p](slices/26_linked_array_list_b_tree_in_place_put.md)) | **7.68x** | **158** | 1,213 | `228.5` ★ | 157 ± 3.0 | 1.9% | 160 | 1,216 ± 11.9 | 1.0% | 1,234 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1133-L1147) ([Zig](bench_xitdb.zig#L1114-L1127) · [🔍 31p](slices/27_linked_array_list_b_tree_index_seek_page_10.md)) | **5.89x** | **365** | 2,150 | `19.5` ★ | 365 ± 4.0 | 1.1% | 369 | 2,246 ± 256 | 11.4% | 2,634 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1156-L1194) ([Zig](bench_xitdb.zig#L1136-L1174) · [🔍 123p](slices/28_sorted_map_b_tree_out_of_order_put.md)) | **7.74x** | **372** | 2,881 | `290.3` ★ | 373 ± 2.8 | 0.8% | 376 | 2,889 ± 22.8 | 0.8% | 2,925 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1196-L1211) ([Zig](bench_xitdb.zig#L1176-L1191) · [🔍 43p](slices/29_sorted_map_b_tree_key_lookup.md)) | **12.30x** | **165** | 2,030 | `256.1` ★ | 166 ± 3.5 | 2.1% | 172 | 2,032 ± 18.9 | 0.9% | 2,055 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1213-L1224) ([Zig](bench_xitdb.zig#L1193-L1204) · [🔍 29p](slices/30_sorted_map_b_tree_rank_query.md)) | **14.88x** | **137** | 2,038 | `195.8` ★ | 137 ± 1.3 | 1.0% | 139 | 2,031 ± 25.6 | 1.3% | 2,063 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1243-L1258) ([Zig](bench_xitdb.zig#L1221-L1235) · [🔍 37p](slices/32_sorted_map_b_tree_lower_bound_page_10.md)) | **6.60x** | **460** | 3,034 | `189.5` ★ | 460 ± 4.1 | 0.9% | 465 | 3,047 ± 35.9 | 1.2% | 3,092 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1260-L1286) ([Zig](bench_xitdb.zig#L1237-L1259) · [🔍 91p](slices/33_sorted_map_b_tree_remove_rebalance.md)) | **13.50x** | **232** | 3,131 | `430.6` ★ | 232 ± 2.3 | 1.0% | 236 | 3,136 ± 17.7 | 0.6% | 3,164 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1302-L1317) ([Zig](bench_xitdb.zig#L1275-L1289) · [🔍 32p](slices/35_sorted_map_b_tree_index_seek_page_10.md)) | **7.84x** | **335** | 2,626 | `236.5` ★ | 334 ± 3.6 | 1.1% | 337 | 2,634 ± 25.5 | 1.0% | 2,672 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1319-L1337) ([Zig](bench_xitdb.zig#L1291-L1311) · [🔍 102p](slices/36_sorted_map_b_tree_in_place_overwrite.md)) | **7.13x** | **346** | 2,468 | `280.5` ★ | 346 ± 2.4 | 0.7% | 349 | 2,477 ± 19.9 | 0.8% | 2,504 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1339-L1360) ([Zig](bench_xitdb.zig#L1313-L1336) · [🔍 102p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md)) | **8.04x** | **328** | 2,638 | `270.4` ★ | 328 ± 3.6 | 1.1% | 332 | 2,639 ± 22.3 | 0.8% | 2,671 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1362-L1376) ([Zig](bench_xitdb.zig#L1338-L1352) · [🔍 42p](slices/38_sorted_set_b_tree_contains_lookup.md)) | **11.97x** | **158** | 1,892 | `201.4` ★ | 158 ± 1.8 | 1.1% | 160 | 1,905 ± 22.9 | 1.2% | 1,938 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1418-L1436) ([Zig](bench_xitdb.zig#L1388-L1411) · [🔍 54p](slices/39_replication_genesis_200_moments.md)) | **2.32x** | **439** | 1,018 | `20.5` ★ | 447 ± 15.1 | 3.4% | 470 | 1,046 ± 75.9 | 7.3% | 1,164 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1624-L1645) ([Zig](bench_xitdb.zig#L1656-L1686) · [🔍 110p](slices/45_hasher_sha_1_20b_hamt_put.md)) | **3.71x** | **207** | 768 | `88.6` ★ | 207 ± 1.6 | 0.8% | 209 | 763 ± 16.5 | 2.2% | 783 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1624-L1645) ([Zig](bench_xitdb.zig#L1689-L1718) · [🔍 113p](slices/46_hasher_sha_256_32b_hamt_put.md)) | **3.89x** | **214** | 832 | `241.0` ★ | 215 ± 3.9 | 1.8% | 220 | 834 ± 5.5 | 0.7% | 843 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L1823-L1876) ([Zig](bench_xitdb.zig#L1903-L1949) · [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md)) | **5.11x** | **218** | 1,114 | `178.1` ★ | 220 ± 5.3 | 2.4% | 228 | 1,113 ± 12.1 | 1.1% | 1,126 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L1878-L1899) ([Zig](bench_xitdb.zig#L1951-L1972) · [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md)) | **5.04x** | **148** | 746 | `150.0` ★ | 148 ± 2.4 | 1.6% | 151 | 749 ± 10.3 | 1.4% | 761 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2110-L2131) ([Zig](bench_xitdb.zig#L2233-L2263) · [🔍 84p](slices/62_tx_aborted_transaction_rollback_truncate.md)) | **3.27x** | **593** | 1,940 | `151.6` ★ | 601 ± 14.7 | 2.4% | 620 | 1,949 ± 18.4 | 0.9% | 1,974 |

#### 4.3 Multi-Microsecond Transactions & Compaction (`µs`, 12 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L581-L612) ([Zig](bench_xitdb.zig#L576-L606) · [🔍 91p](slices/04_hamt_cow_branched_moment_commits.md)) | **2.14x** | **1.04** | 2.24 | `21.7` ★ | 1.05 ± 0.01 | 1.0% | 1.06 | 2.30 ± 0.15 | 6.7% | 2.55 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1087-L1112) ([Zig](bench_xitdb.zig#L1068-L1091) · [🔍 98p](slices/25_linked_array_list_b_tree_concat_slice.md)) | **17.80x** | **1.06** | 18.8 | `148.2` ★ | 1.06 ± 0.01 | 1.1% | 1.08 | 18.9 ± 0.32 | 1.7% | 19.3 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1438-L1463) ([Zig](bench_xitdb.zig#L1413-L1438) · [🔍 102p](slices/40_replication_incremental_1_moment_delta.md)) | **1.58x** | **1.05** | 1.66 | `46.4` ★ | 1.05 ± 0.01 | 1.0% | 1.06 | 1.67 ± 0.03 | 2.0% | 1.71 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1465-L1483) ([Zig](bench_xitdb.zig#L1440-L1458) · [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md)) | 0.93x | 6.03 | **5.58** | `1.8` ~ | 7.26 ± 2.13 | 29.3% | 10.3 | 5.75 ± 0.76 | 13.2% | 6.90 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1485-L1506) ([Zig](bench_xitdb.zig#L1460-L1514) · [🔍 99p](slices/42_compaction_file_offset_map_200_1.md)) | **1.04x** | **13.0** | 13.5 | `0.7` ~ | 13.4 ± 1.30 | 9.7% | 15.4 | 15.0 ± 5.43 | 36.3% | 23.0 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1508-L1567) ([Zig](bench_xitdb.zig#L1516-L1603) · [🔍 167p](slices/43_compaction_heterogeneous_dag_dedup.md)) | **3.22x** | **40.3** | 129.6 | `15.4` ★ | 41.2 ± 2.22 | 5.4% | 44.7 | 129.8 ± 15.1 | 11.6% | 148.4 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1569-L1594) ([Zig](bench_xitdb.zig#L1605-L1635) · [🔍 55p](slices/44_replication_post_compaction_resync.md)) | **1.31x** | **1.35** | 1.77 | `1.9` ~ | 1.49 ± 0.39 | 26.4% | 2.07 | 1.77 ± 0.02 | 1.2% | 1.80 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1716-L1753) ([Zig](bench_xitdb.zig#L1801-L1836) · [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md)) | **1.09x** | **1.38** | 1.51 | `4.4` ★ | 1.37 ± 0.02 | 1.3% | 1.39 | 1.51 ± 0.08 | 5.3% | 1.63 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L1958-L1985) ([Zig](bench_xitdb.zig#L2030-L2069) · [🔍 112p](slices/58_backend_core_memory_commits.md)) | **2.22x** | **1.09** | 2.42 | `55.4` ★ | 1.10 ± 0.02 | 2.1% | 1.13 | 2.45 ± 0.06 | 2.5% | 2.54 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L1988-L2027) ([Zig](bench_xitdb.zig#L2072-L2126) · [🔍 113p](slices/59_backend_core_buffered_file_commits.md)) | **1.24x** | **14.4** | 17.8 | `29.4` ★ | 14.4 ± 0.27 | 1.9% | 14.8 | 17.8 ± 0.14 | 0.8% | 17.9 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2030-L2064) ([Zig](bench_xitdb.zig#L2129-L2178) · [🔍 112p](slices/60_backend_core_file_unbuffered_commits.md)) | **1.13x** | **41.5** | 46.9 | `23.6` ★ | 41.4 ± 0.48 | 1.2% | 42.1 | 47.0 ± 0.40 | 0.9% | 47.6 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2067-L2108) ([Zig](bench_xitdb.zig#L2181-L2231) · [🔍 107p](slices/61_tx_mid_tx_database_freeze_cow_clone.md)) | **1.64x** | **1.11** | 1.82 | `44.4` ★ | 1.11 ± 0.03 | 3.1% | 1.16 | 1.81 ± 0.02 | 1.3% | 1.84 |

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
