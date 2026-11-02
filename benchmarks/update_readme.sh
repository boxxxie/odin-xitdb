#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ODIN_JSONL="${SCRIPT_DIR}/odin.jsonl"
ZIG_JSONL="${SCRIPT_DIR}/zig.jsonl"
README_MD="${SCRIPT_DIR}/README.md"

if [[ ! -f "${ODIN_JSONL}" ]]; then
    echo "Error: ${ODIN_JSONL} not found. Run 'odin run benchmarks -o:speed -microarch:native' first." >&2
    exit 1
fi

if [[ ! -f "${ZIG_JSONL}" ]]; then
    echo "Error: ${ZIG_JSONL} not found. Run 'zig build bench -Doptimize=ReleaseFast -Dcpu=native' first." >&2
    exit 1
fi

TABLES=$(jq -rn '
def commify:
  tostring |
  if test("^[0-9]+$") then
    ([splits("") | select(. != "")] | reverse) as $digits |
    [range(0; $digits | length) |
      $digits[.] + (if . > 0 and (. % 3 == 0) then "," else "" end)
    ] | reverse | join("")
  else . end;

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
      if test("\\.") then . else . + ".0" end) + " KB"
  else
    "—"
  end;

def fmt_speedup($odin; $zig):
  (($zig / ([$odin, 1] | max)) * 100 | round) as $pct |
  (($pct / 100 | floor | tostring) + "." + (($pct % 100) | tostring | if length == 1 then "0" + . else . end) + "x");

def single_lang_table($list):
  "| # | Benchmark | Ops | Total (`ms`) | `ns/op` | `ops/sec` | Footprint |",
  "| ---: | :--- | ---: | ---: | ---: | ---: | ---: |",
  ($list[] |
    "| \(.rank) | `\(.name)` | \(.ops | commify) | \(fmt_ms(.total_ms)) | **\(.ns_per_op | commify)** | \(.ops_per_sec | commify) | \(fmt_kb(.bytes_used)) |"
  );

[inputs] as $all |
($all | map(select(.lang == "odin")) | sort_by(.rank)) as $odin_list |
($all | map(select(.lang == "zig")) | sort_by(.rank)) as $zig_list |
(reduce $zig_list[] as $z ({}; .[$z.name] = $z)) as $zig_map |

"### 1. Odin Results (`-o:speed -microarch:native`)\n",
single_lang_table($odin_list),
"\n### 2. Zig Results (`-Doptimize=ReleaseFast -Dcpu=native`)\n",
single_lang_table($zig_list),
"\n### 3. 1v1 Comparison (Odin vs. Zig)\n",
"| # | Benchmark | Odin (`ns/op`) | Zig (`ns/op`) | Speedup vs. Zig | Footprint |",
"| ---: | :--- | ---: | ---: | ---: | ---: |",
($odin_list[] | . as $o | ($zig_map[$o.name] // $o) as $z |
  ($o.ns_per_op <= $z.ns_per_op) as $odin_wins |
  "| \($o.rank) | `\($o.name)` | \(if $odin_wins then "**\($o.ns_per_op | commify)**" else ($o.ns_per_op | commify) end) | \(if $odin_wins then ($z.ns_per_op | commify) else "**\($z.ns_per_op | commify)**" end) | \(if $odin_wins then "**\(fmt_speedup($o.ns_per_op; $z.ns_per_op))**" else fmt_speedup($o.ns_per_op; $z.ns_per_op) end) | \(fmt_kb($o.bytes_used)) |"
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
echo "Updated ${README_MD} with 3 tables (Odin, Zig, 1v1 Comparison)."
