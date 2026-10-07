#!/usr/bin/env bash
# Run each query in sql/03_queries.sql a few times and report the best wall-clock time.
set -euo pipefail

cd "$(dirname "$0")/.."
RUNS="${RUNS:-3}"

python3 - "$RUNS" <<'PY'
import re, subprocess, sys, time

runs = int(sys.argv[1])
text = open("sql/03_queries.sql").read()
blocks = re.split(r"\n(?=-- Q\d+\.)", text)

print(f"{'query':<70} {'best ms':>8}")
print("-" * 79)
for block in blocks:
    m = re.match(r"-- (Q\d+\.[^\n]*)", block)
    if not m:
        continue
    title = m.group(1)[:68]
    sql = "USE hvac_dw;\n" + "\n".join(l for l in block.splitlines() if not l.strip().startswith("--"))
    best = None
    for _ in range(runs):
        t0 = time.perf_counter()
        subprocess.run(
            ["docker", "exec", "-i", "starrocks", "mysql", "-h127.0.0.1", "-P9030", "-uroot"],
            input=sql.encode(), stdout=subprocess.DEVNULL, check=True,
        )
        ms = (time.perf_counter() - t0) * 1000
        best = ms if best is None else min(best, ms)
    print(f"{title:<70} {best:>8.0f}")

print("\nTimes include docker exec + client startup (~50-100 ms). The query profile in the")
print("FE web UI (http://localhost:8030) shows server-side execution time on its own.")
PY
