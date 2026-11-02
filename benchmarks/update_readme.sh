#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ODIN_JSONL="${SCRIPT_DIR}/odin.jsonl"
ZIG_JSONL="${SCRIPT_DIR}/zig.jsonl"
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

TABLES=$(jq -rn --arg target_commit "${TARGET_COMMIT}" '
def commify:
  tostring |
  if test("^[0-9]+$") then
    ([splits("") | select(. != "")] | reverse) as $digits |
    [range(0; $digits | length) |
      $digits[.] + (if . > 0 and (. % 3 == 0) then "," else "" end)
    ] | reverse | join("")
  else . end;

def fmt_dec1($v):
  (($v * 10 | round) / 10 | tostring) as $s |
  if ($s | test("\\.")) then $s else $s + ".0" end;

def fmt_kb($b):
  if $b > 0 then
    ((($b / 1024.0) * 10 | round) / 10 | tostring |
      if test("\\.") then . else . + ".0" end) + " KB"
  else
    "—"
  end;

def fmt_speedup($odin; $zig):
  (($zig / ([$odin, 1] | max)) * 100 | round) as $pct |
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

def pool_records($recs):
  ($recs[0]) as $first |
  ([ $recs[] | if (.samples_ns | type) == "array" and (.samples_ns | length) > 0 then .samples_ns[] else .ns_per_op end ]) as $samples |
  ($samples | sort) as $sorted |
  ($sorted | length) as $n |
  percentile($sorted; 0.50) as $med |
  (($sorted | add) / ([$n, 1] | max)) as $mean |
  (if $n > 1 then ([ $sorted[] | (. - $mean) * (. - $mean) ] | add) / ($n - 1) else 0 end) as $var |
  ($var | sqrt) as $sd |
  (($sd / ([$mean, 1e-9] | max)) * 100.0) as $cv |
  ($sorted[0] // 0) as $min_ns |
  ($sorted[$n - 1] // 0) as $max_ns |
  (($first.ops * 1e9) / ([($med * ([$first.ops, 1] | max)), 1.0] | max) | round) as $ops_sec |
  {
    rank: $first.rank,
    lang: $first.lang,
    commit: ($first.commit // "unknown"),
    name: $first.name,
    ops: $first.ops,
    runs: $n,
    ns_per_op: ($med | round),
    mean_ns: $mean,
    stddev_ns: $sd,
    cv_pct: $cv,
    min_ns: ($min_ns | round),
    max_ns: ($max_ns | round),
    ops_per_sec: $ops_sec,
    bytes_used: ([ $recs[].bytes_used ] | max)
  };

def filter_and_pool($all; $lang):
  ($all | map(select(.lang == $lang))) as $by_lang |
  (if $target_commit != "" then
    $by_lang | map(select((.commit // "") | startswith($target_commit)))
   else
    (($by_lang | last | .commit) // "unknown") as $latest |
    $by_lang | map(select((.commit // "unknown") == $latest))
   end) as $filtered |
  ($filtered | group_by(.name) | map(pool_records(.)) | sort_by(.rank));

def single_lang_table($list):
  "| # | Benchmark | Ops | Runs | Median (`ns/op`) | Mean ± σ (`ns`) | CV | Min..Max (`ns`) | `ops/sec` | Footprint |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  ($list[] |
    "| \(.rank) | `\(.name)` | \(.ops | commify) | \(.runs) | **\(.ns_per_op | commify)** | \(.mean_ns | round | commify) ± \(fmt_dec1(.stddev_ns)) | \(fmt_dec1(.cv_pct))% | \(.min_ns | commify)..\(.max_ns | commify) | \(.ops_per_sec | commify) | \(fmt_kb(.bytes_used)) |"
  );

[inputs] as $all |
filter_and_pool($all; "odin") as $odin_list |
filter_and_pool($all; "zig") as $zig_list |
(reduce $zig_list[] as $z ({}; .[$z.name] = $z)) as $zig_map |
($odin_list[0].commit // "unknown") as $odin_sha |
($zig_list[0].commit // "unknown") as $zig_sha |

"### 1. Odin Results (`-o:speed -microarch:native`, Commit `\($odin_sha)`)\n",
single_lang_table($odin_list),
"\n### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`, Commit `\($zig_sha)`)\n",
single_lang_table($zig_list),
"\n### 3. 1v1 Comparison (Odin vs. Zig, Commit `\($odin_sha)`)\n",
"| # | Benchmark | Odin (`ns/op` ± σ) | Zig (`ns/op` ± σ) | Speedup vs. Zig | Footprint |",
"| ---: | :--- | ---: | ---: | ---: | ---: |",
($odin_list[] | select($zig_map[.name] != null) | . as $o | $zig_map[$o.name] as $z |
  ($o.ns_per_op <= $z.ns_per_op) as $odin_wins |
  "| \($o.rank) | `\($o.name)` | \(if $odin_wins then "**\($o.ns_per_op | commify)** ± \(fmt_dec1($o.stddev_ns))" else "\($o.ns_per_op | commify) ± \(fmt_dec1($o.stddev_ns))" end) | \(if $odin_wins then "\($z.ns_per_op | commify) ± \(fmt_dec1($z.stddev_ns))" else "**\($z.ns_per_op | commify)** ± \(fmt_dec1($z.stddev_ns))" end) | \(if $odin_wins then "**\(fmt_speedup($o.ns_per_op; $z.ns_per_op))**" else fmt_speedup($o.ns_per_op; $z.ns_per_op) end) | \(fmt_kb($o.bytes_used)) |"
)
' "${ODIN_JSONL}" "${ZIG_JSONL}")

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
echo "Updated ${README_MD} with statistical multi-run tables (Odin, Zig, 1v1 Comparison)."
