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

#### 1.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 16 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **65** | 66 ± 4.7 | 7.1% | 14.1M | 16.9M | 5 | 71 | 71 | 59 | 71 | 2K |
| 6 | `HAMT Hash_Map unordered iterator scan` | **44** | 45 ± 5.7 | 12.5% | 18.2M | 25.0M | 2 | 53 | 55 | 40 | 55 | 2K |
| 15 | `Array_List (Radix Trie) random get` | **54** | 53 ± 2.6 | 4.9% | 17.9M | 20.4M | 1 | 56 | 56 | 49 | 56 | 2K |
| 16 | `Array_List (Radix Trie) iterator scan` | **14** | 14 ± 1.2 | 8.7% | 62.5M | 76.9M | 1 | 16 | 16 | 13 | 16 | 2K |
| 21 | `Linked_Array_List (B-Tree) random get` | **62** | 65 ± 12.4 | 19.0% | 11.5M | 17.5M | 4 | 82 | 86 | 57 | 87 | 2K |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **16** | 16 ± 1.6 | 10.1% | 52.6M | 66.7M | 1 | 18 | 19 | 15 | 19 | 2K |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **14** | 14 ± 0.4 | 3.1% | 66.7M | 71.4M | 0 | 15 | 15 | 14 | 15 | 2K |
| 34 | `Sorted_Map (B+Tree) get_index select` | **70** | 72 ± 5.1 | 7.0% | 12.3M | 14.5M | 3 | 79 | 81 | 69 | 81 | 2K |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **6** | 6 ± 0.5 | 8.6% | 143M | 167M | 1 | 7 | 7 | 6 | 7 | 10K |
| 48 | `Bytes: External Bytes read_bytes_buf` | **10** | 10 ± 0.4 | 4.4% | 90.9M | 100M | 0 | 11 | 11 | 10 | 11 | 10K |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **7** | 8 ± 1.8 | 22.9% | 90.9M | 143M | 0 | 10 | 11 | 7 | 11 | 10K |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **10** | 10 ± 0.4 | 4.4% | 90.9M | 100M | 0 | 11 | 11 | 10 | 11 | 10K |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **56** | 56 ± 1.6 | 2.8% | 17.2M | 18.5M | 2 | 58 | 58 | 54 | 58 | 256 |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **7** | 7 ± 0.4 | 6.6% | 143M | 167M | 0 | 7 | 7 | 6 | 7 | 2K |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **15** | 15 ± 1.2 | 8.2% | 58.8M | 71.4M | 1 | 17 | 17 | 14 | 17 | 2K |
| 63 | `DB: Re-open & trailer checksum verify` | **58** | 59 ± 1.9 | 3.3% | 16.1M | 17.5M | 1 | 61 | 62 | 57 | 62 | 5K |

#### 1.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 39 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **220** | 220 ± 4.1 | 1.8% | 4.5M | 4.7M | 7 | 224 | 224 | 215 | 224 | 2K |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **103** | 106 ± 10.2 | 9.7% | 8.2M | 10.6M | 4 | 119 | 121 | 94 | 122 | 2K |
| 5 | `HAMT Hash_Map remove & branch shortening` | **179** | 195 ± 28.4 | 14.6% | 4.1M | 5.6M | 18 | 234 | 242 | 178 | 244 | 1K |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **227** | 236 ± 38.7 | 16.4% | 3.3M | 5.0M | 31 | 288 | 298 | 202 | 300 | 2K |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **225** | 243 ± 33.4 | 13.7% | 3.3M | 4.5M | 26 | 289 | 297 | 220 | 299 | 2K |
| 9 | `HAMT Counted_Hash_Map remove` | **194** | 195 ± 11.3 | 5.8% | 4.7M | 5.4M | 16 | 209 | 211 | 184 | 211 | 1K |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **198** | 206 ± 20.2 | 9.8% | 4.1M | 5.2M | 2 | 233 | 240 | 194 | 242 | 500 |
| 11 | `HAMT deep suffix-collision branch collapse` | **222** | 224 ± 4.4 | 2.0% | 4.4M | 4.5M | 8 | 229 | 229 | 220 | 229 | 500 |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **243** | 252 ± 22.5 | 8.9% | 3.4M | 4.2M | 5 | 283 | 290 | 238 | 292 | 2K |
| 13 | `HAMT Counted_Hash_Set membership check` | **105** | 107 ± 6.8 | 6.4% | 8.5M | 9.9M | 5 | 116 | 118 | 101 | 118 | 2K |
| 14 | `Array_List (Radix Trie) append` | **127** | 123 ± 7.8 | 6.3% | 7.8M | 9.1M | 6 | 129 | 129 | 110 | 129 | 2K |
| 17 | `Array_List (Radix Trie) in-place put` | **105** | 101 ± 6.0 | 5.9% | 9.4M | 10.6M | 10 | 106 | 106 | 94 | 106 | 2K |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **405** | 392 ± 26.1 | 6.7% | 2.4M | 2.8M | 36 | 418 | 420 | 360 | 421 | 2K |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **794** | 831 ± 140 | 16.8% | 951K | 1.5M | 93 | 1,014 | 1,044 | 680 | 1,052 | 500 |
| 20 | `Linked_Array_List (B-Tree) append` | **260** | 261 ± 8.8 | 3.4% | 3.7M | 4.0M | 13 | 271 | 272 | 251 | 272 | 2K |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **301** | 298 ± 14.2 | 4.8% | 3.2M | 3.6M | 22 | 313 | 314 | 281 | 314 | 500 |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **366** | 369 ± 22.7 | 6.2% | 2.5M | 3.0M | 23 | 394 | 396 | 337 | 396 | 500 |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **914** | 932 ± 65.6 | 7.0% | 985K | 1.2M | 83 | 1,008 | 1,014 | 852 | 1,015 | 400 |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **178** | 200 ± 51.3 | 25.7% | 3.5M | 6.1M | 28 | 271 | 285 | 165 | 289 | 2K |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **425** | 472 ± 96.8 | 20.5% | 1.6M | 2.5M | 78 | 605 | 629 | 405 | 635 | 2K |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **410** | 413 ± 9.3 | 2.3% | 2.3M | 2.5M | 13 | 424 | 426 | 404 | 426 | 2K |
| 29 | `Sorted_Map (B+Tree) key lookup` | **174** | 176 ± 4.7 | 2.7% | 5.4M | 5.8M | 1 | 182 | 184 | 173 | 184 | 2K |
| 30 | `Sorted_Map (B+Tree) rank query` | **139** | 142 ± 7.2 | 5.1% | 6.5M | 7.2M | 1 | 152 | 154 | 138 | 155 | 2K |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **487** | 488 ± 2.8 | 0.6% | 2.0M | 2.1M | 1 | 492 | 493 | 486 | 493 | 2K |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **260** | 260 ± 7.2 | 2.8% | 3.7M | 4.0M | 4 | 270 | 272 | 253 | 272 | 1K |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **430** | 431 ± 4.4 | 1.0% | 2.28M | 2.35M | 1 | 436 | 438 | 426 | 438 | 2K |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **400** | 400 ± 6.1 | 1.5% | 2.4M | 2.6M | 3 | 408 | 409 | 392 | 409 | 2K |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **369** | 369 ± 3.9 | 1.1% | 2.68M | 2.75M | 6 | 373 | 373 | 364 | 373 | 2K |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **155** | 158 ± 8.0 | 5.1% | 5.8M | 6.5M | 4 | 169 | 171 | 153 | 172 | 2K |
| 39 | `Replication (genesis -> 200 moments)` | **120** | 127 ± 20.2 | 15.9% | 6.3M | 9.0M | 23 | 154 | 158 | 111 | 159 | 200 |
| 40 | `Replication (incremental 1-moment delta)` | **813** | 821 ± 26.1 | 3.2% | 1.15M | 1.25M | 12 | 856 | 864 | 802 | 866 | 100 |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **237** | 238 ± 7.2 | 3.0% | 4.0M | 4.3M | 7 | 248 | 250 | 232 | 250 | 2K |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **244** | 246 ± 4.1 | 1.7% | 4.0M | 4.1M | 3 | 252 | 253 | 243 | 253 | 2K |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **308** | 333 ± 45.7 | 13.7% | 2.4M | 3.3M | 36 | 396 | 407 | 302 | 410 | 256 |
| 55 | `Path: 4-level nested cursor_write_path` | **244** | 244 ± 4.3 | 1.8% | 4.0M | 4.2M | 2 | 249 | 250 | 238 | 250 | 500 |
| 56 | `Path: 4-level nested cursor_read_path` | **160** | 158 ± 4.9 | 3.1% | 6.1M | 6.6M | 8 | 163 | 163 | 152 | 163 | 500 |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **104** | 105 ± 2.3 | 2.2% | 9.3M | 9.8M | 4 | 107 | 107 | 102 | 107 | 2K |
| 62 | `Tx: Aborted transaction rollback truncate` | **685** | 679 ± 13.9 | 2.0% | 1.4M | 1.5M | 19 | 694 | 696 | 663 | 696 | 500 |
| 65 | `DSL Layer 1: String Selector get_uint (N=500)` | **570** | 572 ± 6.5 | 1.1% | 1.7M | 1.8M | 6 | 581 | 582 | 565 | 582 | 500 |

#### 1.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 20 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | `HAMT CoW branched moment commits` | **1.05** | 1.10 ± 0.13 | 12.1% | 753K | 998K | 0.08 | 1.28 | 1.32 | 1.00 | 1.33 | 500 |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **4.77** | 4.93 ± 0.47 | 9.6% | 181K | 224K | 0.74 | 5.49 | 5.53 | 4.46 | 5.54 | 1 |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **10.6** | 10.8 ± 0.94 | 8.6% | 80.5K | 99.0K | 0.53 | 12.1 | 12.4 | 10.1 | 12.4 | 1 |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | **136.8** | 138.2 ± 4.54 | 3.3% | 6.8K | 7.4K | 2.82 | 144.4 | 145.7 | 135.1 | 146.0 | 1 |
| 44 | `Replication (Post-compaction resync)` | **1.61** | 1.64 ± 0.03 | 1.9% | 598K | 620K | 0.05 | 1.67 | 1.67 | 1.61 | 1.67 | 1 |
| 58 | `Backend: Core_Memory commits` | **1.25** | 1.28 ± 0.07 | 5.2% | 718K | 814K | 0.03 | 1.37 | 1.39 | 1.23 | 1.39 | 500 |
| 59 | `Backend: Core_Buffered_File commits` | **4.77** | 4.85 ± 0.18 | 3.7% | 194K | 213K | 0.10 | 5.10 | 5.15 | 4.70 | 5.16 | 500 |
| 60 | `Backend: Core_File (unbuffered) commits` | **47.0** | 47.8 ± 1.92 | 4.0% | 19.5K | 21.4K | 0.17 | 50.4 | 51.1 | 46.8 | 51.2 | 500 |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1.17** | 1.16 ± 0.02 | 1.8% | 848K | 887K | 0.02 | 1.18 | 1.18 | 1.13 | 1.18 | 500 |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | **4.41** | 4.42 ± 0.03 | 0.8% | 224K | 228K | 0.04 | 4.46 | 4.47 | 4.39 | 4.47 | 500 |
| 66 | `DSL Layer 3: Struct marshal (N=200)` | **4.46** | 4.50 ± 0.12 | 2.7% | 215K | 228K | 0.20 | 4.65 | 4.66 | 4.39 | 4.66 | 200 |
| 67 | `DSL Layer 3: Struct unmarshal (N=200)` | **2.13** | 2.14 ± 0.04 | 2.1% | 450K | 475K | 0.01 | 2.20 | 2.22 | 2.11 | 2.22 | 200 |
| 68 | `DSL Layer 3: Datomic pull projection (N=200)` | **1.66** | 1.68 ± 0.05 | 3.1% | 564K | 606K | 0.04 | 1.76 | 1.77 | 1.65 | 1.77 | 200 |
| 69 | `DSL Layer 4: diff_moments (1 of 700 mutated)` | **280.9** | 281.4 ± 1.14 | 0.4% | 3.5K | 3.6K | 0.65 | 283.0 | 283.2 | 280.4 | 283.3 | 200 |
| 70 | `DSL Layer 4: history_of lineage (3 moments)` | **2.58** | 2.59 ± 0.11 | 4.2% | 365K | 410K | 0.08 | 2.72 | 2.74 | 2.44 | 2.74 | 200 |
| 71 | `DSL Layer 5: Datalog B+Tree Prefix + Join` | **15.2** | 15.2 ± 0.34 | 2.2% | 64.2K | 67.7K | 0.50 | 15.6 | 15.6 | 14.8 | 15.6 | 100 |
| 72 | `DSL Layer 5: Datalog Grouped Aggs (N=500)` | **589.1** | 589.7 ± 8.65 | 1.5% | 1.66K | 1.72K | 9.63 | 600.9 | 602.6 | 581.9 | 603.1 | 25 |
| 73 | `DSL Layer 5: Datalog Cycle-Safe reach (32-ring)` | **28.8** | 28.9 ± 0.36 | 1.3% | 34.1K | 35.0K | 0.67 | 29.3 | 29.3 | 28.6 | 29.3 | 100 |
| 74 | `DSL Layer 2: Secondary Index Evict+Update (N=200)` | **3.16** | 3.15 ± 0.07 | 2.1% | 311K | 327K | 0.10 | 3.22 | 3.22 | 3.06 | 3.22 | 200 |
| 75 | `DSL Layer 3/4: Cyclic Graph pull + diff (N=200)` | **7.39** | 7.38 ± 0.04 | 0.6% | 135K | 137K | 0.03 | 7.41 | 7.41 | 7.31 | 7.42 | 200 |


### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `40c719e2b02d`, 5 samples across 1 run(s))

#### 2.1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, 10 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | `Array_List (Radix Trie) iterator scan` | **33** | 36 ± 5.4 | 15.1% | 22.2M | 31.3M | 2 | 43 | 45 | 32 | 45 | 2K |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **60** | 61 ± 0.9 | 1.5% | 16.1M | 16.7M | 1 | 62 | 62 | 60 | 62 | 2K |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **53** | 54 ± 2.4 | 4.4% | 17.2M | 19.2M | 2 | 57 | 58 | 52 | 58 | 2K |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **9** | 9 ± 0.9 | 9.5% | 90.9M | 111M | 0 | 11 | 11 | 9 | 11 | 10K |
| 48 | `Bytes: External Bytes read_bytes_buf` | **39** | 39 ± 1.6 | 4.1% | 24.4M | 27.0M | 2 | 41 | 41 | 37 | 41 | 10K |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **8** | 8 ± 1.1 | 13.4% | 100M | 143M | 0 | 10 | 10 | 7 | 10 | 10K |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **57** | 57 ± 1.1 | 2.0% | 17.2M | 18.2M | 1 | 58 | 58 | 55 | 58 | 10K |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **83** | 83 ± 2.1 | 2.5% | 11.9M | 12.7M | 1 | 84 | 84 | 79 | 84 | 256 |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **28** | 28 ± 0.4 | 1.6% | 34.5M | 35.7M | 0 | 29 | 29 | 28 | 29 | 2K |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **30** | 34 ± 7.4 | 21.4% | 21.3M | 33.3M | 5 | 45 | 47 | 30 | 47 | 2K |

#### 2.2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, 16 tests)

| # | Benchmark | Med (`ns`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **798** | 807 ± 18.0 | 2.2% | 1.2M | 1.3M | 34 | 827 | 827 | 792 | 827 | 2K |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **279** | 280 ± 2.3 | 0.8% | 3.5M | 3.6M | 4 | 283 | 283 | 278 | 283 | 2K |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **191** | 191 ± 1.9 | 1.0% | 5.2M | 5.3M | 1 | 193 | 194 | 189 | 194 | 2K |
| 5 | `HAMT Hash_Map remove & branch shortening` | **973** | 985 ± 18.7 | 1.9% | 985K | 1.0M | 19 | 1,010 | 1,014 | 972 | 1,015 | 1K |
| 6 | `HAMT Hash_Map unordered iterator scan` | **148** | 148 ± 0.5 | 0.4% | 6.76M | 6.80M | 1 | 148 | 148 | 147 | 148 | 2K |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **762** | 761 ± 13.6 | 1.8% | 1.28M | 1.34M | 20 | 777 | 779 | 747 | 779 | 2K |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **802** | 806 ± 11.1 | 1.4% | 1.2M | 1.3M | 9 | 822 | 824 | 798 | 825 | 2K |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **538** | 538 ± 6.3 | 1.2% | 1.8M | 1.9M | 5 | 545 | 546 | 529 | 546 | 2K |
| 13 | `HAMT Counted_Hash_Set membership check` | **277** | 281 ± 10.5 | 3.7% | 3.3M | 3.6M | 3 | 296 | 299 | 275 | 300 | 2K |
| 14 | `Array_List (Radix Trie) append` | **223** | 245 ± 42.0 | 17.1% | 3.2M | 4.8M | 37 | 302 | 311 | 210 | 313 | 2K |
| 15 | `Array_List (Radix Trie) random get` | **138** | 144 ± 17.7 | 12.3% | 5.7M | 7.6M | 7 | 168 | 174 | 131 | 175 | 2K |
| 17 | `Array_List (Radix Trie) in-place put` | **209** | 209 ± 14.2 | 6.8% | 4.3M | 5.2M | 12 | 227 | 229 | 192 | 230 | 2K |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **793** | 793 ± 6.2 | 0.8% | 1.2M | 1.3M | 4 | 801 | 803 | 787 | 803 | 2K |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **826** | 825 ± 8.2 | 1.0% | 1.20M | 1.23M | 8 | 832 | 833 | 812 | 833 | 2K |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **259** | 259 ± 1.9 | 0.7% | 3.8M | 3.9M | 2 | 262 | 262 | 257 | 262 | 2K |
| 63 | `DB: Re-open & trailer checksum verify` | **249** | 249 ± 3.9 | 1.6% | 4.0M | 4.1M | 6 | 253 | 253 | 244 | 253 | 5K |

#### 2.3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, 37 tests)

| # | Benchmark | Med (`µs`) | Mean ± σ | CV | Min `ops/s` | Max `ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | `HAMT CoW branched moment commits` | **2.40** | 2.45 ± 0.10 | 4.3% | 381K | 419K | 0.07 | 2.59 | 2.62 | 2.38 | 2.63 | 500 |
| 9 | `HAMT Counted_Hash_Map remove` | **1.02** | 1.02 ± 0.02 | 1.5% | 954K | 993K | 0.00 | 1.04 | 1.05 | 1.01 | 1.05 | 1K |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **1.27** | 1.28 ± 0.02 | 1.6% | 762K | 791K | 0.02 | 1.31 | 1.31 | 1.26 | 1.31 | 500 |
| 11 | `HAMT deep suffix-collision branch collapse` | **2.82** | 2.83 ± 0.03 | 1.1% | 347K | 356K | 0.03 | 2.88 | 2.88 | 2.81 | 2.88 | 500 |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **1.55** | 1.56 ± 0.07 | 4.3% | 605K | 667K | 0.11 | 1.64 | 1.65 | 1.50 | 1.65 | 2K |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **1.53** | 1.54 ± 0.10 | 6.2% | 595K | 696K | 0.10 | 1.66 | 1.68 | 1.44 | 1.68 | 500 |
| 20 | `Linked_Array_List (B-Tree) append` | **3.01** | 2.98 ± 0.10 | 3.2% | 324K | 350K | 0.14 | 3.08 | 3.08 | 2.86 | 3.08 | 2K |
| 21 | `Linked_Array_List (B-Tree) random get` | **2.34** | 2.29 ± 0.11 | 5.0% | 411K | 462K | 0.16 | 2.41 | 2.43 | 2.16 | 2.43 | 2K |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **3.56** | 3.83 ± 0.39 | 10.1% | 233K | 283K | 0.68 | 4.27 | 4.28 | 3.53 | 4.28 | 500 |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **3.58** | 3.61 ± 0.08 | 2.2% | 267K | 283K | 0.01 | 3.71 | 3.74 | 3.54 | 3.74 | 500 |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **36.3** | 36.5 ± 0.56 | 1.5% | 26.8K | 27.9K | 0.69 | 37.2 | 37.2 | 35.9 | 37.3 | 400 |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **2.48** | 2.46 ± 0.11 | 4.3% | 387K | 435K | 0.06 | 2.57 | 2.58 | 2.30 | 2.59 | 2K |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **3.53** | 3.48 ± 0.09 | 2.6% | 282K | 300K | 0.09 | 3.55 | 3.55 | 3.33 | 3.55 | 2K |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **4.51** | 4.53 ± 0.06 | 1.3% | 216K | 223K | 0.04 | 4.61 | 4.62 | 4.48 | 4.63 | 2K |
| 29 | `Sorted_Map (B+Tree) key lookup` | **4.24** | 4.26 ± 0.04 | 1.0% | 231K | 236K | 0.03 | 4.32 | 4.33 | 4.23 | 4.33 | 2K |
| 30 | `Sorted_Map (B+Tree) rank query` | **4.21** | 4.26 ± 0.12 | 2.8% | 224K | 239K | 0.08 | 4.43 | 4.46 | 4.18 | 4.47 | 2K |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **5.41** | 5.37 ± 0.11 | 2.1% | 183K | 193K | 0.03 | 5.46 | 5.47 | 5.18 | 5.47 | 2K |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **5.97** | 5.96 ± 0.03 | 0.5% | 167K | 169K | 0.04 | 6.00 | 6.00 | 5.92 | 6.00 | 1K |
| 34 | `Sorted_Map (B+Tree) get_index select` | **3.28** | 3.28 ± 0.02 | 0.8% | 301K | 308K | 0.02 | 3.31 | 3.32 | 3.25 | 3.32 | 2K |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **4.39** | 4.42 ± 0.08 | 1.8% | 219K | 229K | 0.03 | 4.53 | 4.56 | 4.36 | 4.56 | 2K |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **4.76** | 4.80 ± 0.09 | 2.0% | 201K | 211K | 0.03 | 4.93 | 4.96 | 4.74 | 4.97 | 2K |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **4.26** | 4.26 ± 0.02 | 0.4% | 234K | 236K | 0.03 | 4.28 | 4.28 | 4.24 | 4.28 | 2K |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **3.95** | 3.95 ± 0.01 | 0.3% | 252K | 254K | 0.01 | 3.97 | 3.97 | 3.94 | 3.97 | 2K |
| 39 | `Replication (genesis -> 200 moments)` | **1.04** | 1.15 ± 0.26 | 22.3% | 657K | 1.1M | 0.33 | 1.48 | 1.51 | 0.91 | 1.52 | 200 |
| 40 | `Replication (incremental 1-moment delta)` | **1.68** | 1.72 ± 0.07 | 4.1% | 548K | 599K | 0.09 | 1.81 | 1.82 | 1.67 | 1.82 | 100 |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **7.59** | 8.77 ± 2.77 | 31.6% | 74.9K | 160K | 1.69 | 12.5 | 13.2 | 6.23 | 13.4 | 1 |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **13.7** | 14.5 ± 1.93 | 13.4% | 56.3K | 77.1K | 1.10 | 17.1 | 17.6 | 13.0 | 17.8 | 1 |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | **110.1** | 112.5 ± 8.85 | 7.9% | 8.0K | 9.6K | 12.3 | 123.6 | 124.9 | 104.2 | 125.2 | 1 |
| 44 | `Replication (Post-compaction resync)` | **1.74** | 1.74 ± 0.04 | 2.4% | 561K | 598K | 0.03 | 1.78 | 1.78 | 1.67 | 1.78 | 1 |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **1.67** | 1.69 ± 0.06 | 3.3% | 560K | 609K | 0.03 | 1.77 | 1.78 | 1.64 | 1.79 | 256 |
| 55 | `Path: 4-level nested cursor_write_path` | **1.55** | 1.57 ± 0.04 | 2.4% | 618K | 654K | 0.05 | 1.61 | 1.62 | 1.53 | 1.62 | 500 |
| 56 | `Path: 4-level nested cursor_read_path` | **1.29** | 1.29 ± 0.01 | 0.8% | 765K | 779K | 0.01 | 1.31 | 1.31 | 1.28 | 1.31 | 500 |
| 58 | `Backend: Core_Memory commits` | **2.53** | 2.59 ± 0.16 | 6.0% | 348K | 397K | 0.01 | 2.80 | 2.86 | 2.52 | 2.87 | 500 |
| 59 | `Backend: Core_Buffered_File commits` | **18.6** | 18.7 ± 0.63 | 3.4% | 50.6K | 55.0K | 0.45 | 19.6 | 19.7 | 18.2 | 19.8 | 500 |
| 60 | `Backend: Core_File (unbuffered) commits` | **48.5** | 48.9 ± 0.97 | 2.0% | 19.9K | 20.8K | 1.34 | 50.2 | 50.3 | 48.1 | 50.3 | 500 |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1.96** | 1.97 ± 0.09 | 4.4% | 480K | 531K | 0.14 | 2.07 | 2.08 | 1.89 | 2.09 | 500 |
| 62 | `Tx: Aborted transaction rollback truncate` | **1.93** | 1.94 ± 0.03 | 1.6% | 502K | 523K | 0.02 | 1.98 | 1.99 | 1.91 | 1.99 | 500 |

### 3. 1v1 Statistical Comparison (Odin vs. Zig, Commit `40c719e2b02d`)

#### 3.1 Sub-100ns Fast Path (`ns`, 16 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | **2.94x** | **65** | 191 | `55.7` ★ | 66 ± 4.7 | 7.1% | 71 | 191 ± 1.9 | 1.0% | 193 |
| 6 | `HAMT Hash_Map unordered iterator scan` | **3.36x** | **44** | 148 | `40.0` ★ | 45 ± 5.7 | 12.5% | 53 | 148 ± 0.5 | 0.4% | 148 |
| 15 | `Array_List (Radix Trie) random get` | **2.56x** | **54** | 138 | `11.4` ★ | 53 ± 2.6 | 4.9% | 56 | 144 ± 17.7 | 12.3% | 168 |
| 16 | `Array_List (Radix Trie) iterator scan` | **2.36x** | **14** | 33 | `8.8` ★ | 14 ± 1.2 | 8.7% | 16 | 36 ± 5.4 | 15.1% | 43 |
| 21 | `Linked_Array_List (B-Tree) random get` | **37.66x** | **62** | 2,335 | `43.5` ★ | 65 ± 12.4 | 19.0% | 82 | 2,292 ± 114 | 5.0% | 2,414 |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **3.75x** | **16** | 60 | `53.1` ★ | 16 ± 1.6 | 10.1% | 18 | 61 ± 0.9 | 1.5% | 62 |
| 31 | `Sorted_Map (B+Tree) ordered scan` | **3.79x** | **14** | 53 | `36.8` ★ | 14 ± 0.4 | 3.1% | 15 | 54 ± 2.4 | 4.4% | 57 |
| 34 | `Sorted_Map (B+Tree) get_index select` | **46.86x** | **70** | 3,280 | `281.8` ★ | 72 ± 5.1 | 7.0% | 79 | 3,280 ± 24.9 | 0.8% | 3,312 |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | **1.50x** | **6** | 9 | `6.4` ★ | 6 ± 0.5 | 8.6% | 7 | 9 ± 0.9 | 9.5% | 11 |
| 48 | `Bytes: External Bytes read_bytes_buf` | **3.90x** | **10** | 39 | `39.2` ★ | 10 ± 0.4 | 4.4% | 11 | 39 ± 1.6 | 4.1% | 41 |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | **1.14x** | **7** | 8 | `0.4` ~ | 8 ± 1.8 | 22.9% | 10 | 8 ± 1.1 | 13.4% | 10 |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | **5.70x** | **10** | 57 | `84.7` ★ | 10 ± 0.4 | 4.4% | 11 | 57 ± 1.1 | 2.0% | 58 |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **1.48x** | **56** | 83 | `22.8` ★ | 56 ± 1.6 | 2.8% | 58 | 83 ± 2.1 | 2.5% | 84 |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | **4.00x** | **7** | 28 | `75.7` ★ | 7 ± 0.4 | 6.6% | 7 | 28 ± 0.4 | 1.6% | 29 |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **2.00x** | **15** | 30 | `5.8` ★ | 15 ± 1.2 | 8.2% | 17 | 34 ± 7.4 | 21.4% | 45 |
| 63 | `DB: Re-open & trailer checksum verify` | **4.29x** | **58** | 249 | `97.9` ★ | 59 ± 1.9 | 3.3% | 61 | 249 ± 3.9 | 1.6% | 253 |

#### 3.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 38 tests)

| # | Benchmark | Speedup | Odin Med (`ns`) | Zig Med (`ns`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | **3.63x** | **220** | 798 | `71.2` ★ | 220 ± 4.1 | 1.8% | 224 | 807 ± 18.0 | 2.2% | 827 |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | **2.71x** | **103** | 279 | `37.1` ★ | 106 ± 10.2 | 9.7% | 119 | 280 ± 2.3 | 0.8% | 283 |
| 5 | `HAMT Hash_Map remove & branch shortening` | **5.44x** | **179** | 973 | `51.9` ★ | 195 ± 28.4 | 14.6% | 234 | 985 ± 18.7 | 1.9% | 1,010 |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | **3.36x** | **227** | 762 | `28.6` ★ | 236 ± 38.7 | 16.4% | 288 | 761 ± 13.6 | 1.8% | 777 |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | **3.56x** | **225** | 802 | `35.8` ★ | 243 ± 33.4 | 13.7% | 289 | 806 ± 11.1 | 1.4% | 822 |
| 9 | `HAMT Counted_Hash_Map remove` | **5.25x** | **194** | 1,019 | `96.7` ★ | 195 ± 11.3 | 5.8% | 209 | 1,022 ± 15.4 | 1.5% | 1,042 |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | **6.41x** | **198** | 1,269 | `84.5` ★ | 206 ± 20.2 | 9.8% | 233 | 1,279 ± 19.9 | 1.6% | 1,306 |
| 11 | `HAMT deep suffix-collision branch collapse` | **12.68x** | **222** | 2,816 | `185.5` ★ | 224 ± 4.4 | 2.0% | 229 | 2,833 ± 31.1 | 1.1% | 2,875 |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | **2.21x** | **243** | 538 | `27.3` ★ | 252 ± 22.5 | 8.9% | 283 | 538 ± 6.3 | 1.2% | 545 |
| 13 | `HAMT Counted_Hash_Set membership check` | **2.64x** | **105** | 277 | `31.2` ★ | 107 ± 6.8 | 6.4% | 116 | 281 ± 10.5 | 3.7% | 296 |
| 14 | `Array_List (Radix Trie) append` | **1.76x** | **127** | 223 | `6.4` ★ | 123 ± 7.8 | 6.3% | 129 | 245 ± 42.0 | 17.1% | 302 |
| 17 | `Array_List (Radix Trie) in-place put` | **1.99x** | **105** | 209 | `15.7` ★ | 101 ± 6.0 | 5.9% | 106 | 209 ± 14.2 | 6.8% | 227 |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **3.81x** | **405** | 1,545 | `36.4` ★ | 392 ± 26.1 | 6.7% | 418 | 1,563 ± 67.0 | 4.3% | 1,644 |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **1.93x** | **794** | 1,532 | `9.3` ★ | 831 ± 140 | 16.8% | 1,014 | 1,536 ± 95.8 | 6.2% | 1,658 |
| 20 | `Linked_Array_List (B-Tree) append` | **11.57x** | **260** | 3,007 | `63.3` ★ | 261 ± 8.8 | 3.4% | 271 | 2,977 ± 95.6 | 3.2% | 3,075 |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **11.83x** | **301** | 3,562 | `20.3` ★ | 298 ± 14.2 | 4.8% | 313 | 3,834 ± 389 | 10.1% | 4,274 |
| 24 | `Linked_Array_List (B-Tree) middle remove` | **9.79x** | **366** | 3,584 | `87.9` ★ | 369 ± 22.7 | 6.2% | 394 | 3,607 ± 79.1 | 2.2% | 3,713 |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **39.67x** | **914** | 36,262 | `141.5` ★ | 932 ± 65.6 | 7.0% | 1,008 | 36,471 ± 558 | 1.5% | 37,171 |
| 26 | `Linked_Array_List (B-Tree) in-place put` | **13.94x** | **178** | 2,481 | `43.1` ★ | 200 ± 51.3 | 25.7% | 271 | 2,456 ± 105 | 4.3% | 2,567 |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | **8.29x** | **425** | 3,525 | `50.7` ★ | 472 ± 96.8 | 20.5% | 605 | 3,482 ± 90.9 | 2.6% | 3,549 |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **11.00x** | **410** | 4,511 | `153.7` ★ | 413 ± 9.3 | 2.3% | 424 | 4,526 ± 59.1 | 1.3% | 4,606 |
| 29 | `Sorted_Map (B+Tree) key lookup` | **24.38x** | **174** | 4,242 | `216.5` ★ | 176 ± 4.7 | 2.7% | 182 | 4,263 ± 41.9 | 1.0% | 4,320 |
| 30 | `Sorted_Map (B+Tree) rank query` | **30.25x** | **139** | 4,205 | `75.8` ★ | 142 ± 7.2 | 5.1% | 152 | 4,261 ± 121 | 2.8% | 4,429 |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **11.10x** | **487** | 5,407 | `98.8` ★ | 488 ± 2.8 | 0.6% | 492 | 5,369 ± 110 | 2.1% | 5,457 |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **22.95x** | **260** | 5,966 | `398.3` ★ | 260 ± 7.2 | 2.8% | 270 | 5,964 ± 31.2 | 0.5% | 5,997 |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **10.20x** | **430** | 4,388 | `109.0` ★ | 431 ± 4.4 | 1.0% | 436 | 4,418 ± 81.7 | 1.8% | 4,530 |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **11.89x** | **400** | 4,757 | `104.2` ★ | 400 ± 6.1 | 1.5% | 408 | 4,800 ± 94.2 | 2.0% | 4,930 |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **11.56x** | **369** | 4,265 | `462.9` ★ | 369 ± 3.9 | 1.1% | 373 | 4,264 ± 18.4 | 0.4% | 4,281 |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **25.50x** | **155** | 3,953 | `589.3` ★ | 158 ± 8.0 | 5.1% | 169 | 3,952 ± 12.0 | 0.3% | 3,967 |
| 39 | `Replication (genesis -> 200 moments)` | **8.70x** | **120** | 1,044 | `8.9` ★ | 127 ± 20.2 | 15.9% | 154 | 1,149 ± 256 | 22.3% | 1,478 |
| 40 | `Replication (incremental 1-moment delta)` | **2.06x** | **813** | 1,675 | `26.9` ★ | 821 ± 26.1 | 3.2% | 856 | 1,719 ± 69.9 | 4.1% | 1,811 |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **3.35x** | **237** | 793 | `130.5` ★ | 238 ± 7.2 | 3.0% | 248 | 793 ± 6.2 | 0.8% | 801 |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **3.39x** | **244** | 826 | `141.5` ★ | 246 ± 4.1 | 1.7% | 252 | 825 ± 8.2 | 1.0% | 832 |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **5.44x** | **308** | 1,674 | `42.2` ★ | 333 ± 45.7 | 13.7% | 396 | 1,693 ± 55.8 | 3.3% | 1,769 |
| 55 | `Path: 4-level nested cursor_write_path` | **6.34x** | **244** | 1,548 | `79.3` ★ | 244 ± 4.3 | 1.8% | 249 | 1,565 ± 37.0 | 2.4% | 1,612 |
| 56 | `Path: 4-level nested cursor_read_path` | **8.08x** | **160** | 1,293 | `232.9` ★ | 158 ± 4.9 | 3.1% | 163 | 1,293 ± 9.7 | 0.8% | 1,305 |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **2.49x** | **104** | 259 | `115.2` ★ | 105 ± 2.3 | 2.2% | 107 | 259 ± 1.9 | 0.7% | 262 |
| 62 | `Tx: Aborted transaction rollback truncate` | **2.82x** | **685** | 1,930 | `81.5` ★ | 679 ± 13.9 | 2.0% | 694 | 1,941 ± 31.7 | 1.6% | 1,984 |

#### 3.3 Multi-Microsecond Transactions & Compaction (`µs`, 9 tests)

| # | Benchmark | Speedup | Odin Med (`µs`) | Zig Med (`µs`) | Welch $z$ | Odin Mean ± σ | Odin CV | Odin `p95` | Zig Mean ± σ | Zig CV | Zig `p95` |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | `HAMT CoW branched moment commits` | **2.29x** | **1.05** | 2.40 | `17.9` ★ | 1.10 ± 0.13 | 12.1% | 1.28 | 2.45 ± 0.10 | 4.3% | 2.59 |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **1.59x** | **4.77** | 7.59 | `3.1` ★ | 4.93 ± 0.47 | 9.6% | 5.49 | 8.77 ± 2.77 | 31.6% | 12.5 |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **1.29x** | **10.6** | 13.7 | `3.8` ★ | 10.8 ± 0.94 | 8.6% | 12.1 | 14.5 ± 1.93 | 13.4% | 17.1 |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 0.81x | 136.8 | **110.1** | `5.8` ★ | 138.2 ± 4.54 | 3.3% | 144.4 | 112.5 ± 8.85 | 7.9% | 123.6 |
| 44 | `Replication (Post-compaction resync)` | **1.08x** | **1.61** | 1.74 | `4.4` ★ | 1.64 ± 0.03 | 1.9% | 1.67 | 1.74 ± 0.04 | 2.4% | 1.78 |
| 58 | `Backend: Core_Memory commits` | **2.02x** | **1.25** | 2.53 | `17.4` ★ | 1.28 ± 0.07 | 5.2% | 1.37 | 2.59 ± 0.16 | 6.0% | 2.80 |
| 59 | `Backend: Core_Buffered_File commits` | **3.89x** | **4.77** | 18.6 | `47.2` ★ | 4.85 ± 0.18 | 3.7% | 5.10 | 18.7 ± 0.63 | 3.4% | 19.6 |
| 60 | `Backend: Core_File (unbuffered) commits` | **1.03x** | **47.0** | 48.5 | `1.2` ~ | 47.8 ± 1.92 | 4.0% | 50.4 | 48.9 ± 0.97 | 2.0% | 50.2 |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **1.67x** | **1.17** | 1.96 | `20.2` ★ | 1.16 ± 0.02 | 1.8% | 1.18 | 1.97 ± 0.09 | 4.4% | 2.07 |

### 4. Commit-vs-Commit Progression (`2d6f9a7120f3` → `40c719e2b02d`, Odin)

#### 4.1 Sub-100ns Fast Path (`ns`, 16 tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `2d6f9a7` (`ns`) | Curr `40c719e` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 3 | `HAMT Hash_Map lookup (pre-hashed digest)` | `~NOISE` | `+8.3%` | 0.92x | 60 | **65** | `0.9` | 77 ± 27.4 | 66 ± 4.7 |
| 6 | `HAMT Hash_Map unordered iterator scan` | **REGRESSION** | `+18.9%` | 0.84x | 37 | **44** | `3.3` | 37 ± 0.8 | 45 ± 5.7 |
| 15 | `Array_List (Radix Trie) random get` | **REGRESSION** | `+17.4%` | 0.85x | 46 | **54** | `5.7` | 46 ± 0.5 | 53 ± 2.6 |
| 16 | `Array_List (Radix Trie) iterator scan` | `~NOISE` | `+7.7%` | 0.93x | 13 | **14** | `2.3` | 13 ± 0.5 | 14 ± 1.2 |
| 21 | `Linked_Array_List (B-Tree) random get` | **REGRESSION** | `+17.0%` | 0.85x | 53 | **62** | `2.1` | 54 ± 0.9 | 65 ± 12.4 |
| 22 | `Linked_Array_List (B-Tree) iterator scan` | **REGRESSION** | `+23.1%` | 0.81x | 13 | **16** | `3.6` | 13 ± 0.5 | 16 ± 1.6 |
| 31 | `Sorted_Map (B+Tree) ordered scan` | `~NOISE` | `+7.7%` | 0.93x | 13 | **14** | `6.0` | 13 ± 0.0 | 14 ± 0.4 |
| 34 | `Sorted_Map (B+Tree) get_index select` | **REGRESSION** | `+9.4%` | 0.91x | 64 | **70** | `3.2` | 65 ± 1.3 | 72 ± 5.1 |
| 47 | `Bytes: Inline Short_Bytes read_bytes_buf` | `~NOISE` | `+0.0%` | 1.00x | 6 | **6** | `1.6` | 6 ± 0.0 | 6 ± 0.5 |
| 48 | `Bytes: External Bytes read_bytes_buf` | `~NOISE` | `+11.1%` | 0.90x | 9 | **10** | `6.0` | 9 ± 0.0 | 10 ± 0.4 |
| 49 | `Bytes: Tagged Short_Bytes read_bytes_buf` | `~NOISE` | `+16.7%` | 0.86x | 6 | **7** | `2.2` | 6 ± 0.0 | 8 ± 1.8 |
| 50 | `Bytes: Tagged External Bytes read_bytes_buf` | `~NOISE` | `+11.1%` | 0.90x | 9 | **10** | `3.5` | 9 ± 0.4 | 10 ± 0.4 |
| 52 | `Stream: Cursor_Reader (256 x 4KB = 1MB)` | **REGRESSION** | `+7.7%` | 0.93x | 52 | **56** | `4.2` | 53 ± 0.9 | 56 ± 1.6 |
| 53 | `Stream: Cursor_Reader random seek + 64B read` | `~NOISE` | `+16.7%` | 0.86x | 6 | **7** | `0.9` | 6 ± 0.9 | 7 ± 0.4 |
| 54 | `Stream: Cursor_Writer random seek + 16B patch` | **REGRESSION** | `+15.4%` | 0.87x | 13 | **15** | `3.1` | 13 ± 0.4 | 15 ± 1.2 |
| 63 | `DB: Re-open & trailer checksum verify` | **REGRESSION** | `+3.6%` | 0.97x | 56 | **58** | `2.7` | 56 ± 0.5 | 59 ± 1.9 |

#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, 39 tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `2d6f9a7` (`ns`) | Curr `40c719e` (`ns`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | `~NOISE` | `+8.9%` | 0.92x | 202 | **220** | `0.5` | 241 ± 86.3 | 220 ± 4.1 |
| 2 | `HAMT Hash_Map point lookup (with SHA-1)` | `~NOISE` | `+8.4%` | 0.92x | 95 | **103** | `0.2` | 109 ± 31.4 | 106 ± 10.2 |
| 5 | `HAMT Hash_Map remove & branch shortening` | `~NOISE` | `+7.2%` | 0.93x | 167 | **179** | `1.5` | 173 ± 16.6 | 195 ± 28.4 |
| 7 | `HAMT Hash_Map in-place overwrite (1 tx)` | `~NOISE` | `+18.2%` | 0.85x | 192 | **227** | `1.9` | 201 ± 16.6 | 236 ± 38.7 |
| 8 | `HAMT Counted_Hash_Map bulk put (1 tx)` | `~NOISE` | `+7.1%` | 0.93x | 210 | **225** | `1.4` | 218 ± 22.8 | 243 ± 33.4 |
| 9 | `HAMT Counted_Hash_Map remove` | **REGRESSION** | `+17.6%` | 0.85x | 165 | **194** | `3.2` | 172 ± 11.7 | 195 ± 11.3 |
| 10 | `HAMT deep suffix-collision put (depth 10+)` | `~NOISE` | `+2.6%` | 0.97x | 193 | **198** | `0.3` | 202 ± 24.8 | 206 ± 20.2 |
| 11 | `HAMT deep suffix-collision branch collapse` | **REGRESSION** | `+5.2%` | 0.95x | 211 | **222** | `4.7` | 212 ± 3.8 | 224 ± 4.4 |
| 12 | `HAMT Counted_Hash_Set key-only put (1 tx)` | `~NOISE` | `+9.5%` | 0.91x | 222 | **243** | `0.9` | 236 ± 32.9 | 252 ± 22.5 |
| 13 | `HAMT Counted_Hash_Set membership check` | **REGRESSION** | `+15.4%` | 0.87x | 91 | **105** | `4.9` | 91 ± 1.5 | 107 ± 6.8 |
| 14 | `Array_List (Radix Trie) append` | **REGRESSION** | `+17.6%` | 0.85x | 108 | **127** | `4.1` | 109 ± 0.9 | 123 ± 7.8 |
| 17 | `Array_List (Radix Trie) in-place put` | **REGRESSION** | `+18.0%` | 0.85x | 89 | **105** | `4.3` | 89 ± 1.1 | 101 ± 6.0 |
| 18 | `Array_List (Radix Trie) index-seek page(10)` | **REGRESSION** | `+16.7%` | 0.86x | 347 | **405** | `3.5` | 349 ± 6.3 | 392 ± 26.1 |
| 19 | `Array_List (Radix Trie) depth-collapse slice` | **REGRESSION** | `+13.3%` | 0.88x | 701 | **794** | `2.1` | 699 ± 8.6 | 831 ± 140 |
| 20 | `Linked_Array_List (B-Tree) append` | **REGRESSION** | `+12.6%` | 0.89x | 231 | **260** | `6.9` | 231 ± 4.5 | 261 ± 8.8 |
| 23 | `Linked_Array_List (B-Tree) middle insert` | **REGRESSION** | `+16.7%` | 0.86x | 258 | **301** | `6.1` | 258 ± 2.9 | 298 ± 14.2 |
| 24 | `Linked_Array_List (B-Tree) middle remove` | `~NOISE` | `+4.9%` | 0.95x | 349 | **366** | `1.8` | 350 ± 6.4 | 369 ± 22.7 |
| 25 | `Linked_Array_List (B-Tree) concat + slice` | **REGRESSION** | `+13.3%` | 0.88x | 807 | **914** | `4.0` | 812 ± 13.1 | 932 ± 65.6 |
| 26 | `Linked_Array_List (B-Tree) in-place put` | `~NOISE` | `+10.6%` | 0.90x | 161 | **178** | `1.7` | 162 ± 1.9 | 200 ± 51.3 |
| 27 | `Linked_Array_List (B-Tree) index-seek page(10)` | `~NOISE` | `+7.9%` | 0.93x | 394 | **425** | `1.8` | 395 ± 2.3 | 472 ± 96.8 |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | **REGRESSION** | `+5.7%` | 0.95x | 388 | **410** | `6.0` | 387 ± 1.7 | 413 ± 9.3 |
| 29 | `Sorted_Map (B+Tree) key lookup` | **REGRESSION** | `+6.7%` | 0.94x | 163 | **174** | `5.8` | 163 ± 1.0 | 176 ± 4.7 |
| 30 | `Sorted_Map (B+Tree) rank query` | **REGRESSION** | `+6.1%` | 0.94x | 131 | **139** | `3.5` | 131 ± 0.7 | 142 ± 7.2 |
| 32 | `Sorted_Map (B+Tree) lower-bound page(10)` | **REGRESSION** | `+4.5%` | 0.96x | 466 | **487** | `16.1` | 465 ± 1.5 | 488 ± 2.8 |
| 33 | `Sorted_Map (B+Tree) remove & rebalance` | **REGRESSION** | `+13.0%` | 0.88x | 230 | **260** | `8.6` | 231 ± 2.6 | 260 ± 7.2 |
| 35 | `Sorted_Map (B+Tree) index-seek page(10)` | **REGRESSION** | `+7.2%` | 0.93x | 401 | **430** | `14.0` | 401 ± 1.5 | 431 ± 4.4 |
| 36 | `Sorted_Map (B+Tree) in-place overwrite` | **REGRESSION** | `+10.5%` | 0.91x | 362 | **400** | `13.8` | 362 ± 1.3 | 400 ± 6.1 |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | **REGRESSION** | `+7.6%` | 0.93x | 343 | **369** | `13.4` | 343 ± 2.0 | 369 ± 3.9 |
| 38 | `Sorted_Set (B+Tree) contains lookup` | **REGRESSION** | `+7.6%` | 0.93x | 144 | **155** | `3.7` | 145 ± 0.9 | 158 ± 8.0 |
| 39 | `Replication (genesis -> 200 moments)` | `~NOISE` | `+15.4%` | 0.87x | 104 | **120** | `1.9` | 107 ± 11.2 | 127 ± 20.2 |
| 40 | `Replication (incremental 1-moment delta)` | **REGRESSION** | `+9.4%` | 0.91x | 743 | **813** | `4.8` | 752 ± 17.9 | 821 ± 26.1 |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | **REGRESSION** | `+6.3%` | 0.94x | 223 | **237** | `4.5` | 223 ± 2.9 | 238 ± 7.2 |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | **REGRESSION** | `+4.7%` | 0.95x | 233 | **244** | `6.0` | 233 ± 2.5 | 246 ± 4.1 |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | **REGRESSION** | `+6.9%` | 0.94x | 288 | **308** | `2.0` | 291 ± 9.9 | 333 ± 45.7 |
| 55 | `Path: 4-level nested cursor_write_path` | **REGRESSION** | `+6.1%` | 0.94x | 230 | **244** | `6.0` | 231 ± 1.9 | 244 ± 4.3 |
| 56 | `Path: 4-level nested cursor_read_path` | **REGRESSION** | `+8.1%` | 0.93x | 148 | **160** | `3.7` | 148 ± 4.2 | 158 ± 4.9 |
| 57 | `Cursor: Full KV-pair scan (read_kv_pair)` | **REGRESSION** | `+7.2%` | 0.93x | 97 | **104** | `5.2` | 97 ± 2.1 | 105 ± 2.3 |
| 62 | `Tx: Aborted transaction rollback truncate` | `~NOISE` | `-1.2%` | 1.01x | 693 | **685** | `2.1` | 693 ± 3.5 | 679 ± 13.9 |
| 65 | `DSL Layer 1: String Selector get_uint (N=500)` | **REGRESSION** | `+5.6%` | 0.95x | 540 | **570** | `5.7` | 540 ± 10.9 | 572 ± 6.5 |

#### 4.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, 18 tests)

| # | Benchmark | Verdict | Delta | Speedup | Base `2d6f9a7` (`µs`) | Curr `40c719e` (`µs`) | Welch $z$ | Base Mean ± σ | Curr Mean ± σ |
| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4 | `HAMT CoW branched moment commits` | `~NOISE` | `+13.3%` | 0.88x | 0.92 | **1.05** | `0.3` | 1.14 ± 0.31 | 1.10 ± 0.13 |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | **REGRESSION** | `+28.6%` | 0.78x | 3.71 | **4.77** | `4.0` | 3.89 ± 0.32 | 4.93 ± 0.47 |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | **REGRESSION** | `+13.8%` | 0.88x | 9.35 | **10.6** | `2.8` | 9.49 ± 0.48 | 10.8 ± 0.94 |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | **REGRESSION** | `+8.0%` | 0.93x | 126.6 | **136.8** | `4.2` | 126.4 ± 4.40 | 138.2 ± 4.54 |
| 44 | `Replication (Post-compaction resync)` | **REGRESSION** | `+10.3%` | 0.91x | 1.46 | **1.61** | `8.1` | 1.46 ± 0.04 | 1.64 ± 0.03 |
| 58 | `Backend: Core_Memory commits` | `~NOISE` | `+3.1%` | 0.97x | 1.22 | **1.25** | `1.9` | 1.22 ± 0.01 | 1.28 ± 0.07 |
| 59 | `Backend: Core_Buffered_File commits` | **REGRESSION** | `+4.1%` | 0.96x | 4.58 | **4.77** | `3.4` | 4.58 ± 0.02 | 4.85 ± 0.18 |
| 60 | `Backend: Core_File (unbuffered) commits` | **REGRESSION** | `+6.6%` | 0.94x | 44.1 | **47.0** | `4.2` | 44.1 ± 0.19 | 47.8 ± 1.92 |
| 61 | `Tx: Mid-tx database_freeze + CoW clone` | **REGRESSION** | `+4.7%` | 0.96x | 1.12 | **1.17** | `4.4` | 1.11 ± 0.01 | 1.16 ± 0.02 |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | `~NOISE` | `-3.4%` | 1.04x | 4.56 | **4.41** | `1.7` | 4.71 ± 0.39 | 4.42 ± 0.03 |
| 66 | `DSL Layer 3: Struct marshal (N=200)` | `~NOISE` | `+5.4%` | 0.95x | 4.23 | **4.46** | `0.7` | 4.41 ± 0.28 | 4.50 ± 0.12 |
| 67 | `DSL Layer 3: Struct unmarshal (N=200)` | **REGRESSION** | `+7.8%` | 0.93x | 1.98 | **2.13** | `7.5` | 1.97 ± 0.03 | 2.14 ± 0.04 |
| 68 | `DSL Layer 3: Datomic pull projection (N=200)` | **REGRESSION** | `+8.0%` | 0.93x | 1.53 | **1.66** | `5.5` | 1.54 ± 0.03 | 1.68 ± 0.05 |
| 69 | `DSL Layer 4: diff_moments (1 of 700 mutated)` | **REGRESSION** | `+7.4%` | 0.93x | 261.7 | **280.9** | `9.2` | 263.4 ± 4.24 | 281.4 ± 1.14 |
| 70 | `DSL Layer 4: history_of lineage (3 moments)` | **REGRESSION** | `+37.0%` | 0.73x | 1.88 | **2.58** | `12.0` | 1.83 ± 0.09 | 2.59 ± 0.11 |
| 71 | `DSL Layer 5: Datalog B+Tree Prefix + Join` | `~NOISE` | `-1.0%` | 1.01x | 15.4 | **15.2** | `1.2` | 15.6 ± 0.68 | 15.2 ± 0.34 |
| 72 | `DSL Layer 5: Datalog Grouped Aggs (N=500)` | **FASTER** | `-31.1%` | 1.45x | 855.4 | **589.1** | `21.4` | 842.9 ± 25.0 | 589.7 ± 8.65 |
| 73 | `DSL Layer 5: Datalog Cycle-Safe reach (32-ring)` | **REGRESSION** | `+6.2%` | 0.94x | 27.1 | **28.8** | `2.3` | 27.7 ± 1.17 | 28.9 ± 0.36 |

### 5. Database Storage Footprint (`bytes_used > 0`)

| # | Benchmark | Ops | Odin Size | Zig Size |
| ---: | :--- | ---: | ---: | ---: |
| 1 | `HAMT Hash_Map bulk put (1 tx)` | 2K | 214.5 KB | 214.5 KB |
| 4 | `HAMT CoW branched moment commits` | 500 | 457.7 KB | 457.7 KB |
| 14 | `Array_List (Radix Trie) append` | 2K | 19.3 KB | 19.3 KB |
| 20 | `Linked_Array_List (B-Tree) append` | 2K | 45.3 KB | 45.3 KB |
| 28 | `Sorted_Map (B+Tree) out-of-order put` | 2K | 115.4 KB | 115.4 KB |
| 37 | `Sorted_Set (B+Tree) key-only put (1 tx)` | 2K | 80.0 KB | 80.0 KB |
| 39 | `Replication (genesis -> 200 moments)` | 200 | 250.9 KB | 250.9 KB |
| 40 | `Replication (incremental 1-moment delta)` | 100 | 132.7 KB | 132.7 KB |
| 41 | `Compaction (Memory_Offset_Map, 200 -> 1)` | 1 | 1.2 KB | 1.2 KB |
| 42 | `Compaction (File_Offset_Map, 200 -> 1)` | 1 | 1.2 KB | 1.2 KB |
| 43 | `Compaction (Heterogeneous DAG + dedup)` | 1 | 23.4 KB | 23.4 KB |
| 44 | `Replication (Post-compaction resync)` | 1 | 23.4 KB | 23.4 KB |
| 45 | `Hasher: SHA-1 (20B) HAMT put` | 2K | 224.7 KB | 224.7 KB |
| 46 | `Hasher: SHA-256 (32B) HAMT put` | 2K | 248.7 KB | 248.7 KB |
| 51 | `Stream: Cursor_Writer (256 x 4KB = 1MB)` | 256 | 1024.1 KB | 1024.1 KB |
| 58 | `Backend: Core_Memory commits` | 500 | 391.0 KB | 391.0 KB |
| 59 | `Backend: Core_Buffered_File commits` | 500 | 391.0 KB | 391.0 KB |
| 60 | `Backend: Core_File (unbuffered) commits` | 500 | 391.0 KB | 391.0 KB |
| 64 | `DSL Layer 2: Tx Commit + Secondary Index (N=500)` | 500 | 231.4 KB | — |
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
