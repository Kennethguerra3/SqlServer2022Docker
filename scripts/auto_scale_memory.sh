#!/bin/bash
set -euo pipefail

# Autoajuste de memoria de SQL Server según carga de CPU

SQL_USER="sa"
SQL_PASS="${MSSQL_SA_PASSWORD:-}"
SQL_HOST="localhost"
SQL_PORT="1433"

LOW_LIMIT=2048
HIGH_LIMIT=4096
CPU_THRESHOLD=20
CHECK_INTERVAL=600
CONSECUTIVE_REQUIRED=2

if [ -z "$SQL_PASS" ]; then
  exit 0
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
  exit 0
fi

CURRENT_STATE="UNKNOWN"
COUNTER=0

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
        RECONFIGURE;" > /dev/null 2>&1
}

while true; do
  CPU_USAGE="$(top -b -n1 | awk '/sqlservr/ {print int($9); exit}')"
  CPU_USAGE="${CPU_USAGE:-0}"

  if [ "$CPU_USAGE" -lt "$CPU_THRESHOLD" ]; then
    TARGET_STATE="LOW"
  else
    TARGET_STATE="HIGH"
  fi

  if [ "$TARGET_STATE" = "$CURRENT_STATE" ]; then
    COUNTER=0
  else
    COUNTER=$((COUNTER + 1))
    if [ "$COUNTER" -ge "$CONSECUTIVE_REQUIRED" ]; then
      if [ "$TARGET_STATE" = "LOW" ]; then
        set_memory_limit "$LOW_LIMIT"
      else
        set_memory_limit "$HIGH_LIMIT"
      fi
      CURRENT_STATE="$TARGET_STATE"
      COUNTER=0
    fi
  fi

  sleep "$CHECK_INTERVAL"
done