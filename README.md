# dgx-spark-observability

Layer-1 host observability for DGX Spark / Blackwell GB10 / sm_121a / aarch64.

## What you get

A self-contained, 11-container LGTM-style stack:

- **Prometheus** + **Grafana** + **Loki** + **Promtail** + **Alertmanager** + **ntfy** (self-hosted push).
- Exporters: **node-exporter**, **smartctl-exporter** (arm64-rebuilt), **cAdvisor**, **dcgm-exporter**, plus an **nvidia-textfile** sidecar that fills DCGM gaps on Blackwell unified memory.
- 6-month metric retention, 90-day system-log retention.
- 13 hardware alerts (RAM/disk/GPU temp/throttle/OOM/NVMe SMART/etc.) with runbook annotations.
- Overnight push mute (23:00–08:00 in `${TZ}`).
- Custom **38-panel** at-a-glance host dashboard (`Spark Host Overview`) plus three pre-wired Grafana community dashboards.

## Why this exists

Generic LGTM templates assume x86_64 + discrete-VRAM NVIDIA GPUs. DGX Spark is **aarch64 + Blackwell GB10 with unified memory**, and that combination breaks several common assumptions:

- `smartctl_exporter` ships **amd64-only** manifests upstream.
- `dcgm-exporter` 4.x doesn't expose `FB_USED/FB_FREE` on unified memory and doesn't load the profiling module on sm_121a.
- `cadvisor` v0.49.x uses a Docker client API too old for Docker 25+.
- Alertmanager rejects overnight mute windows directly.
- A handful of `nvidia-smi` query fields behave differently on unified memory and on driver 580+.

This template documents and works around all of these. See [`docs/DGX-SPARK-QUIRKS.md`](docs/DGX-SPARK-QUIRKS.md) for the full list with symptom / cause / fix / upstream status.

## Hardware compatibility

| | |
|---|---|
| **Tested** | DGX Spark (GB10 / sm_121a / aarch64), Ubuntu 24.04, Docker 25+ |
| **Likely compatible** | NVIDIA Jetson Orin / Thor (aarch64 + NVIDIA), Grace+Hopper (aarch64 + Hopper), any ARM64 Linux + NVIDIA GPU |
| **Untested but should work** | x86_64 NVIDIA hosts. You can swap `namerci/smartctl-exporter` for the upstream `prometheus-community/smartctl_exporter` and pick any DCGM tag you prefer. |

## Quick start

```bash
git clone https://github.com/cadaverine/dgx-spark-observability.git
cd dgx-spark-observability

cp .env.example .env
# Edit .env: set GRAFANA_ADMIN_PASSWORD, NTFY_TOPIC (must be unguessable),
#            BIND_ADDRESS, TZ.

docker network create observability-net
docker compose up -d
# Wait ~60s for everything to be ready.

curl -sf http://127.0.0.1:3001/api/health   # Grafana check

# Optional: download three Grafana community dashboards
./scripts/fetch-community-dashboards.sh
docker compose restart grafana
```

## Endpoints

All UIs bind to `${BIND_ADDRESS}` (default `127.0.0.1`). For remote access either set `BIND_ADDRESS` to a Tailscale IP, or SSH-forward:

| Service | Port | URL |
|---|---|---|
| Grafana | `3001` | `http://${BIND_ADDRESS}:3001` (admin / `${GRAFANA_ADMIN_PASSWORD}`) |
| Prometheus | `9090` | `http://${BIND_ADDRESS}:9090` |
| Alertmanager | `9093` | `http://${BIND_ADDRESS}:9093` |
| ntfy | `8081` | `http://${BIND_ADDRESS}:8081` (subscribe via the ntfy mobile app to topic `${NTFY_TOPIC}`) |

## Architecture

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design — network model, metric sources, label schema, log pipeline, dashboard structure, alerting design, retention choices.

## Quirks

See [`docs/DGX-SPARK-QUIRKS.md`](docs/DGX-SPARK-QUIRKS.md) for the Blackwell / aarch64 specific gotchas this template handles.

## Customization

The template ships with two static labels — `host=spark`, `hardware=gb10` — applied in three places:

- `prometheus/prometheus.yml` (`external_labels` + per-job `instance`)
- `promtail/promtail-config.yml` (per-job `labels`)
- Some alert annotations in `prometheus/rules/host.yml`

If you're running on something other than a DGX Spark, search-and-replace `spark` and `gb10` to whatever fits your inventory. The Grafana dashboard's `$host` template variable picks them up automatically.

## What is NOT included

This template is intentionally **host-level only**. If you also want application-level monitoring, fork or extend:

- vLLM `/metrics` scrape (TTFT, KV cache, queue, throughput).
- LiteLLM / per-key cost tracking.
- Container `stdout`/`stderr` shipping to Loki.
- Distributed tracing (Tempo, etc.).
- Multi-host federation, HA replicas, SSO.

The label schema and Prometheus / Loki are deliberately not pre-bound to any application so that adding these on top does not require rewriting Layer 1.

## Contributing

PRs welcome — particularly for additional hardware compatibility (Jetson, Grace+Hopper) or further quirk documentation.

License: MIT.
