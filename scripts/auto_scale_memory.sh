#!/bin/bash
set -euo pipefail

# Autoajuste de memoria de SQL Server según carga de CPU

SQL_USER="sa"
SQL_PASS="${MSSQL_SA_PASSWORD:-}"
SQL_HOST="localhost"
SQL_PORT="1433"

LOW_LIMIT=2048
HIGH_LIMIT=4096
CPU_THRESHOLD=10
CHECK_INTERVAL=300

if [ -z "$SQL_PASS" ]; then
  echo "Error: MSSQL_SA_PASSWORD no está definida"
  exit 1
fi

SQLCMD_BIN="$(command -v sqlcmd || true)"

if [ -z "$SQLCMD_BIN" ]; then
  for p in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
    if [ -x "$p" ]; then
      SQLCMD_BIN="$p"
      break
    fi
  done
fi

if [ -z "$SQLCMD_BIN" ]; then
  echo "Error: sqlcmd no fue encontrado"
  exit 1
fi

CURRENT_STATE="UNKNOWN"

set_memory_limit() {
  local limit="$1"

  "$SQLCMD_BIN" \
    -S "${SQL_HOST},${SQL_PORT}" \
    -U "$SQL_USER" \
    -P "$SQL_PASS" \
    -C \
    -Q "EXEC sp_configure 'show advanced options', 1;
        RECONFIGURE;
        EXEC sp_configure 'max server memory (MB)', ${limit};
        RECONFIGURE;"
}

while true; do
  CPU_USAGE="$(top -b -n1 | awk '/sqlservr/ {print int($9); exit}')"
  CPU_USAGE="${CPU_USAGE:-0}"

  echo "CPU sqlservr: ${CPU_USAGE}% | Estado actual: ${CURRENT_STATE}"

  if [ "$CPU_USAGE" -lt "$CPU_THRESHOLD" ]; then
    if [ "$CURRENT_STATE" != "LOW" ]; then
      echo "Carga baja: ajustando memoria a ${LOW_LIMIT} MB"
      set_memory_limit "$LOW_LIMIT"
      CURRENT_STATE="LOW"
    fi
  else
    if [ "$CURRENT_STATE" != "HIGH" ]; then
      echo "Carga alta: ajustando memoria a ${HIGH_LIMIT} MB"
      set_memory_limit "$HIGH_LIMIT"
      CURRENT_STATE="HIGH"
    fi
  fi

  sleep "$CHECK_INTERVAL"
done