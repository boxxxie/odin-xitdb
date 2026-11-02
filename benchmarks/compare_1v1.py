#!/usr/bin/env python3
"""
1v1 Benchmark Runner & Side-by-Side Comparison: xitdb-odin vs xitdb-zig
"""

import os
import re
import shutil
import subprocess
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ROW_RE = re.compile(
    r"^\s*(.+?)\s+\|\s+(\d+)\s+\|\s+([\d.]+)\s+\|\s+(\d+)\s+\|\s+(\d+)(?:\s+\(([\d.]+\s+KB)\))?\s*$"
)


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


def parse_rows(output: str):
    rows = []
    for line in output.splitlines():
        m = ROW_RE.match(line)
        if m:
            name = m.group(1).strip()
            ops = int(m.group(2))
            total_ms = float(m.group(3))
            ns_per_op = int(m.group(4))
            ops_per_sec = int(m.group(5))
            size_str = m.group(6).strip() if m.group(6) else "-"
            rows.append(
                {
                    "name": name,
                    "ops": ops,
                    "total_ms": total_ms,
                    "ns_per_op": ns_per_op,
                    "ops_per_sec": ops_per_sec,
                    "size_str": size_str,
                }
            )
    return rows


def run_cmd(cmd, label):
    print(f"==> Running {label}: {' '.join(cmd)}", file=sys.stderr)
    proc = subprocess.run(
        cmd,
        cwd=ROOT_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if proc.returncode != 0:
        print(f"ERROR running {label}:\n{proc.stderr}\n{proc.stdout}", file=sys.stderr)
        sys.exit(proc.returncode)
    return proc.stdout + "\n" + proc.stderr


def main():
    zig_bin = find_zig()
    odin_out = run_cmd(["odin", "run", "benchmarks", "-o:speed"], "xitdb-odin (-o:speed)")
    zig_out = run_cmd(
        [zig_bin, "build", "bench", "-Doptimize=ReleaseFast"],
        "xitdb-zig (-Doptimize=ReleaseFast)",
    )

    odin_rows = parse_rows(odin_out)
    zig_rows = parse_rows(zig_out)

    if len(odin_rows) != len(zig_rows):
        print(
            f"ERROR: Row count mismatch: Odin={len(odin_rows)}, Zig={len(zig_rows)}",
            file=sys.stderr,
        )
        sys.exit(1)

    print()
    print("=" * 124)
    print(
        f"  xitdb 1v1 Benchmark Comparison: Odin (-o:speed) vs Zig 0.17.0 (-Doptimize=ReleaseFast) [{len(odin_rows)} benchmarks]"
    )
    print("=" * 124)
    header = (
        f"  {'Benchmark':<46} | {'Ops':>8} | {'Odin ns/op':>11} | {'Zig ns/op':>11} | "
        f"{'Ratio (Zig/Odin)':>17} | {'DB Footprint':>12}"
    )
    print(header)
    print("  " + "-" * 120)

    odin_wins = 0
    zig_wins = 0
    ties = 0
    footprint_mismatches = 0

    for o, z in zip(odin_rows, zig_rows):
        if o["name"] != z["name"] or o["ops"] != z["ops"]:
            print(
                f"ERROR: Benchmark mismatch: Odin=({o['name']}, {o['ops']}) vs Zig=({z['name']}, {z['ops']})",
                file=sys.stderr,
            )
            sys.exit(1)

        if o["size_str"] != z["size_str"]:
            footprint_mismatches += 1
            size_col = f"{o['size_str']} != {z['size_str']}"
        else:
            size_col = o["size_str"]

        o_ns = max(o["ns_per_op"], 1)
        z_ns = max(z["ns_per_op"], 1)
        if o["ns_per_op"] == z["ns_per_op"]:
            ties += 1
            ratio_str = "1.00x (tie)"
        elif o_ns < z_ns:
            odin_wins += 1
            ratio = z_ns / o_ns
            ratio_str = f"{ratio:5.2f}x Odin"
        else:
            zig_wins += 1
            ratio = o_ns / z_ns
            ratio_str = f"{ratio:5.2f}x Zig "

        print(
            f"  {o['name']:<46} | {o['ops']:>8} | {o['ns_per_op']:>8} ns | {z['ns_per_op']:>8} ns | "
            f"{ratio_str:>17} | {size_col:>12}"
        )

    print("=" * 124)
    print(
        f"  Summary: Odin faster on {odin_wins}/{len(odin_rows)}, "
        f"Zig faster on {zig_wins}/{len(odin_rows)}, "
        f"Ties: {ties}/{len(odin_rows)} | "
        f"Wire Footprint Mismatches: {footprint_mismatches}"
    )
    print("=" * 124)


if __name__ == "__main__":
    main()
