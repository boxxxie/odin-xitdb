# xitdb Benchmarks

This directory contains the statistical performance benchmark suite for `xitdb`, measuring throughput (`ops/sec`), median/mean latency (`ns/op`), variance (`±σ`, `CV%`, `IQR`, `p95`, `p99`, `min..max`), and resulting database byte footprint across all collection types, storage backends, and the 5-layer DSL/Datalog engine.

---

## Running the Benchmarks

Always compile benchmarks with `-o:speed` (and `-microarch:native` to enable target-specific SIMD instructions alongside runtime x86 SHA-NI detection). The primary runner is [`hugi`](https://github.com/boxxxie/hugi) (`v0.1.0+`), which reads defaults from [`hugi.json`](../hugi.json) (`runs=7`, `warmup=1`, `-microarch:native`, `db="benchmarks/history.hugidb"`), forwards `--pin`, `--counters`, `--test`, and `--host-warned`, collects exact integer `u64` batch nanosecond samples (`HPKT\x02`) plus host provenance (`HENV`), and ingests runs into `benchmarks/history.hugidb`:

```bash
# Inspect host CPU governor, scaling frequency, boost state, SMT, and hugi.json config
hugi doctor

# Build & run all Odin benchmarks with hugi (honoring hugi.json: 7 runs, 1 warmup, -microarch:native)
hugi run --counters

# Smoke-test the entire benchmark suite (1 run, 0 warmup, skips DB ingest)
hugi run --test --counters

# Pin execution to CPU 0 and run a single group into an in-memory CoW Core_Overlay branch
hugi run --overlay --groups hamt --pin 0 --runs 7 --warmup 1

# Run and gate immediately on Hodges-Lehmann CI + Mann-Whitney U regressions against a baseline commit
hugi run --baseline-commit bab4850e4f8e --fail-on-regression

# Run the embedded LuaJIT benchmark suite via hugi
hugi run --lang lua
```

You can also invoke the Odin benchmark binary directly (passing `-collection:hugi=../hugi/hugi -collection:obench=../hugi/deps/obench/obench`, which `hugi run` injects automatically from [`ols.json`](../ols.json) / `HUGI_HOME`):

```bash
# Direct Odin invocation (writes benchmarks/odin.jsonl & benchmarks/history.jsonl)
odin run benchmarks -collection:hugi=../hugi/hugi -collection:obench=../hugi/deps/obench/obench -o:speed -microarch:native -- --runs 7 --warmup 1

# Emit an HPKT binary packet (with HENV provenance and optional perf counters) for later ingestion
odin run benchmarks -collection:hugi=../hugi/hugi -collection:obench=../hugi/deps/obench/obench -o:speed -microarch:native -- --runs 7 --warmup 1 --pin 0 --counters --packet-out .tmp/odin.hpk --quiet
hugi ingest --db benchmarks/history.hugidb .tmp/odin.hpk

# Disable bounds checking in hot loops for peak release numbers
odin run benchmarks -collection:hugi=../hugi/hugi -collection:obench=../hugi/deps/obench/obench -o:speed -microarch:native -no-bounds-check -- --runs 7
```

### 1v1 Comparison with Upstream Zig (`reference/xitdb-zig` & `reference/xitdb-zig-patched`)

The upstream Zig reference implementation is tracked in `reference/xitdb-zig` (and our patched fork with all 6 guide optimizations is tracked in `reference/xitdb-zig-patched`). To run the Zig benchmark suite (requires Zig `0.17.0-dev` matching `reference/xitdb-zig/build.zig.zon`) and ingest its JSONL output into `benchmarks/history.hugidb`:

```bash
# Run against upstream reference/xitdb-zig (default)
zig build bench -Doptimize=ReleaseFast -Dcpu=native -- --runs 7 --warmup 1 --output .tmp/zig.jsonl --no-history

# Run against reference/xitdb-zig-patched
zig build bench -Doptimize=ReleaseFast -Dcpu=native -Dpatched=true -- --runs 7 --warmup 1 --output .tmp/zig-patched.jsonl --no-history

# Ingest Zig (or Lua) JSONL snapshots into the hugi store with host/runtime provenance and run 1v1 comparison
hugi ingest --db benchmarks/history.hugidb .tmp/zig.jsonl --capture-host-env --build-flags "-Doptimize=ReleaseFast -Dcpu=native" --runtime-version "zig $(zig version)"
hugi compare-1v1 --db benchmarks/history.hugidb --langs odin,zig
```

Or run both Odin and Zig suites back-to-back with unified commit/run tagging and statistical significance reporting (Welch's `z`-test) using `compare_1v1.py`:

```bash
./benchmarks/compare_1v1.py --runs 7 --warmup 1
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
hugi run --groups dsl --filter "Datalog|Secondary Index"
./benchmarks/compare_1v1.py --groups dsl --filter "Datalog|Secondary Index"
odin run benchmarks -collection:hugi=../hugi/hugi -collection:obench=../hugi/deps/obench/obench -o:speed -microarch:native -- --groups sorted_map,compaction --filter "Incremental"
```

### Multi-Run Pooling, Commit History & Regression Analysis (`history.hugidb`)

Benchmark history across `odin`, `zig`, and `lua` is stored in the compressed `xitdb`-backed store at `benchmarks/history.hugidb` (backfilled from `history.jsonl` and `lua.jsonl`, and compactable into cold columnar rollups):

```bash
# Backfill or ingest packets/JSONL files into history.hugidb and compact cold chunks
hugi ingest --db benchmarks/history.hugidb benchmarks/history.jsonl benchmarks/lua.jsonl
hugi compact --db benchmarks/history.hugidb --keep-hot 0

# List stored commits, languages, run counts, and sample totals
hugi history --db benchmarks/history.hugidb --limit 0

# Inspect pooled quantiles, AR(1) ci95, CV%, sample-shape warnings, and footprint for matching benchmarks
hugi inspect --db benchmarks/history.hugidb "HAMT Hash_Map"

# Compare two Git commits (Hodges-Lehmann CI + Mann-Whitney U + Welch t-test; add --by-run for per-run medians) or compare Odin vs. Zig 1v1
hugi compare --db benchmarks/history.hugidb --commits <baseline_sha>..<candidate_sha> --lang odin
hugi compare --db benchmarks/history.hugidb --commits <baseline_sha>..<candidate_sha> --lang odin --by-run
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
### 1. Latest Code-Change Impact & Affected Benchmarks (`8332eda00de6` → `69fb30701a3c`, Odin, 75 / 75 tests re-run)

- **Code Diff Inspected:** `b83ff52~1..b83ff52` · **Changed Files:** `xitdb/cursor.odin`
- **Modified Procedures:** `_assign_btree_heights`, `_decode_slot_block_raw`, `_fill_slot_block_from`, `_fill_slot_block_rev`, `_init_array_list_stack`, `_init_btree_stack_from_index`, `_init_btree_stack`, `_init_counted_hash_iter`, `_iterator_step_internal`, `_read_btree_iter_level`, `cursor_iterator_array_list_from_index_init`, `cursor_iterator_array_list_reverse_from_index_init`, `cursor_iterator_init`, `cursor_iterator_linked_array_list_from_index_init`, `cursor_iterator_linked_array_list_reverse_from_index_init`, `cursor_iterator_next`, `cursor_iterator_prev`, `cursor_iterator_reverse_init`, `cursor_iterator_sorted_from_index_init`, `cursor_iterator_sorted_from_key_init`, `cursor_iterator_sorted_reverse_from_index_init`, `cursor_iterator_sorted_reverse_from_key_init`
- **Mapped Benchmark Scope:** Odin groups=`hamt`, `lists`, `sorted_map`, `compaction`, `hashers`, `backends`, `dsl` (**75 / 75** Odin benchmarks executed; **0** unchanged benchmarks retained from `8332eda`)

#### 1.1 Sub-100ns Fast Path (`ns`, 15 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `8332eda` (`ns`) | Curr `69fb307` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L718-L737) [🔍 40p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **REGRESSION** | `+14.5%` | 0.87x | 53 | **61** | `10.2` | 54 ± 1.3 | 62 ± 1.7 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L804-L822) [🔍 49p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **REGRESSION** | `+38.0%` | 0.72x | 34 | **47** | `17.1` | 34 ± 0.8 | 47 ± 1.8 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L1056-L1073) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | `~NOISE` | `+14.3%` | 0.88x | 43 | **49** | `2.7` | 43 ± 0.5 | 53 ± 9.7 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L1075-L1094) [🔍 50p](slices/16_array_list_radix_trie_iterator_scan.md) | `~NOISE` | `+10.1%` | 0.92x | 12 | **13** | `2.3` | 12 ± 0.1 | 14 ± 2.5 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L1096-L1116) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | `~NOISE` | `+11.3%` | 0.90x | 89 | **99** | `2.5` | 89 ± 1.0 | 106 ± 18.7 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1213-L1232) [🔍 50p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **REGRESSION** | `+62.2%` | 0.60x | 12 | **20** | `8.7` | 12 ± 0.1 | 21 ± 2.6 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1438-L1455) [🔍 49p](slices/31_sorted_map_b_tree_ordered_scan.md) | **REGRESSION** | `+89.4%` | 0.52x | 12 | **23** | `4.0` | 12 ± 0.1 | 26 ± 9.4 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1900-L1928) [🔍 105p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | `~NOISE` | `+5.9%` | 0.86x | 6 | **7** | `1.4` | 6 ± 0.0 | 7 ± 2.2 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1930-L1942) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | `~NOISE` | `+3.6%` | 1.00x | 11 | **11** | `1.5` | 11 ± 0.2 | 13 ± 3.4 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1944-L1963) [🔍 85p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | `~NOISE` | `-0.3%` | 1.00x | 7 | **7** | `1.5` | 7 ± 0.0 | 8 ± 2.7 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1965-L1977) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | `~NOISE` | `+4.8%` | 0.92x | 11 | **12** | `2.1` | 11 ± 0.2 | 15 ± 4.4 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L2021-L2039) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | `~NOISE` | `+17.8%` | 0.84x | 53 | **63** | `1.7` | 54 ± 1.0 | 131 ± 122 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L2041-L2058) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | `~NOISE` | `+5.6%` | 0.80x | 4 | **5** | `1.8` | 4 ± 0.0 | 5 ± 1.6 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L2060-L2092) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | `~NOISE` | `+9.6%` | 0.92x | 23 | **25** | `1.7` | 24 ± 3.3 | 30 ± 7.9 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2421-L2438) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | `~NOISE` | `+4.9%` | 0.95x | 60 | **63** | `4.5` | 59 ± 1.5 | 63 ± 1.6 |

#### 1.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 37 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `8332eda` (`ns`) | Curr `69fb307` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L669-L696) [🔍 90p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **REGRESSION** | `+15.6%` | 0.87x | 196 | **226** | `11.3` | 196 ± 1.9 | 225 ± 6.5 |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L698-L716) [🔍 47p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **REGRESSION** | `+17.7%` | 0.85x | 88 | **104** | `5.0` | 91 ± 6.9 | 104 ± 1.9 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L774-L802) [🔍 87p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **REGRESSION** | `+16.5%` | 0.86x | 170 | **198** | `6.3` | 168 ± 4.6 | 201 ± 13.1 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L824-L849) [🔍 90p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | `~NOISE` | `+26.2%` | 0.79x | 194 | **245** | `2.5` | 209 ± 40.6 | 250 ± 10.7 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L851-L877) [🔍 98p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | `~NOISE` | `+17.4%` | 0.85x | 198 | **232** | `0.8` | 221 ± 60.1 | 238 ± 11.5 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L879-L899) [🔍 84p](slices/09_hamt_counted_hash_map_remove.md) | `~NOISE` | `+15.7%` | 0.87x | 168 | **194** | `0.6` | 185 ± 51.0 | 197 ± 7.0 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L901-L943) [🔍 87p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | `~NOISE` | `+23.1%` | 0.81x | 190 | **234** | `1.3` | 209 ± 52.9 | 235 ± 9.1 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L945-L967) [🔍 84p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | `~NOISE` | `+16.0%` | 0.86x | 198 | **229** | `0.8` | 215 ± 44.5 | 229 ± 5.8 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L969-L989) [🔍 86p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **REGRESSION** | `+17.2%` | 0.85x | 213 | **250** | `12.1` | 211 ± 5.8 | 252 ± 6.7 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L991-L1009) [🔍 50p](slices/13_hamt_counted_hash_set_membership_check.md) | **REGRESSION** | `+14.9%` | 0.87x | 89 | **102** | `11.3` | 89 ± 1.1 | 103 ± 3.2 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L1019-L1054) [🔍 91p](slices/14_array_list_radix_trie_append.md) | `~NOISE` | `+9.3%` | 0.91x | 104 | **114** | `2.0` | 104 ± 2.3 | 123 ± 25.6 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L1118-L1134) [🔍 45p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **FASTER** | `-22.5%` | 1.29x | 344 | **267** | `33.7` | 343 ± 3.8 | 267 ± 4.6 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L1136-L1154) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **REGRESSION** | `+20.1%` | 0.83x | 735 | **883** | `11.7` | 732 ± 7.6 | 879 ± 32.2 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L1157-L1192) [🔍 109p](slices/20_linked_array_list_b_tree_append.md) | **REGRESSION** | `+20.5%` | 0.83x | 226 | **272** | `16.7` | 226 ± 2.2 | 271 ± 6.7 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1194-L1211) [🔍 43p](slices/21_linked_array_list_b_tree_random_get.md) | **REGRESSION** | `+384.3%` | 0.21x | 52 | **250** | `113.8` | 52 ± 0.6 | 251 ± 4.6 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1234-L1262) [🔍 94p](slices/23_linked_array_list_b_tree_middle_insert.md) | **REGRESSION** | `+21.8%` | 0.82x | 251 | **306** | `13.8` | 251 ± 5.0 | 306 ± 9.2 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1264-L1285) [🔍 94p](slices/24_linked_array_list_b_tree_middle_remove.md) | **REGRESSION** | `+30.8%` | 0.77x | 317 | **414** | `9.7` | 318 ± 4.6 | 419 ± 27.4 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1316-L1335) [🔍 88p](slices/26_linked_array_list_b_tree_in_place_put.md) | **REGRESSION** | `+30.1%` | 0.77x | 158 | **206** | `28.8` | 157 ± 3.0 | 205 ± 3.2 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1337-L1353) [🔍 45p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **REGRESSION** | `+40.1%` | 0.71x | 365 | **512** | `46.6` | 365 ± 4.0 | 513 ± 7.4 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1362-L1402) [🔍 128p](slices/28_sorted_map_b_tree_out_of_order_put.md) | `~NOISE` | `+22.2%` | 0.82x | 372 | **454** | `3.1` | 373 ± 2.8 | 521 ± 125 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1404-L1421) [🔍 51p](slices/29_sorted_map_b_tree_key_lookup.md) | **REGRESSION** | `+189.1%` | 0.35x | 165 | **478** | `7.4` | 166 ± 3.5 | 565 ± 142 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1423-L1436) [🔍 36p](slices/30_sorted_map_b_tree_rank_query.md) | **REGRESSION** | `+208.0%` | 0.32x | 137 | **422** | `7.5` | 137 ± 1.3 | 474 ± 118 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1457-L1474) [🔍 51p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **REGRESSION** | `+59.8%` | 0.63x | 460 | **736** | `6.1` | 460 ± 4.1 | 786 ± 142 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1476-L1504) [🔍 94p](slices/33_sorted_map_b_tree_remove_rebalance.md) | `~NOISE` | `+30.5%` | 0.77x | 232 | **302** | `2.5` | 232 ± 2.3 | 333 ± 107 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1506-L1520) [🔍 43p](slices/34_sorted_map_b_tree_get_index_select.md) | **REGRESSION** | `+409.3%` | 0.20x | 70 | **358** | `9.6` | 70 ± 0.5 | 395 ± 89.1 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1522-L1539) [🔍 46p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **REGRESSION** | `+81.4%` | 0.55x | 335 | **607** | `6.7` | 334 ± 3.6 | 683 ± 137 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1541-L1561) [🔍 107p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | `~NOISE` | `+24.4%` | 0.80x | 346 | **430** | `3.1` | 346 ± 2.4 | 513 ± 143 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1563-L1586) [🔍 107p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | `~NOISE` | `+24.1%` | 0.81x | 328 | **407** | `3.3` | 328 ± 3.6 | 472 ± 117 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1588-L1604) [🔍 50p](slices/38_sorted_set_b_tree_contains_lookup.md) | **REGRESSION** | `+192.7%` | 0.34x | 158 | **462** | `7.3` | 158 ± 1.8 | 538 ± 138 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1646-L1666) [🔍 54p](slices/39_replication_genesis_200_moments.md) | `~NOISE` | `+5.5%` | 0.95x | 439 | **463** | `1.5` | 447 ± 15.1 | 490 ± 75.2 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1874-L1897) [🔍 111p](slices/45_hasher_sha_1_20b_hamt_put.md) | `~NOISE` | `-1.5%` | 1.01x | 207 | **204** | `1.3` | 207 ± 1.6 | 228 ± 43.3 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1874-L1897) [🔍 114p](slices/46_hasher_sha_256_32b_hamt_put.md) | `~NOISE` | `+0.7%` | 0.99x | 214 | **216** | `1.0` | 215 ± 3.9 | 229 ± 36.4 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L2095-L2150) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | `~NOISE` | `+6.4%` | 0.94x | 218 | **232** | `2.1` | 220 ± 5.3 | 276 ± 72.1 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L2152-L2175) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **REGRESSION** | `+70.6%` | 0.58x | 148 | **253** | `5.2` | 148 ± 2.4 | 295 ± 74.9 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L2178-L2213) [🔍 147p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | `~NOISE` | `+22.4%` | 0.82x | 91 | **111** | `3.2` | 93 ± 4.8 | 126 ± 26.8 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2396-L2419) [🔍 85p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **REGRESSION** | `+14.1%` | 0.88x | 593 | **677** | `7.1` | 601 ± 14.7 | 669 ± 20.7 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2508-L2523) [🔍 94p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **REGRESSION** | `+13.2%` | 0.88x | 607 | **687** | `12.4` | 609 ± 11.9 | 682 ± 10.0 |

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 23 affected tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `8332eda` (`µs`) | Curr `69fb307` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L739-L772) [🔍 92p](slices/04_hamt_cow_branched_moment_commits.md) | **REGRESSION** | `+19.5%` | 0.84x | 1.04 | **1.25** | `13.9` | 1.05 ± 0.01 | 1.27 ± 0.04 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1287-L1314) [🔍 100p](slices/25_linked_array_list_b_tree_concat_slice.md) | **REGRESSION** | `+86.8%` | 0.54x | 1.06 | **1.98** | `27.2` | 1.06 ± 0.01 | 2.00 ± 0.09 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1668-L1705) [🔍 103p](slices/40_replication_incremental_1_moment_delta.md) | `~NOISE` | `+6.4%` | 0.94x | 1.05 | **1.12** | `2.2` | 1.05 ± 0.01 | 1.14 ± 0.10 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1707-L1727) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | `~NOISE` | `+0.6%` | 0.99x | 6.03 | **6.07** | `1.2` | 7.26 ± 2.13 | 6.27 ± 0.62 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1729-L1752) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | `~NOISE` | `+4.8%` | 0.95x | 13.0 | **13.6** | `0.6` | 13.4 ± 1.30 | 13.7 ± 0.77 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1754-L1815) [🔍 172p](slices/43_compaction_heterogeneous_dag_dedup.md) | `~NOISE` | `+8.2%` | 0.92x | 40.3 | **43.6** | `2.3` | 41.2 ± 2.22 | 45.3 ± 4.05 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1817-L1844) [🔍 55p](slices/44_replication_post_compaction_resync.md) | `~NOISE` | `+4.4%` | 0.96x | 1.35 | **1.41** | `0.5` | 1.49 ± 0.39 | 1.41 ± 0.05 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1980-L2019) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | `~NOISE` | `+8.3%` | 0.92x | 1.38 | **1.50** | `2.4` | 1.37 ± 0.02 | 1.72 ± 0.38 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L2236-L2265) [🔍 113p](slices/58_backend_core_memory_commits.md) | `~NOISE` | `+7.6%` | 0.93x | 1.09 | **1.17** | `5.5` | 1.10 ± 0.02 | 1.18 ± 0.03 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L2268-L2309) [🔍 114p](slices/59_backend_core_buffered_file_commits.md) | `~NOISE` | `+7.1%` | 0.93x | 14.4 | **15.4** | `5.9` | 14.4 ± 0.27 | 15.3 ± 0.31 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2312-L2348) [🔍 113p](slices/60_backend_core_file_unbuffered_commits.md) | `~NOISE` | `+6.4%` | 0.94x | 41.5 | **44.2** | `10.0` | 41.4 ± 0.48 | 44.2 ± 0.54 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2351-L2394) [🔍 108p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | `~NOISE` | `+7.7%` | 0.93x | 1.11 | **1.19** | `4.3` | 1.11 ± 0.03 | 1.18 ± 0.03 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2466-L2504) [🔍 113p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | `~NOISE` | `+3.7%` | 0.96x | 4.20 | **4.35** | `3.8` | 4.21 ± 0.07 | 4.37 ± 0.08 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2527-L2566) [🔍 185p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | `~NOISE` | `+1.5%` | 0.99x | 3.86 | **3.92** | `0.5` | 4.03 ± 0.43 | 3.94 ± 0.08 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2568-L2581) [🔍 173p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | `~NOISE` | `+6.7%` | 0.94x | 1.89 | **2.02** | `4.2` | 1.92 ± 0.06 | 2.01 ± 0.02 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2583-L2596) [🔍 133p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | `~NOISE` | `+2.5%` | 0.98x | 1.69 | **1.73** | `2.3` | 1.70 ± 0.04 | 1.76 ± 0.05 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2601-L2621) [🔍 176p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | `~NOISE` | `+6.2%` | 0.94x | 231.8 | **246.2** | `10.9` | 232.4 ± 2.10 | 247.9 ± 3.12 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2623-L2635) [🔍 110p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | `~NOISE` | `+2.9%` | 0.97x | 1.58 | **1.63** | `1.9` | 1.57 ± 0.05 | 1.64 ± 0.07 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2639-L2662) [🔍 158p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | `~NOISE` | `+1.4%` | 0.99x | 15.3 | **15.5** | `1.5` | 15.4 ± 0.25 | 15.6 ± 0.31 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2665-L2683) [🔍 158p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | `~NOISE` | `-4.8%` | 1.05x | 660.2 | **628.6** | `3.2` | 666.7 ± 13.6 | 637.1 ± 20.7 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2686-L2704) [🔍 158p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | `~NOISE` | `-7.0%` | 1.07x | 28.7 | **26.7** | `9.2` | 28.7 ± 0.46 | 26.8 ± 0.32 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2708-L2728) [🔍 112p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | `~NOISE` | `+4.1%` | 0.96x | 3.08 | **3.20** | `3.1` | 3.08 ± 0.03 | 3.25 ± 0.15 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2731-L2776) [🔍 218p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **REGRESSION** | `+16.2%` | 0.86x | 6.46 | **7.51** | `11.1` | 6.48 ± 0.06 | 7.57 ± 0.25 |


### 2. Odin Full Suite Results (`-o:speed -microarch:native`, Commit `69fb30701a3c`, 7 samples across 1 run(s))

#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 15 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L718-L737) [🔍 40p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **61** | 62 ± 1.7 | 2.7% | 15.6M | 16.7M | 3 | 64 | 64 | 60 | 64 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L804-L822) [🔍 49p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **47** | 47 ± 1.8 | 3.9% | 20.0M | 22.2M | 2 | 50 | 50 | 45 | 50 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L1056-L1073) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **49** | 53 ± 9.7 | 18.3% | 13.3M | 20.8M | 2 | 68 | 73 | 48 | 75 | 2K |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L1075-L1094) [🔍 50p](slices/16_array_list_radix_trie_iterator_scan.md) | **13** | 14 ± 2.5 | 18.3% | 52.6M | 83.3M | 1 | 18 | 19 | 12 | 19 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L1096-L1116) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **99** | 106 ± 18.7 | 17.6% | 6.8M | 10.5M | 4 | 135 | 145 | 95 | 148 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1213-L1232) [🔍 50p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **20** | 21 ± 2.6 | 12.3% | 38.5M | 52.6M | 1 | 25 | 26 | 19 | 26 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1438-L1455) [🔍 49p](slices/31_sorted_map_b_tree_ordered_scan.md) | **23** | 26 ± 9.4 | 35.8% | 20.8M | 45.5M | 2 | 41 | 46 | 22 | 48 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1900-L1928) [🔍 105p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **7** | 7 ± 2.2 | 29.6% | 83.3M | 167M | 0 | 11 | 12 | 6 | 12 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1930-L1942) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **11** | 13 ± 3.4 | 26.4% | 50.0M | 90.9M | 2 | 19 | 20 | 11 | 20 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1944-L1963) [🔍 85p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **7** | 8 ± 2.7 | 33.4% | 83.3M | 143M | 3 | 12 | 12 | 7 | 12 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1965-L1977) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **12** | 15 ± 4.4 | 30.1% | 45.5M | 90.9M | 6 | 21 | 22 | 11 | 22 | 10K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L2021-L2039) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **63** | 131 ± 122 | 93.1% | 2.9M | 17.9M | 115 | 320 | 335 | 56 | 339 | 256 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L2041-L2058) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **5** | 5 ± 1.6 | 29.9% | 125M | 250M | 2 | 8 | 8 | 4 | 8 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L2060-L2092) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **25** | 30 ± 7.9 | 26.6% | 24.4M | 41.7M | 10 | 41 | 41 | 24 | 41 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2421-L2438) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **63** | 63 ± 1.6 | 2.6% | 15.4M | 16.4M | 3 | 65 | 65 | 61 | 65 | 5K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 37 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L669-L696) [🔍 90p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **226** | 225 ± 6.5 | 2.9% | 4.3M | 4.6M | 12 | 231 | 231 | 216 | 231 | 2K |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L698-L716) [🔍 47p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **104** | 104 ± 1.9 | 1.8% | 9.3M | 9.8M | 2 | 107 | 107 | 102 | 107 | 2K |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L774-L802) [🔍 87p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **198** | 201 ± 13.1 | 6.5% | 4.4M | 5.3M | 7 | 220 | 227 | 189 | 229 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L824-L849) [🔍 90p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **245** | 250 ± 10.7 | 4.3% | 3.7M | 4.1M | 6 | 266 | 271 | 242 | 273 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L851-L877) [🔍 98p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **232** | 238 ± 11.5 | 4.8% | 3.8M | 4.3M | 9 | 257 | 260 | 230 | 261 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L879-L899) [🔍 84p](slices/09_hamt_counted_hash_map_remove.md) | **194** | 197 ± 7.0 | 3.6% | 4.8M | 5.2M | 10 | 208 | 209 | 191 | 209 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L901-L943) [🔍 87p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **234** | 235 ± 9.1 | 3.9% | 4.1M | 4.4M | 17 | 245 | 245 | 226 | 245 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L945-L967) [🔍 84p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **229** | 229 ± 5.8 | 2.6% | 4.2M | 4.5M | 7 | 237 | 238 | 223 | 239 | 500 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L969-L989) [🔍 86p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **250** | 252 ± 6.7 | 2.6% | 3.8M | 4.1M | 10 | 261 | 262 | 245 | 262 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L991-L1009) [🔍 50p](slices/13_hamt_counted_hash_set_membership_check.md) | **102** | 103 ± 3.2 | 3.1% | 9.2M | 10.0M | 2 | 108 | 109 | 100 | 109 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L1019-L1054) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **114** | 123 ± 25.6 | 20.8% | 5.5M | 9.1M | 4 | 162 | 177 | 110 | 181 | 2K |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L1118-L1134) [🔍 45p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **267** | 267 ± 4.6 | 1.7% | 3.6M | 3.8M | 4 | 273 | 274 | 261 | 275 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L1136-L1154) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **883** | 879 ± 32.2 | 3.7% | 1.1M | 1.2M | 29 | 923 | 934 | 836 | 937 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L1157-L1192) [🔍 109p](slices/20_linked_array_list_b_tree_append.md) | **272** | 271 ± 6.7 | 2.5% | 3.6M | 3.8M | 10 | 278 | 278 | 261 | 278 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1194-L1211) [🔍 43p](slices/21_linked_array_list_b_tree_random_get.md) | **250** | 251 ± 4.6 | 1.8% | 3.9M | 4.1M | 6 | 257 | 258 | 246 | 258 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1234-L1262) [🔍 94p](slices/23_linked_array_list_b_tree_middle_insert.md) | **306** | 306 ± 9.2 | 3.0% | 3.1M | 3.4M | 13 | 319 | 319 | 296 | 320 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1264-L1285) [🔍 94p](slices/24_linked_array_list_b_tree_middle_remove.md) | **414** | 419 ± 27.4 | 6.5% | 2.1M | 2.5M | 15 | 460 | 474 | 398 | 478 | 500 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1316-L1335) [🔍 88p](slices/26_linked_array_list_b_tree_in_place_put.md) | **206** | 205 ± 3.2 | 1.6% | 4.8M | 5.0M | 5 | 208 | 208 | 200 | 208 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1337-L1353) [🔍 45p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **512** | 513 ± 7.4 | 1.4% | 1.9M | 2.0M | 6 | 521 | 522 | 499 | 522 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1362-L1402) [🔍 128p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **454** | 521 ± 125 | 24.1% | 1.4M | 2.3M | 131 | 708 | 712 | 435 | 713 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1404-L1421) [🔍 51p](slices/29_sorted_map_b_tree_key_lookup.md) | **478** | 565 ± 142 | 25.2% | 1.3M | 2.2M | 186 | 774 | 782 | 455 | 784 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1423-L1436) [🔍 36p](slices/30_sorted_map_b_tree_rank_query.md) | **422** | 474 ± 118 | 25.0% | 1.4M | 2.6M | 102 | 662 | 690 | 390 | 698 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1457-L1474) [🔍 51p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **736** | 786 ± 142 | 18.1% | 905K | 1.4M | 36 | 1,003 | 1,084 | 713 | 1,105 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1476-L1504) [🔍 94p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **302** | 333 ± 107 | 32.1% | 1.7M | 3.6M | 20 | 494 | 559 | 279 | 575 | 1K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1506-L1520) [🔍 43p](slices/34_sorted_map_b_tree_get_index_select.md) | **358** | 395 ± 89.1 | 22.6% | 1.7M | 2.8M | 21 | 533 | 582 | 351 | 594 | 2K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1522-L1539) [🔍 46p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **607** | 683 ± 137 | 20.1% | 1.1M | 1.7M | 109 | 903 | 938 | 600 | 947 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1541-L1561) [🔍 107p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **430** | 513 ± 143 | 27.8% | 1.3M | 2.3M | 136 | 730 | 741 | 428 | 743 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1563-L1586) [🔍 107p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **407** | 472 ± 117 | 24.7% | 1.5M | 2.5M | 126 | 647 | 651 | 396 | 652 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1588-L1604) [🔍 50p](slices/38_sorted_set_b_tree_contains_lookup.md) | **462** | 538 ± 138 | 25.7% | 1.3M | 2.2M | 146 | 740 | 741 | 453 | 741 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1646-L1666) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **463** | 490 ± 75.2 | 15.3% | 1.5M | 2.2M | 20 | 606 | 648 | 449 | 659 | 200 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1874-L1897) [🔍 111p](slices/45_hasher_sha_1_20b_hamt_put.md) | **204** | 228 ± 43.3 | 19.0% | 3.3M | 5.0M | 42 | 295 | 300 | 201 | 301 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1874-L1897) [🔍 114p](slices/46_hasher_sha_256_32b_hamt_put.md) | **216** | 229 ± 36.4 | 15.9% | 3.2M | 4.8M | 6 | 284 | 305 | 207 | 311 | 2K |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L2095-L2150) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **232** | 276 ± 72.1 | 26.1% | 2.5M | 4.5M | 93 | 384 | 391 | 222 | 393 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L2152-L2175) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **253** | 295 ± 74.9 | 25.3% | 2.3M | 4.1M | 72 | 412 | 424 | 243 | 427 | 500 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L2178-L2213) [🔍 147p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **111** | 126 ± 26.8 | 21.4% | 6.1M | 9.3M | 30 | 165 | 165 | 107 | 165 | 2K |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2396-L2419) [🔍 85p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **677** | 669 ± 20.7 | 3.1% | 1.4M | 1.6M | 29 | 693 | 696 | 642 | 697 | 500 |
| 65 | [`DSL Layer 1: String Selector get_uint (N=500)`](bench_xitdb.odin#L2508-L2523) [🔍 94p](slices/65_dsl_layer_1_string_selector_get_uint_n_500.md) | **687** | 682 ± 10.0 | 1.5% | 1.4M | 1.5M | 12 | 691 | 692 | 665 | 692 | 500 |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 23 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L739-L772) [🔍 92p](slices/04_hamt_cow_branched_moment_commits.md) | **1.25** | 1.27 ± 0.04 | 3.3% | 749K | 818K | 0.06 | 1.33 | 1.33 | 1.22 | 1.34 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1287-L1314) [🔍 100p](slices/25_linked_array_list_b_tree_concat_slice.md) | **1.98** | 2.00 ± 0.09 | 4.5% | 467K | 522K | 0.14 | 2.13 | 2.14 | 1.92 | 2.14 | 400 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1668-L1705) [🔍 103p](slices/40_replication_incremental_1_moment_delta.md) | **1.12** | 1.14 ± 0.10 | 8.9% | 739K | 944K | 0.06 | 1.29 | 1.34 | 1.06 | 1.35 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1707-L1727) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **6.07** | 6.27 ± 0.62 | 9.8% | 139K | 176K | 0.93 | 7.13 | 7.16 | 5.68 | 7.17 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1729-L1752) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **13.6** | 13.7 ± 0.77 | 5.6% | 65.1K | 76.5K | 0.52 | 14.9 | 15.3 | 13.1 | 15.4 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1754-L1815) [🔍 172p](slices/43_compaction_heterogeneous_dag_dedup.md) | **43.6** | 45.3 ± 4.05 | 9.0% | 19.1K | 24.2K | 4.03 | 51.5 | 52.2 | 41.4 | 52.4 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1817-L1844) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **1.41** | 1.41 ± 0.05 | 3.7% | 661K | 739K | 0.05 | 1.49 | 1.51 | 1.35 | 1.51 | 1 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1980-L2019) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **1.50** | 1.72 ± 0.38 | 22.0% | 434K | 695K | 0.50 | 2.28 | 2.30 | 1.44 | 2.30 | 256 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L2236-L2265) [🔍 113p](slices/58_backend_core_memory_commits.md) | **1.17** | 1.18 ± 0.03 | 2.4% | 812K | 873K | 0.02 | 1.22 | 1.23 | 1.15 | 1.23 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L2268-L2309) [🔍 114p](slices/59_backend_core_buffered_file_commits.md) | **15.4** | 15.3 ± 0.31 | 2.0% | 63.0K | 66.8K | 0.33 | 15.8 | 15.8 | 15.0 | 15.9 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2312-L2348) [🔍 113p](slices/60_backend_core_file_unbuffered_commits.md) | **44.2** | 44.2 ± 0.54 | 1.2% | 22.3K | 23.2K | 0.46 | 44.8 | 44.8 | 43.2 | 44.8 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2351-L2394) [🔍 108p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **1.19** | 1.18 ± 0.03 | 2.3% | 824K | 873K | 0.04 | 1.21 | 1.21 | 1.15 | 1.21 | 500 |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2466-L2504) [🔍 113p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | **4.35** | 4.37 ± 0.08 | 1.9% | 220K | 232K | 0.05 | 4.50 | 4.54 | 4.31 | 4.54 | 500 |
| 66 | [`DSL Layer 3: Struct marshal (N=200)`](bench_xitdb.odin#L2527-L2566) [🔍 185p](slices/66_dsl_layer_3_struct_marshal_n_200.md) | **3.92** | 3.94 ± 0.08 | 2.0% | 244K | 258K | 0.07 | 4.07 | 4.09 | 3.88 | 4.10 | 200 |
| 67 | [`DSL Layer 3: Struct unmarshal (N=200)`](bench_xitdb.odin#L2568-L2581) [🔍 173p](slices/67_dsl_layer_3_struct_unmarshal_n_200.md) | **2.02** | 2.01 ± 0.02 | 1.1% | 489K | 505K | 0.02 | 2.04 | 2.05 | 1.98 | 2.05 | 200 |
| 68 | [`DSL Layer 3: Datomic pull projection (N=200)`](bench_xitdb.odin#L2583-L2596) [🔍 133p](slices/68_dsl_layer_3_datomic_pull_projection_n_200.md) | **1.73** | 1.76 ± 0.05 | 3.0% | 540K | 582K | 0.06 | 1.84 | 1.85 | 1.72 | 1.85 | 200 |
| 69 | [`DSL Layer 4: diff_moments (1 of 700 mutated)`](bench_xitdb.odin#L2601-L2621) [🔍 176p](slices/69_dsl_layer_4_diff_moments_1_of_700_mutated.md) | **246.2** | 247.9 ± 3.12 | 1.3% | 3.9K | 4.1K | 2.91 | 252.8 | 253.5 | 245.5 | 253.7 | 200 |
| 70 | [`DSL Layer 4: history_of lineage (3 moments)`](bench_xitdb.odin#L2623-L2635) [🔍 110p](slices/70_dsl_layer_4_history_of_lineage_3_moments.md) | **1.63** | 1.64 ± 0.07 | 4.3% | 577K | 656K | 0.08 | 1.72 | 1.73 | 1.52 | 1.73 | 200 |
| 71 | [`DSL Layer 5: Datalog B+Tree Prefix + Join`](bench_xitdb.odin#L2639-L2662) [🔍 158p](slices/71_dsl_layer_5_datalog_b_tree_prefix_join.md) | **15.5** | 15.6 ± 0.31 | 2.0% | 62.0K | 65.5K | 0.31 | 16.1 | 16.1 | 15.3 | 16.1 | 100 |
| 72 | [`DSL Layer 5: Datalog Grouped Aggs (N=500)`](bench_xitdb.odin#L2665-L2683) [🔍 158p](slices/72_dsl_layer_5_datalog_grouped_aggs_n_500.md) | **628.6** | 637.1 ± 20.7 | 3.2% | 1.5K | 1.6K | 23.7 | 666.5 | 672.8 | 615.1 | 674.4 | 25 |
| 73 | [`DSL Layer 5: Datalog Cycle-Safe reach (32-ring)`](bench_xitdb.odin#L2686-L2704) [🔍 158p](slices/73_dsl_layer_5_datalog_cycle_safe_reach_32_ring.md) | **26.7** | 26.8 ± 0.32 | 1.2% | 36.4K | 37.8K | 0.16 | 27.3 | 27.4 | 26.4 | 27.4 | 100 |
| 74 | [`DSL Layer 2: Secondary Index Evict+Update (N=200)`](bench_xitdb.odin#L2708-L2728) [🔍 112p](slices/74_dsl_layer_2_secondary_index_evict_update_n_200.md) | **3.20** | 3.25 ± 0.15 | 4.5% | 288K | 323K | 0.21 | 3.46 | 3.47 | 3.09 | 3.47 | 200 |
| 75 | [`DSL Layer 3/4: Cyclic Graph pull + diff (N=200)`](bench_xitdb.odin#L2731-L2776) [🔍 218p](slices/75_dsl_layer_3_4_cyclic_graph_pull_diff_n_200.md) | **7.51** | 7.57 ± 0.25 | 3.3% | 127K | 138K | 0.39 | 7.89 | 7.89 | 7.26 | 7.89 | 200 |


### 3. Zig Full Suite Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `69fb30701a3c`, 7 samples across 1 run(s))

#### 3.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 9 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.zig#L882-L896) [🔍 50p](slices/16_array_list_radix_trie_iterator_scan.md) | **53** | 51 ± 3.1 | 6.0% | 18.5M | 22.2M | 3 | 54 | 54 | 45 | 54 | 2K |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.zig#L1004-L1018) [🔍 50p](slices/22_linked_array_list_b_tree_iterator_scan.md) | **89** | 89 ± 10.4 | 11.7% | 9.7M | 14.3M | 9 | 101 | 103 | 70 | 103 | 2K |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.zig#L1206-L1219) [🔍 49p](slices/31_sorted_map_b_tree_ordered_scan.md) | **88** | 94 ± 21.3 | 22.8% | 7.2M | 14.3M | 9 | 126 | 136 | 70 | 138 | 2K |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1721-L1752) [🔍 105p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md) | **14** | 14 ± 2.9 | 21.0% | 55.6M | 111M | 3 | 17 | 18 | 9 | 18 | 10K |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.zig#L1754-L1763) [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md) | **62** | 60 ± 6.3 | 10.7% | 14.9M | 20.4M | 8 | 66 | 67 | 49 | 67 | 10K |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.zig#L1765-L1787) [🔍 85p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md) | **14** | 14 ± 2.1 | 15.3% | 62.5M | 100M | 3 | 16 | 16 | 10 | 16 | 10K |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.zig#L1789-L1798) [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md) | **90** | 86 ± 9.3 | 10.7% | 10.4M | 14.1M | 13 | 95 | 96 | 71 | 96 | 10K |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.zig#L1856-L1871) [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md) | **56** | 54 ± 8.1 | 15.1% | 16.7M | 26.3M | 10 | 60 | 60 | 38 | 60 | 2K |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.zig#L1873-L1900) [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md) | **59** | 58 ± 7.8 | 13.4% | 14.7M | 22.7M | 8 | 67 | 68 | 44 | 68 | 2K |

#### 3.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 13 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.zig#L539-L555) [🔍 47p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md) | **502** | 522 ± 152 | 29.1% | 1.2M | 2.7M | 159 | 740 | 791 | 364 | 804 | 2K |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.zig#L557-L574) [🔍 40p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md) | **321** | 315 ± 53.4 | 16.9% | 2.6M | 3.9M | 88 | 382 | 383 | 256 | 383 | 2K |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.zig#L632-L646) [🔍 49p](slices/06_hamt_hash_map_unordered_iterator_scan.md) | **238** | 237 ± 32.0 | 13.5% | 3.4M | 4.9M | 37 | 283 | 292 | 204 | 294 | 2K |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.zig#L786-L806) [🔍 86p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md) | **939** | 904 ± 154 | 17.0% | 914K | 1.5M | 209 | 1,073 | 1,090 | 657 | 1,094 | 2K |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.zig#L808-L824) [🔍 50p](slices/13_hamt_counted_hash_set_membership_check.md) | **417** | 451 ± 82.4 | 18.3% | 1.8M | 3.0M | 108 | 554 | 560 | 331 | 562 | 2K |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.zig#L834-L863) [🔍 91p](slices/14_array_list_radix_trie_append.md) | **357** | 395 ± 152 | 38.4% | 1.4M | 4.0M | 69 | 629 | 700 | 249 | 718 | 2K |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.zig#L865-L880) [🔍 30p](slices/15_array_list_radix_trie_random_get.md) | **186** | 193 ± 15.1 | 7.8% | 4.6M | 5.6M | 20 | 214 | 216 | 177 | 217 | 2K |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.zig#L898-L918) [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md) | **327** | 318 ± 29.0 | 9.1% | 2.9M | 3.9M | 21 | 341 | 342 | 258 | 342 | 2K |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.zig#L987-L1002) [🔍 43p](slices/21_linked_array_list_b_tree_random_get.md) | **200** | 578 ± 683 | 118.0% | 615K | 6.8M | 714 | 1,596 | 1,621 | 146 | 1,627 | 2K |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.zig#L1261-L1273) [🔍 43p](slices/34_sorted_map_b_tree_get_index_select.md) | **294** | 295 ± 28.1 | 9.5% | 2.9M | 4.1M | 15 | 330 | 337 | 245 | 339 | 2K |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.zig#L1838-L1854) [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md) | **396** | 460 ± 145 | 31.6% | 1.4M | 3.4M | 113 | 683 | 722 | 296 | 732 | 256 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.zig#L1975-L2018) [🔍 147p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md) | **452** | 469 ± 52.5 | 11.2% | 1.8M | 2.6M | 52 | 538 | 551 | 390 | 554 | 2K |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.zig#L2265-L2279) [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md) | **362** | 371 ± 37.3 | 10.1% | 2.2M | 3.0M | 29 | 428 | 443 | 338 | 447 | 5K |

#### 3.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 41 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L513-L537) [🔍 90p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | **1.33** | 1.33 ± 0.18 | 13.3% | 595K | 884K | 0.12 | 1.58 | 1.66 | 1.13 | 1.68 | 2K |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.zig#L576-L606) [🔍 92p](slices/04_hamt_cow_branched_moment_commits.md) | **3.93** | 4.37 ± 1.22 | 28.0% | 155K | 322K | 1.66 | 6.07 | 6.39 | 3.11 | 6.47 | 500 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.zig#L608-L630) [🔍 87p](slices/05_hamt_hash_map_remove_branch_shortening.md) | **1.60** | 1.59 ± 0.23 | 14.3% | 519K | 786K | 0.27 | 1.87 | 1.92 | 1.27 | 1.93 | 1K |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.zig#L648-L670) [🔍 90p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md) | **1.27** | 1.27 ± 0.18 | 14.5% | 645K | 1.0M | 0.19 | 1.50 | 1.54 | 0.98 | 1.55 | 2K |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.zig#L672-L700) [🔍 98p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md) | **1.34** | 1.30 ± 0.11 | 8.6% | 693K | 863K | 0.17 | 1.43 | 1.44 | 1.16 | 1.44 | 2K |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.zig#L702-L721) [🔍 84p](slices/09_hamt_counted_hash_map_remove.md) | **1.67** | 1.69 ± 0.16 | 9.5% | 517K | 682K | 0.19 | 1.90 | 1.93 | 1.47 | 1.93 | 1K |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.zig#L723-L761) [🔍 87p](slices/10_hamt_deep_suffix_collision_put_depth_10.md) | **1.99** | 1.94 ± 0.21 | 10.6% | 446K | 600K | 0.28 | 2.19 | 2.23 | 1.67 | 2.24 | 500 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.zig#L763-L784) [🔍 84p](slices/11_hamt_deep_suffix_collision_branch_collapse.md) | **4.13** | 4.20 ± 0.37 | 8.9% | 215K | 278K | 0.47 | 4.64 | 4.64 | 3.60 | 4.64 | 500 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.zig#L920-L933) [🔍 45p](slices/18_array_list_radix_trie_index_seek_page_10.md) | **2.41** | 2.41 ± 0.31 | 13.0% | 328K | 484K | 0.18 | 2.87 | 3.01 | 2.07 | 3.05 | 2K |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.zig#L935-L953) [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md) | **2.39** | 2.29 ± 0.30 | 13.2% | 381K | 533K | 0.49 | 2.60 | 2.62 | 1.88 | 2.62 | 500 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.zig#L956-L985) [🔍 109p](slices/20_linked_array_list_b_tree_append.md) | **3.01** | 3.00 ± 0.43 | 14.4% | 272K | 411K | 0.43 | 3.56 | 3.65 | 2.43 | 3.67 | 2K |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.zig#L1020-L1043) [🔍 94p](slices/23_linked_array_list_b_tree_middle_insert.md) | **3.32** | 3.35 ± 0.20 | 5.9% | 280K | 322K | 0.35 | 3.57 | 3.57 | 3.10 | 3.57 | 500 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.zig#L1045-L1066) [🔍 94p](slices/24_linked_array_list_b_tree_middle_remove.md) | **3.50** | 4.35 ± 2.65 | 60.8% | 97.1K | 376K | 0.24 | 8.30 | 9.90 | 2.66 | 10.3 | 500 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.zig#L1068-L1091) [🔍 100p](slices/25_linked_array_list_b_tree_concat_slice.md) | **31.4** | 35.1 ± 12.2 | 34.6% | 16.1K | 36.5K | 3.71 | 53.5 | 60.5 | 27.4 | 62.3 | 400 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.zig#L1093-L1112) [🔍 88p](slices/26_linked_array_list_b_tree_in_place_put.md) | **1.96** | 1.88 ± 0.18 | 9.3% | 490K | 643K | 0.21 | 2.03 | 2.04 | 1.56 | 2.04 | 2K |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.zig#L1114-L1127) [🔍 45p](slices/27_linked_array_list_b_tree_index_seek_page_10.md) | **3.34** | 3.31 ± 0.34 | 10.4% | 271K | 351K | 0.58 | 3.68 | 3.69 | 2.85 | 3.70 | 2K |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.zig#L1136-L1174) [🔍 128p](slices/28_sorted_map_b_tree_out_of_order_put.md) | **5.12** | 4.90 ± 0.51 | 10.3% | 181K | 236K | 0.81 | 5.45 | 5.51 | 4.24 | 5.52 | 2K |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.zig#L1176-L1191) [🔍 51p](slices/29_sorted_map_b_tree_key_lookup.md) | **3.50** | 3.32 ± 0.34 | 10.1% | 275K | 353K | 0.55 | 3.64 | 3.64 | 2.83 | 3.64 | 2K |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.zig#L1193-L1204) [🔍 36p](slices/30_sorted_map_b_tree_rank_query.md) | **3.04** | 3.14 ± 0.32 | 10.2% | 277K | 374K | 0.32 | 3.58 | 3.60 | 2.68 | 3.61 | 2K |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.zig#L1221-L1235) [🔍 51p](slices/32_sorted_map_b_tree_lower_bound_page_10.md) | **4.79** | 4.83 ± 0.37 | 7.6% | 187K | 226K | 0.55 | 5.32 | 5.35 | 4.43 | 5.35 | 2K |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.zig#L1237-L1259) [🔍 94p](slices/33_sorted_map_b_tree_remove_rebalance.md) | **5.26** | 5.11 ± 0.68 | 13.2% | 165K | 231K | 1.03 | 5.95 | 6.05 | 4.32 | 6.07 | 1K |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.zig#L1275-L1289) [🔍 46p](slices/35_sorted_map_b_tree_index_seek_page_10.md) | **4.36** | 4.34 ± 0.28 | 6.5% | 213K | 255K | 0.37 | 4.68 | 4.69 | 3.93 | 4.69 | 2K |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.zig#L1291-L1311) [🔍 107p](slices/36_sorted_map_b_tree_in_place_overwrite.md) | **3.88** | 4.02 ± 0.41 | 10.2% | 213K | 277K | 0.56 | 4.62 | 4.68 | 3.61 | 4.70 | 2K |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.zig#L1313-L1336) [🔍 107p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | **4.42** | 4.35 ± 0.62 | 14.3% | 197K | 287K | 1.01 | 5.02 | 5.06 | 3.48 | 5.07 | 2K |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.zig#L1338-L1352) [🔍 50p](slices/38_sorted_set_b_tree_contains_lookup.md) | **3.26** | 3.09 ± 0.41 | 13.4% | 286K | 403K | 0.67 | 3.48 | 3.49 | 2.48 | 3.49 | 2K |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.zig#L1388-L1411) [🔍 54p](slices/39_replication_genesis_200_moments.md) | **2.55** | 2.48 ± 0.21 | 8.4% | 361K | 449K | 0.31 | 2.72 | 2.76 | 2.23 | 2.77 | 200 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.zig#L1413-L1438) [🔍 103p](slices/40_replication_incremental_1_moment_delta.md) | **2.95** | 2.97 ± 0.27 | 9.2% | 297K | 368K | 0.42 | 3.36 | 3.37 | 2.72 | 3.37 | 100 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1440-L1458) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | **21.4** | 25.9 ± 8.40 | 32.4% | 24.5K | 54.3K | 11.0 | 37.9 | 40.2 | 18.4 | 40.8 | 1 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.zig#L1460-L1514) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | **40.6** | 40.8 ± 4.10 | 10.1% | 21.0K | 27.7K | 5.71 | 46.2 | 47.2 | 36.1 | 47.5 | 1 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.zig#L1516-L1603) [🔍 172p](slices/43_compaction_heterogeneous_dag_dedup.md) | **270.8** | 304.5 ± 147.0 | 48.3% | 1.6K | 4.8K | 68.7 | 528.9 | 608.6 | 207.1 | 628.5 | 1 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.zig#L1605-L1635) [🔍 55p](slices/44_replication_post_compaction_resync.md) | **2.80** | 2.97 ± 0.34 | 11.5% | 284K | 384K | 0.46 | 3.46 | 3.51 | 2.61 | 3.52 | 1 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.zig#L1656-L1686) [🔍 111p](slices/45_hasher_sha_1_20b_hamt_put.md) | **1.30** | 1.29 ± 0.22 | 16.7% | 641K | 974K | 0.35 | 1.54 | 1.56 | 1.03 | 1.56 | 2K |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.zig#L1689-L1718) [🔍 114p](slices/46_hasher_sha_256_32b_hamt_put.md) | **1.54** | 1.45 ± 0.22 | 15.2% | 580K | 892K | 0.30 | 1.70 | 1.72 | 1.12 | 1.72 | 2K |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.zig#L1801-L1836) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | **3.64** | 3.47 ± 0.29 | 8.5% | 263K | 331K | 0.37 | 3.75 | 3.79 | 3.02 | 3.80 | 256 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.zig#L1903-L1949) [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md) | **1.97** | 1.86 ± 0.25 | 13.5% | 474K | 713K | 0.30 | 2.10 | 2.11 | 1.40 | 2.11 | 500 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.zig#L1951-L1972) [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md) | **1.22** | 1.21 ± 0.10 | 8.6% | 751K | 947K | 0.12 | 1.32 | 1.33 | 1.06 | 1.33 | 500 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.zig#L2030-L2069) [🔍 113p](slices/58_backend_core_memory_commits.md) | **3.67** | 3.82 ± 0.57 | 14.8% | 201K | 298K | 0.52 | 4.70 | 4.92 | 3.36 | 4.97 | 500 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.zig#L2072-L2126) [🔍 114p](slices/59_backend_core_buffered_file_commits.md) | **27.1** | 27.1 ± 2.56 | 9.5% | 32.8K | 42.8K | 3.00 | 30.4 | 30.5 | 23.4 | 30.5 | 500 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.zig#L2129-L2178) [🔍 113p](slices/60_backend_core_file_unbuffered_commits.md) | **69.5** | 69.8 ± 6.49 | 9.3% | 12.9K | 16.5K | 10.00 | 77.4 | 77.5 | 60.7 | 77.6 | 500 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.zig#L2181-L2231) [🔍 108p](slices/61_tx_mid_tx_database_freeze_cow_clone.md) | **2.57** | 2.78 ± 0.55 | 19.8% | 251K | 418K | 0.24 | 3.63 | 3.92 | 2.39 | 3.99 | 500 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.zig#L2233-L2263) [🔍 85p](slices/62_tx_aborted_transaction_rollback_truncate.md) | **2.69** | 2.76 ± 0.37 | 13.3% | 283K | 413K | 0.27 | 3.32 | 3.49 | 2.42 | 3.53 | 500 |

### 4. 1v1 Statistical Comparison (Odin vs. Zig, Commit `69fb30701a3c`)

#### 4.1 Sub-100ns Fast Path (`ns`, 15 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | [`HAMT Hash_Map lookup (pre-hashed digest)`](bench_xitdb.odin#L718-L737) ([Zig](bench_xitdb.zig#L557-L574) · [🔍 40p](slices/03_hamt_hash_map_lookup_pre_hashed_digest.md)) | **5.26x** | **61** | 321 | `12.5` ★ | 62 ± 1.7 | 2.7% | 64 | 315 ± 53.4 | 16.9% | 382 |
| 6 | [`HAMT Hash_Map unordered iterator scan`](bench_xitdb.odin#L804-L822) ([Zig](bench_xitdb.zig#L632-L646) · [🔍 49p](slices/06_hamt_hash_map_unordered_iterator_scan.md)) | **5.06x** | **47** | 238 | `15.7` ★ | 47 ± 1.8 | 3.9% | 50 | 237 ± 32.0 | 13.5% | 283 |
| 15 | [`Array_List (Radix Trie) random get`](bench_xitdb.odin#L1056-L1073) ([Zig](bench_xitdb.zig#L865-L880) · [🔍 30p](slices/15_array_list_radix_trie_random_get.md)) | **3.80x** | **49** | 186 | `20.7` ★ | 53 ± 9.7 | 18.3% | 68 | 193 ± 15.1 | 7.8% | 214 |
| 16 | [`Array_List (Radix Trie) iterator scan`](bench_xitdb.odin#L1075-L1094) ([Zig](bench_xitdb.zig#L882-L896) · [🔍 50p](slices/16_array_list_radix_trie_iterator_scan.md)) | **4.08x** | **13** | 53 | `24.9` ★ | 14 ± 2.5 | 18.3% | 18 | 51 ± 3.1 | 6.0% | 54 |
| 17 | [`Array_List (Radix Trie) in-place put`](bench_xitdb.odin#L1096-L1116) ([Zig](bench_xitdb.zig#L898-L918) · [🔍 74p](slices/17_array_list_radix_trie_in_place_put.md)) | **3.30x** | **99** | 327 | `16.3` ★ | 106 ± 18.7 | 17.6% | 135 | 318 ± 29.0 | 9.1% | 341 |
| 22 | [`Linked_Array_List (B-Tree) iterator scan`](bench_xitdb.odin#L1213-L1232) ([Zig](bench_xitdb.zig#L1004-L1018) · [🔍 50p](slices/22_linked_array_list_b_tree_iterator_scan.md)) | **4.45x** | **20** | 89 | `16.8` ★ | 21 ± 2.6 | 12.3% | 25 | 89 ± 10.4 | 11.7% | 101 |
| 31 | [`Sorted_Map (B+Tree) ordered scan`](bench_xitdb.odin#L1438-L1455) ([Zig](bench_xitdb.zig#L1206-L1219) · [🔍 49p](slices/31_sorted_map_b_tree_ordered_scan.md)) | **3.83x** | **23** | 88 | `7.6` ★ | 26 ± 9.4 | 35.8% | 41 | 94 ± 21.3 | 22.8% | 126 |
| 47 | [`Bytes: Inline Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1900-L1928) ([Zig](bench_xitdb.zig#L1721-L1752) · [🔍 105p](slices/47_bytes_inline_short_bytes_read_bytes_buf.md)) | **2.00x** | **7** | 14 | `4.6` ★ | 7 ± 2.2 | 29.6% | 11 | 14 ± 2.9 | 21.0% | 17 |
| 48 | [`Bytes: External Bytes read_bytes_buf`](bench_xitdb.odin#L1930-L1942) ([Zig](bench_xitdb.zig#L1754-L1763) · [🔍 18p](slices/48_bytes_external_bytes_read_bytes_buf.md)) | **5.64x** | **11** | 62 | `17.1` ★ | 13 ± 3.4 | 26.4% | 19 | 60 ± 6.3 | 10.7% | 66 |
| 49 | [`Bytes: Tagged Short_Bytes read_bytes_buf`](bench_xitdb.odin#L1944-L1963) ([Zig](bench_xitdb.zig#L1765-L1787) · [🔍 85p](slices/49_bytes_tagged_short_bytes_read_bytes_buf.md)) | **2.00x** | **7** | 14 | `4.1` ★ | 8 ± 2.7 | 33.4% | 12 | 14 ± 2.1 | 15.3% | 16 |
| 50 | [`Bytes: Tagged External Bytes read_bytes_buf`](bench_xitdb.odin#L1965-L1977) ([Zig](bench_xitdb.zig#L1789-L1798) · [🔍 18p](slices/50_bytes_tagged_external_bytes_read_bytes_buf.md)) | **7.50x** | **12** | 90 | `18.4` ★ | 15 ± 4.4 | 30.1% | 21 | 86 ± 9.3 | 10.7% | 95 |
| 52 | [`Stream: Cursor_Reader (256 x 4KB = 1MB)`](bench_xitdb.odin#L2021-L2039) ([Zig](bench_xitdb.zig#L1838-L1854) · [🔍 21p](slices/52_stream_cursor_reader_256_x_4kb_1mb.md)) | **6.29x** | **63** | 396 | `4.6` ★ | 131 ± 122 | 93.1% | 320 | 460 ± 145 | 31.6% | 683 |
| 53 | [`Stream: Cursor_Reader random seek + 64B read`](bench_xitdb.odin#L2041-L2058) ([Zig](bench_xitdb.zig#L1856-L1871) · [🔍 8p](slices/53_stream_cursor_reader_random_seek_64b_read.md)) | **11.20x** | **5** | 56 | `15.5` ★ | 5 ± 1.6 | 29.9% | 8 | 54 ± 8.1 | 15.1% | 60 |
| 54 | [`Stream: Cursor_Writer random seek + 16B patch`](bench_xitdb.odin#L2060-L2092) ([Zig](bench_xitdb.zig#L1873-L1900) · [🔍 62p](slices/54_stream_cursor_writer_random_seek_16b_patch.md)) | **2.36x** | **25** | 59 | `6.7` ★ | 30 ± 7.9 | 26.6% | 41 | 58 ± 7.8 | 13.4% | 67 |
| 63 | [`DB: Re-open & trailer checksum verify`](bench_xitdb.odin#L2421-L2438) ([Zig](bench_xitdb.zig#L2265-L2279) · [🔍 47p](slices/63_db_re_open_trailer_checksum_verify.md)) | **5.75x** | **63** | 362 | `21.8` ★ | 63 ± 1.6 | 2.6% | 65 | 371 ± 37.3 | 10.1% | 428 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 36 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L669-L696) ([Zig](bench_xitdb.zig#L513-L537) · [🔍 90p](slices/01_hamt_hash_map_bulk_put_1_tx.md)) | **5.90x** | **226** | 1,333 | `16.5` ★ | 225 ± 6.5 | 2.9% | 231 | 1,330 ± 177 | 13.3% | 1,583 |
| 2 | [`HAMT Hash_Map point lookup (with SHA-1)`](bench_xitdb.odin#L698-L716) ([Zig](bench_xitdb.zig#L539-L555) · [🔍 47p](slices/02_hamt_hash_map_point_lookup_with_sha_1.md)) | **4.83x** | **104** | 502 | `7.3` ★ | 104 ± 1.9 | 1.8% | 107 | 522 ± 152 | 29.1% | 740 |
| 5 | [`HAMT Hash_Map remove & branch shortening`](bench_xitdb.odin#L774-L802) ([Zig](bench_xitdb.zig#L608-L630) · [🔍 87p](slices/05_hamt_hash_map_remove_branch_shortening.md)) | **8.06x** | **198** | 1,596 | `16.1` ★ | 201 ± 13.1 | 6.5% | 220 | 1,586 ± 227 | 14.3% | 1,869 |
| 7 | [`HAMT Hash_Map in-place overwrite (1 tx)`](bench_xitdb.odin#L824-L849) ([Zig](bench_xitdb.zig#L648-L670) · [🔍 90p](slices/07_hamt_hash_map_in_place_overwrite_1_tx.md)) | **5.20x** | **245** | 1,273 | `14.7` ★ | 250 ± 10.7 | 4.3% | 266 | 1,266 ± 183 | 14.5% | 1,495 |
| 8 | [`HAMT Counted_Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L851-L877) ([Zig](bench_xitdb.zig#L672-L700) · [🔍 98p](slices/08_hamt_counted_hash_map_bulk_put_1_tx.md)) | **5.77x** | **232** | 1,338 | `25.1` ★ | 238 ± 11.5 | 4.8% | 257 | 1,304 ± 112 | 8.6% | 1,430 |
| 9 | [`HAMT Counted_Hash_Map remove`](bench_xitdb.odin#L879-L899) ([Zig](bench_xitdb.zig#L702-L721) · [🔍 84p](slices/09_hamt_counted_hash_map_remove.md)) | **8.62x** | **194** | 1,673 | `24.5` ★ | 197 ± 7.0 | 3.6% | 208 | 1,685 ± 160 | 9.5% | 1,904 |
| 10 | [`HAMT deep suffix-collision put (depth 10+)`](bench_xitdb.odin#L901-L943) ([Zig](bench_xitdb.zig#L723-L761) · [🔍 87p](slices/10_hamt_deep_suffix_collision_put_depth_10.md)) | **8.51x** | **234** | 1,991 | `21.9` ★ | 235 ± 9.1 | 3.9% | 245 | 1,936 ± 206 | 10.6% | 2,189 |
| 11 | [`HAMT deep suffix-collision branch collapse`](bench_xitdb.odin#L945-L967) ([Zig](bench_xitdb.zig#L763-L784) · [🔍 84p](slices/11_hamt_deep_suffix_collision_branch_collapse.md)) | **18.03x** | **229** | 4,130 | `28.2` ★ | 229 ± 5.8 | 2.6% | 237 | 4,196 ± 372 | 8.9% | 4,636 |
| 12 | [`HAMT Counted_Hash_Set key-only put (1 tx)`](bench_xitdb.odin#L969-L989) ([Zig](bench_xitdb.zig#L786-L806) · [🔍 86p](slices/12_hamt_counted_hash_set_key_only_put_1_tx.md)) | **3.76x** | **250** | 939 | `11.2` ★ | 252 ± 6.7 | 2.6% | 261 | 904 ± 154 | 17.0% | 1,073 |
| 13 | [`HAMT Counted_Hash_Set membership check`](bench_xitdb.odin#L991-L1009) ([Zig](bench_xitdb.zig#L808-L824) · [🔍 50p](slices/13_hamt_counted_hash_set_membership_check.md)) | **4.09x** | **102** | 417 | `11.2` ★ | 103 ± 3.2 | 3.1% | 108 | 451 ± 82.4 | 18.3% | 554 |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L1019-L1054) ([Zig](bench_xitdb.zig#L834-L863) · [🔍 91p](slices/14_array_list_radix_trie_append.md)) | **3.13x** | **114** | 357 | `4.7` ★ | 123 ± 25.6 | 20.8% | 162 | 395 ± 152 | 38.4% | 629 |
| 18 | [`Array_List (Radix Trie) index-seek page(10)`](bench_xitdb.odin#L1118-L1134) ([Zig](bench_xitdb.zig#L920-L933) · [🔍 45p](slices/18_array_list_radix_trie_index_seek_page_10.md)) | **9.02x** | **267** | 2,409 | `18.1` ★ | 267 ± 4.6 | 1.7% | 273 | 2,411 ± 313 | 13.0% | 2,865 |
| 19 | [`Array_List (Radix Trie) depth-collapse slice`](bench_xitdb.odin#L1136-L1154) ([Zig](bench_xitdb.zig#L935-L953) · [🔍 73p](slices/19_array_list_radix_trie_depth_collapse_slice.md)) | **2.71x** | **883** | 2,389 | `12.3` ★ | 879 ± 32.2 | 3.7% | 923 | 2,294 ± 302 | 13.2% | 2,600 |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L1157-L1192) ([Zig](bench_xitdb.zig#L956-L985) · [🔍 109p](slices/20_linked_array_list_b_tree_append.md)) | **11.06x** | **272** | 3,008 | `16.7` ★ | 271 ± 6.7 | 2.5% | 278 | 2,998 ± 432 | 14.4% | 3,564 |
| 21 | [`Linked_Array_List (B-Tree) random get`](bench_xitdb.odin#L1194-L1211) ([Zig](bench_xitdb.zig#L987-L1002) · [🔍 43p](slices/21_linked_array_list_b_tree_random_get.md)) | 0.80x | 250 | **200** | `1.3` ~ | 251 ± 4.6 | 1.8% | 257 | 578 ± 683 | 118.0% | 1,596 |
| 23 | [`Linked_Array_List (B-Tree) middle insert`](bench_xitdb.odin#L1234-L1262) ([Zig](bench_xitdb.zig#L1020-L1043) · [🔍 94p](slices/23_linked_array_list_b_tree_middle_insert.md)) | **10.84x** | **306** | 3,317 | `40.6` ★ | 306 ± 9.2 | 3.0% | 319 | 3,348 ± 198 | 5.9% | 3,565 |
| 24 | [`Linked_Array_List (B-Tree) middle remove`](bench_xitdb.odin#L1264-L1285) ([Zig](bench_xitdb.zig#L1045-L1066) · [🔍 94p](slices/24_linked_array_list_b_tree_middle_remove.md)) | **8.46x** | **414** | 3,501 | `3.9` ★ | 419 ± 27.4 | 6.5% | 460 | 4,349 ± 2,645 | 60.8% | 8,299 |
| 26 | [`Linked_Array_List (B-Tree) in-place put`](bench_xitdb.odin#L1316-L1335) ([Zig](bench_xitdb.zig#L1093-L1112) · [🔍 88p](slices/26_linked_array_list_b_tree_in_place_put.md)) | **9.52x** | **206** | 1,962 | `25.2` ★ | 205 ± 3.2 | 1.6% | 208 | 1,879 ± 176 | 9.3% | 2,033 |
| 27 | [`Linked_Array_List (B-Tree) index-seek page(10)`](bench_xitdb.odin#L1337-L1353) ([Zig](bench_xitdb.zig#L1114-L1127) · [🔍 45p](slices/27_linked_array_list_b_tree_index_seek_page_10.md)) | **6.52x** | **512** | 3,339 | `21.6` ★ | 513 ± 7.4 | 1.4% | 521 | 3,306 ± 343 | 10.4% | 3,681 |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1362-L1402) ([Zig](bench_xitdb.zig#L1136-L1174) · [🔍 128p](slices/28_sorted_map_b_tree_out_of_order_put.md)) | **11.27x** | **454** | 5,115 | `22.3` ★ | 521 ± 125 | 24.1% | 708 | 4,904 ± 505 | 10.3% | 5,451 |
| 29 | [`Sorted_Map (B+Tree) key lookup`](bench_xitdb.odin#L1404-L1421) ([Zig](bench_xitdb.zig#L1176-L1191) · [🔍 51p](slices/29_sorted_map_b_tree_key_lookup.md)) | **7.32x** | **478** | 3,497 | `20.0` ★ | 565 ± 142 | 25.2% | 774 | 3,319 ± 336 | 10.1% | 3,640 |
| 30 | [`Sorted_Map (B+Tree) rank query`](bench_xitdb.odin#L1423-L1436) ([Zig](bench_xitdb.zig#L1193-L1204) · [🔍 36p](slices/30_sorted_map_b_tree_rank_query.md)) | **7.21x** | **422** | 3,041 | `20.7` ★ | 474 ± 118 | 25.0% | 662 | 3,140 ± 320 | 10.2% | 3,577 |
| 32 | [`Sorted_Map (B+Tree) lower-bound page(10)`](bench_xitdb.odin#L1457-L1474) ([Zig](bench_xitdb.zig#L1221-L1235) · [🔍 51p](slices/32_sorted_map_b_tree_lower_bound_page_10.md)) | **6.51x** | **736** | 4,790 | `27.2` ★ | 786 ± 142 | 18.1% | 1,003 | 4,830 ± 368 | 7.6% | 5,323 |
| 33 | [`Sorted_Map (B+Tree) remove & rebalance`](bench_xitdb.odin#L1476-L1504) ([Zig](bench_xitdb.zig#L1237-L1259) · [🔍 94p](slices/33_sorted_map_b_tree_remove_rebalance.md)) | **17.40x** | **302** | 5,255 | `18.5` ★ | 333 ± 107 | 32.1% | 494 | 5,110 ± 676 | 13.2% | 5,949 |
| 34 | [`Sorted_Map (B+Tree) get_index select`](bench_xitdb.odin#L1506-L1520) ([Zig](bench_xitdb.zig#L1261-L1273) · [🔍 43p](slices/34_sorted_map_b_tree_get_index_select.md)) | 0.82x | 358 | **294** | `2.8` ★ | 395 ± 89.1 | 22.6% | 533 | 295 ± 28.1 | 9.5% | 330 |
| 35 | [`Sorted_Map (B+Tree) index-seek page(10)`](bench_xitdb.odin#L1522-L1539) ([Zig](bench_xitdb.zig#L1275-L1289) · [🔍 46p](slices/35_sorted_map_b_tree_index_seek_page_10.md)) | **7.18x** | **607** | 4,361 | `30.7` ★ | 683 ± 137 | 20.1% | 903 | 4,337 ± 284 | 6.5% | 4,683 |
| 36 | [`Sorted_Map (B+Tree) in-place overwrite`](bench_xitdb.odin#L1541-L1561) ([Zig](bench_xitdb.zig#L1291-L1311) · [🔍 107p](slices/36_sorted_map_b_tree_in_place_overwrite.md)) | **9.02x** | **430** | 3,879 | `21.3` ★ | 513 ± 143 | 27.8% | 730 | 4,024 ± 412 | 10.2% | 4,620 |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1563-L1586) ([Zig](bench_xitdb.zig#L1313-L1336) · [🔍 107p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md)) | **10.86x** | **407** | 4,418 | `16.2` ★ | 472 ± 117 | 24.7% | 647 | 4,353 ± 621 | 14.3% | 5,020 |
| 38 | [`Sorted_Set (B+Tree) contains lookup`](bench_xitdb.odin#L1588-L1604) ([Zig](bench_xitdb.zig#L1338-L1352) · [🔍 50p](slices/38_sorted_set_b_tree_contains_lookup.md)) | **7.06x** | **462** | 3,263 | `15.5` ★ | 538 ± 138 | 25.7% | 740 | 3,094 ± 414 | 13.4% | 3,481 |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1646-L1666) ([Zig](bench_xitdb.zig#L1388-L1411) · [🔍 54p](slices/39_replication_genesis_200_moments.md)) | **5.51x** | **463** | 2,551 | `23.7` ★ | 490 ± 75.2 | 15.3% | 606 | 2,477 ± 208 | 8.4% | 2,723 |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1874-L1897) ([Zig](bench_xitdb.zig#L1656-L1686) · [🔍 111p](slices/45_hasher_sha_1_20b_hamt_put.md)) | **6.38x** | **204** | 1,301 | `12.8` ★ | 228 ± 43.3 | 19.0% | 295 | 1,292 ± 216 | 16.7% | 1,542 |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1874-L1897) ([Zig](bench_xitdb.zig#L1689-L1718) · [🔍 114p](slices/46_hasher_sha_256_32b_hamt_put.md)) | **7.11x** | **216** | 1,535 | `14.5` ★ | 229 ± 36.4 | 15.9% | 284 | 1,455 ± 220 | 15.2% | 1,703 |
| 55 | [`Path: 4-level nested cursor_write_path`](bench_xitdb.odin#L2095-L2150) ([Zig](bench_xitdb.zig#L1903-L1949) · [🔍 74p](slices/55_path_4_level_nested_cursor_write_path.md)) | **8.49x** | **232** | 1,970 | `16.0` ★ | 276 ± 72.1 | 26.1% | 384 | 1,860 ± 252 | 13.5% | 2,099 |
| 56 | [`Path: 4-level nested cursor_read_path`](bench_xitdb.odin#L2152-L2175) ([Zig](bench_xitdb.zig#L1951-L1972) · [🔍 26p](slices/56_path_4_level_nested_cursor_read_path.md)) | **4.82x** | **253** | 1,220 | `18.9` ★ | 295 ± 74.9 | 25.3% | 412 | 1,206 ± 103 | 8.6% | 1,316 |
| 57 | [`Cursor: Full KV-pair scan (read_kv_pair)`](bench_xitdb.odin#L2178-L2213) ([Zig](bench_xitdb.zig#L1975-L2018) · [🔍 147p](slices/57_cursor_full_kv_pair_scan_read_kv_pair.md)) | **4.07x** | **111** | 452 | `15.4` ★ | 126 ± 26.8 | 21.4% | 165 | 469 ± 52.5 | 11.2% | 538 |
| 62 | [`Tx: Aborted transaction rollback truncate`](bench_xitdb.odin#L2396-L2419) ([Zig](bench_xitdb.zig#L2233-L2263) · [🔍 85p](slices/62_tx_aborted_transaction_rollback_truncate.md)) | **3.98x** | **677** | 2,692 | `15.0` ★ | 669 ± 20.7 | 3.1% | 693 | 2,765 ± 368 | 13.3% | 3,320 |

#### 4.3 Multi-Microsecond Transactions & Compaction (`µs`, 12 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L739-L772) ([Zig](bench_xitdb.zig#L576-L606) · [🔍 92p](slices/04_hamt_cow_branched_moment_commits.md)) | **3.15x** | **1.25** | 3.93 | `6.7` ★ | 1.27 ± 0.04 | 3.3% | 1.33 | 4.37 ± 1.22 | 28.0% | 6.07 |
| 25 | [`Linked_Array_List (B-Tree) concat + slice`](bench_xitdb.odin#L1287-L1314) ([Zig](bench_xitdb.zig#L1068-L1091) · [🔍 100p](slices/25_linked_array_list_b_tree_concat_slice.md)) | **15.87x** | **1.98** | 31.4 | `7.2` ★ | 2.00 ± 0.09 | 4.5% | 2.13 | 35.1 ± 12.2 | 34.6% | 53.5 |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1668-L1705) ([Zig](bench_xitdb.zig#L1413-L1438) · [🔍 103p](slices/40_replication_incremental_1_moment_delta.md)) | **2.63x** | **1.12** | 2.95 | `16.6` ★ | 1.14 ± 0.10 | 8.9% | 1.29 | 2.97 ± 0.27 | 9.2% | 3.36 |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1707-L1727) ([Zig](bench_xitdb.zig#L1440-L1458) · [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md)) | **3.53x** | **6.07** | 21.4 | `6.2` ★ | 6.27 ± 0.62 | 9.8% | 7.13 | 25.9 ± 8.40 | 32.4% | 37.9 |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1729-L1752) ([Zig](bench_xitdb.zig#L1460-L1514) · [🔍 99p](slices/42_compaction_file_offset_map_200_1.md)) | **2.99x** | **13.6** | 40.6 | `17.1` ★ | 13.7 ± 0.77 | 5.6% | 14.9 | 40.8 ± 4.10 | 10.1% | 46.2 |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1754-L1815) ([Zig](bench_xitdb.zig#L1516-L1603) · [🔍 172p](slices/43_compaction_heterogeneous_dag_dedup.md)) | **6.21x** | **43.6** | 270.8 | `4.7` ★ | 45.3 ± 4.05 | 9.0% | 51.5 | 304.5 ± 147.0 | 48.3% | 528.9 |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1817-L1844) ([Zig](bench_xitdb.zig#L1605-L1635) · [🔍 55p](slices/44_replication_post_compaction_resync.md)) | **1.98x** | **1.41** | 2.80 | `11.9` ★ | 1.41 ± 0.05 | 3.7% | 1.49 | 2.97 ± 0.34 | 11.5% | 3.46 |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1980-L2019) ([Zig](bench_xitdb.zig#L1801-L1836) · [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md)) | **2.44x** | **1.50** | 3.64 | `9.6` ★ | 1.72 ± 0.38 | 22.0% | 2.28 | 3.47 ± 0.29 | 8.5% | 3.75 |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L2236-L2265) ([Zig](bench_xitdb.zig#L2030-L2069) · [🔍 113p](slices/58_backend_core_memory_commits.md)) | **3.13x** | **1.17** | 3.67 | `12.3` ★ | 1.18 ± 0.03 | 2.4% | 1.22 | 3.82 ± 0.57 | 14.8% | 4.70 |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L2268-L2309) ([Zig](bench_xitdb.zig#L2072-L2126) · [🔍 114p](slices/59_backend_core_buffered_file_commits.md)) | **1.76x** | **15.4** | 27.1 | `12.1` ★ | 15.3 ± 0.31 | 2.0% | 15.8 | 27.1 ± 2.56 | 9.5% | 30.4 |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2312-L2348) ([Zig](bench_xitdb.zig#L2129-L2178) · [🔍 113p](slices/60_backend_core_file_unbuffered_commits.md)) | **1.57x** | **44.2** | 69.5 | `10.4` ★ | 44.2 ± 0.54 | 1.2% | 44.8 | 69.8 ± 6.49 | 9.3% | 77.4 |
| 61 | [`Tx: Mid-tx database_freeze + CoW clone`](bench_xitdb.odin#L2351-L2394) ([Zig](bench_xitdb.zig#L2181-L2231) · [🔍 108p](slices/61_tx_mid_tx_database_freeze_cow_clone.md)) | **2.16x** | **1.19** | 2.57 | `7.7` ★ | 1.18 ± 0.03 | 2.3% | 1.21 | 2.78 ± 0.55 | 19.8% | 3.63 |

### 5. Database Storage Footprint (`bytes_used > 0`)

| # | Benchmark | Ops | Odin Size | Zig Size |
| ---: | :--- | ---: | ---: | ---: |
| 1 | [`HAMT Hash_Map bulk put (1 tx)`](bench_xitdb.odin#L669-L696) [🔍 90p](slices/01_hamt_hash_map_bulk_put_1_tx.md) | 2K | 214.5 KB | 214.5 KB |
| 4 | [`HAMT CoW branched moment commits`](bench_xitdb.odin#L739-L772) [🔍 92p](slices/04_hamt_cow_branched_moment_commits.md) | 500 | 457.7 KB | 457.7 KB |
| 14 | [`Array_List (Radix Trie) append`](bench_xitdb.odin#L1019-L1054) [🔍 91p](slices/14_array_list_radix_trie_append.md) | 2K | 19.3 KB | 19.3 KB |
| 20 | [`Linked_Array_List (B-Tree) append`](bench_xitdb.odin#L1157-L1192) [🔍 109p](slices/20_linked_array_list_b_tree_append.md) | 2K | 45.3 KB | 45.3 KB |
| 28 | [`Sorted_Map (B+Tree) out-of-order put`](bench_xitdb.odin#L1362-L1402) [🔍 128p](slices/28_sorted_map_b_tree_out_of_order_put.md) | 2K | 115.4 KB | 115.4 KB |
| 37 | [`Sorted_Set (B+Tree) key-only put (1 tx)`](bench_xitdb.odin#L1563-L1586) [🔍 107p](slices/37_sorted_set_b_tree_key_only_put_1_tx.md) | 2K | 80.0 KB | 80.0 KB |
| 39 | [`Replication (genesis -> 200 moments)`](bench_xitdb.odin#L1646-L1666) [🔍 54p](slices/39_replication_genesis_200_moments.md) | 200 | 250.9 KB | 250.9 KB |
| 40 | [`Replication (incremental 1-moment delta)`](bench_xitdb.odin#L1668-L1705) [🔍 103p](slices/40_replication_incremental_1_moment_delta.md) | 100 | 132.7 KB | 132.7 KB |
| 41 | [`Compaction (Memory_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1707-L1727) [🔍 100p](slices/41_compaction_memory_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 42 | [`Compaction (File_Offset_Map, 200 -> 1)`](bench_xitdb.odin#L1729-L1752) [🔍 99p](slices/42_compaction_file_offset_map_200_1.md) | 1 | 1.2 KB | 1.2 KB |
| 43 | [`Compaction (Heterogeneous DAG + dedup)`](bench_xitdb.odin#L1754-L1815) [🔍 172p](slices/43_compaction_heterogeneous_dag_dedup.md) | 1 | 23.4 KB | 23.4 KB |
| 44 | [`Replication (Post-compaction resync)`](bench_xitdb.odin#L1817-L1844) [🔍 55p](slices/44_replication_post_compaction_resync.md) | 1 | 23.4 KB | 23.4 KB |
| 45 | [`Hasher: SHA-1 (20B) HAMT put`](bench_xitdb.odin#L1874-L1897) [🔍 111p](slices/45_hasher_sha_1_20b_hamt_put.md) | 2K | 224.7 KB | 224.7 KB |
| 46 | [`Hasher: SHA-256 (32B) HAMT put`](bench_xitdb.odin#L1874-L1897) [🔍 114p](slices/46_hasher_sha_256_32b_hamt_put.md) | 2K | 248.7 KB | 248.7 KB |
| 51 | [`Stream: Cursor_Writer (256 x 4KB = 1MB)`](bench_xitdb.odin#L1980-L2019) [🔍 78p](slices/51_stream_cursor_writer_256_x_4kb_1mb.md) | 256 | 1024.1 KB | 1024.1 KB |
| 58 | [`Backend: Core_Memory commits`](bench_xitdb.odin#L2236-L2265) [🔍 113p](slices/58_backend_core_memory_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 59 | [`Backend: Core_Buffered_File commits`](bench_xitdb.odin#L2268-L2309) [🔍 114p](slices/59_backend_core_buffered_file_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 60 | [`Backend: Core_File (unbuffered) commits`](bench_xitdb.odin#L2312-L2348) [🔍 113p](slices/60_backend_core_file_unbuffered_commits.md) | 500 | 391.0 KB | 391.0 KB |
| 64 | [`DSL Layer 2: Tx Commit + Secondary Index (N=500)`](bench_xitdb.odin#L2466-L2504) [🔍 113p](slices/64_dsl_layer_2_tx_commit_secondary_index_n_500.md) | 500 | 231.4 KB | — |
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
