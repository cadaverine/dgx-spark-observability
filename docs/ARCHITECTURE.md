# Architecture — DGX Spark / Blackwell GB10 host observability

This template is a self-contained, single-host observability stack focused on **hardware and server health**: CPU, RAM, GPU, temperature, throttling, disk, NVMe SMART, network, and per-container resource usage. It also captures system logs (kernel, syslog) for hardware-incident postmortems.

It is intentionally **not bound to any application stack**. The label schema and pipelines are designed so that application-level scrape jobs and dashboards can be added on top without rewriting any of this.

## 1. Goals

In priority order:

1. **At-a-glance hardware state, any moment in the last 6 months** — CPU, RAM, GPU, temps, throttle, disk, network. Open Grafana, understand "how is the host" within ten seconds.
2. **Hardware-incident postmortem** — OOM, thermal throttle, disk-full, NVMe wear — root-cause via metrics + kernel logs on a single timeline.
3. **Wake only on real hardware problems** — RAM critical, disk critical, GPU temp critical, OOM detected. **No overnight pushes** by default (23:00–08:00 mute).
4. **Full independence from any application stack.** This stack can be brought up, torn down, or rebuilt without touching any other project.

## 2. Non-goals

Explicitly out of scope:

- vLLM `/metrics` scrape (TTFT, KV cache, throughput) — fork or extend if you need it.
- Application-level metrics (HTTP latency, per-key cost, etc.).
- Container `stdout`/`stderr` shipping (only host-level system logs are collected).
- Distributed tracing (Tempo, OTel pipeline).
- Multi-host federation, HA replicas.
- Telegram/email/PagerDuty receivers (only ntfy is wired by default).
- SSO/OAuth on Grafana (admin/password locally; access via `BIND_ADDRESS` + Tailscale or SSH tunnel).

## 3. Hardware context

Reference host: DGX Spark (NVIDIA GB10, sm_121a, 128 GB **unified** CPU+GPU memory, Blackwell consumer/edge line, aarch64).

Relevant quirks (full list in [`DGX-SPARK-QUIRKS.md`](DGX-SPARK-QUIRKS.md)):

- The NVML/DCGM/nvidia-smi ecosystem on Blackwell consumer hardware is incomplete. Several "standard" metrics (`DCGM_FI_DEV_FB_USED/FREE`, `DCGM_FI_PROF_*`) are not exposed.
- **Unified memory** means GPU and CPU share one 128 GB pool. Tuning advice written for discrete GPUs (Hopper/Ada/A100/H100) generally does not transfer.
- The NVMe and `smartctl_exporter` arm64 story is also bumpy — upstream ships amd64-only manifests.

## 4. Topology

### 4.1 Containers

| Container | Role | Host access |
|---|---|---|
| `prometheus` | TSDB + scraper | `observability-net` |
| `grafana` | UI + alert/dashboard orchestration | `observability-net`, port `3001` |
| `loki` | Log storage | `observability-net` |
| `promtail` | Log shipper (system logs only) | `/var/log` (RO) |
| `alertmanager` | Alert routing, mute windows | `observability-net`, port `9093` |
| `ntfy` | Self-hosted push | `observability-net`, port `8081` |
| `node-exporter` | Host CPU / RAM / disk / network | `network_mode: host`, `pid: host`, bind `/proc`, `/sys`, `/` (RO) |
| `smartctl-exporter` | NVMe / SATA SMART metrics | privileged, `/dev` (RO) |
| `cadvisor` | Per-container resource usage | `/var/run/docker.sock`, `/sys`, `/var/lib/docker` (RO) |
| `dcgm-exporter` | GPU metrics | `runtime: nvidia`, `cap_add: SYS_ADMIN` |
| `nvidia-textfile` | Sidecar that fills DCGM gaps on unified memory | `runtime: nvidia`, `pid: host`, bind `/proc/meminfo` (RO), shared textfile volume to node-exporter |

### 4.2 Network model

A single internal Docker network `observability-net` connects the observability containers. `node-exporter` runs in `network_mode: host` so it reports correct host network/disk/temperature metrics. `nvidia-textfile` runs in `network_mode: none` and writes to a shared volume picked up by node-exporter's textfile collector.

Host ports are bound to `${BIND_ADDRESS}` (default `127.0.0.1`), never `0.0.0.0`. For remote access, set `BIND_ADDRESS` to a Tailscale IP or use SSH port-forwarding.

### 4.3 Directory layout

```
.
├── docker-compose.yml
├── .env.example
├── prometheus/
│   ├── prometheus.yml
│   └── rules/host.yml
├── grafana/
│   ├── provisioning/{datasources,dashboards}/
│   └── dashboards/{community,custom}/
├── loki/loki-config.yml
├── promtail/promtail-config.yml
├── alertmanager/
│   ├── alertmanager.yml
│   └── entrypoint.sh             # env-var substitution shim
├── ntfy/server.yml
├── scripts/
│   ├── nvidia-smi-textfile.sh    # sidecar metric collector
│   └── fetch-community-dashboards.sh
└── docs/
    ├── ARCHITECTURE.md
    └── DGX-SPARK-QUIRKS.md
```

### 4.4 Principles

- All exporter volume mounts are **read-only** where possible.
- All host-bound UI ports default to `127.0.0.1`; remote access via Tailscale or SSH tunnel.
- `.env` is `.gitignore`d; `.env.example` is committed.
- Dashboards are JSON-in-git — single source of truth.

## 5. Metric sources

| Source | Endpoint | Scrape | Highlights |
|---|---|---|---|
| `prometheus` (self) | `:9090/metrics` | 15s | Meta-monitoring (scrape duration, dropped samples) |
| `node-exporter` | `:9100/metrics` | 15s | CPU per-core, RAM, swap, disk I/O, net throughput, load, context switches, kernel-reported throttle, **textfile collector** |
| `smartctl-exporter` | `:9633/metrics` | 60s | NVMe SMART: critical_warning bitmask, percentage_used, available_spare, media_errors, temperature |
| `cadvisor` | `:8080/metrics` | 15s | Per-container CPU, RAM, network, disk I/O, restart count, OOM kills, throttled time |
| `dcgm-exporter` | `:9400/metrics` | 5s | GPU util, temp, power, NVLink, PCIe replay, XID errors |
| `nvidia-textfile` (via node-exporter textfile) | (file) | 5s | `nvidia_gpu_memory_used_bytes`, `nvidia_gpu_memory_total_bytes`, `nvidia_gpu_throttle_active`, `nvidia_gpu_temp_celsius`, `nvidia_gpu_utilization_ratio`, `nvidia_gpu_power_draw_watts` — fills DCGM coverage gaps on Blackwell unified memory |

### 5.1 Why 5s for DCGM (and the textfile sidecar)

Thermal throttling on consumer-class Blackwell can be a 5–10 s spike. A 15 s scrape interval smooths it out and you'd never see it. After the first week, watch `prometheus_target_interval_length_seconds` for the dcgm job — if scrape duration is regularly above 1 s, relax to 10 s.

### 5.2 Label schema

Hardware-level labels only at this layer:

```yaml
host: "spark"           # multi-host hook
hardware: "gb10"        # multi-hardware hook
```

These are set as `external_labels` in `prometheus.yml` and as static `labels` in promtail. Override per host as needed.

If you later add application-level scrape jobs, do it as **new jobs with additional labels** (`service`, `model`, etc.) rather than mutating these.

## 6. Log pipeline

Promtail ships **only host-level logs**:

1. **`/var/log/kern.log`** — kernel events: OOM killer, NVIDIA driver warnings, thermal events, hardware errors. The single most important source for hardware postmortems.
2. **`/var/log/syslog`** — broader system events.
3. **journald** — disabled by default; uncomment in `promtail-config.yml` if `/var/log/journal` exists on your host.

Pipeline stages on `kern.log` extract structured labels:

- `oom_killed=true` and `oom_process=<name>` from "Out of memory: Killed process".
- `thermal_event=true` from anything matching `(thermal|temperature|throttl)`.

These structured labels feed two things: the `HostOomDetected` alert (Loki rule queried by Prometheus via Alertmanager not directly — see alerting section) and Grafana Loki annotation overlays on the dashboard.

Log retention: **90 days**, enforced by Loki's built-in compactor with `retention_enabled: true`. System logs are low-volume in normal operation (kilobytes per day), but events are rare and important — long history is the point.

## 7. Dashboards

One custom dashboard plus three Grafana community dashboards.

### 7.1 `spark-host-overview.json` (custom, 38 panels)

Single big dashboard rather than several small ones — at this layer "host health" is one topic. Template variable `$host` for multi-host expansion.

Sections:

- **System** — CPU per-core heatmap, load avg, RAM split, swap, context switches, processes.
- **GPU (DCGM + textfile)** — utilization, memory used/total, temperature, power vs cap, throttle reasons timeline, SM activity, clocks, PCIe replay.
- **Thermal correlation** — CPU temp vs GPU temp on one chart (cooling is shared on Spark).
- **Storage** — disk usage % per mountpoint, NVMe SMART (temp / wear / errors), per-device IOPS and throughput.
- **Network** — per-interface throughput, established TCP, retransmits / errors / drops.
- **Containers (cadvisor)** — stacked CPU and RAM per container, restart count, OOM kills.

### 7.2 Community dashboards

Fetched on demand by `scripts/fetch-community-dashboards.sh` (kept out of git to keep the repo small):

- `1860` — Node Exporter Full
- `12239` — NVIDIA DCGM Exporter Dashboard
- `13946` — cAdvisor Docker Insights

### 7.3 Cross-cutting

- Shared time picker between dashboards.
- Click-through from a metric panel into Loki via the configured Loki datasource.
- Loki annotation source surfaces OOM events on the metrics graphs.

## 8. Alerting

### 8.1 Pipeline

`Prometheus alerting rules → Alertmanager → ntfy webhook → mobile app push`.

`Alertmanager` is configured with a single `night` mute interval applied to every child route (the root route cannot carry mute intervals in Alertmanager v0.27 — see quirks). Add Telegram, email, or PagerDuty receivers as additional `receivers` without changing the rules.

### 8.2 Severity → ntfy priority

| Severity | ntfy priority | Behavior |
|---|---|---|
| `critical` | 4 | Sound + vibrate (no DND bypass — overnight mute already handles that) |
| `warning` | 3 | Standard notification |
| `info` | 2 | Quiet in shade |

### 8.3 Critical alerts

- `HostMemoryCritical` — RAM > 95% AND swap heavily used, 5m
- `DiskCritical` — `/` or `/var` > 95%, 5m
- `GpuTempCritical` — GPU temp > 80°C, 2m
- `HostOomDetected` — OOM event in kernel log within 5m
- `NodeExporterDown` — host-level metrics unavailable, 5m
- `NvmeCriticalWarning` — `smartctl_device_critical_warning > 0`, immediate

### 8.4 Warning alerts

- `HostMemoryHigh` — RAM > 85%, 15m
- `DiskWarning` — > 85%, 10m
- `GpuMemoryHigh` — > 90%, 10m
- `GpuThermalThrottle` — `nvidia_gpu_throttle_active == 1`, 5m
- `NvmeMediaErrors` — `smartctl_device_media_errors > 0`, immediate
- `NvmeAvailableSpareLow` — within 10% of threshold
- `HighContextSwitches` — > 100k/s sustained 10m (livelock indicator)

### 8.5 Inhibit rules

`NodeExporterDown` inhibits all warning/critical alerts for the same host (if node-exporter is down we cannot trust RAM/disk/CPU expressions anyway).

### 8.6 Group / dedup / repeat

- `group_by: [alertname, severity, host]`
- `group_wait: 30s`
- `group_interval: 5m`
- `repeat_interval: 4h`

### 8.7 Calibration

After 7–10 days of running:

- Tune `HighContextSwitches` to your workload baseline.
- Tune `NvmeAvailableSpareLow` to your drive's actual threshold.
- Add `NvmeWearHigh` once `smartctl_device_percentage_used` baseline is known (it's 0 on a fresh drive).
- Set `--storage.tsdb.retention.size` based on observed cardinality.

## 9. Retention

| What | How long | Where enforced |
|---|---|---|
| Prometheus TSDB | 180 days **or** 30 GB, whichever first | `--storage.tsdb.retention.time` + `--storage.tsdb.retention.size` |
| Loki logs | 90 days | `limits_config.retention_period` + `compactor` |
| Grafana state | persistent until container removed | `grafana_data` volume |
| Alertmanager state | persistent until container removed | `alertmanager_data` volume |

## 10. Extending

This template is host-level only. If you want application-level monitoring on top, the additive path is:

- Attach `prometheus` to your application's Docker network (e.g. `app-net`) so it can reach app `/metrics` endpoints.
- Add scrape jobs in `prometheus.yml` with new labels (`service`, `model`, etc.).
- Add a new Promtail pipeline for container `stdout`/`stderr` (separate from the host log pipeline).
- Drop new dashboards into `grafana/dashboards/custom/`.
- Drop new alert rules into `prometheus/rules/` alongside `host.yml`.

Nothing in Layer 1 needs to be rewritten for any of these.
