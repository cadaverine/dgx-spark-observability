# Security policy

## Reporting a vulnerability

Email Vladimir Chekholin <kennville@gmail.com>. Expect an acknowledgement within 7 days. There is no bug bounty.

## Threat model

This template is intended for **single-host personal infrastructure** with optional remote access via Tailscale or SSH tunnel. **It is not hardened for direct internet exposure.** All host ports default to `BIND_ADDRESS=127.0.0.1`. If you change that, audit your firewall and ntfy configuration first.

## Privileged containers

Several containers run with elevated privileges. Each is justified below — review and decide whether the trade-off matches your threat model.

| Container | Privilege | Reason | Risk |
|---|---|---|---|
| `smartctl-exporter` | `privileged: true`, mounts `/dev` ro | Needs raw access to NVMe S.M.A.R.T. data via `/dev/nvme*` | Container escape would expose all host devices |
| `cadvisor` | `privileged: true`, mounts `/var/run/docker.sock` ro | Introspects all containers via the Docker API | Read access to all container metadata; bind-mount of the docker socket is a well-known elevated risk |
| `dcgm-exporter` | `cap_add: SYS_ADMIN` | NVML / DCGM library requires it for driver introspection | Capability allows several privileged kernel operations |
| `node-exporter` | `network_mode: host`, `pid: host` | Needs raw view of host network stack and process table | Visibility into all host-level networking and processes |

## Push notification security (ntfy)

By default `auth-default-access: read-write` and the `${NTFY_TOPIC}` value is the **only access control**. Recommendations:

- Always use an unguessable topic name (not the placeholder). `openssl rand -hex 16` is fine.
- If exposing ntfy beyond `127.0.0.1`, also rotate the topic and consider `auth-default-access: deny-all` plus auth tokens. Configuring auth tokens is out of scope for this template.

## Default credentials

`.env.example` ships placeholder credentials (`changeme`, `CHANGE_ME_TO_AN_UNGUESSABLE_STRING`). The stack **will start** with these unchanged. Rotate them before exposing any port beyond loopback.

## No internet exposure assumed

All host ports default to `BIND_ADDRESS=127.0.0.1`. The template assumes you reach the UIs via SSH port-forwarding or Tailscale. There is no reverse proxy, TLS termination, or auth proxy in this stack.

## Image provenance

- `namerci/smartctl-exporter` is a **third-party rebuild** — used because the upstream `prometheus-community/smartctl_exporter` ships amd64-only manifests. Verify the maintainer or build from source if your threat model requires reviewable provenance.
- All other images come from official registries: `docker.io`, `gcr.io`, `nvcr.io`, `quay.io`, `grafana/`, `prom/`.

## Update cadence

Image tags are pinned. Watch upstream advisories for security issues. Bump tags via PR after testing. Dependabot is configured to open weekly Docker / GitHub Actions update PRs.
