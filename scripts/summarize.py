"""측정 원자료에서 회차별 값을 뽑는다.

    python3 scripts/summarize.py results/2026-11

docs/results.md 의 회차별 표가 이 출력이다.
"""

import gzip
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ORDER = ["lua", "watch", "atomic", "pess", "rlock", "opt"]


def read(path):
    if path.suffix == ".gz":
        return gzip.decompress(path.read_bytes()).decode()
    return path.read_text()


def count(metrics, name, key="count"):
    m = metrics.get(name)
    return m.get(key, 0) if m else 0


def dbstat(text, section):
    block = text.split(f"=== dbstat {section} ===")[1].split("===")[0]
    return {p[0]: float(p[1]) for p in (line.split() for line in block.splitlines()) if len(p) == 2 and p[1].isdigit()}


def run_seconds(k6_text):
    m, s = re.findall(r"(\d+)m(\d+\.\d)s/5m0s\s+20000/20000", k6_text)[-1]
    return int(m) * 60 + float(s)


def load_cpu(vmstat_text, start, end):
    """k6 가 부하를 건 구간의 vmstat 만 본다. 측정 전후의 유휴 구간을 빼야 포화 여부가 보인다."""
    rows = []
    for line in vmstat_text.splitlines():
        p = line.split()
        if not p or not p[0].isdigit():
            continue
        ts = datetime.strptime(f"{p[-2]} {p[-1]}", "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp()
        if start <= ts <= end:
            rows.append((int(p[12]), int(p[14])))
    return sum(r[0] for r in rows) / len(rows), sum(r[1] for r in rows) / len(rows), min(r[1] for r in rows)


def summarize(root, name):
    app, k6 = root / "app", root / "k6"
    metrics = json.loads(read(k6 / f"{name}.json"))["metrics"]
    k6_text = read(k6 / f"{name}.txt.gz")
    before, after = read(app / f"before-{name}.txt"), read(app / f"after-{name}.txt")
    b, a = dbstat(before, "BEFORE"), dbstat(after, "AFTER")
    delta = {k: int(a[k] - b[k]) for k in ("Com_insert", "Com_rollback", "Com_update", "Innodb_row_lock_waits")}
    maxes = dict(re.findall(r"^\s+(hikaricp_connections_\w+)\s+([\d.]+)", after, re.M))

    seconds = run_seconds(k6_text)
    end = float(read(k6 / f"{name}-time.txt").split()[3])
    us, idle, idle_min = load_cpu(read(app / f"vmstat-{name}.txt"), end - seconds, end)

    iterations = count(metrics, "iterations")
    errors = count(metrics, "errors")
    return {
        "name": name,
        "seconds": seconds,
        "k6_issued": count(metrics, "issued"),
        "db_issued": int(re.search(r"발급 (\d+)", read(app / f"drain-{name}.txt")).group(1)),
        "fail_rate": 100 * errors / iterations,
        "server_errors": count(metrics, "server_errors"),
        "timeouts": count(metrics, "timeouts"),
        "other_errors": count(metrics, "other_errors"),
        "server_error_med": count(metrics, "server_error_duration", "med") / 1000,
        "p95": metrics["http_req_duration"]["p(95)"] / 1000,
        "pool": int(float(maxes["hikaricp_connections_max"])),
        "active": int(float(maxes.get("hikaricp_connections_active", 0))),
        "pending": int(float(maxes.get("hikaricp_connections_pending", 0))),
        "cpu_us": us,
        "cpu_idle": idle,
        "cpu_idle_min": idle_min,
        "accept_queue_max": int(after.strip().splitlines()[-1]),
        **delta,
    }


def main():
    root = Path(sys.argv[1])
    names = [p.name.removesuffix(".json") for p in (root / "k6").glob("*.json")]
    names.sort(key=lambda n: (ORDER.index(n.split("-")[0]), -int(n.split("-")[1]), n))
    print(
        "| 회차 | 풀 | 실행 | k6 발급 | DB 발급 | 실패율 | 5xx | 타임아웃 | 5xx 중앙값 | p95 | active | pending "
        "| 부하 구간 CPU us | 유휴 평균 | 유휴 최저 | accept 큐 최대 | insert | rollback | update | 락 대기 |"
    )
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for n in names:
        r = summarize(root, n)
        med = f"{r['server_error_med']:.1f}s" if r["server_errors"] else "-"
        print(
            f"| `{n}` | {r['pool']} | {r['seconds']:.1f}s | {r['k6_issued']:,} | {r['db_issued']:,} | {r['fail_rate']:.2f}% "
            f"| {r['server_errors']:,} | {r['timeouts']:,} | {med} | {r['p95']:.2f}s | {r['active']} | {r['pending']} "
            f"| {r['cpu_us']:.1f}% | {r['cpu_idle']:.1f}% | {r['cpu_idle_min']}% | {r['accept_queue_max']:,} "
            f"| {r['Com_insert']:,} | {r['Com_rollback']:,} | {r['Com_update']:,} | {r['Innodb_row_lock_waits']:,} |"
        )


if __name__ == "__main__":
    main()
