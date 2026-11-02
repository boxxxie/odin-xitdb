#!/usr/bin/env python3
"""
Sophisticated Benchmark Runner, Multi-Run Aggregator & Commit Regression Analyzer
for xitdb-odin vs xitdb-zig.

Features:
- Multi-sample variance tracking (Mean, Median/p50, StdDev, Variance, CV%, Min/Max, IQR, p95, p99)
- Pools multiple runs associated with the same (commit, lang, benchmark) from JSONL history
- 1v1 Comparison (Odin vs Zig) with noise/variance significance awareness
- Commit-vs-Commit regression comparison (--compare-commits <SHA_A> <SHA_B>)
- Commit & Run history inspection (--list-commits, --inspect <pattern>)
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import time
from collections import defaultdict
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENCH_DIR = os.path.join(ROOT_DIR, "benchmarks")
ODIN_JSONL = os.path.join(BENCH_DIR, "odin.jsonl")
ZIG_JSONL = os.path.join(BENCH_DIR, "zig.jsonl")
HISTORY_JSONL = os.path.join(BENCH_DIR, "history.jsonl")


def find_zig() -> str:
    if "ZIG" in os.environ:
        return os.environ["ZIG"]
    bundled = os.path.join(ROOT_DIR, ".tmp", "tools", "zig-x86_64-linux-0.17.0", "zig")
    if os.path.isfile(bundled) and os.access(bundled, os.X_OK):
        return bundled
    zig_bin = shutil.which("zig")
    if zig_bin:
        return zig_bin
    raise RuntimeError("Could not find 'zig' binary. Set ZIG=/path/to/zig (0.17.0).")


def current_git_commit() -> str:
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--short=12", "HEAD"],
            cwd=ROOT_DIR,
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return out if out else "unknown"
    except Exception:
        return "unknown"


def calc_percentile(sorted_vals: List[float], p: float) -> float:
    n = len(sorted_vals)
    if n == 0:
        return 0.0
    if n == 1:
        return sorted_vals[0]
    pos = p * (n - 1)
    lo = int(math.floor(pos))
    hi = min(lo + 1, n - 1)
    frac = pos - lo
    return sorted_vals[lo] + frac * (sorted_vals[hi] - sorted_vals[lo])


def compute_pooled_stats(records: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Pools all raw `samples_ns` across multiple run records associated with the same
    (commit, lang, benchmark_name) and computes unified variance statistics.
    """
    first = records[0]
    samples: List[float] = []
    run_ids: List[str] = []

    for r in records:
        rid = str(r.get("run_id", "run-0"))
        if rid not in run_ids:
            run_ids.append(rid)
        if "samples_ns" in r and isinstance(r["samples_ns"], list) and len(r["samples_ns"]) > 0:
            samples.extend(float(x) for x in r["samples_ns"])
        elif "ns_per_op" in r:
            samples.append(float(r["ns_per_op"]))

    if not samples:
        samples = [0.0]

    sorted_s = sorted(samples)
    n = len(sorted_s)
    min_ns = sorted_s[0]
    max_ns = sorted_s[-1]
    median_ns = calc_percentile(sorted_s, 0.50)
    q1_ns = calc_percentile(sorted_s, 0.25)
    q3_ns = calc_percentile(sorted_s, 0.75)
    iqr_ns = q3_ns - q1_ns
    p95_ns = calc_percentile(sorted_s, 0.95)
    p99_ns = calc_percentile(sorted_s, 0.99)

    mean_ns = sum(sorted_s) / n
    if n > 1:
        variance_ns2 = sum((x - mean_ns) ** 2 for x in sorted_s) / (n - 1)
    else:
        variance_ns2 = 0.0
    stddev_ns = math.sqrt(variance_ns2)
    cv_pct = (stddev_ns / max(mean_ns, 1e-9)) * 100.0

    ops = int(first.get("ops", 1))
    bytes_used = max(int(r.get("bytes_used", 0)) for r in records)
    total_ms = (median_ns * max(ops, 1)) / 1e6
    ops_per_sec = (ops * 1e9) / max(median_ns * max(ops, 1), 1.0)

    return {
        "rank": int(first.get("rank", 0)),
        "lang": first.get("lang", "odin"),
        "commit": first.get("commit", "unknown"),
        "run_ids": run_ids,
        "num_invocations": len(records),
        "name": first["name"],
        "ops": ops,
        "runs": n,
        "total_ms": total_ms,
        "ns_per_op": round(median_ns),
        "median_ns": median_ns,
        "mean_ns": mean_ns,
        "stddev_ns": stddev_ns,
        "variance_ns2": variance_ns2,
        "cv_pct": cv_pct,
        "min_ns": min_ns,
        "max_ns": max_ns,
        "iqr_ns": iqr_ns,
        "p95_ns": p95_ns,
        "p99_ns": p99_ns,
        "ops_per_sec": round(ops_per_sec),
        "bytes_used": bytes_used,
        "samples_ns": samples,
    }


def load_jsonl_file(path: str) -> List[Dict[str, Any]]:
    if not os.path.isfile(path):
        return []
    out = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def match_commit(record_commit: str, target_commit: Optional[str]) -> bool:
    if not target_commit:
        return True
    rc = record_commit.strip()
    tc = target_commit.strip()
    return rc.startswith(tc) or tc.startswith(rc)


def pool_by_lang_and_test(
    records: List[Dict[str, Any]],
    lang: str,
    commit: Optional[str] = None,
) -> List[Dict[str, Any]]:
    filtered = [r for r in records if r.get("lang") == lang and match_commit(str(r.get("commit", "unknown")), commit)]
    if not filtered and commit:
        return []
    # If commit wasn't specified and multiple commits exist, default to the last commit seen in the file
    if not commit and filtered:
        latest_commit = filtered[-1].get("commit", "unknown")
        filtered = [r for r in filtered if r.get("commit", "unknown") == latest_commit]

    grouped: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    order: List[str] = []
    for r in filtered:
        name = r["name"]
        if name not in grouped:
            order.append(name)
        grouped[name].append(r)

    pooled = [compute_pooled_stats(grouped[name]) for name in order]
    pooled.sort(key=lambda x: x["rank"])
    return pooled


def fmt_kb(bytes_used: int) -> str:
    if bytes_used > 0:
        return f"{bytes_used / 1024.0:.1f} KB"
    return "-"


def welch_z_score(a: Dict[str, Any], b: Dict[str, Any]) -> float:
    var_a = a["variance_ns2"]
    var_b = b["variance_ns2"]
    n_a = max(a["runs"], 1)
    n_b = max(b["runs"], 1)
    se = math.sqrt((var_a / n_a) + (var_b / n_b))
    if se < 1e-6:
        return 99.0 if abs(a["mean_ns"] - b["mean_ns"]) >= 1.0 else 0.0
    return abs(a["mean_ns"] - b["mean_ns"]) / se


def run_cmd(cmd: List[str], label: str) -> None:
    print(f"==> Running {label}: {' '.join(cmd)}", file=sys.stderr)
    proc = subprocess.run(cmd, cwd=ROOT_DIR)
    if proc.returncode != 0:
        sys.exit(proc.returncode)


def print_1v1_comparison(odin_rows: List[Dict[str, Any]], zig_rows: List[Dict[str, Any]]) -> None:
    zig_map = {r["name"]: r for r in zig_rows}
    shared = [(o, zig_map[o["name"]]) for o in odin_rows if o["name"] in zig_map]
    odin_only = [o for o in odin_rows if o["name"] not in zig_map]

    if not shared:
        print("ERROR: No matching benchmarks found between Odin and Zig.", file=sys.stderr)
        sys.exit(1)

    o_commit = odin_rows[0]["commit"]
    z_commit = zig_rows[0]["commit"]
    o_samples = odin_rows[0]["runs"]
    z_samples = zig_rows[0]["runs"]

    print()
    print("=" * 150)
    print(
        f"  xitdb 1v1 Statistical Benchmark Comparison: Odin (-o:speed) vs Zig 0.17.0 (-Doptimize=ReleaseFast)\n"
        f"  Commit: Odin={o_commit} ({o_samples} samples/test across {odin_rows[0]['num_invocations']} run(s)) | "
        f"Zig={z_commit} ({z_samples} samples/test across {zig_rows[0]['num_invocations']} run(s))"
    )
    print("=" * 150)
    header = (
        f"  {'Benchmark':<46} | {'Ops':>7} | {'Odin Med ± σ (CV%)':>23} | "
        f"{'Zig Med ± σ (CV%)':>23} | {'Speedup (Sig)':>19} | {'Footprint':>12}"
    )
    print(header)
    print("  " + "-" * 146)

    odin_wins = 0
    zig_wins = 0
    ties = 0
    footprint_mismatches = 0

    for o, z in shared:
        o_sz = fmt_kb(o["bytes_used"])
        z_sz = fmt_kb(z["bytes_used"])
        if o_sz != z_sz:
            footprint_mismatches += 1
            size_col = f"{o_sz}!={z_sz}"
        else:
            size_col = o_sz

        o_med = max(o["median_ns"], 1.0)
        z_med = max(z["median_ns"], 1.0)
        z_stat = welch_z_score(o, z)
        sig_flag = "*" if z_stat >= 1.96 else "~"

        o_cell = f"{o['ns_per_op']:>6} ± {o['stddev_ns']:>5.1f} ({o['cv_pct']:>4.1f}%)"
        z_cell = f"{z['ns_per_op']:>6} ± {z['stddev_ns']:>5.1f} ({z['cv_pct']:>4.1f}%)"

        if o["ns_per_op"] == z["ns_per_op"]:
            ties += 1
            ratio_str = "1.00x (tie)"
        elif o_med < z_med:
            odin_wins += 1
            ratio = z_med / o_med
            ratio_str = f"{ratio:5.2f}x Odin ({sig_flag})"
        else:
            zig_wins += 1
            ratio = o_med / z_med
            ratio_str = f"{ratio:5.2f}x Zig  ({sig_flag})"

        print(
            f"  {o['name']:<46} | {o['ops']:>7} | {o_cell:>23} | "
            f"{z_cell:>23} | {ratio_str:>19} | {size_col:>12}"
        )

    if odin_only:
        print("  " + "-" * 146)
        print(f"  Odin-Only Benchmarks (5-Layer DSL & Datalog Engine) [{len(odin_only)} benchmarks]:")
        for o in odin_only:
            o_cell = f"{o['ns_per_op']:>6} ± {o['stddev_ns']:>5.1f} ({o['cv_pct']:>4.1f}%)"
            o_sz = fmt_kb(o["bytes_used"])
            print(
                f"  {o['name']:<46} | {o['ops']:>7} | {o_cell:>23} | "
                f"{'—':>23} | {'—':>19} | {o_sz:>12}"
            )

    print("=" * 150)
    print(
        f"  Summary ({len(shared)} shared): Odin faster on {odin_wins}/{len(shared)}, "
        f"Zig faster on {zig_wins}/{len(shared)}, Ties: {ties}/{len(shared)} | "
        f"Footprint Mismatches: {footprint_mismatches} | (* = Welch z>=1.96, ~ = within variance)"
    )
    print("=" * 150)


def compare_commits(records: List[Dict[str, Any]], sha_a: str, sha_b: str, lang: str) -> None:
    rows_a = pool_by_lang_and_test(records, lang, sha_a)
    rows_b = pool_by_lang_and_test(records, lang, sha_b)

    if not rows_a:
        print(f"ERROR: No benchmark records found for commit '{sha_a}' (lang={lang}).", file=sys.stderr)
        sys.exit(1)
    if not rows_b:
        print(f"ERROR: No benchmark records found for commit '{sha_b}' (lang={lang}).", file=sys.stderr)
        sys.exit(1)

    map_b = {r["name"]: r for r in rows_b}
    paired = [(a, map_b[a["name"]]) for a in rows_a if a["name"] in map_b]

    full_a = rows_a[0]["commit"]
    full_b = rows_b[0]["commit"]

    print()
    print("=" * 154)
    print(
        f"  Commit-vs-Commit Benchmark Regression Report [{lang.upper()}]\n"
        f"  Baseline (A): {full_a} ({rows_a[0]['runs']} samples across {rows_a[0]['num_invocations']} run(s))  vs  "
        f"Candidate (B): {full_b} ({rows_b[0]['runs']} samples across {rows_b[0]['num_invocations']} run(s))"
    )
    print("=" * 154)
    print(
        f"  {'Benchmark':<46} | {'Baseline A (Med ± σ)':>22} | {'Candidate B (Med ± σ)':>22} | "
        f"{'Delta %':>9} | {'Speedup':>9} | {'Welch z':>7} | {'Verdict':<14}"
    )
    print("  " + "-" * 150)

    faster = 0
    slower = 0
    unchanged = 0

    for a, b in paired:
        med_a = max(a["median_ns"], 1.0)
        med_b = max(b["median_ns"], 1.0)
        delta_pct = ((med_b - med_a) / med_a) * 100.0
        speedup = med_a / med_b
        z = welch_z_score(a, b)

        is_sig = (z >= 1.96) and (abs(delta_pct) >= 3.0) and (abs(med_b - med_a) >= 2.0)
        if is_sig and med_b < med_a:
            verdict = "FASTER"
            faster += 1
        elif is_sig and med_b > med_a:
            verdict = "REGRESSION"
            slower += 1
        else:
            verdict = "~NOISE"
            unchanged += 1

        cell_a = f"{a['ns_per_op']:>7} ± {a['stddev_ns']:>5.1f} ns"
        cell_b = f"{b['ns_per_op']:>7} ± {b['stddev_ns']:>5.1f} ns"
        print(
            f"  {a['name']:<46} | {cell_a:>22} | {cell_b:>22} | "
            f"{delta_pct:>+8.1f}% | {speedup:>8.2f}x | {z:>7.2f} | {verdict:<14}"
        )

    print("=" * 154)
    print(
        f"  Summary ({len(paired)} benchmarks): {faster} FASTER, {slower} REGRESSION, {unchanged} ~NOISE (within variance)"
    )
    print("=" * 154)


def list_commits(records: List[Dict[str, Any]]) -> None:
    if not records:
        print("No benchmark history records found.")
        return

    summary: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for r in records:
        key = (str(r.get("commit", "unknown")), str(r.get("lang", "odin")))
        if key not in summary:
            summary[key] = {"run_ids": set(), "tests": set(), "total_samples": defaultdict(int)}
        rid = str(r.get("run_id", "run-0"))
        summary[key]["run_ids"].add(rid)
        name = r.get("name", "")
        summary[key]["tests"].add(name)
        s_cnt = len(r.get("samples_ns", [])) if isinstance(r.get("samples_ns"), list) else int(r.get("runs", 1))
        summary[key]["total_samples"][name] += max(s_cnt, 1)

    print()
    print("=" * 96)
    print(f"  {'Commit SHA':<16} | {'Lang':<6} | {'Run Sessions':>12} | {'Benchmarks':>10} | {'Pooled Samples/Test':>20} | {'Run IDs'}")
    print("  " + "-" * 92)
    for (commit, lang), info in summary.items():
        samples_counts = list(info["total_samples"].values())
        min_s = min(samples_counts) if samples_counts else 0
        max_s = max(samples_counts) if samples_counts else 0
        samp_str = f"{min_s}" if min_s == max_s else f"{min_s}..{max_s}"
        rids = ", ".join(sorted(info["run_ids"])[:4])
        if len(info["run_ids"]) > 4:
            rids += f" (+{len(info['run_ids']) - 4} more)"
        print(
            f"  {commit:<16} | {lang:<6} | {len(info['run_ids']):>12} | {len(info['tests']):>10} | {samp_str:>20} | {rids}"
        )
    print("=" * 96)


def inspect_test(records: List[Dict[str, Any]], pattern: str, commit: Optional[str]) -> None:
    pat = pattern.lower()
    matched = [
        r for r in records
        if pat in r.get("name", "").lower() and match_commit(str(r.get("commit", "unknown")), commit)
    ]
    if not matched:
        print(f"No benchmark records matching '{pattern}'" + (f" at commit '{commit}'" if commit else ""))
        return

    grouped: Dict[Tuple[str, str, str], List[Dict[str, Any]]] = defaultdict(list)
    for r in matched:
        key = (str(r.get("commit", "unknown")), str(r.get("lang", "odin")), r["name"])
        grouped[key].append(r)

    print()
    for (c_sha, lang, name), recs in grouped.items():
        pooled = compute_pooled_stats(recs)
        print("=" * 110)
        print(f"  Benchmark : {name}")
        print(f"  Commit    : {c_sha} | Lang: {lang} | Invocations: {pooled['num_invocations']} | Total Pooled Samples: {pooled['runs']}")
        print(
            f"  Stats (ns): Median={pooled['median_ns']:.2f} | Mean={pooled['mean_ns']:.2f} ± {pooled['stddev_ns']:.2f} "
            f"(CV={pooled['cv_pct']:.2f}%, Var={pooled['variance_ns2']:.2f})"
        )
        print(
            f"  Quantiles : Min={pooled['min_ns']:.0f} | IQR={pooled['iqr_ns']:.2f} | "
            f"p95={pooled['p95_ns']:.0f} | p99={pooled['p99_ns']:.0f} | Max={pooled['max_ns']:.0f}"
        )
        print(f"  Samples   : {[round(x) for x in pooled['samples_ns']]}")
        for idx, r in enumerate(recs, 1):
            r_samples = r.get("samples_ns", [r.get("ns_per_op", 0)])
            print(f"    Run #{idx} ({r.get('run_id', 'run-0')}): median={r.get('ns_per_op')} ns/op, samples={r_samples}")
    print("=" * 110)


def load_all_history() -> List[Dict[str, Any]]:
    records = load_jsonl_file(HISTORY_JSONL)
    if not records:
        records = load_jsonl_file(ODIN_JSONL) + load_jsonl_file(ZIG_JSONL)
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description="xitdb Multi-Run Statistical Benchmark Runner & Analyzer")
    parser.add_argument("--runs", type=int, default=5, help="In-process measured trials per test (default: 5)")
    parser.add_argument("--warmup", type=int, default=1, help="In-process warmup passes before trials (default: 1)")
    parser.add_argument("--commit", type=str, default=None, help="Git commit SHA to tag or query")
    parser.add_argument("--run-id", type=str, default=None, help="Run session identifier")
    parser.add_argument("--append", action="store_true", help="Append to odin.jsonl/zig.jsonl to accumulate multiple runs")
    parser.add_argument("--no-history", action="store_true", help="Do not append to benchmarks/history.jsonl")
    parser.add_argument("--from-jsonl", action="store_true", help="Analyze existing JSONL files without re-running binaries")
    parser.add_argument(
        "--compare-commits",
        nargs=2,
        metavar=("SHA_A", "SHA_B"),
        help="Compare benchmark distributions between two git commit SHAs",
    )
    parser.add_argument("--lang", choices=["odin", "zig", "both"], default="odin", help="Language for --compare-commits")
    parser.add_argument("--list-commits", action="store_true", help="List all commits and run sessions in history")
    parser.add_argument("--inspect", type=str, default=None, help="Inspect all runs and sample distributions for matching tests")

    args = parser.parse_args()

    if args.list_commits:
        list_commits(load_all_history())
        return

    if args.inspect:
        inspect_test(load_all_history(), args.inspect, args.commit)
        return

    if args.compare_commits:
        sha_a, sha_b = args.compare_commits
        records = load_all_history()
        langs = ["odin", "zig"] if args.lang == "both" else [args.lang]
        for lg in langs:
            compare_commits(records, sha_a, sha_b, lg)
        return

    if not args.from_jsonl:
        zig_bin = find_zig()
        commit_sha = args.commit or current_git_commit()
        run_id = args.run_id or f"run-{int(time.time())}"

        common_flags = [
            "--runs", str(args.runs),
            "--warmup", str(args.warmup),
            "--commit", commit_sha,
            "--run-id", run_id,
        ]
        if args.append:
            common_flags.append("--append")
        if args.no_history:
            common_flags.append("--no-history")

        run_cmd(
            ["odin", "run", "benchmarks", "-o:speed", "-microarch:native", "--"] + common_flags,
            "xitdb-odin (-o:speed -microarch:native)",
        )
        run_cmd(
            [zig_bin, "build", "bench", "-Doptimize=ReleaseFast", "-Dcpu=native", "--"] + common_flags,
            "xitdb-zig (-Doptimize=ReleaseFast -Dcpu=native)",
        )

    odin_raw = load_jsonl_file(ODIN_JSONL)
    zig_raw = load_jsonl_file(ZIG_JSONL)

    odin_rows = pool_by_lang_and_test(odin_raw, "odin", args.commit)
    zig_rows = pool_by_lang_and_test(zig_raw, "zig", args.commit)

    print_1v1_comparison(odin_rows, zig_rows)


if __name__ == "__main__":
    main()
