# Extending the template

Patterns for users who want to add their own exporters, alerts, dashboards, or integrate the template into a larger setup. Stay within Layer 1 scope (host health) — for application-level monitoring, fork or extend separately.

---

## Add a new exporter

Example: scraping `redis-exporter` for a Redis instance running on the host.

**1. Add the service to `docker-compose.yml`:**
```yaml
  redis-exporter:
    image: oliver006/redis_exporter:v1.62.0
    container_name: redis-exporter
    restart: unless-stopped
    networks: [observability-net]
    mem_limit: 128m
    environment:
      REDIS_ADDR: "redis://your-redis-host:6379"
```

**2. Add a scrape job in `prometheus/prometheus.yml`:**
```yaml
  - job_name: redis
    static_configs:
      - targets: ['redis-exporter:9121']
        labels:
          instance: spark
```

**3. Apply:**
```bash
docker compose up -d redis-exporter
docker compose restart prometheus
```

---

## Add a new alert rule

Example: high Redis memory utilization.

Append to `prometheus/rules/host.yml` under `host-warning`:
```yaml
      - alert: RedisMemoryHigh
        expr: |
          redis_memory_used_bytes / redis_memory_max_bytes > 0.85
        for: 10m
        labels:
          severity: warning
          layer: "1"
        annotations:
          summary: "Redis memory > 85% on {{ $labels.instance }}"
          runbook: |
            1) docker exec redis-cli INFO memory
            2) Identify large keys: redis-cli MEMORY USAGE <key>
            3) Increase maxmemory or evict
```

Restart Prometheus. The new rule appears in `/api/v1/rules` immediately.

---

## Add a new Grafana dashboard

**Option A — drop JSON in:** Save the dashboard JSON to `grafana/dashboards/custom/<name>.json`. The provisioning provider auto-loads it within 30 seconds.

**Option B — build in UI:** Set `editable: true` (already set in `grafana/provisioning/dashboards/custom.yml`), build in Grafana → Dashboards → New, then `Share → Export → Save to file` and drop into the same directory. Subsequent edits will be persisted to file via provisioning reload.

**Option C — fetch a community dashboard:** Add an entry to `scripts/fetch-community-dashboards.sh`, run the script, restart Grafana.

---

## Override default labels (`host` / `hardware`)

The template ships with `host: spark` and `hardware: gb10` as defaults. To override:

**1.** In `prometheus/prometheus.yml`, change `external_labels`:
```yaml
global:
  external_labels:
    host: my-server-01
    hardware: rtx-4090
    layer: "1"
```

**2.** In `promtail/promtail-config.yml`, change static labels in each `scrape_configs` entry:
```yaml
        labels:
          host: my-server-01
          hardware: rtx-4090
```

**3.** Restart Prometheus and Promtail.

The dashboard's `$host` template variable is data-driven (queries `node_uname_info`) and automatically picks up the new value.

---

## Add a private downstream layer

If you want to monitor an application that runs in its own Docker network (e.g. an LLM serving stack, a web app, a database cluster) without polluting this template:

**1.** Keep this template's `observability-net` for Layer 1.

**2.** Add a second network to `prometheus`:
```yaml
  prometheus:
    networks:
      - observability-net
      - app-net   # external network owned by your application
```

**3.** Declare the external network at the bottom:
```yaml
networks:
  observability-net:
    external: true
  app-net:
    external: true
```

**4.** Add scrape jobs for the application targets, with new label dimensions (`service`, `model`, `tenant`, etc.) so dashboards can drill in.

**5.** Optionally add a separate Promtail pipeline for container `stdout`/`stderr` of the application — keep it distinct from the host log pipeline so you can manage retention / cardinality independently.

This keeps Layer 1 (this template) reusable and composable. Application-specific dashboards / alerts live in your downstream fork or as additional files.

---

## Resource limits

Each service has a `mem_limit` in `docker-compose.yml`. If you find a service is hitting its ceiling (visible in cAdvisor as `container_memory_working_set_bytes` near the limit, or as OOMs), bump the value and `docker compose up -d <service>` to recreate.

---

## What we explicitly don't aim to support

- **Multi-host federation.** This is a single-host template. For fleets, use an upstream Prometheus + Mimir / Thanos.
- **HA replicas.** No replication or sharding. If a container dies, alerts/metrics stop until it comes back.
- **Auto-update.** Image tags are pinned. Use Dependabot (configured in `.github/dependabot.yml`) for PR-based bumps; verify before merge.
- **Cross-organisation auth.** Single-user setup with admin/admin defaults that you rotate. SSO / RBAC is out of scope.
