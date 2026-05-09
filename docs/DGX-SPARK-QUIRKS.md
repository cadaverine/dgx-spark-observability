# DGX Spark / Blackwell GB10 Quirks

This template handles several non-obvious gaps in the NVIDIA + ARM64 observability ecosystem on Blackwell consumer/edge hardware. Each section explains: what we tried, what failed, what works.

If you're debugging a similar setup, these are the eight things most likely to cost you a day if you don't know them.

---

## 1. `smartctl_exporter` ships amd64-only manifests

**Symptom.** On any aarch64 host (DGX Spark, Jetson, AWS Graviton, Apple Silicon dev box), the canonical exporter image refuses to pull:

```bash
$ docker pull quay.io/prometheuscommunity/smartctl-exporter:v0.13.0
no matching manifest for linux/arm64/v8 in the manifest list entries
```

**Cause.** `prometheus-community/smartctl_exporter`'s GitHub Actions release workflow only builds `linux/amd64`. Verified for tags v0.7.0 through v0.14.0 plus `master` and `latest` — every published manifest is single-arch amd64.

**Fix in this template.** Use a third-party multi-arch rebuild:

```yaml
image: namerci/smartctl-exporter:0.14.0
```

This image pulls and runs on aarch64 with no other config changes.

**Upstream status.** Issue to be filed at `prometheus-community/smartctl_exporter` requesting `linux/arm64` in the buildx matrix. Low-effort fix; high-impact for the ARM ecosystem.

---

## 2. DCGM-exporter has coverage gaps on Blackwell GB10

**Symptom.** `dcgm-exporter` starts cleanly, exposes `:9400/metrics`, **but** several common metric series are missing:

- `DCGM_FI_DEV_FB_USED` and `DCGM_FI_DEV_FB_FREE` (framebuffer used/free).
- All `DCGM_FI_PROF_*` (profiling: PCIe TX/RX, SM activity, DRAM activity, GR engine activity).

Container startup logs say:

> "This request is serviced by a module of DCGM that is not currently loaded"

**Cause (two different things, conflated in the symptom):**

1. **`FB_USED/FREE` — by design.** Blackwell GB10 uses **unified memory**: there is no separate VRAM pool, so framebuffer "used" and "free" don't have a meaningful definition in the data-center sense. nvidia-smi's `memory.used`/`memory.total` queries return `[N/A]` for the same reason (see quirk #8).
2. **`PROF_*` — module-not-loaded gap.** The DCGM profiling module isn't loaded on sm_121a in the current `nvcr.io/nvidia/k8s/dcgm-exporter:4.1.1-4.0.4-ubuntu22.04` image. SM activity, PCIe bandwidth, etc. are hardware-supported, but the DCGM module that surfaces them is not initialized for this SKU.

What IS exposed and works correctly: `GPU_TEMP`, `GPU_UTIL`, `MEMORY_TEMP`, `POWER_USAGE`, `SM_CLOCK`, `MEM_COPY_UTIL`, `ENC_UTIL`, `DEC_UTIL`, `NVLINK_BANDWIDTH_TOTAL`, `PCIE_REPLAY_COUNTER`, `TOTAL_ENERGY_CONSUMPTION`, `XID_ERRORS`.

**Fix in this template.** A small `nvidia-textfile` sidecar runs `nvidia-smi` every 5 s and writes Prometheus textfile-format metrics into a volume picked up by node-exporter's textfile collector:

- `nvidia_gpu_temp_celsius`
- `nvidia_gpu_memory_used_bytes` — sum of `--query-compute-apps=used_memory` across processes (see quirk #8)
- `nvidia_gpu_memory_total_bytes` — `MemTotal` from `/proc/meminfo` (unified memory: GPU pool == host RAM)
- `nvidia_gpu_utilization_ratio`
- `nvidia_gpu_power_draw_watts`
- `nvidia_gpu_throttle_active` — derived from `clocks_throttle_reasons.active`

The sidecar runs `network_mode: none`, `pid: host`, with `runtime: nvidia` and a read-only bind of `/proc/meminfo`. See `scripts/nvidia-smi-textfile.sh`.

**Upstream status.** Issue to be filed at `NVIDIA/dcgm-exporter` (or `NVIDIA/DCGM` itself, since the gap is at the DCGM library/module-packaging layer, not the exporter wrapper). May need a NVIDIA-side response.

---

## 3. cAdvisor v0.49.x is incompatible with Docker 25+

**Symptom.** cAdvisor starts but logs Docker API errors and reports no container metrics:

```
client version 1.41 is too old. Minimum supported API version is 1.44
```

**Cause.** cAdvisor v0.49.1 ships a Docker client at API 1.41. Docker server 25+ requires minimum API 1.44.

**Fix in this template.** Pin to **v0.55.1** or newer:

```yaml
image: gcr.io/cadvisor/cadvisor:v0.55.1
```

**Upstream status.** Already fixed in cAdvisor itself (newer releases bump the client). Most blog posts and copy-paste compose files still reference v0.47/v0.49 — that's the trap. No upstream action needed; this is a "stale tutorials" issue.

---

## 4. Alertmanager has no `--config.expand-env`

**Symptom.** You write `${TZ}` and `${NTFY_TOPIC}` into `alertmanager.yml` and start the container. Alertmanager fails to validate the config — the dollar-syntax is treated as literal.

**Cause.** Prometheus has `--config.expand-env`. Alertmanager **does not**. Env-var expansion in the config file is a Prometheus-only feature, not a shared property of the prometheus.io project.

**Fix in this template.** A small `entrypoint.sh` does sed-based substitution of the known env vars into a writable copy of the config, then `exec`s alertmanager:

```sh
sed -e "s|\${TZ}|${TZ}|g" \
    -e "s|\${NTFY_TOPIC}|${NTFY_TOPIC}|g" \
    /etc/alertmanager/alertmanager.yml.tmpl > /alertmanager/alertmanager.yml
exec /bin/alertmanager --config.file=/alertmanager/alertmanager.yml ...
```

The mounted `.yml.tmpl` is read-only; the rendered output goes into the existing `alertmanager_data` volume.

**Upstream status.** Long-standing feature gap. Possible feature request at `prometheus/alertmanager` to add `--config.expand-env` for parity. Low priority — the workaround is six lines.

---

## 5. Alertmanager `mute_time_intervals` cannot span midnight

**Symptom.** A natural way to write "mute pushes at night":

```yaml
time_intervals:
  - name: night
    time_intervals:
      - times:
          - start_time: '23:00'
            end_time: '08:00'
        location: 'UTC'
```

is rejected on startup with `start time cannot be equal or greater than end time`.

**Cause.** A single `times` entry in Alertmanager v0.27 must lie within `[00:00, 24:00]` and have `start < end`. There is no wrap-around / overnight semantic.

**Fix in this template.** Split the overnight window into two same-day ranges sharing one `location`:

```yaml
time_intervals:
  - name: night
    time_intervals:
      - times:
          - start_time: '00:00'
            end_time: '08:00'
          - start_time: '23:00'
            end_time: '24:00'
        location: '${TZ}'
```

The union covers the full 23:00 → next-day 08:00 window. Awkward but supported.

**Upstream status.** Discussion-level feature request at `prometheus/alertmanager` proposing either `start > end` wrap-around or `24:00+` end times. Low priority — workaround is documented and works.

---

## 6. Alertmanager v0.27 disallows `mute_time_intervals` on the root route

**Symptom.**

```
root route must not have any mute time intervals
```

**Cause.** Validation tightened in v0.27. The intent is to make routing decisions explicit per-leaf rather than globally inherited.

**Fix in this template.** Apply `mute_time_intervals: [night]` on every child route. The child matchers (`severity=critical`, `severity=warning`, `severity=info`) together exhaust the routing space, so coverage is identical to a root-level mute.

**Upstream status.** Working as designed — documenting because the error message doesn't tell you "apply per child route instead".

---

## 7. node-exporter has no `--collector.smartctl` flag

**Symptom.** Many older tutorials (and the first draft of this stack's plan) reference a node-exporter built-in for SMART metrics. It does not exist.

**Cause.** SMART metrics moved out of node-exporter into a separate `smartctl_exporter` years ago. node-exporter never had a built-in `--collector.smartctl` (you may be thinking of `--collector.smart` from far older mailing-list discussions, which also wasn't a real flag — only proposed).

**Fix in this template.** Run `smartctl-exporter` as its own container (see also quirk #1 for the arm64 manifest issue) and scrape it on `:9633`.

**Upstream status.** Not a bug — just stale documentation in the wider ecosystem. If you find a tutorial telling you to add `--collector.smartctl` to node-exporter, it's wrong.

---

## 8. `nvidia-smi memory.used` returns `[N/A]` on unified memory

**Symptom.**

```bash
$ nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits
[N/A], [N/A]
```

**Cause.** GB10's unified memory has no separate VRAM pool. The `memory.used`/`memory.total` query is defined against a discrete VRAM model that doesn't apply.

**Fix in this template.** Derive the two values from sources that **do** exist on unified memory:

- **Used** — sum per-process compute allocations:

  ```bash
  nvidia-smi --query-compute-apps=used_memory --format=csv,noheader,nounits \
    | awk '{s+=$1} END {print s+0}'
  ```

  This returns MiB; convert to bytes.

- **Total** — host RAM, since the "GPU memory pool" *is* host RAM under unified memory:

  ```bash
  awk '/^MemTotal:/ {print $2}' /proc/meminfo   # in kB
  ```

The textfile sidecar bind-mounts `/proc/meminfo` from the host (rather than reading the container's own `/proc/meminfo`, which would report container-cgroup limits).

**Upstream status.** Working as designed — documenting because tooling that calls `--query-gpu=memory.used` and parses the result will silently produce `N/A` strings on Spark. nvtop has the same class of issue (separately tracked).

---

## 9. `nvidia-smi` field name is `clocks_throttle_reasons.active` (underscores), not `clocks.throttle_reasons.active` (dots)

**Symptom.**

```bash
$ nvidia-smi --query-gpu=clocks.throttle_reasons.active --format=csv,noheader,nounits
Field "clocks.throttle_reasons.active" is not a valid field to query.
```

**Cause.** Driver 580+ standardized on the underscore form `clocks_throttle_reasons.active`. Many older docs, blog posts, and the `nvidia-smi --help-query-gpu` output on older drivers list the dotted form. Both forms have appeared in NVIDIA documentation across driver generations.

**Fix in this template.** Use the underscore form:

```bash
nvidia-smi --query-gpu=clocks_throttle_reasons.active --format=csv,noheader,nounits
```

The sidecar script returns a 64-bit hex bitmask (e.g. `0x0000000000000000` for "no throttle"); the script normalizes this to a binary `nvidia_gpu_throttle_active{0,1}` gauge for alerting and dashboards.

**Upstream status.** Just a documentation/version mismatch. If you see older code using the dotted form, it predates driver 580.

---

## How to use this list

If you fork this template for non-Spark hardware (Jetson Orin/Thor, Grace+Hopper, plain ARM64 NVIDIA boxes), the relevant quirks are:

- **All ARM64 hosts:** quirks #1, #3, #7.
- **Any unified-memory NVIDIA SKU:** quirks #2 (FB_USED part), #8.
- **Anyone using Alertmanager mute windows:** quirks #4, #5, #6.
- **Anyone reading old NVIDIA tutorials:** quirks #7, #9.

If you find another quirk worth documenting, PRs welcome.
