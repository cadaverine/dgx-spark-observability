#!/bin/sh
# Render env vars into alertmanager.yml, then exec alertmanager.
#
# Why this exists: prom/alertmanager (unlike prom/prometheus) has no
# --config.expand-env flag, so env vars in the config (${TZ},
# ${NTFY_TOPIC}) need to be substituted before alertmanager loads it.
# The mounted .yml.tmpl is read-only; we render to /alertmanager/
# (writable storage volume).
set -eu

SRC=/etc/alertmanager/alertmanager.yml.tmpl
DST=/alertmanager/alertmanager.yml

sed \
  -e "s|\${TZ}|${TZ}|g" \
  -e "s|\${NTFY_TOPIC}|${NTFY_TOPIC}|g" \
  "$SRC" > "$DST"

exec /bin/alertmanager \
  --config.file="$DST" \
  --storage.path=/alertmanager \
  --web.external-url=http://127.0.0.1:9093
