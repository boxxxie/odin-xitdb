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

<!-- BEGIN_BENCHMARK_TABLE -->
### 1. Odin Results (`-o:speed -microarch:native`, Commit `40c719e2b02d`, 5 samples across 1 run(s))

| # | Benchmark | Ops | Median (`ns`) | Mean ± σ (`ns`) | CV | IQR | `p95` / `p99` | Min..Max | `ops/sec` | Size |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | **220** | 220 ± 4.1 | 1.8% | 7 | 224 / 224 | 215..224 | 4,545,455 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | **103** | 106 ± 10.2 | 9.7% | 4 | 119 / 121 | 94..122 | 9,708,738 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | **65** | 66 ± 4.7 | 7.1% | 5 | 71 / 71 | 59..71 | 15,384,615 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | **1,046** | 1,100 ± 133 | 12.1% | 80 | 1,283 / 1,319 | 1,002..1,328 | 956,023 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | **179** | 195 ± 28.4 | 14.6% | 18 | 234 / 242 | 178..244 | 5,586,592 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | **44** | 45 ± 5.7 | 12.5% | 2 | 53 / 55 | 40..55 | 22,727,273 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | **227** | 236 ± 38.7 | 16.4% | 31 | 288 / 298 | 202..300 | 4,405,286 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | **225** | 243 ± 33.4 | 13.7% | 26 | 289 / 297 | 220..299 | 4,444,444 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | **194** | 195 ± 11.3 | 5.8% | 16 | 209 / 211 | 184..211 | 5,154,639 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | **198** | 206 ± 20.2 | 9.8% | 2 | 233 / 240 | 194..242 | 5,050,505 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | **222** | 224 ± 4.4 | 2.0% | 8 | 229 / 229 | 220..229 | 4,504,505 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | **243** | 252 ± 22.5 | 8.9% | 5 | 283 / 290 | 238..292 | 4,115,226 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | **105** | 107 ± 6.8 | 6.4% | 5 | 116 / 118 | 101..118 | 9,523,810 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | **127** | 123 ± 7.8 | 6.3% | 6 | 129 / 129 | 110..129 | 7,874,016 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | **54** | 53 ± 2.6 | 4.9% | 1 | 56 / 56 | 49..56 | 18,518,519 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | **14** | 14 ± 1.2 | 8.7% | 1 | 16 / 16 | 13..16 | 71,428,571 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | **105** | 101 ± 6.0 | 5.9% | 10 | 106 / 106 | 94..106 | 9,523,810 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | **405** | 392 ± 26.1 | 6.7% | 36 | 418 / 420 | 360..421 | 2,469,136 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | **794** | 831 ± 140 | 16.8% | 93 | 1,014 / 1,044 | 680..1,052 | 1,259,446 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | **260** | 261 ± 8.8 | 3.4% | 13 | 271 / 272 | 251..272 | 3,846,154 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | **62** | 65 ± 12.4 | 19.0% | 4 | 82 / 86 | 57..87 | 16,129,032 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | **16** | 16 ± 1.6 | 10.1% | 1 | 18 / 19 | 15..19 | 62,500,000 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | **301** | 298 ± 14.2 | 4.8% | 22 | 313 / 314 | 281..314 | 3,322,259 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | **366** | 369 ± 22.7 | 6.2% | 23 | 394 / 396 | 337..396 | 2,732,240 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | **914** | 932 ± 65.6 | 7.0% | 83 | 1,008 / 1,014 | 852..1,015 | 1,094,092 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | **178** | 200 ± 51.3 | 25.7% | 28 | 271 / 285 | 165..289 | 5,617,978 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | **425** | 472 ± 96.8 | 20.5% | 78 | 605 / 629 | 405..635 | 2,352,941 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | **410** | 413 ± 9.3 | 2.3% | 13 | 424 / 426 | 404..426 | 2,439,024 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | **174** | 176 ± 4.7 | 2.7% | 1 | 182 / 184 | 173..184 | 5,747,126 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | **139** | 142 ± 7.2 | 5.1% | 1 | 152 / 154 | 138..155 | 7,194,245 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | **14** | 14 ± 0.4 | 3.1% | 0 | 15 / 15 | 14..15 | 71,428,571 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | **487** | 488 ± 2.8 | 0.6% | 1 | 492 / 493 | 486..493 | 2,053,388 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | **260** | 260 ± 7.2 | 2.8% | 4 | 270 / 272 | 253..272 | 3,846,154 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | **70** | 72 ± 5.1 | 7.0% | 3 | 79 / 81 | 69..81 | 14,285,714 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | **430** | 431 ± 4.4 | 1.0% | 1 | 436 / 438 | 426..438 | 2,325,581 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | **400** | 400 ± 6.1 | 1.5% | 3 | 408 / 409 | 392..409 | 2,500,000 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | **369** | 369 ± 3.9 | 1.1% | 6 | 373 / 373 | 364..373 | 2,710,027 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | **155** | 158 ± 8.0 | 5.1% | 4 | 169 / 171 | 153..172 | 6,451,613 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | **120** | 127 ± 20.2 | 15.9% | 23 | 154 / 158 | 111..159 | 8,333,333 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | **813** | 821 ± 26.1 | 3.2% | 12 | 856 / 864 | 802..866 | 1,230,012 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | **4,769** | 4,929 ± 473 | 9.6% | 741 | 5,494 / 5,531 | 4,459..5,540 | 209,688 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | **10,640** | 10,822 ± 935 | 8.6% | 530 | 12,086 / 12,356 | 10,099..12,423 | 93,985 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | **136,776** | 138,195 ± 4,542 | 3.3% | 2,816 | 144,415 / 145,710 | 135,104..146,034 | 7,311 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | **1,613** | 1,635 ± 30.3 | 1.9% | 50 | 1,671 / 1,673 | 1,613..1,673 | 619,963 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | **237** | 238 ± 7.2 | 3.0% | 7 | 248 / 250 | 232..250 | 4,219,409 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | **244** | 246 ± 4.1 | 1.7% | 3 | 252 / 253 | 243..253 | 4,098,361 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | **6** | 6 ± 0.5 | 8.6% | 1 | 7 / 7 | 6..7 | 166,666,667 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | **10** | 10 ± 0.4 | 4.4% | 0 | 11 / 11 | 10..11 | 100,000,000 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | **7** | 8 ± 1.8 | 22.9% | 0 | 10 / 11 | 7..11 | 142,857,143 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | **10** | 10 ± 0.4 | 4.4% | 0 | 11 / 11 | 10..11 | 100,000,000 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | **308** | 333 ± 45.7 | 13.7% | 36 | 396 / 407 | 302..410 | 3,246,753 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | **56** | 56 ± 1.6 | 2.8% | 2 | 58 / 58 | 54..58 | 17,857,143 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | **7** | 7 ± 0.4 | 6.6% | 0 | 7 / 7 | 6..7 | 142,857,143 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | **15** | 15 ± 1.2 | 8.2% | 1 | 17 / 17 | 14..17 | 66,666,667 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | **244** | 244 ± 4.3 | 1.8% | 2 | 249 / 250 | 238..250 | 4,098,361 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | **160** | 158 ± 4.9 | 3.1% | 8 | 163 / 163 | 152..163 | 6,250,000 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | **104** | 105 ± 2.3 | 2.2% | 4 | 107 / 107 | 102..107 | 9,615,385 | — |
| 58 | `Backend: Core_Memory commits` | 500 | **1,254** | 1,277 ± 66.7 | 5.2% | 30 | 1,368 / 1,388 | 1,228..1,393 | 797,448 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | **4,769** | 4,852 ± 181 | 3.7% | 99 | 5,099 / 5,145 | 4,699..5,157 | 209,688 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | **46,979** | 47,784 ± 1,924 | 4.0% | 165 | 50,384 / 51,055 | 46,825..51,223 | 21,286 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | **1,170** | 1,160 ± 20.9 | 1.8% | 23 | 1,178 / 1,179 | 1,128..1,179 | 854,701 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | **685** | 679 ± 13.9 | 2.0% | 19 | 694 / 696 | 663..696 | 1,459,854 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | **58** | 59 ± 1.9 | 3.3% | 1 | 61 / 62 | 57..62 | 17,241,379 | — |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | 500 | **4,406** | 4,420 ± 33.9 | 0.8% | 44 | 4,462 / 4,466 | 4,385..4,467 | 226,963 | 231.4 KB |
| 65 | `DSL Layer 1: String Selector get_uint (N=500)` | 500 | **570** | 572 ± 6.5 | 1.1% | 6 | 581 / 582 | 565..582 | 1,754,386 | — |
| 66 | `DSL Layer 3: Struct marshal (N=200)` | 200 | **4,462** | 4,505 ± 123 | 2.7% | 204 | 4,651 / 4,659 | 4,387..4,661 | 224,115 | — |
| 67 | `DSL Layer 3: Struct unmarshal (N=200)` | 200 | **2,132** | 2,144 ± 44.4 | 2.1% | 5 | 2,203 / 2,217 | 2,106..2,221 | 469,043 | — |
| 68 | `DSL Layer 3: Datomic pull projection (N=200)` | 200 | **1,656** | 1,685 ± 51.8 | 3.1% | 35 | 1,756 / 1,770 | 1,651..1,773 | 603,865 | — |
| 69 | `DSL Layer 4: diff_moments (1 of 700 mutated)` | 200 | **280,944** | 281,413 ± 1,139 | 0.4% | 654 | 282,958 / 283,241 | 280,377..283,312 | 3,559 | — |
| 70 | `DSL Layer 4: history_of lineage (3 moments)` | 200 | **2,576** | 2,587 ± 109 | 4.2% | 83 | 2,717 / 2,735 | 2,442..2,739 | 388,199 | — |
| 71 | `DSL Layer 5: Datalog B+Tree Prefix + Join` | 100 | **15,207** | 15,203 ± 339 | 2.2% | 495 | 15,559 / 15,575 | 14,763..15,579 | 65,759 | — |
| 72 | `DSL Layer 5: Datalog Grouped Aggs (N=500)` | 25 | **589,105** | 589,689 ± 8,649 | 1.5% | 9,632 | 600,863 / 602,637 | 581,910..603,081 | 1,697 | — |
| 73 | `DSL Layer 5: Datalog Cycle-Safe reach (32-ring)` | 100 | **28,785** | 28,926 ± 365 | 1.3% | 667 | 29,331 / 29,339 | 28,586..29,341 | 34,740 | — |
| 74 | `DSL Layer 2: Secondary Index Evict+Update (N=200)` | 200 | **3,162** | 3,146 ± 67.1 | 2.1% | 97 | 3,215 / 3,219 | 3,059..3,220 | 316,256 | — |
| 75 | `DSL Layer 3/4: Cyclic Graph pull + diff (N=200)` | 200 | **7,394** | 7,375 ± 41.3 | 0.6% | 31 | 7,411 / 7,414 | 7,309..7,415 | 135,245 | — |

### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `40c719e2b02d`, 5 samples across 1 run(s))

| # | Benchmark | Ops | Median (`ns`) | Mean ± σ (`ns`) | CV | IQR | `p95` / `p99` | Min..Max | `ops/sec` | Size |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | **798** | 807 ± 18.0 | 2.2% | 34 | 827 / 827 | 792..827 | 1,253,133 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | **279** | 280 ± 2.3 | 0.8% | 4 | 283 / 283 | 278..283 | 3,584,229 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | **191** | 191 ± 1.9 | 1.0% | 1 | 193 / 194 | 189..194 | 5,235,602 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | **2,395** | 2,450 ± 104 | 4.3% | 73 | 2,594 / 2,621 | 2,384..2,628 | 417,537 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | **973** | 985 ± 18.7 | 1.9% | 19 | 1,010 / 1,014 | 972..1,015 | 1,027,749 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | **148** | 148 ± 0.5 | 0.4% | 1 | 148 / 148 | 147..148 | 6,756,757 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | **762** | 761 ± 13.6 | 1.8% | 20 | 777 / 779 | 747..779 | 1,312,336 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | **802** | 806 ± 11.1 | 1.4% | 9 | 822 / 824 | 798..825 | 1,246,883 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | **1,019** | 1,022 ± 15.4 | 1.5% | 4 | 1,042 / 1,047 | 1,007..1,048 | 981,354 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | **1,269** | 1,279 ± 19.9 | 1.6% | 17 | 1,306 / 1,311 | 1,265..1,312 | 788,022 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | **2,816** | 2,833 ± 31.1 | 1.1% | 30 | 2,875 / 2,881 | 2,808..2,883 | 355,114 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | **538** | 538 ± 6.3 | 1.2% | 5 | 545 / 546 | 529..546 | 1,858,736 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | **277** | 281 ± 10.5 | 3.7% | 3 | 296 / 299 | 275..300 | 3,610,108 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | **223** | 245 ± 42.0 | 17.1% | 37 | 302 / 311 | 210..313 | 4,484,305 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | **138** | 144 ± 17.7 | 12.3% | 7 | 168 / 174 | 131..175 | 7,246,377 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | **33** | 36 ± 5.4 | 15.1% | 2 | 43 / 45 | 32..45 | 30,303,030 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | **209** | 209 ± 14.2 | 6.8% | 12 | 227 / 229 | 192..230 | 4,784,689 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | **1,545** | 1,563 ± 67.0 | 4.3% | 105 | 1,644 / 1,651 | 1,500..1,653 | 647,249 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | **1,532** | 1,536 ± 95.8 | 6.2% | 100 | 1,658 / 1,676 | 1,437..1,681 | 652,742 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | **3,007** | 2,977 ± 95.6 | 3.2% | 142 | 3,075 / 3,082 | 2,859..3,084 | 332,557 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | **2,335** | 2,292 ± 114 | 5.0% | 161 | 2,414 / 2,428 | 2,164..2,431 | 428,266 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | **60** | 61 ± 0.9 | 1.5% | 1 | 62 / 62 | 60..62 | 16,666,667 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | **3,562** | 3,834 ± 389 | 10.1% | 677 | 4,274 / 4,282 | 3,532..4,284 | 280,741 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | **3,584** | 3,607 ± 79.1 | 2.2% | 6 | 3,713 / 3,738 | 3,538..3,744 | 279,018 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | **36,262** | 36,471 ± 558 | 1.5% | 693 | 37,171 / 37,241 | 35,888..37,259 | 27,577 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | **2,481** | 2,456 ± 105 | 4.3% | 56 | 2,567 / 2,583 | 2,298..2,587 | 403,063 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | **3,525** | 3,482 ± 90.9 | 2.6% | 85 | 3,549 / 3,551 | 3,333..3,551 | 283,688 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | **4,511** | 4,526 ± 59.1 | 1.3% | 37 | 4,606 / 4,623 | 4,481..4,627 | 221,680 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | **4,242** | 4,263 ± 41.9 | 1.0% | 32 | 4,320 / 4,330 | 4,231..4,333 | 235,738 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | **4,205** | 4,261 ± 121 | 2.8% | 75 | 4,429 / 4,463 | 4,185..4,471 | 237,812 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | **53** | 54 ± 2.4 | 4.4% | 2 | 57 / 58 | 52..58 | 18,867,925 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | **5,407** | 5,369 ± 110 | 2.1% | 33 | 5,457 / 5,466 | 5,180..5,468 | 184,945 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | **5,966** | 5,964 ± 31.2 | 0.5% | 36 | 5,997 / 5,999 | 5,920..6,000 | 167,616 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | **3,280** | 3,280 ± 24.9 | 0.8% | 21 | 3,312 / 3,317 | 3,252..3,318 | 304,878 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | **4,388** | 4,418 ± 81.7 | 1.8% | 29 | 4,530 / 4,555 | 4,358..4,561 | 227,894 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | **4,757** | 4,800 ± 94.2 | 2.0% | 34 | 4,930 / 4,959 | 4,739..4,966 | 210,217 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | **4,265** | 4,264 ± 18.4 | 0.4% | 27 | 4,281 / 4,281 | 4,238..4,281 | 234,467 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | **3,953** | 3,952 ± 12.0 | 0.3% | 12 | 3,967 / 3,969 | 3,939..3,970 | 252,972 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | **1,044** | 1,149 ± 256 | 22.3% | 328 | 1,478 / 1,514 | 912..1,523 | 957,854 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | **1,675** | 1,719 ± 69.9 | 4.1% | 90 | 1,811 / 1,821 | 1,669..1,824 | 597,015 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | **7,594** | 8,768 ± 2,769 | 31.6% | 1,693 | 12,519 / 13,188 | 6,232..13,355 | 131,683 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | **13,706** | 14,459 ± 1,934 | 13.4% | 1,102 | 17,114 / 17,641 | 12,965..17,773 | 72,961 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | **110,126** | 112,451 ± 8,848 | 7.9% | 12,324 | 123,634 / 124,851 | 104,196..125,155 | 9,081 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | **1,743** | 1,735 ± 41.2 | 2.4% | 30 | 1,778 / 1,783 | 1,673..1,784 | 573,723 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | **793** | 793 ± 6.2 | 0.8% | 4 | 801 / 803 | 787..803 | 1,261,034 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | **826** | 825 ± 8.2 | 1.0% | 8 | 832 / 833 | 812..833 | 1,210,654 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | **9** | 9 ± 0.9 | 9.5% | 0 | 11 / 11 | 9..11 | 111,111,111 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | **39** | 39 ± 1.6 | 4.1% | 2 | 41 / 41 | 37..41 | 25,641,026 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | **8** | 8 ± 1.1 | 13.4% | 0 | 10 / 10 | 7..10 | 125,000,000 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | **57** | 57 ± 1.1 | 2.0% | 1 | 58 / 58 | 55..58 | 17,543,860 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | **1,674** | 1,693 ± 55.8 | 3.3% | 31 | 1,769 / 1,783 | 1,643..1,787 | 597,372 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | **83** | 83 ± 2.1 | 2.5% | 1 | 84 / 84 | 79..84 | 12,048,193 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | **28** | 28 ± 0.4 | 1.6% | 0 | 29 / 29 | 28..29 | 35,714,286 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | **30** | 34 ± 7.4 | 21.4% | 5 | 45 / 47 | 30..47 | 33,333,333 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | **1,548** | 1,565 ± 37.0 | 2.4% | 48 | 1,612 / 1,617 | 1,530..1,618 | 645,995 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | **1,293** | 1,293 ± 9.7 | 0.8% | 9 | 1,305 / 1,307 | 1,283..1,308 | 773,395 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | **259** | 259 ± 1.9 | 0.7% | 2 | 262 / 262 | 257..262 | 3,861,004 | — |
| 58 | `Backend: Core_Memory commits` | 500 | **2,527** | 2,594 ± 155 | 6.0% | 5 | 2,803 / 2,858 | 2,521..2,872 | 395,726 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | **18,568** | 18,706 ± 631 | 3.4% | 448 | 19,556 / 19,719 | 18,166..19,760 | 53,856 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | **48,505** | 48,905 ± 974 | 2.0% | 1,342 | 50,158 / 50,293 | 48,071..50,327 | 20,616 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | **1,959** | 1,967 ± 86.9 | 4.4% | 135 | 2,072 / 2,082 | 1,885..2,085 | 510,465 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | **1,930** | 1,941 ± 31.7 | 1.6% | 23 | 1,984 / 1,991 | 1,912..1,993 | 518,135 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | **249** | 249 ± 3.9 | 1.6% | 6 | 253 / 253 | 244..253 | 4,016,064 | — |

### 3. 1v1 Statistical Comparison (Odin vs. Zig, Commit `40c719e2b02d`)

| # | Benchmark | Odin (`Med ± σ` · `CV` · `p95`) | Zig (`Med ± σ` · `CV` · `p95`) | Speedup | Welch $z$ | Size |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **220** ± 4.1 (`1.8%`, p95 `224`) | 798 ± 18.0 (`2.2%`, p95 `827`) | **3.63x** | `71.2` ★ | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **103** ± 10.2 (`9.7%`, p95 `119`) | 279 ± 2.3 (`0.8%`, p95 `283`) | **2.71x** | `37.1` ★ | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **65** ± 4.7 (`7.1%`, p95 `71`) | 191 ± 1.9 (`1.0%`, p95 `193`) | **2.94x** | `55.7` ★ | — |
| 4 | `HAMT CoW branched moment commits` | **1,046** ± 133 (`12.1%`, p95 `1,283`) | 2,395 ± 104 (`4.3%`, p95 `2,594`) | **2.29x** | `17.9` ★ | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | **179** ± 28.4 (`14.6%`, p95 `234`) | 973 ± 18.7 (`1.9%`, p95 `1,010`) | **5.44x** | `51.9` ★ | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | **44** ± 5.7 (`12.5%`, p95 `53`) | 148 ± 0.5 (`0.4%`, p95 `148`) | **3.36x** | `40.0` ★ | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **227** ± 38.7 (`16.4%`, p95 `288`) | 762 ± 13.6 (`1.8%`, p95 `777`) | **3.36x** | `28.6` ★ | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **225** ± 33.4 (`13.7%`, p95 `289`) | 802 ± 11.1 (`1.4%`, p95 `822`) | **3.56x** | `35.8` ★ | — |
| 9 | `HAMT Counted_Hash_Map remove` | **194** ± 11.3 (`5.8%`, p95 `209`) | 1,019 ± 15.4 (`1.5%`, p95 `1,042`) | **5.25x** | `96.7` ★ | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **198** ± 20.2 (`9.8%`, p95 `233`) | 1,269 ± 19.9 (`1.6%`, p95 `1,306`) | **6.41x** | `84.5` ★ | — |
| 11 | `HAMT deep suffix-collision branch collapse` | **222** ± 4.4 (`2.0%`, p95 `229`) | 2,816 ± 31.1 (`1.1%`, p95 `2,875`) | **12.68x** | `185.5` ★ | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **243** ± 22.5 (`8.9%`, p95 `283`) | 538 ± 6.3 (`1.2%`, p95 `545`) | **2.21x** | `27.3` ★ | — |
| 13 | `HAMT Counted_Hash_Set membership check` | **105** ± 6.8 (`6.4%`, p95 `116`) | 277 ± 10.5 (`3.7%`, p95 `296`) | **2.64x** | `31.2` ★ | — |
| 14 | `Array_List (Radix Trie) append` | **127** ± 7.8 (`6.3%`, p95 `129`) | 223 ± 42.0 (`17.1%`, p95 `302`) | **1.76x** | `6.4` ★ | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | **54** ± 2.6 (`4.9%`, p95 `56`) | 138 ± 17.7 (`12.3%`, p95 `168`) | **2.56x** | `11.4` ★ | — |
| 16 | `Array_List (Radix Trie) iterator scan` | **14** ± 1.2 (`8.7%`, p95 `16`) | 33 ± 5.4 (`15.1%`, p95 `43`) | **2.36x** | `8.8` ★ | — |
| 17 | `Array_List (Radix Trie) in-place put` | **105** ± 6.0 (`5.9%`, p95 `106`) | 209 ± 14.2 (`6.8%`, p95 `227`) | **1.99x** | `15.7` ★ | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **405** ± 26.1 (`6.7%`, p95 `418`) | 1,545 ± 67.0 (`4.3%`, p95 `1,644`) | **3.81x** | `36.4` ★ | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **794** ± 140 (`16.8%`, p95 `1,014`) | 1,532 ± 95.8 (`6.2%`, p95 `1,658`) | **1.93x** | `9.3` ★ | — |
| 20 | `Linked_Array_List (B-Tree) append` | **260** ± 8.8 (`3.4%`, p95 `271`) | 3,007 ± 95.6 (`3.2%`, p95 `3,075`) | **11.57x** | `63.3` ★ | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | **62** ± 12.4 (`19.0%`, p95 `82`) | 2,335 ± 114 (`5.0%`, p95 `2,414`) | **37.66x** | `43.5` ★ | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **16** ± 1.6 (`10.1%`, p95 `18`) | 60 ± 0.9 (`1.5%`, p95 `62`) | **3.75x** | `53.1` ★ | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **301** ± 14.2 (`4.8%`, p95 `313`) | 3,562 ± 389 (`10.1%`, p95 `4,274`) | **11.83x** | `20.3` ★ | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **366** ± 22.7 (`6.2%`, p95 `394`) | 3,584 ± 79.1 (`2.2%`, p95 `3,713`) | **9.79x** | `87.9` ★ | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **914** ± 65.6 (`7.0%`, p95 `1,008`) | 36,262 ± 558 (`1.5%`, p95 `37,171`) | **39.67x** | `141.5` ★ | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **178** ± 51.3 (`25.7%`, p95 `271`) | 2,481 ± 105 (`4.3%`, p95 `2,567`) | **13.94x** | `43.1` ★ | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **425** ± 96.8 (`20.5%`, p95 `605`) | 3,525 ± 90.9 (`2.6%`, p95 `3,549`) | **8.29x** | `50.7` ★ | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **410** ± 9.3 (`2.3%`, p95 `424`) | 4,511 ± 59.1 (`1.3%`, p95 `4,606`) | **11.00x** | `153.7` ★ | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | **174** ± 4.7 (`2.7%`, p95 `182`) | 4,242 ± 41.9 (`1.0%`, p95 `4,320`) | **24.38x** | `216.5` ★ | — |
| 30 | `Sorted_Map (B+Tree) rank query` | **139** ± 7.2 (`5.1%`, p95 `152`) | 4,205 ± 121 (`2.8%`, p95 `4,429`) | **30.25x** | `75.8` ★ | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **14** ± 0.4 (`3.1%`, p95 `15`) | 53 ± 2.4 (`4.4%`, p95 `57`) | **3.79x** | `36.8` ★ | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **487** ± 2.8 (`0.6%`, p95 `492`) | 5,407 ± 110 (`2.1%`, p95 `5,457`) | **11.10x** | `98.8` ★ | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **260** ± 7.2 (`2.8%`, p95 `270`) | 5,966 ± 31.2 (`0.5%`, p95 `5,997`) | **22.95x** | `398.3` ★ | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | **70** ± 5.1 (`7.0%`, p95 `79`) | 3,280 ± 24.9 (`0.8%`, p95 `3,312`) | **46.86x** | `281.8` ★ | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **430** ± 4.4 (`1.0%`, p95 `436`) | 4,388 ± 81.7 (`1.8%`, p95 `4,530`) | **10.20x** | `109.0` ★ | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **400** ± 6.1 (`1.5%`, p95 `408`) | 4,757 ± 94.2 (`2.0%`, p95 `4,930`) | **11.89x** | `104.2` ★ | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **369** ± 3.9 (`1.1%`, p95 `373`) | 4,265 ± 18.4 (`0.4%`, p95 `4,281`) | **11.56x** | `462.9` ★ | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **155** ± 8.0 (`5.1%`, p95 `169`) | 3,953 ± 12.0 (`0.3%`, p95 `3,967`) | **25.50x** | `589.3` ★ | — |
| 39 | `Replication (genesis -> 200 moments)` | **120** ± 20.2 (`15.9%`, p95 `154`) | 1,044 ± 256 (`22.3%`, p95 `1,478`) | **8.70x** | `8.9` ★ | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | **813** ± 26.1 (`3.2%`, p95 `856`) | 1,675 ± 69.9 (`4.1%`, p95 `1,811`) | **2.06x** | `26.9` ★ | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **4,769** ± 473 (`9.6%`, p95 `5,494`) | 7,594 ± 2,769 (`31.6%`, p95 `12,519`) | **1.59x** | `3.1` ★ | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **10,640** ± 935 (`8.6%`, p95 `12,086`) | 13,706 ± 1,934 (`13.4%`, p95 `17,114`) | **1.29x** | `3.8` ★ | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 136,776 ± 4,542 (`3.3%`, p95 `144,415`) | **110,126** ± 8,848 (`7.9%`, p95 `123,634`) | 0.81x | `5.8` ★ | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | **1,613** ± 30.3 (`1.9%`, p95 `1,671`) | 1,743 ± 41.2 (`2.4%`, p95 `1,778`) | **1.08x** | `4.4` ★ | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **237** ± 7.2 (`3.0%`, p95 `248`) | 793 ± 6.2 (`0.8%`, p95 `801`) | **3.35x** | `130.5` ★ | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **244** ± 4.1 (`1.7%`, p95 `252`) | 826 ± 8.2 (`1.0%`, p95 `832`) | **3.39x** | `141.5` ★ | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **6** ± 0.5 (`8.6%`, p95 `7`) | 9 ± 0.9 (`9.5%`, p95 `11`) | **1.50x** | `6.4` ★ | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | **10** ± 0.4 (`4.4%`, p95 `11`) | 39 ± 1.6 (`4.1%`, p95 `41`) | **3.90x** | `39.2` ★ | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **7** ± 1.8 (`22.9%`, p95 `10`) | 8 ± 1.1 (`13.4%`, p95 `10`) | **1.14x** | `0.4` ~ | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **10** ± 0.4 (`4.4%`, p95 `11`) | 57 ± 1.1 (`2.0%`, p95 `58`) | **5.70x** | `84.7` ★ | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **308** ± 45.7 (`13.7%`, p95 `396`) | 1,674 ± 55.8 (`3.3%`, p95 `1,769`) | **5.44x** | `42.2` ★ | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **56** ± 1.6 (`2.8%`, p95 `58`) | 83 ± 2.1 (`2.5%`, p95 `84`) | **1.48x** | `22.8` ★ | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **7** ± 0.4 (`6.6%`, p95 `7`) | 28 ± 0.4 (`1.6%`, p95 `29`) | **4.00x** | `75.7` ★ | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **15** ± 1.2 (`8.2%`, p95 `17`) | 30 ± 7.4 (`21.4%`, p95 `45`) | **2.00x** | `5.8` ★ | — |
| 55 | `Path: 4-level nested cursor_write_path` | **244** ± 4.3 (`1.8%`, p95 `249`) | 1,548 ± 37.0 (`2.4%`, p95 `1,612`) | **6.34x** | `79.3` ★ | — |
| 56 | `Path: 4-level nested cursor_read_path` | **160** ± 4.9 (`3.1%`, p95 `163`) | 1,293 ± 9.7 (`0.8%`, p95 `1,305`) | **8.08x** | `232.9` ★ | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **104** ± 2.3 (`2.2%`, p95 `107`) | 259 ± 1.9 (`0.7%`, p95 `262`) | **2.49x** | `115.2` ★ | — |
| 58 | `Backend: Core_Memory commits` | **1,254** ± 66.7 (`5.2%`, p95 `1,368`) | 2,527 ± 155 (`6.0%`, p95 `2,803`) | **2.02x** | `17.4` ★ | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | **4,769** ± 181 (`3.7%`, p95 `5,099`) | 18,568 ± 631 (`3.4%`, p95 `19,556`) | **3.89x** | `47.2` ★ | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | **46,979** ± 1,924 (`4.0%`, p95 `50,384`) | 48,505 ± 974 (`2.0%`, p95 `50,158`) | **1.03x** | `1.2` ~ | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1,170** ± 20.9 (`1.8%`, p95 `1,178`) | 1,959 ± 86.9 (`4.4%`, p95 `2,072`) | **1.67x** | `20.2` ★ | — |
| 62 | `Tx: Aborted transaction rollback truncate` | **685** ± 13.9 (`2.0%`, p95 `694`) | 1,930 ± 31.7 (`1.6%`, p95 `1,984`) | **2.82x** | `81.5` ★ | — |
| 63 | `DB: Re-open & trailer checksum verify` | **58** ± 1.9 (`3.3%`, p95 `61`) | 249 ± 3.9 (`1.6%`, p95 `253`) | **4.29x** | `97.9` ★ | — |

### 4. Commit-vs-Commit Progression (`2d6f9a7120f3` → `40c719e2b02d`, Odin)

| # | Benchmark | Baseline `2d6f9a7` (`Med ± σ`) | Current `40c719e` (`Med ± σ`) | Delta (%) | Speedup | Welch $z$ | Verdict |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | :--- |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 202 ± 86.3 | **220** ± 4.1 | `+8.9%` | 0.92x | `0.5` | `~NOISE` |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 95 ± 31.4 | **103** ± 10.2 | `+8.4%` | 0.92x | `0.2` | `~NOISE` |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 60 ± 27.4 | **65** ± 4.7 | `+8.3%` | 0.92x | `0.9` | `~NOISE` |
| 4 | `HAMT CoW branched moment commits` | 923 ± 307 | **1,046** ± 133 | `+13.3%` | 0.88x | `0.3` | `~NOISE` |
| 5 | `HAMT Hash_Map remove & branch shortening` | 167 ± 16.6 | **179** ± 28.4 | `+7.2%` | 0.93x | `1.5` | `~NOISE` |
| 6 | `HAMT Hash_Map unordered iterator scan` | 37 ± 0.8 | **44** ± 5.7 | `+18.9%` | 0.84x | `3.3` | **REGRESSION** |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 192 ± 16.6 | **227** ± 38.7 | `+18.2%` | 0.85x | `1.9` | `~NOISE` |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 210 ± 22.8 | **225** ± 33.4 | `+7.1%` | 0.93x | `1.4` | `~NOISE` |
| 9 | `HAMT Counted_Hash_Map remove` | 165 ± 11.7 | **194** ± 11.3 | `+17.6%` | 0.85x | `3.2` | **REGRESSION** |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 193 ± 24.8 | **198** ± 20.2 | `+2.6%` | 0.97x | `0.3` | `~NOISE` |
| 11 | `HAMT deep suffix-collision branch collapse` | 211 ± 3.8 | **222** ± 4.4 | `+5.2%` | 0.95x | `4.7` | **REGRESSION** |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 222 ± 32.9 | **243** ± 22.5 | `+9.5%` | 0.91x | `0.9` | `~NOISE` |
| 13 | `HAMT Counted_Hash_Set membership check` | 91 ± 1.5 | **105** ± 6.8 | `+15.4%` | 0.87x | `4.9` | **REGRESSION** |
| 14 | `Array_List (Radix Trie) append` | 108 ± 0.9 | **127** ± 7.8 | `+17.6%` | 0.85x | `4.1` | **REGRESSION** |
| 15 | `Array_List (Radix Trie) random get` | 46 ± 0.5 | **54** ± 2.6 | `+17.4%` | 0.85x | `5.7` | **REGRESSION** |
| 16 | `Array_List (Radix Trie) iterator scan` | 13 ± 0.5 | **14** ± 1.2 | `+7.7%` | 0.93x | `2.3` | `~NOISE` |
| 17 | `Array_List (Radix Trie) in-place put` | 89 ± 1.1 | **105** ± 6.0 | `+18.0%` | 0.85x | `4.3` | **REGRESSION** |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 347 ± 6.3 | **405** ± 26.1 | `+16.7%` | 0.86x | `3.5` | **REGRESSION** |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 701 ± 8.6 | **794** ± 140 | `+13.3%` | 0.88x | `2.1` | **REGRESSION** |
| 20 | `Linked_Array_List (B-Tree) append` | 231 ± 4.5 | **260** ± 8.8 | `+12.6%` | 0.89x | `6.9` | **REGRESSION** |
| 21 | `Linked_Array_List (B-Tree) random get` | 53 ± 0.9 | **62** ± 12.4 | `+17.0%` | 0.85x | `2.1` | **REGRESSION** |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 13 ± 0.5 | **16** ± 1.6 | `+23.1%` | 0.81x | `3.6` | **REGRESSION** |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 258 ± 2.9 | **301** ± 14.2 | `+16.7%` | 0.86x | `6.1` | **REGRESSION** |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 349 ± 6.4 | **366** ± 22.7 | `+4.9%` | 0.95x | `1.8` | `~NOISE` |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 807 ± 13.1 | **914** ± 65.6 | `+13.3%` | 0.88x | `4.0` | **REGRESSION** |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 161 ± 1.9 | **178** ± 51.3 | `+10.6%` | 0.90x | `1.7` | `~NOISE` |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 394 ± 2.3 | **425** ± 96.8 | `+7.9%` | 0.93x | `1.8` | `~NOISE` |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 388 ± 1.7 | **410** ± 9.3 | `+5.7%` | 0.95x | `6.0` | **REGRESSION** |
| 29 | `Sorted_Map (B+Tree) key lookup` | 163 ± 1.0 | **174** ± 4.7 | `+6.7%` | 0.94x | `5.8` | **REGRESSION** |
| 30 | `Sorted_Map (B+Tree) rank query` | 131 ± 0.7 | **139** ± 7.2 | `+6.1%` | 0.94x | `3.5` | **REGRESSION** |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 13 ± 0.0 | **14** ± 0.4 | `+7.7%` | 0.93x | `6.0` | `~NOISE` |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 466 ± 1.5 | **487** ± 2.8 | `+4.5%` | 0.96x | `16.1` | **REGRESSION** |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 230 ± 2.6 | **260** ± 7.2 | `+13.0%` | 0.88x | `8.6` | **REGRESSION** |
| 34 | `Sorted_Map (B+Tree) get_index select` | 64 ± 1.3 | **70** ± 5.1 | `+9.4%` | 0.91x | `3.2` | **REGRESSION** |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 401 ± 1.5 | **430** ± 4.4 | `+7.2%` | 0.93x | `14.0` | **REGRESSION** |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 362 ± 1.3 | **400** ± 6.1 | `+10.5%` | 0.91x | `13.8` | **REGRESSION** |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 343 ± 2.0 | **369** ± 3.9 | `+7.6%` | 0.93x | `13.4` | **REGRESSION** |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 144 ± 0.9 | **155** ± 8.0 | `+7.6%` | 0.93x | `3.7` | **REGRESSION** |
| 39 | `Replication (genesis -> 200 moments)` | 104 ± 11.2 | **120** ± 20.2 | `+15.4%` | 0.87x | `1.9` | `~NOISE` |
| 40 | `Replication (incremental 1-moment delta)` | 743 ± 17.9 | **813** ± 26.1 | `+9.4%` | 0.91x | `4.8` | **REGRESSION** |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 3,707 ± 324 | **4,769** ± 473 | `+28.6%` | 0.78x | `4.0` | **REGRESSION** |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 9,347 ± 481 | **10,640** ± 935 | `+13.8%` | 0.88x | `2.8` | **REGRESSION** |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 126,618 ± 4,396 | **136,776** ± 4,542 | `+8.0%` | 0.93x | `4.2` | **REGRESSION** |
| 44 | `Replication (Post-compaction resync)` | 1,462 ± 36.7 | **1,613** ± 30.3 | `+10.3%` | 0.91x | `8.1` | **REGRESSION** |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 223 ± 2.9 | **237** ± 7.2 | `+6.3%` | 0.94x | `4.5` | **REGRESSION** |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 233 ± 2.5 | **244** ± 4.1 | `+4.7%` | 0.95x | `6.0` | **REGRESSION** |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 6 ± 0.0 | **6** ± 0.5 | `+0.0%` | 1.00x | `1.6` | `~NOISE` |
| 48 | `Bytes: External Bytes read_bytes_buf` | 9 ± 0.0 | **10** ± 0.4 | `+11.1%` | 0.90x | `6.0` | `~NOISE` |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 6 ± 0.0 | **7** ± 1.8 | `+16.7%` | 0.86x | `2.2` | `~NOISE` |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 9 ± 0.4 | **10** ± 0.4 | `+11.1%` | 0.90x | `3.5` | `~NOISE` |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 288 ± 9.9 | **308** ± 45.7 | `+6.9%` | 0.94x | `2.0` | **REGRESSION** |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 52 ± 0.9 | **56** ± 1.6 | `+7.7%` | 0.93x | `4.2` | **REGRESSION** |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 6 ± 0.9 | **7** ± 0.4 | `+16.7%` | 0.86x | `0.9` | `~NOISE` |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 13 ± 0.4 | **15** ± 1.2 | `+15.4%` | 0.87x | `3.1` | **REGRESSION** |
| 55 | `Path: 4-level nested cursor_write_path` | 230 ± 1.9 | **244** ± 4.3 | `+6.1%` | 0.94x | `6.0` | **REGRESSION** |
| 56 | `Path: 4-level nested cursor_read_path` | 148 ± 4.2 | **160** ± 4.9 | `+8.1%` | 0.93x | `3.7` | **REGRESSION** |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 97 ± 2.1 | **104** ± 2.3 | `+7.2%` | 0.93x | `5.2` | **REGRESSION** |
| 58 | `Backend: Core_Memory commits` | 1,216 ± 10.7 | **1,254** ± 66.7 | `+3.1%` | 0.97x | `1.9` | `~NOISE` |
| 59 | `Backend: Core_Buffered_File commits` | 4,579 ± 15.1 | **4,769** ± 181 | `+4.1%` | 0.96x | `3.4` | **REGRESSION** |
| 60 | `Backend: Core_File (unbuffered) commits` | 44,053 ± 193 | **46,979** ± 1,924 | `+6.6%` | 0.94x | `4.2` | **REGRESSION** |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 1,118 ± 9.4 | **1,170** ± 20.9 | `+4.7%` | 0.96x | `4.4` | **REGRESSION** |
| 62 | `Tx: Aborted transaction rollback truncate` | 693 ± 3.5 | **685** ± 13.9 | `-1.2%` | 1.01x | `2.1` | `~NOISE` |
| 63 | `DB: Re-open & trailer checksum verify` | 56 ± 0.5 | **58** ± 1.9 | `+3.6%` | 0.97x | `2.7` | **REGRESSION** |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | 4,562 ± 386 | **4,406** ± 33.9 | `-3.4%` | 1.04x | `1.7` | `~NOISE` |
| 65 | `DSL Layer 1: String Selector get_uint (N=500)` | 540 ± 10.9 | **570** ± 6.5 | `+5.6%` | 0.95x | `5.7` | **REGRESSION** |
| 66 | `DSL Layer 3: Struct marshal (N=200)` | 4,233 ± 282 | **4,462** ± 123 | `+5.4%` | 0.95x | `0.7` | `~NOISE` |
| 67 | `DSL Layer 3: Struct unmarshal (N=200)` | 1,977 ± 25.7 | **2,132** ± 44.4 | `+7.8%` | 0.93x | `7.5` | **REGRESSION** |
| 68 | `DSL Layer 3: Datomic pull projection (N=200)` | 1,534 ± 31.0 | **1,656** ± 51.8 | `+8.0%` | 0.93x | `5.5` | **REGRESSION** |
| 69 | `DSL Layer 4: diff_moments (1 of 700 mutated)` | 261,697 ± 4,235 | **280,944** ± 1,139 | `+7.4%` | 0.93x | `9.2` | **REGRESSION** |
| 70 | `DSL Layer 4: history_of lineage (3 moments)` | 1,880 ± 87.8 | **2,576** ± 109 | `+37.0%` | 0.73x | `12.0` | **REGRESSION** |
| 71 | `DSL Layer 5: Datalog B+Tree Prefix + Join` | 15,366 ± 677 | **15,207** ± 339 | `-1.0%` | 1.01x | `1.2` | `~NOISE` |
| 72 | `DSL Layer 5: Datalog Grouped Aggs (N=500)` | 855,426 ± 25,041 | **589,105** ± 8,649 | `-31.1%` | 1.45x | `21.4` | **FASTER** |
| 73 | `DSL Layer 5: Datalog Cycle-Safe reach (32-ring)` | 27,103 ± 1,173 | **28,785** ± 365 | `+6.2%` | 0.94x | `2.3` | **REGRESSION** |
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
