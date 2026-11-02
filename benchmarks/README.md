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
### 1. Odin Results (`-o:speed -microarch:native`, Commit `cadcc64f08ac`)

| # | Benchmark | Ops | Runs | Median (`ns/op`) | Mean ± σ (`ns`) | CV | Min..Max (`ns`) | `ops/sec` | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | 5 | **212** | 212 ± 6.9 | 3.3% | 204..222 | 4,716,981 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | 5 | **96** | 97 ± 3.7 | 3.8% | 93..103 | 10,416,667 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | 5 | **58** | 58 ± 1.6 | 2.8% | 55..59 | 17,241,379 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | 5 | **990** | 1,034 ± 145.5 | 14.1% | 945..1,291 | 1,010,101 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | 5 | **173** | 174 ± 4.7 | 2.7% | 170..182 | 5,780,347 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | 5 | **38** | 38 ± 0.5 | 1.4% | 38..39 | 26,315,789 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | 5 | **203** | 207 ± 13.8 | 6.7% | 198..231 | 4,926,108 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | 5 | **216** | 223 ± 15.9 | 7.1% | 213..251 | 4,629,630 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | 5 | **171** | 176 ± 10.3 | 5.9% | 170..194 | 5,847,953 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | 5 | **183** | 193 ± 19.5 | 10.1% | 181..227 | 5,464,481 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | 5 | **228** | 227 ± 2.9 | 1.3% | 222..229 | 4,385,965 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | 5 | **233** | 244 ± 26.0 | 10.6% | 227..290 | 4,291,845 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | 5 | **96** | 97 ± 1.7 | 1.8% | 96..100 | 10,416,667 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | 5 | **117** | 122 ± 13.7 | 11.2% | 113..146 | 8,547,009 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | 5 | **51** | 55 ± 7.0 | 12.7% | 49..64 | 19,607,843 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | 5 | **13** | 14 ± 1.9 | 14.3% | 12..17 | 76,923,077 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | 5 | **100** | 103 ± 10.9 | 10.6% | 95..122 | 10,000,000 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | 5 | **365** | 364 ± 12.4 | 3.4% | 346..379 | 2,739,726 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | 5 | **740** | 742 ± 39.8 | 5.4% | 680..787 | 1,351,351 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | 5 | **244** | 245 ± 10.8 | 4.4% | 232..262 | 4,098,361 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | 5 | **57** | 56 ± 1.9 | 3.4% | 53..58 | 17,543,860 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | 5 | **15** | 15 ± 0.5 | 3.8% | 14..15 | 66,666,667 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | 5 | **281** | 277 ± 9.1 | 3.3% | 261..283 | 3,558,719 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | 5 | **375** | 365 ± 15.2 | 4.2% | 341..376 | 2,666,667 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | 5 | **866** | 863 ± 23.8 | 2.8% | 827..891 | 1,154,734 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | 5 | **174** | 174 ± 4.8 | 2.7% | 167..179 | 5,747,126 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | 5 | **414** | 434 ± 45.5 | 10.5% | 407..515 | 2,415,459 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | 5 | **391** | 391 ± 1.3 | 0.3% | 390..393 | 2,557,545 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | 5 | **172** | 173 ± 1.3 | 0.8% | 171..174 | 5,813,953 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | 5 | **136** | 137 ± 2.3 | 1.7% | 135..141 | 7,352,941 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | 5 | **13** | 13 ± 0.0 | 0.0% | 13..13 | 76,923,077 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | 5 | **472** | 472 ± 1.9 | 0.4% | 469..474 | 2,118,644 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | 5 | **247** | 248 ± 2.6 | 1.0% | 246..251 | 4,048,583 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | 5 | **74** | 74 ± 1.1 | 1.5% | 73..76 | 13,513,514 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | 5 | **413** | 414 ± 1.8 | 0.4% | 412..416 | 2,421,308 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | 5 | **370** | 370 ± 1.5 | 0.4% | 369..373 | 2,702,703 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | 5 | **369** | 369 ± 2.2 | 0.6% | 366..372 | 2,710,027 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | 5 | **151** | 151 ± 1.3 | 0.9% | 149..152 | 6,622,517 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 5 | **105** | 105 ± 1.1 | 1.0% | 104..107 | 9,523,810 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 5 | **776** | 785 ± 29.9 | 3.8% | 761..837 | 1,288,660 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 5 | **3,747** | 3,695 ± 240.0 | 6.5% | 3,316..3,967 | 266,880 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 5 | **10,098** | 10,029 ± 269.3 | 2.7% | 9,668..10,390 | 99,030 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 5 | **107,262** | 108,295 ± 6465.1 | 6.0% | 100,418..117,390 | 9,323 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 5 | **1,573** | 1,567 ± 35.8 | 2.3% | 1,513..1,613 | 635,728 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | 5 | **225** | 225 ± 2.7 | 1.2% | 221..228 | 4,444,444 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | 5 | **233** | 233 ± 1.1 | 0.5% | 232..235 | 4,291,845 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | 5 | **6** | 6 ± 0.0 | 0.0% | 6..6 | 166,666,667 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | 5 | **9** | 9 ± 0.0 | 0.0% | 9..9 | 111,111,111 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | 5 | **6** | 6 ± 0.0 | 0.0% | 6..6 | 166,666,667 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | 5 | **9** | 9 ± 0.4 | 4.9% | 9..10 | 111,111,111 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 5 | **295** | 305 ± 23.9 | 7.8% | 293..348 | 3,389,831 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | 5 | **53** | 53 ± 0.4 | 0.8% | 52..53 | 18,867,925 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | 5 | **6** | 6 ± 0.0 | 0.0% | 6..6 | 166,666,667 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 5 | **13** | 13 ± 0.5 | 4.1% | 13..14 | 76,923,077 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | 5 | **249** | 249 ± 3.0 | 1.2% | 245..253 | 4,016,064 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | 5 | **151** | 154 ± 6.4 | 4.2% | 150..165 | 6,622,517 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | 5 | **100** | 101 ± 1.9 | 1.9% | 99..103 | 10,000,000 | — |
| 58 | `Backend: Core_Memory commits` | 500 | 5 | **1,234** | 1,481 ± 578.8 | 39.1% | 1,198..2,516 | 810,373 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 5 | **4,684** | 4,704 ± 100.6 | 2.1% | 4,616..4,863 | 213,493 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 5 | **44,717** | 46,073 ± 3218.2 | 7.0% | 44,270..51,807 | 22,363 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | 5 | **1,142** | 1,130 ± 64.5 | 5.7% | 1,050..1,204 | 875,657 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | 5 | **675** | 677 ± 10.6 | 1.6% | 664..693 | 1,481,481 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | 5 | **57** | 59 ± 3.9 | 6.6% | 56..65 | 17,543,860 | — |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | 500 | 5 | **4,642** | 4,647 ± 59.2 | 1.3% | 4,585..4,709 | 215,424 | 232.5 KB |
| 65 | `DSL Layer 1: String Selector get_uint (N=500)` | 500 | 5 | **553** | 550 ± 14.9 | 2.7% | 531..567 | 1,808,318 | — |
| 66 | `DSL Layer 3: Struct marshal (N=200)` | 200 | 5 | **4,242** | 4,259 ± 77.5 | 1.8% | 4,192..4,378 | 235,738 | — |
| 67 | `DSL Layer 3: Struct unmarshal (N=200)` | 200 | 5 | **2,091** | 2,078 ± 36.4 | 1.8% | 2,021..2,117 | 478,240 | — |
| 68 | `DSL Layer 3: Datomic pull projection (N=200)` | 200 | 5 | **1,575** | 1,566 ± 26.8 | 1.7% | 1,520..1,588 | 634,921 | — |
| 69 | `DSL Layer 4: diff_moments (1 of 700 mutated)` | 200 | 5 | **278,457** | 280,083 ± 5028.5 | 1.8% | 277,148..288,995 | 3,591 | — |
| 70 | `DSL Layer 4: history_of lineage (3 moments)` | 200 | 5 | **2,314** | 2,341 ± 70.8 | 3.0% | 2,289..2,464 | 432,152 | — |
| 71 | `DSL Layer 5: Datalog B+Tree Prefix + Join` | 100 | 5 | **14,312** | 14,777 ± 1148.5 | 7.8% | 14,042..16,795 | 69,871 | — |
| 72 | `DSL Layer 5: Datalog Grouped Aggs (N=500)` | 25 | 5 | **613,623** | 614,199 ± 5196.1 | 0.8% | 608,326..622,542 | 1,630 | — |
| 73 | `DSL Layer 5: Datalog Cycle-Safe reach (32-ring)` | 100 | 5 | **27,683** | 27,558 ± 572.4 | 2.1% | 26,987..28,317 | 36,123 | — |

### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `cadcc64f08ac`)

| # | Benchmark | Ops | Runs | Median (`ns/op`) | Mean ± σ (`ns`) | CV | Min..Max (`ns`) | `ops/sec` | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2,000 | 5 | **786** | 793 ± 39.1 | 4.9% | 736..831 | 1,272,265 | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | 2,000 | 5 | **271** | 272 ± 8.3 | 3.0% | 261..281 | 3,690,037 | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | 2,000 | 5 | **186** | 183 ± 5.8 | 3.2% | 173..187 | 5,376,344 | — |
| 4 | `HAMT CoW branched moment commits` | 500 | 5 | **2,326** | 2,346 ± 112.2 | 4.8% | 2,196..2,484 | 429,923 | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | 1,000 | 5 | **949** | 951 ± 23.5 | 2.5% | 917..979 | 1,053,741 | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | 2,000 | 5 | **148** | 149 ± 4.6 | 3.1% | 143..155 | 6,756,757 | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | 2,000 | 5 | **740** | 810 ± 174.3 | 21.5% | 711..1,121 | 1,351,351 | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | 2,000 | 5 | **791** | 806 ± 42.8 | 5.3% | 772..879 | 1,264,223 | — |
| 9 | `HAMT Counted_Hash_Map remove` | 1,000 | 5 | **983** | 983 ± 26.7 | 2.7% | 943..1,015 | 1,017,294 | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | 500 | 5 | **1,234** | 1,225 ± 37.1 | 3.0% | 1,165..1,265 | 810,373 | — |
| 11 | `HAMT deep suffix-collision branch collapse` | 500 | 5 | **2,741** | 2,725 ± 112.8 | 4.1% | 2,562..2,877 | 364,830 | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | 2,000 | 5 | **522** | 521 ± 18.5 | 3.6% | 499..549 | 1,915,709 | — |
| 13 | `HAMT Counted_Hash_Set membership check` | 2,000 | 5 | **264** | 261 ± 10.8 | 4.2% | 243..272 | 3,787,879 | — |
| 14 | `Array_List (Radix Trie) append` | 2,000 | 5 | **210** | 208 ± 4.4 | 2.1% | 201..212 | 4,761,905 | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | 2,000 | 5 | **128** | 128 ± 0.5 | 0.4% | 127..128 | 7,812,500 | — |
| 16 | `Array_List (Radix Trie) iterator scan` | 2,000 | 5 | **32** | 32 ± 0.4 | 1.4% | 31..32 | 31,250,000 | — |
| 17 | `Array_List (Radix Trie) in-place put` | 2,000 | 5 | **197** | 198 ± 2.6 | 1.3% | 195..202 | 5,076,142 | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | 2,000 | 5 | **1,527** | 1,529 ± 8.5 | 0.6% | 1,521..1,543 | 654,879 | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | 500 | 5 | **1,364** | 1,366 ± 27.4 | 2.0% | 1,340..1,410 | 733,138 | — |
| 20 | `Linked_Array_List (B-Tree) append` | 2,000 | 5 | **2,807** | 2,804 ± 11.7 | 0.4% | 2,789..2,819 | 356,252 | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | 2,000 | 5 | **2,145** | 2,149 ± 18.9 | 0.9% | 2,131..2,176 | 466,200 | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | 2,000 | 5 | **60** | 60 ± 1.6 | 2.6% | 58..62 | 16,666,667 | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | 500 | 5 | **3,473** | 3,469 ± 18.8 | 0.5% | 3,443..3,491 | 287,936 | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | 500 | 5 | **3,515** | 3,510 ± 10.3 | 0.3% | 3,493..3,518 | 284,495 | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | 400 | 5 | **33,325** | 33,379 ± 294.5 | 0.9% | 33,105..33,858 | 30,008 | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | 2,000 | 5 | **2,288** | 2,285 ± 11.2 | 0.5% | 2,266..2,295 | 437,063 | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | 2,000 | 5 | **3,288** | 3,286 ± 18.1 | 0.5% | 3,256..3,302 | 304,136 | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2,000 | 5 | **4,390** | 4,408 ± 29.9 | 0.7% | 4,383..4,442 | 227,790 | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | 2,000 | 5 | **4,307** | 4,325 ± 31.1 | 0.7% | 4,298..4,360 | 232,180 | — |
| 30 | `Sorted_Map (B+Tree) rank query` | 2,000 | 5 | **4,150** | 4,135 ± 40.6 | 1.0% | 4,066..4,171 | 240,964 | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | 2,000 | 5 | **51** | 51 ± 1.4 | 2.8% | 49..53 | 19,607,843 | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | 2,000 | 5 | **5,340** | 5,335 ± 37.8 | 0.7% | 5,273..5,374 | 187,266 | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | 1,000 | 5 | **5,793** | 5,796 ± 36.7 | 0.6% | 5,748..5,833 | 172,622 | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | 2,000 | 5 | **3,172** | 3,173 ± 17.5 | 0.6% | 3,148..3,190 | 315,259 | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | 2,000 | 5 | **4,284** | 4,282 ± 15.3 | 0.4% | 4,267..4,302 | 233,427 | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | 2,000 | 5 | **4,618** | 4,624 ± 10.7 | 0.2% | 4,614..4,637 | 216,544 | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2,000 | 5 | **4,170** | 4,166 ± 10.0 | 0.2% | 4,155..4,175 | 239,808 | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | 2,000 | 5 | **3,956** | 3,966 ± 64.5 | 1.6% | 3,910..4,076 | 252,781 | — |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 5 | **931** | 942 ± 41.3 | 4.4% | 899..1,010 | 1,074,114 | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 5 | **1,678** | 1,681 ± 17.1 | 1.0% | 1,660..1,704 | 595,948 | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 5 | **7,043** | 8,272 ± 3192.5 | 38.6% | 6,161..13,936 | 141,985 | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 5 | **13,856** | 13,707 ± 1208.9 | 8.8% | 12,293..15,428 | 72,171 | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 5 | **108,664** | 111,052 ± 8474.1 | 7.6% | 101,410..124,524 | 9,203 | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 5 | **1,684** | 1,787 ± 233.0 | 13.0% | 1,673..2,204 | 593,824 | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2,000 | 5 | **786** | 788 ± 4.4 | 0.6% | 784..795 | 1,272,265 | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2,000 | 5 | **818** | 820 ± 5.2 | 0.6% | 816..829 | 1,222,494 | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | 10,000 | 5 | **8** | 8 ± 1.7 | 19.9% | 7..11 | 125,000,000 | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | 10,000 | 5 | **38** | 38 ± 0.7 | 1.9% | 37..39 | 26,315,789 | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | 10,000 | 5 | **7** | 7 ± 0.4 | 6.2% | 7..8 | 142,857,143 | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | 10,000 | 5 | **56** | 55 ± 3.2 | 5.8% | 51..59 | 17,857,143 | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 5 | **1,664** | 1,630 ± 55.0 | 3.4% | 1,567..1,677 | 600,962 | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | 256 | 5 | **73** | 75 ± 5.5 | 7.3% | 72..85 | 13,698,630 | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | 2,000 | 5 | **28** | 28 ± 0.0 | 0.0% | 28..28 | 35,714,286 | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | 2,000 | 5 | **29** | 29 ± 1.5 | 5.1% | 27..31 | 34,482,759 | — |
| 55 | `Path: 4-level nested cursor_write_path` | 500 | 5 | **1,493** | 1,493 ± 11.2 | 0.7% | 1,483..1,510 | 669,792 | — |
| 56 | `Path: 4-level nested cursor_read_path` | 500 | 5 | **1,258** | 1,260 ± 20.6 | 1.6% | 1,241..1,294 | 794,913 | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | 2,000 | 5 | **265** | 265 ± 2.5 | 0.9% | 261..267 | 3,773,585 | — |
| 58 | `Backend: Core_Memory commits` | 500 | 5 | **2,426** | 2,454 ± 50.3 | 2.0% | 2,413..2,523 | 412,201 | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 5 | **17,846** | 17,894 ± 159.4 | 0.9% | 17,770..18,168 | 56,035 | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 5 | **46,942** | 46,993 ± 480.9 | 1.0% | 46,456..47,766 | 21,303 | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | 500 | 5 | **1,848** | 1,976 ± 266.9 | 13.5% | 1,793..2,442 | 541,126 | — |
| 62 | `Tx: Aborted transaction rollback truncate` | 500 | 5 | **1,932** | 1,934 ± 20.8 | 1.1% | 1,909..1,967 | 517,598 | — |
| 63 | `DB: Re-open & trailer checksum verify` | 5,000 | 5 | **236** | 238 ± 3.8 | 1.6% | 234..243 | 4,237,288 | — |

### 3. 1v1 Comparison (Odin vs. Zig, Commit `cadcc64f08ac`)

| # | Benchmark | Odin (`ns/op` ± σ) | Zig (`ns/op` ± σ) | Speedup vs. Zig | Footprint |
| ---: | :--- | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **212** ± 6.9 | 786 ± 39.1 | **3.71x** | 214.5 KB |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **96** ± 3.7 | 271 ± 8.3 | **2.82x** | — |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **58** ± 1.6 | 186 ± 5.8 | **3.21x** | — |
| 4 | `HAMT CoW branched moment commits` | **990** ± 145.5 | 2,326 ± 112.2 | **2.35x** | 457.7 KB |
| 5 | `HAMT Hash_Map remove & branch shortening` | **173** ± 4.7 | 949 ± 23.5 | **5.49x** | — |
| 6 | `HAMT Hash_Map unordered iterator scan` | **38** ± 0.5 | 148 ± 4.6 | **3.89x** | — |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **203** ± 13.8 | 740 ± 174.3 | **3.65x** | — |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **216** ± 15.9 | 791 ± 42.8 | **3.66x** | — |
| 9 | `HAMT Counted_Hash_Map remove` | **171** ± 10.3 | 983 ± 26.7 | **5.75x** | — |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **183** ± 19.5 | 1,234 ± 37.1 | **6.74x** | — |
| 11 | `HAMT deep suffix-collision branch collapse` | **228** ± 2.9 | 2,741 ± 112.8 | **12.02x** | — |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **233** ± 26.0 | 522 ± 18.5 | **2.24x** | — |
| 13 | `HAMT Counted_Hash_Set membership check` | **96** ± 1.7 | 264 ± 10.8 | **2.75x** | — |
| 14 | `Array_List (Radix Trie) append` | **117** ± 13.7 | 210 ± 4.4 | **1.79x** | 19.3 KB |
| 15 | `Array_List (Radix Trie) random get` | **51** ± 7.0 | 128 ± 0.5 | **2.51x** | — |
| 16 | `Array_List (Radix Trie) iterator scan` | **13** ± 1.9 | 32 ± 0.4 | **2.46x** | — |
| 17 | `Array_List (Radix Trie) in-place put` | **100** ± 10.9 | 197 ± 2.6 | **1.97x** | — |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **365** ± 12.4 | 1,527 ± 8.5 | **4.18x** | — |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **740** ± 39.8 | 1,364 ± 27.4 | **1.84x** | — |
| 20 | `Linked_Array_List (B-Tree) append` | **244** ± 10.8 | 2,807 ± 11.7 | **11.50x** | 45.3 KB |
| 21 | `Linked_Array_List (B-Tree) random get` | **57** ± 1.9 | 2,145 ± 18.9 | **37.63x** | — |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **15** ± 0.5 | 60 ± 1.6 | **4.00x** | — |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **281** ± 9.1 | 3,473 ± 18.8 | **12.36x** | — |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **375** ± 15.2 | 3,515 ± 10.3 | **9.37x** | — |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **866** ± 23.8 | 33,325 ± 294.5 | **38.48x** | — |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **174** ± 4.8 | 2,288 ± 11.2 | **13.15x** | — |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **414** ± 45.5 | 3,288 ± 18.1 | **7.94x** | — |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **391** ± 1.3 | 4,390 ± 29.9 | **11.23x** | 115.4 KB |
| 29 | `Sorted_Map (B+Tree) key lookup` | **172** ± 1.3 | 4,307 ± 31.1 | **25.04x** | — |
| 30 | `Sorted_Map (B+Tree) rank query` | **136** ± 2.3 | 4,150 ± 40.6 | **30.51x** | — |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **13** ± 0.0 | 51 ± 1.4 | **3.92x** | — |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **472** ± 1.9 | 5,340 ± 37.8 | **11.31x** | — |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **247** ± 2.6 | 5,793 ± 36.7 | **23.45x** | — |
| 34 | `Sorted_Map (B+Tree) get_index select` | **74** ± 1.1 | 3,172 ± 17.5 | **42.86x** | — |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **413** ± 1.8 | 4,284 ± 15.3 | **10.37x** | — |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **370** ± 1.5 | 4,618 ± 10.7 | **12.48x** | — |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **369** ± 2.2 | 4,170 ± 10.0 | **11.30x** | 80.0 KB |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **151** ± 1.3 | 3,956 ± 64.5 | **26.20x** | — |
| 39 | `Replication (genesis -> 200 moments)` | **105** ± 1.1 | 931 ± 41.3 | **8.87x** | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | **776** ± 29.9 | 1,678 ± 17.1 | **2.16x** | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **3,747** ± 240.0 | 7,043 ± 3192.5 | **1.88x** | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **10,098** ± 269.3 | 13,856 ± 1208.9 | **1.37x** | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | **107,262** ± 6465.1 | 108,664 ± 8474.1 | **1.01x** | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | **1,573** ± 35.8 | 1,684 ± 233.0 | **1.07x** | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **225** ± 2.7 | 786 ± 4.4 | **3.49x** | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **233** ± 1.1 | 818 ± 5.2 | **3.51x** | 248.7 KB |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **6** ± 0.0 | 8 ± 1.7 | **1.33x** | — |
| 48 | `Bytes: External Bytes read_bytes_buf` | **9** ± 0.0 | 38 ± 0.7 | **4.22x** | — |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **6** ± 0.0 | 7 ± 0.4 | **1.17x** | — |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **9** ± 0.4 | 56 ± 3.2 | **6.22x** | — |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **295** ± 23.9 | 1,664 ± 55.0 | **5.64x** | 1024.1 KB |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **53** ± 0.4 | 73 ± 5.5 | **1.38x** | — |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **6** ± 0.0 | 28 ± 0.0 | **4.67x** | — |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **13** ± 0.5 | 29 ± 1.5 | **2.23x** | — |
| 55 | `Path: 4-level nested cursor_write_path` | **249** ± 3.0 | 1,493 ± 11.2 | **6.00x** | — |
| 56 | `Path: 4-level nested cursor_read_path` | **151** ± 6.4 | 1,258 ± 20.6 | **8.33x** | — |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **100** ± 1.9 | 265 ± 2.5 | **2.65x** | — |
| 58 | `Backend: Core_Memory commits` | **1,234** ± 578.8 | 2,426 ± 50.3 | **1.97x** | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | **4,684** ± 100.6 | 17,846 ± 159.4 | **3.81x** | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | **44,717** ± 3218.2 | 46,942 ± 480.9 | **1.05x** | 391.0 KB |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1,142** ± 64.5 | 1,848 ± 266.9 | **1.62x** | — |
| 62 | `Tx: Aborted transaction rollback truncate` | **675** ± 10.6 | 1,932 ± 20.8 | **2.86x** | — |
| 63 | `DB: Re-open & trailer checksum verify` | **57** ± 3.9 | 236 ± 3.8 | **4.14x** | — |
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
