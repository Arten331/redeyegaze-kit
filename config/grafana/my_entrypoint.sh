#!/bin/bash

DATASOURCE_FILE="/etc/grafana/provisioning/datasources/monitoring.yaml"
DASHBOARD_DIR="/etc/grafana/provisioning/dashboards-content"

echo "Running custom Grafana entrypoint script..."

PROMETHEUS_UID=$(grep -A 8 'name: Prometheus' "$DATASOURCE_FILE" | grep 'uid:' | awk '{print $2}')

if [ -z "$PROMETHEUS_UID" ]; then
  echo "Error: Could not find Prometheus UID in $DATASOURCE_FILE. Please ensure 'name: Prometheus' and 'uid:' are correctly defined in that file."
  exit 1
fi

echo "Prometheus UID for replacement: $PROMETHEUS_UID"

echo "Processing dashboard JSON files for datasource replacement..."
for file in "$DASHBOARD_DIR"/*.json; do
  if [ -f "$file" ]; then
    echo "  - Modifying: $file"
    sed -i "s|\\\"\${DS_PROMETHEUS}\\\"|\\\"$PROMETHEUS_UID\\\"|g" "$file"
  else
    echo "  - Skipping (not a file or does not exist): $file"
  fi
done

echo "Starting Grafana with its original entrypoint..."
exec /run.sh "$@"