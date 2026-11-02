#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ODIN_JSONL="${SCRIPT_DIR}/odin.jsonl"
ZIG_JSONL="${SCRIPT_DIR}/zig.jsonl"
HISTORY_JSONL="${SCRIPT_DIR}/history.jsonl"
README_MD="${SCRIPT_DIR}/README.md"
TARGET_COMMIT="${1:-}"

if [[ ! -f "${ODIN_JSONL}" ]]; then
    echo "Error: ${ODIN_JSONL} not found. Run 'odin run benchmarks -o:speed -microarch:native' first." >&2
    exit 1
fi

if [[ ! -f "${ZIG_JSONL}" ]]; then
    echo "Error: ${ZIG_JSONL} not found. Run 'zig build bench -Doptimize=ReleaseFast -Dcpu=native' first." >&2
    exit 1
fi

INPUT_FILES=()
if [[ -f "${HISTORY_JSONL}" ]]; then
    INPUT_FILES+=("${HISTORY_JSONL}")
fi
INPUT_FILES+=("${ODIN_JSONL}" "${ZIG_JSONL}")

TABLES=$(jq -rn --arg target_commit "${TARGET_COMMIT}" '
def commify:
  tostring |
  if test("^-?[0-9]+$") then
    (if startswith("-") then "-" else "" end) as $sign |
    (ltrimstr("-") | [splits("") | select(. != "")] | reverse) as $digits |
    $sign + ([range(0; $digits | length) |
      $digits[.] + (if . > 0 and (. % 3 == 0) then "," else "" end)
    ] | reverse | join(""))
  else . end;

def nbsp:
  gsub(" "; "\u00a0");

def fmt_dec1($v):
  (($v * 10 | round) / 10 | tostring) as $s |
  if ($s | test("\\.")) then $s else $s + ".0" end;

def fmt_dec2($v):
  (($v * 100 | round) / 100 | tostring) as $s |
  if ($s | test("\\.")) then
    ($s | split(".")) as $parts |
    $parts[0] + "." + (if ($parts[1] | length) == 1 then $parts[1] + "0" else $parts[1] end)
  else
    $s + ".00"
  end;

def fmt_sigma($v):
  if $v >= 100 then ($v | round | commify) else fmt_dec1($v) end;

def fmt_us($ns):
  ($ns / 1000.0) as $us |
  if $us >= 10.0 then fmt_dec1($us)
  else fmt_dec2($us)
  end;

def fmt_ops_count($n):
  if $n >= 1000 and ($n % 1000 == 0) then (($n / 1000 | tostring) + "K")
  else ($n | commify)
  end;

def fmt_si1($v):
  if $v >= 1e8 then (($v / 1e6 | round | tostring) + "M")
  elif $v >= 1e6 then (fmt_dec1($v / 1e6) + "M")
  elif $v >= 1e5 then (($v / 1e3 | round | tostring) + "K")
  elif $v >= 1e3 then (fmt_dec1($v / 1e3) + "K")
  else ($v | round | tostring)
  end;

def fmt_si2($v):
  if $v >= 1e8 then (fmt_dec1($v / 1e6) + "M")
  elif $v >= 1e6 then (fmt_dec2($v / 1e6) + "M")
  elif $v >= 1e5 then (fmt_dec1($v / 1e3) + "K")
  elif $v >= 1e3 then (fmt_dec2($v / 1e3) + "K")
  else ($v | round | tostring)
  end;

def fmt_ops_bounds($min_ns; $max_ns):
  (1e9 / ([$max_ns, 1] | max)) as $lo_ops |
  (1e9 / ([$min_ns, 1] | max)) as $hi_ops |
  fmt_si1($lo_ops) as $lo1 |
  fmt_si1($hi_ops) as $hi1 |
  if $min_ns == $max_ns then
    [$lo1, $hi1]
  elif $lo1 != $hi1 then
    [$lo1, $hi1]
  else
    fmt_si2($lo_ops) as $lo2 |
    fmt_si2($hi_ops) as $hi2 |
    if $lo2 != $hi2 then [$lo2, $hi2] else [$lo1, $hi1] end
  end;

def fmt_ms($ms):
  (($ms * 100 | round) / 100 | tostring) as $s |
  if ($s | test("\\.")) then
    ($s | split(".")) as $parts |
    $parts[0] + "." + (if ($parts[1] | length) == 1 then $parts[1] + "0" else $parts[1] end)
  else
    $s + ".00"
  end;

def fmt_kb($b):
  if $b > 0 then
    ((($b / 1024.0) * 10 | round) / 10 | tostring |
      if test("\\.") then . else . + ".0" end) + "\u00a0KB"
  else
    "—"
  end;

def fmt_speedup($a; $b):
  (($b / ([$a, 1] | max)) * 100 | round) as $pct |
  (($pct / 100 | floor | tostring) + "." + (($pct % 100) | tostring | if length == 1 then "0" + . else . end) + "x");

def percentile($sorted; $p):
  ($sorted | length) as $n |
  if $n == 0 then 0
  elif $n == 1 then $sorted[0]
  else
    ($p * ($n - 1)) as $pos |
    ($pos | floor) as $lo |
    ([$lo + 1, $n - 1] | min) as $hi |
    ($pos - $lo) as $frac |
    $sorted[$lo] + $frac * ($sorted[$hi] - $sorted[$lo])
  end;

def welch_z($a; $b):
  ((($a.variance_ns2 / ([$a.runs, 1] | max)) + ($b.variance_ns2 / ([$b.runs, 1] | max))) | sqrt) as $se |
  if $se < 1e-6 then
    (if (($a.mean_ns - $b.mean_ns) | fabs) >= 1.0 then 99.0 else 0.0 end)
  else
    (($a.mean_ns - $b.mean_ns) | fabs) / $se
  end;

def pool_records($recs):
  ($recs | unique_by(.run_id // "run-0")) as $uniq_recs |
  ($uniq_recs[0]) as $first |
  ([ $uniq_recs[] | if (.samples_ns | type) == "array" and (.samples_ns | length) > 0 then .samples_ns[] else .ns_per_op end ]) as $samples |
  ($samples | sort) as $sorted |
  ($sorted | length) as $n |
  percentile($sorted; 0.50) as $med |
  percentile($sorted; 0.25) as $q1 |
  percentile($sorted; 0.75) as $q3 |
  ($q3 - $q1) as $iqr |
  percentile($sorted; 0.95) as $p95 |
  percentile($sorted; 0.99) as $p99 |
  (($sorted | add) / ([$n, 1] | max)) as $mean |
  (if $n > 1 then ([ $sorted[] | (. - $mean) * (. - $mean) ] | add) / ($n - 1) else 0 end) as $var |
  ($var | sqrt) as $sd |
  (($sd / ([$mean, 1e-9] | max)) * 100.0) as $cv |
  ($sorted[0] // 0) as $min_ns |
  ($sorted[$n - 1] // 0) as $max_ns |
  (($med * ([$first.ops, 1] | max)) / 1e6) as $total_ms |
  (($first.ops * 1e9) / ([($med * ([$first.ops, 1] | max)), 1.0] | max) | round) as $ops_sec |
  {
    rank: $first.rank,
    lang: $first.lang,
    commit: ($first.commit // "unknown"),
    invocations: ($uniq_recs | length),
    name: $first.name,
    ops: $first.ops,
    runs: $n,
    total_ms: $total_ms,
    ns_per_op: ($med | round),
    median_ns: $med,
    mean_ns: $mean,
    stddev_ns: $sd,
    variance_ns2: $var,
    cv_pct: $cv,
    iqr_ns: $iqr,
    p95_ns: ($p95 | round),
    p99_ns: ($p99 | round),
    min_ns: ($min_ns | round),
    max_ns: ($max_ns | round),
    ops_per_sec: $ops_sec,
    bytes_used: ([ $uniq_recs[].bytes_used ] | max)
  };

def distinct_commits($all; $lang):
  reduce ($all[] | select(.lang == $lang and (.commit // "unknown") != "unknown") | .commit) as $c (
    [];
    if (index($c) == null) then . + [$c] else . end
  );

def filter_and_pool_commit($all; $lang; $sha):
  ($all | map(select(.lang == $lang and ((.commit // "unknown") | startswith($sha))))) as $filtered |
  ($filtered | group_by(.name) | map(pool_records(.)) | sort_by(.rank));

def tier_table_ns($list):
  "| # | Benchmark | Med\u00a0(`ns`) | Mean\u00a0±\u00a0σ | CV | Min\u00a0`ops/s` | Max\u00a0`ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ($list[] |
    fmt_ops_bounds(.min_ns; .max_ns) as $ops_b |
    "| \(.rank) | `\(.name | nbsp)` | **\(.ns_per_op | commify)** | \(.mean_ns | round | commify)\u00a0±\u00a0\(fmt_sigma(.stddev_ns)) | \(fmt_dec1(.cv_pct))% | \($ops_b[0]) | \($ops_b[1]) | \(.iqr_ns | round | commify) | \(.p95_ns | commify) | \(.p99_ns | commify) | \(.min_ns | commify) | \(.max_ns | commify) | \(fmt_ops_count(.ops)) |"
  );

def tier_table_us($list):
  "| # | Benchmark | Med\u00a0(`µs`) | Mean\u00a0±\u00a0σ | CV | Min\u00a0`ops/s` | Max\u00a0`ops/s` | IQR | `p95` | `p99` | Min | Max | Ops |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ($list[] |
    fmt_ops_bounds(.min_ns; .max_ns) as $ops_b |
    "| \(.rank) | `\(.name | nbsp)` | **\(fmt_us(.median_ns))** | \(fmt_us(.mean_ns))\u00a0±\u00a0\(fmt_us(.stddev_ns)) | \(fmt_dec1(.cv_pct))% | \($ops_b[0]) | \($ops_b[1]) | \(fmt_us(.iqr_ns)) | \(fmt_us(.p95_ns)) | \(fmt_us(.p99_ns)) | \(fmt_us(.min_ns)) | \(fmt_us(.max_ns)) | \(fmt_ops_count(.ops)) |"
  );

def single_lang_section($sec_num; $lang_label; $flags; $sha; $list):
  ($list | map(select(.ns_per_op < 100))) as $fast |
  ($list | map(select(.ns_per_op >= 100 and .ns_per_op < 1000))) as $mid |
  ($list | map(select(.ns_per_op >= 1000))) as $heavy |
  "### \($sec_num). \($lang_label) Results (`\($flags)`, Commit `\($sha)`, \($list[0].runs) samples across \($list[0].invocations) run(s))\n",
  "#### \($sec_num).1 Sub-100ns Fast Path (`< 100 ns` · `10M–167M ops/s`, \($fast | length) tests)\n",
  tier_table_ns($fast),
  "\n#### \($sec_num).2 Sub-Microsecond Collection & Cursor Ops (`100–999 ns` · `1M–10M ops/s`, \($mid | length) tests)\n",
  tier_table_ns($mid),
  "\n#### \($sec_num).3 Multi-Microsecond Transactions, Compaction & Queries (`≥ 1 µs` · `1.7K–1M ops/s`, \($heavy | length) tests)\n",
  tier_table_us($heavy);

def compare_1v1_table($list; $zig_map; $unit):
  "| # | Benchmark | Speedup | Odin\u00a0Med\u00a0(`\($unit)`) | Zig\u00a0Med\u00a0(`\($unit)`) | Welch\u00a0$z$ | Odin\u00a0Mean\u00a0±\u00a0σ | Odin\u00a0CV | Odin\u00a0`p95` | Zig\u00a0Mean\u00a0±\u00a0σ | Zig\u00a0CV | Zig\u00a0`p95` |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ($list[] | . as $o | $zig_map[$o.name] as $z |
    ($o.ns_per_op <= $z.ns_per_op) as $odin_wins |
    welch_z($o; $z) as $wz |
    (if $wz >= 1.96 then "`\(fmt_dec1($wz))`\u00a0★" else "`\(fmt_dec1($wz))`\u00a0~" end) as $sig_col |
    (if $unit == "µs" then
      (if $odin_wins then "**\(fmt_us($o.median_ns))**" else fmt_us($o.median_ns) end) as $o_med |
      (if $odin_wins then fmt_us($z.median_ns) else "**\(fmt_us($z.median_ns))**" end) as $z_med |
      "\(fmt_us($o.mean_ns))\u00a0±\u00a0\(fmt_us($o.stddev_ns))" as $o_ms |
      "\(fmt_us($z.mean_ns))\u00a0±\u00a0\(fmt_us($z.stddev_ns))" as $z_ms |
      fmt_us($o.p95_ns) as $o_p95 |
      fmt_us($z.p95_ns) as $z_p95 |
      "| \($o.rank) | `\($o.name | nbsp)` | \(if $odin_wins then "**\(fmt_speedup($o.ns_per_op; $z.ns_per_op))**" else fmt_speedup($o.ns_per_op; $z.ns_per_op) end) | \($o_med) | \($z_med) | \($sig_col) | \($o_ms) | \(fmt_dec1($o.cv_pct))% | \($o_p95) | \($z_ms) | \(fmt_dec1($z.cv_pct))% | \($z_p95) |"
     else
      (if $odin_wins then "**\($o.ns_per_op | commify)**" else ($o.ns_per_op | commify) end) as $o_med |
      (if $odin_wins then ($z.ns_per_op | commify) else "**\($z.ns_per_op | commify)**" end) as $z_med |
      "\($o.mean_ns | round | commify)\u00a0±\u00a0\(fmt_sigma($o.stddev_ns))" as $o_ms |
      "\($z.mean_ns | round | commify)\u00a0±\u00a0\(fmt_sigma($z.stddev_ns))" as $z_ms |
      ($o.p95_ns | commify) as $o_p95 |
      ($z.p95_ns | commify) as $z_p95 |
      "| \($o.rank) | `\($o.name | nbsp)` | \(if $odin_wins then "**\(fmt_speedup($o.ns_per_op; $z.ns_per_op))**" else fmt_speedup($o.ns_per_op; $z.ns_per_op) end) | \($o_med) | \($z_med) | \($sig_col) | \($o_ms) | \(fmt_dec1($o.cv_pct))% | \($o_p95) | \($z_ms) | \(fmt_dec1($z.cv_pct))% | \($z_p95) |"
     end)
  );

def compare_commits_table($list; $prev_map; $prev_sha; $curr_sha; $unit):
  "| # | Benchmark | Verdict | Delta | Speedup | Base\u00a0`\($prev_sha[0:7])`\u00a0(`\($unit)`) | Curr\u00a0`\($curr_sha[0:7])`\u00a0(`\($unit)`) | Welch\u00a0$z$ | Base\u00a0Mean\u00a0±\u00a0σ | Curr\u00a0Mean\u00a0±\u00a0σ |",
  "| ---: | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ($list[] | . as $curr | $prev_map[$curr.name] as $base |
    ([$base.median_ns, 1.0] | max) as $med_a |
    ([$curr.median_ns, 1.0] | max) as $med_b |
    ((($med_b - $med_a) / $med_a) * 100.0) as $delta_pct |
    welch_z($base; $curr) as $wz |
    (($wz >= 1.96) and (($delta_pct | fabs) >= 3.0) and ((($med_b - $med_a) | fabs) >= 2.0)) as $is_sig |
    (if ($is_sig and ($med_b < $med_a)) then "**FASTER**"
     elif ($is_sig and ($med_b > $med_a)) then "**REGRESSION**"
     else "`~NOISE`" end) as $verdict |
    (if $delta_pct >= 0 then "+\(fmt_dec1($delta_pct))%" else "\(fmt_dec1($delta_pct))%" end) as $delta_str |
    (if $unit == "µs" then
      "| \($curr.rank) | `\($curr.name | nbsp)` | \($verdict) | `\($delta_str)` | \(fmt_speedup($curr.ns_per_op; $base.ns_per_op)) | \(fmt_us($base.median_ns)) | **\(fmt_us($curr.median_ns))** | `\(fmt_dec1($wz))` | \(fmt_us($base.mean_ns))\u00a0±\u00a0\(fmt_us($base.stddev_ns)) | \(fmt_us($curr.mean_ns))\u00a0±\u00a0\(fmt_us($curr.stddev_ns)) |"
     else
      "| \($curr.rank) | `\($curr.name | nbsp)` | \($verdict) | `\($delta_str)` | \(fmt_speedup($curr.ns_per_op; $base.ns_per_op)) | \($base.ns_per_op | commify) | **\($curr.ns_per_op | commify)** | `\(fmt_dec1($wz))` | \($base.mean_ns | round | commify)\u00a0±\u00a0\(fmt_sigma($base.stddev_ns)) | \($curr.mean_ns | round | commify)\u00a0±\u00a0\(fmt_sigma($curr.stddev_ns)) |"
     end)
  );

[inputs] as $all |
distinct_commits($all; "odin") as $odin_commits |
distinct_commits($all; "zig") as $zig_commits |
(if $target_commit != "" then $target_commit else ($odin_commits | last // "unknown") end) as $odin_target |
(if $target_commit != "" then $target_commit else ($zig_commits | last // "unknown") end) as $zig_target |
filter_and_pool_commit($all; "odin"; $odin_target) as $odin_list |
filter_and_pool_commit($all; "zig"; $zig_target) as $zig_list |
(reduce $zig_list[] as $z ({}; .[$z.name] = $z)) as $zig_map |
($odin_list[0].commit // "unknown") as $odin_sha |
($zig_list[0].commit // "unknown") as $zig_sha |
($odin_list | map(select($zig_map[.name] != null))) as $paired_list |
($paired_list | map(select(.ns_per_op < 100))) as $paired_fast |
($paired_list | map(select(.ns_per_op >= 100 and .ns_per_op < 1000))) as $paired_mid |
($paired_list | map(select(.ns_per_op >= 1000))) as $paired_heavy |

single_lang_section("1"; "Odin"; "-o:speed -microarch:native"; $odin_sha; $odin_list),
"\n",
single_lang_section("2"; "Zig"; "-Doptimize=ReleaseFast -Dcpu=native"; $zig_sha; $zig_list),
"\n### 3. 1v1 Statistical Comparison (Odin vs. Zig, Commit `\($odin_sha)`)\n",
"#### 3.1 Sub-100ns Fast Path (`ns`, \($paired_fast | length) tests)\n",
compare_1v1_table($paired_fast; $zig_map; "ns"),
"\n#### 3.2 Sub-Microsecond Collection & Cursor Ops (`ns`, \($paired_mid | length) tests)\n",
compare_1v1_table($paired_mid; $zig_map; "ns"),
"\n#### 3.3 Multi-Microsecond Transactions & Compaction (`µs`, \($paired_heavy | length) tests)\n",
compare_1v1_table($paired_heavy; $zig_map; "µs"),
(if ($odin_commits | length) >= 2 then
  ($odin_commits[-2]) as $prev_sha |
  filter_and_pool_commit($all; "odin"; $prev_sha) as $prev_list |
  (reduce $prev_list[] as $p ({}; .[$p.name] = $p)) as $prev_map |
  ($odin_list | map(select($prev_map[.name] != null))) as $prog_list |
  ($prog_list | map(select(.ns_per_op < 100))) as $prog_fast |
  ($prog_list | map(select(.ns_per_op >= 100 and .ns_per_op < 1000))) as $prog_mid |
  ($prog_list | map(select(.ns_per_op >= 1000))) as $prog_heavy |
  "\n### 4. Commit-vs-Commit Progression (`\($prev_sha)` → `\($odin_sha)`, Odin)\n",
  "#### 4.1 Sub-100ns Fast Path (`ns`, \($prog_fast | length) tests)\n",
  compare_commits_table($prog_fast; $prev_map; $prev_sha; $odin_sha; "ns"),
  "\n#### 4.2 Sub-Microsecond Collection & Cursor Ops (`ns`, \($prog_mid | length) tests)\n",
  compare_commits_table($prog_mid; $prev_map; $prev_sha; $odin_sha; "ns"),
  "\n#### 4.3 Multi-Microsecond Transactions, Compaction & Queries (`µs`, \($prog_heavy | length) tests)\n",
  compare_commits_table($prog_heavy; $prev_map; $prev_sha; $odin_sha; "µs")
 else empty end),
"\n### 5. Database Storage Footprint (`bytes_used > 0`)\n",
"| # | Benchmark | Ops | Odin\u00a0Size | Zig\u00a0Size |",
"| ---: | :--- | ---: | ---: | ---: |",
($odin_list[] | select(.bytes_used > 0) | . as $o | ($zig_map[$o.name] // null) as $z |
  "| \($o.rank) | `\($o.name | nbsp)` | \(fmt_ops_count($o.ops)) | \(fmt_kb($o.bytes_used)) | \(if $z != null and $z.bytes_used > 0 then fmt_kb($z.bytes_used) else "—" end) |"
)
' "${INPUT_FILES[@]}")

AWK_SCRIPT='
BEGIN { in_block = 0 }
/<!-- BEGIN_BENCHMARK_TABLE -->/ {
    print
    print tables
    in_block = 1
    next
}
/<!-- END_BENCHMARK_TABLE -->/ {
    in_block = 0
}
!in_block { print }
'

awk -v tables="${TABLES}" "${AWK_SCRIPT}" "${README_MD}" > "${README_MD}.tmp"
mv "${README_MD}.tmp" "${README_MD}"
echo "Updated ${README_MD} with full statistical tables (Odin, Zig, 1v1 Comparison, and Commit-vs-Commit Progression)."
