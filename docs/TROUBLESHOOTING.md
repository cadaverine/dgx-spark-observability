# Troubleshooting

Common breakage scenarios with diagnosis steps and fixes. If your issue isn't here, open a [bug report](../.github/ISSUE_TEMPLATE/bug-report.yml) with the artifacts the template asks for.

---

## Containers don't come up after host reboot

**Symptom.** After a host reboot, one or more containers are missing or stuck.

**Diagnosis.**
```bash
systemctl is-enabled docker          # should be `enabled`
docker ps -a --format 'table {{.Names}}\t{{.Status}}'
docker compose ps
```
Each service in this template uses `restart: unless-stopped`, so on a healthy reboot they should come back automatically. A common rare failure is Docker losing iptables/proxy bindings for one container — `docker ps` will show the container `Up` but `ss -tlnp` won't show its host port.

**Fix.** Soft restart of the affected container:
```bash
docker compose restart <service>
```
If the daemon itself didn't auto-start: `sudo systemctl enable docker` and reboot once.

---

## Grafana login fails or shows "not found"

**Symptom.** `http://<bind>:3001` returns 404 or rejects admin login.

**Diagnosis.**
```bash
docker compose logs grafana --tail 50
curl -sf http://127.0.0.1:3001/api/health
```

**Fix.** Verify `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` in `.env`, then:
```bash
docker compose restart grafana
```
First start can take 10–15 s for DB migrations and provisioning load — wait before declaring failure.

---

## Prometheus targets show as DOWN

**Symptom.** `/api/v1/targets` shows `health: down` for one or more jobs.

**Diagnosis.**
```bash
curl -s 'http://127.0.0.1:9090/api/v1/targets?state=active' | python3 -m json.tool | head -60
```
Common causes:
- Target container not on `observability-net` (only `node-exporter` should be on host network).
- Scrape target hostname doesn't resolve inside Prometheus container — check `extra_hosts` for `host.docker.internal`.
- Container is healthy but `/metrics` endpoint is on a different port than the scrape config expects.

**Fix.** From inside Prometheus container, sanity-check the target:
```bash
docker exec prometheus wget -qO- http://<target>:<port>/metrics | head -5
```
Adjust `prometheus.yml` and `docker compose restart prometheus` (NOT just `/-/reload` — bind-mount inode caching can defeat reload after a file edit).

---

## Loki returns no logs

**Symptom.** Grafana → Explore → Loki query `{host=~".+"}` returns empty.

**Diagnosis.**
```bash
docker compose logs promtail --tail 30
docker exec prometheus wget -qO- http://loki:3100/ready
```
If Promtail logs show "no targets" or "permission denied" — `/var/log` mount is missing or the container is on the wrong network.

**Fix.** Verify the Promtail compose block has `/var/log:/var/log:ro` and is on `observability-net`. Restart Promtail after fixing.

---

## ntfy notifications don't arrive

**Symptom.** Alerts fire in Alertmanager UI (`/api/v2/alerts`) but no push on the phone.

**Diagnosis.**
1. Topic mismatch — phone subscription must match `${NTFY_TOPIC}` exactly.
2. Mute window is active — check `${TZ}` and the configured `time_intervals.night` window (default 23:00–08:00).
3. Phone subscription points to the wrong server URL (must match the ntfy host:port reachable from the phone).

**Fix.** Manual smoke test from the host:
```bash
source .env && curl -d "test from host" "http://127.0.0.1:8081/${NTFY_TOPIC}"
```
If that arrives on the phone but Alertmanager-fired notifications don't, check Alertmanager → Status page for the loaded routing tree and active mute intervals.

---

## Custom dashboard shows "No data"

**Symptom.** Panels in `Spark Host Overview` are empty.

**Diagnosis.**
- Datasource UID mismatch — this template uses literal UIDs `prometheus` and `loki`. If Grafana picked different UIDs at provisioning, panels won't resolve.
- The metric simply isn't available on this hardware (very common for `DCGM_FI_DEV_FB_*` on Blackwell — see [DGX-SPARK-QUIRKS.md](DGX-SPARK-QUIRKS.md)).
- Time range is too narrow — fresh stack has only minutes of data on first start.

**Fix.** In Grafana → Connections → Data sources, confirm Prometheus and Loki are present and "Save & test" returns green. If a specific metric is missing, query the exporter directly:
```bash
docker exec prometheus wget -qO- http://<exporter>:<port>/metrics | grep '^<metric_name>'
```

---

## DCGM-exporter container exits or shows zero metrics

**Symptom.** GPU panels empty; `docker compose logs dcgm-exporter` shows NVML init or module-load issues.

**Fix.** See [DGX-SPARK-QUIRKS.md](DGX-SPARK-QUIRKS.md) — Blackwell has known coverage gaps. The `nvidia-textfile` sidecar in this template fills the most important gaps (FB used/total, throttle indicator) via `nvidia-smi` directly.

---

## `docker compose up` fails with "manifest unknown"

**Symptom.** Image pull fails.

**Cause.** The pinned image tag was retracted, or your host architecture isn't included in the manifest. Most common on aarch64 hosts when an image is amd64-only.

**Fix.**
```bash
docker manifest inspect <image>:<tag>            # confirm tag exists
docker manifest inspect <image>:<tag> | grep architecture | sort -u
```
If the architecture you need isn't listed, find a multi-arch alternative or pin a different tag. See [DGX-SPARK-QUIRKS.md](DGX-SPARK-QUIRKS.md) for the smartctl-exporter case.

---

## High Loki disk usage

**Symptom.** `LokiDiskHigh` alert fires; `du -sh /var/lib/docker/volumes/*loki*` is much higher than expected.

**Diagnosis.**
```bash
docker exec loki du -sh /loki/* | sort -h | tail
docker compose logs loki --tail 100 | grep -i 'compact\|retention'
```
The compactor runs every 10 minutes and enforces retention (default 90 days). If logs show retention errors, the compactor isn't keeping up.

**Fix.** Lower `LOKI_RETENTION_DAYS` in `.env` (then restart loki), or investigate which job is producing too many bytes (`{job=~".+"} | logfmt | __error__=""` aggregated by `job`).
