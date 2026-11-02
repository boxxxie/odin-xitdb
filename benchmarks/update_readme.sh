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

def fmt_sigma($v):
  if $v >= 100 then ($v | round | commify) else fmt_dec1($v) end;

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

def single_lang_table($list):
  "| # | Benchmark | Ops | Median\u00a0(`ns`) | Mean\u00a0±\u00a0σ\u00a0(`ns`) | CV | IQR | `p95`\u00a0/\u00a0`p99` | Min..Max | `ops/sec` | Size |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ($list[] |
    "| \(.rank) | `\(.name | nbsp)` | \(.ops | commify) | **\(.ns_per_op | commify)** | \(.mean_ns | round | commify)\u00a0±\u00a0\(fmt_sigma(.stddev_ns)) | \(fmt_dec1(.cv_pct))% | \(.iqr_ns | round | commify) | \(.p95_ns | commify)\u00a0/\u00a0\(.p99_ns | commify) | \(.min_ns | commify)..\(.max_ns | commify) | \(.ops_per_sec | commify) | \(fmt_kb(.bytes_used)) |"
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

"### 1. Odin Results (`-o:speed -microarch:native`, Commit `\($odin_sha)`, \($odin_list[0].runs) samples across \($odin_list[0].invocations) run(s))\n",
single_lang_table($odin_list),
"\n### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `\($zig_sha)`, \($zig_list[0].runs) samples across \($zig_list[0].invocations) run(s))\n",
single_lang_table($zig_list),
"\n### 3. 1v1 Statistical Comparison (Odin vs. Zig, Commit `\($odin_sha)`)\n",
"| # | Benchmark | Odin\u00a0(`Med\u00a0±\u00a0σ`\u00a0·\u00a0`CV`\u00a0·\u00a0`p95`) | Zig\u00a0(`Med\u00a0±\u00a0σ`\u00a0·\u00a0`CV`\u00a0·\u00a0`p95`) | Speedup | Welch\u00a0$z$ | Size |",
"| ---: | :--- | ---: | ---: | ---: | ---: | ---: |",
($odin_list[] | select($zig_map[.name] != null) | . as $o | $zig_map[$o.name] as $z |
  ($o.ns_per_op <= $z.ns_per_op) as $odin_wins |
  welch_z($o; $z) as $wz |
  (if $wz >= 1.96 then "`\(fmt_dec1($wz))`\u00a0★" else "`\(fmt_dec1($wz))`\u00a0~" end) as $sig_col |
  "| \($o.rank) | `\($o.name | nbsp)` | \(if $odin_wins then "**\($o.ns_per_op | commify)**" else ($o.ns_per_op | commify) end)\u00a0±\u00a0\(fmt_sigma($o.stddev_ns))\u00a0(`\(fmt_dec1($o.cv_pct))%`,\u00a0p95\u00a0`\($o.p95_ns | commify)`) | \(if $odin_wins then ($z.ns_per_op | commify) else "**\($z.ns_per_op | commify)**" end)\u00a0±\u00a0\(fmt_sigma($z.stddev_ns))\u00a0(`\(fmt_dec1($z.cv_pct))%`,\u00a0p95\u00a0`\($z.p95_ns | commify)`) | \(if $odin_wins then "**\(fmt_speedup($o.ns_per_op; $z.ns_per_op))**" else fmt_speedup($o.ns_per_op; $z.ns_per_op) end) | \($sig_col) | \(fmt_kb($o.bytes_used)) |"
),
(if ($odin_commits | length) >= 2 then
  ($odin_commits[-2]) as $prev_sha |
  filter_and_pool_commit($all; "odin"; $prev_sha) as $prev_list |
  (reduce $prev_list[] as $p ({}; .[$p.name] = $p)) as $prev_map |
  "\n### 4. Commit-vs-Commit Progression (`\($prev_sha)` → `\($odin_sha)`, Odin)\n",
  "| # | Benchmark | Baseline\u00a0`\($prev_sha[0:7])`\u00a0(`Med\u00a0±\u00a0σ`) | Current\u00a0`\($odin_sha[0:7])`\u00a0(`Med\u00a0±\u00a0σ`) | Delta\u00a0(%) | Speedup | Welch\u00a0$z$ | Verdict |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: | :--- |",
  ($odin_list[] | select($prev_map[.name] != null) | . as $curr | $prev_map[$curr.name] as $base |
    ([$base.median_ns, 1.0] | max) as $med_a |
    ([$curr.median_ns, 1.0] | max) as $med_b |
    ((($med_b - $med_a) / $med_a) * 100.0) as $delta_pct |
    welch_z($base; $curr) as $wz |
    (($wz >= 1.96) and (($delta_pct | fabs) >= 3.0) and ((($med_b - $med_a) | fabs) >= 2.0)) as $is_sig |
    (if ($is_sig and ($med_b < $med_a)) then "**FASTER**"
     elif ($is_sig and ($med_b > $med_a)) then "**REGRESSION**"
     else "`~NOISE`" end) as $verdict |
    (if $delta_pct >= 0 then "+\(fmt_dec1($delta_pct))%" else "\(fmt_dec1($delta_pct))%" end) as $delta_str |
    "| \($curr.rank) | `\($curr.name | nbsp)` | \($base.ns_per_op | commify)\u00a0±\u00a0\(fmt_sigma($base.stddev_ns)) | **\($curr.ns_per_op | commify)**\u00a0±\u00a0\(fmt_sigma($curr.stddev_ns)) | `\($delta_str)` | \(fmt_speedup($curr.ns_per_op; $base.ns_per_op)) | `\(fmt_dec1($wz))` | \($verdict) |"
  )
 else empty end)
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
