# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1, by reference).
- GitHub issue forms (`bug-report.yml`, `quirk-report.yml`) and PR template.
- `.github/workflows/validate.yml` — CI: compose / promtool / amtool / yaml / json / shellcheck.
- `.github/dependabot.yml` — weekly Docker image and GitHub Actions bumps.
- `docs/TROUBLESHOOTING.md` — 9 common breakage scenarios with diagnosis + fix.
- `docs/EXTENDING.md` — patterns for adding exporters, alerts, dashboards, downstream layers.
- `mem_limit` on every service in `docker-compose.yml` (defends host from misbehaving exporter).
- `LokiDiskHigh` alert rule for log retention pressure.
- README "What it looks like" section with screenshot placeholder at `docs/img/dashboard.png`.

### Fixed

- Removed `aeon-net` example reference in `docs/ARCHITECTURE.md` (replaced with neutral `app-net`).

## [0.1.0] - 2026-05-04

### Added

- Initial public template for DGX Spark / Blackwell GB10 / sm_121a / aarch64.
- 11-container LGTM-style stack: Prometheus, Grafana, Loki, Promtail, Alertmanager, ntfy, node-exporter, smartctl-exporter (third-party arm64 rebuild), cAdvisor, dcgm-exporter, nvidia-textfile sidecar.
- 13 host-level alert rules (RAM/disk/GPU/OOM/NVMe SMART/context-switches), each with inline runbook annotations.
- Custom 38-panel `Spark Host Overview` dashboard (System / GPU / Thermal / Storage / Network / Containers).
- Three pre-wired Grafana community dashboards (`1860`, `12239`, `13946`) via `scripts/fetch-community-dashboards.sh`.
- Overnight push mute (23:00–08:00 in `${TZ}`, default UTC) via Alertmanager `mute_time_intervals`.
- 6-month metric retention, 90-day system-log retention.
- nvidia-smi textfile collector sidecar to fill DCGM gaps on Blackwell unified memory (`nvidia_gpu_memory_used_bytes`, `nvidia_gpu_throttle_active`, etc.).
- Documentation: `README.md`, `docs/ARCHITECTURE.md`, `docs/DGX-SPARK-QUIRKS.md` (eight Blackwell-specific gotchas with symptom / cause / fix / upstream status).

### Known issues

- `NTFY_TOPIC` placeholder must be rotated before any non-loopback exposure.
- `NvmeWearHigh` alert disabled until threshold can be calibrated against host's actual wear progression.
