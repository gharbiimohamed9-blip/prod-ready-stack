#!/usr/bin/env python3
"""Génère le dashboard Grafana : monitoring/grafana/dashboards/stack-overview.json"""
import json
from pathlib import Path

PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
_ids = iter(range(1, 100))


def _panel(kind, title, x, y, w, h, targets, ds, **extra):
    panel = {
        "id": next(_ids),
        "type": kind,
        "title": title,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "datasource": ds,
        "targets": targets,
    }
    panel.update(extra)
    return panel



def _prom_targets(queries):
    return [
        {
            "refId": chr(65 + i),
            "datasource": PROM,
            "expr": expr,
            "legendFormat": legend,
        }
        for i, (expr, legend) in enumerate(queries)
    ]


def timeseries(title, x, y, w, h, queries, unit="short"):
    return _panel(
        "timeseries",
        title,
        x,
        y,
        w,
        h,
        _prom_targets(queries),
        PROM,
        fieldConfig={
            "defaults": {"unit": unit},
            "overrides": [],
        },
    )


def stat(title, x, y, w, h, expr, red_from=None):
    steps = [{"color": "green", "value": None}]
    if red_from is not None:
        steps.append({"color": "red", "value": red_from})

    return _panel(
        "stat",
        title,
        x,
        y,
        w,
        h,
        _prom_targets([(expr, "")]),
        PROM,
        fieldConfig={
            "defaults": {
                "thresholds": {
                    "mode": "absolute",
                    "steps": steps,
                }
            },
            "overrides": [],
        },
    )


def logs(title, x, y, w, h, expr):
    target = [{"refId": "A", "datasource": LOKI, "expr": expr}]
    return _panel(
        "logs",
        title,
        x,
        y,
        w,
        h,
        target,
        LOKI,
        options={
            "showTime": True,
            "wrapLogMessage": True,
            "sortOrder": "Descending",
        },
    )


DISK = (
    '100 - (node_filesystem_avail_bytes{mountpoint="/",fstype!="rootfs"} * 100'
    ' / node_filesystem_size_bytes{mountpoint="/",fstype!="rootfs"})'
)

panels = [
    stat("Cibles UP", 0, 0, 6, 4, "sum(up)"),
    stat(
        "Cibles DOWN",
        6,
        0,
        6,
        4,
        "count(up == 0) or vector(0)",
        red_from=1,
    ),
    stat(
        "Connexions PostgreSQL",
        12,
        0,
        6,
        4,
        "sum(pg_stat_activity_count)",
        red_from=24,
    ),
    stat(
        "Connexions MongoDB",
        18,
        0,
        6,
        4,
        'mongodb_ss_connections{conn_type="current"}',
    ),
    timeseries(
        "API : requêtes/s par code HTTP",
        0,
        4,
        12,
        8,
        [
            (
                "sum by (status) (rate(http_requests_total[1m]))",
                "{{status}}",
            )
        ],
        "reqps",
    ),
    timeseries(
        "API : latence p95",
        12,
        4,
        12,
        8,
        [
            (
                "histogram_quantile(0.95, sum by (le) "
                "(rate(http_request_duration_seconds_bucket[5m])))",
                "p95",
            )
        ],
        "s",
    ),
    timeseries(
        "Hôte : CPU %",
        0,
        12,
        8,
        8,
        [
            (
                '100 - avg(rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100',
                "cpu",
            )
        ],
        "percent",
    ),
    timeseries(
        "Hôte : mémoire %",
        8,
        12,
        8,
        8,
        [
            (
                "100 * (1 - node_memory_MemAvailable_bytes / "
                "node_memory_MemTotal_bytes)",
                "mem",
            )
        ],
        "percent",
    ),
    timeseries(
        "Hôte : disque / %",
        16,
        12,
        8,
        8,
        [(DISK, "disque")],
        "percent",
    ),
    timeseries(
        "Conteneurs : CPU %",
        0,
        20,
        12,
        8,
        [
            (
                'sum by (name) '
                '(rate(container_cpu_usage_seconds_total{name!=""}[1m])) * 100',
                "{{name}}",
            )
        ],
        "percent",
    ),
    timeseries(
        "Conteneurs : mémoire",
        12,
        20,
        12,
        8,
        [
            (
                'sum by (name) '
                '(container_memory_working_set_bytes{name!=""})',
                "{{name}}",
            )
        ],
        "bytes",
    ),
    logs(
        "Nginx : erreurs 5xx",
        0,
        28,
        24,
        8,
        '{service="nginx"} | json | status >= 500',
    ),
    logs(
        "API / bases : erreurs",
        0,
        36,
        24,
        8,
        '{service=~"api|postgres|mongo"} |~ '
        '"(?i)error|fatal|exception|indisponible"',
    ),
]

dashboard = {
    "uid": "prod-stack-overview",
    "title": "Production-Ready Stack : vue d'ensemble",
    "tags": ["prod-ready-stack"],
    "schemaVersion": 39,
    "version": 1,
    "editable": True,
    "refresh": "10s",
    "time": {"from": "now-30m", "to": "now"},
    "templating": {"list": []},
    "panels": panels,
}

out = Path(__file__).parent / "dashboards" / "stack-overview.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(
    json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n",
    encoding="utf-8",
)

print(f"Dashboard écrit : {out}")
