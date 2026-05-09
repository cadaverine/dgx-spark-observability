# Contributing

Thanks for your interest in improving this template.

## Welcome / scope

This is a **Layer-1 host observability template** for DGX Spark / Blackwell / aarch64 hardware. It is deliberately scoped to host-level concerns: CPU, RAM, disk, network, GPU health, container metrics, and host system logs.

**Out of scope:** LLM-server metrics (vLLM, TGI, llama.cpp), application-level monitoring, multi-host federation, HA replicas, SSO, distributed tracing. Fork instead — the label schema is intentionally not pre-bound to any application so Layer 2/3 can live in a separate repo.

## Issues

Use the [issue templates](.github/ISSUE_TEMPLATE/). To help us reproduce, please include:

- **Hardware:** CPU arch, GPU model, kernel version
- **Docker version:** `docker version`
- **The exact failing command**
- **Full container logs:** `docker compose logs <service> --tail 200`
- **`docker compose config` output** if compose-related

## PRs

- One fix per PR — keep changes small and focused
- Describe the **symptom** the fix addresses, not just the diff
- Include smoke-test instructions in a `## Test plan` section
- The CI workflow validates compose / Prometheus rules / Alertmanager config / YAML / JSON / shell

## What we love

- New quirks for [`docs/DGX-SPARK-QUIRKS.md`](docs/DGX-SPARK-QUIRKS.md) with reproduction steps
- arm64 / Jetson / Grace+Hopper compatibility reports
- New alert rules for hardware health (with runbook annotations)
- Dashboard improvements that survive `git diff` — i.e. exported cleanly

## What we'll close

- Vendor-specific extensions outside Layer 1 scope (vLLM, LiteLLM, app metrics) — fork instead
- Sweeping refactors without a stated symptom

## License

This project is MIT-licensed. By submitting a PR you agree your contribution is released under MIT.
