#!/usr/bin/env bash
# Fetches community Grafana dashboards into grafana/dashboards/community/
# Run after first clone or to refresh from upstream.
#
# Why this isn't committed: each dashboard JSON is ~40-470 KB. They are
# upstream artifacts owned by their respective authors on grafana.com;
# fetching per-clone keeps this template small and ensures users always
# get the latest revision.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p grafana/dashboards/community
cd grafana/dashboards/community

declare -A DASHBOARDS=(
  [1860]=node-exporter-full
  [12239]=nvidia-dcgm-exporter
  [13946]=cadvisor-docker-monitoring
)

for id in "${!DASHBOARDS[@]}"; do
  name="${DASHBOARDS[$id]}"
  out="${name}-${id}.json"
  echo "Fetching dashboard ${id} -> ${out}"
  curl -fsSL "https://grafana.com/api/dashboards/${id}/revisions/latest/download" -o "${out}"
done

# Patch DS_PROMETHEUS placeholder so dashboards bind to our provisioned
# Prometheus datasource (uid: prometheus) without requiring a manual import.
echo "Patching datasource UID placeholders..."
# The ${DS_PROMETHEUS}-style strings are LITERAL placeholders inside the
# dashboard JSON files (Grafana export format), not shell variables.
# Single quotes are correct here.
for f in *.json; do
  # shellcheck disable=SC2016
  sed -i \
    -e 's/"${DS_PROMETHEUS}"/"prometheus"/g' \
    -e 's/"DS_PROMETHEUS"/"prometheus"/g' \
    -e 's/"${DS_PROMETHEUS-FHY}"/"prometheus"/g' \
    -e 's/"DS_PROMETHEUS-FHY"/"prometheus"/g' \
    "$f"
done

echo "Done. Restart Grafana to load: docker compose restart grafana"
