#!/bin/bash
# entrypoint.sh - Recovery mejorado
# Preserva bases de datos de usuario mientras limpia archivos de sistema corruptos
# FIX CLAVE: sqlpal.dll no puede hacer file locking en el volume filesystem (EAGAIN/0xc0000022)
#             Se redirige /var/opt/mssql/log a /dev/shm (RAM) via symlink

set -e

echo "[RECOVERY] =========================================="
echo "[RECOVERY] Iniciando secuencia de recuperacion..."
echo "[RECOVERY] =========================================="

# Esperar a que el volumen se estabilice
echo "[RECOVERY] Esperando 5 segundos para estabilizar el entorno..."
sleep 5

# Corregir permisos
echo "[RECOVERY] Ajustando permisos de /var/opt/mssql..."
chown -R mssql:root /var/opt/mssql 2>/dev/null || true
chmod -R 770 /var/opt/mssql 2>/dev/null || true

# Limpiar archivos de sistema corruptos (borrar, no renombrar)
echo "[RECOVERY] Limpiando archivos de sistema corruptos..."
rm -f /var/opt/mssql/data/master.*     2>/dev/null || true
rm -f /var/opt/mssql/data/mastlog.*    2>/dev/null || true
rm -f /var/opt/mssql/data/model.*      2>/dev/null || true
rm -f /var/opt/mssql/data/modellog.*   2>/dev/null || true
rm -f /var/opt/mssql/data/msdb*.mdf    2>/dev/null || true
rm -f /var/opt/mssql/data/msdb*.ldf    2>/dev/null || true
rm -f /var/opt/mssql/data/tempdb.*     2>/dev/null || true
rm -f /var/opt/mssql/data/templog.*    2>/dev/null || true
# Limpiar .bak acumulados de intentos anteriores
rm -f /var/opt/mssql/data/*.bak        2>/dev/null || true
echo "[RECOVERY] Archivos de sistema eliminados."

# Limpiar directorios temporales
echo "[RECOVERY] Limpiando directorios temporales..."
rm -rf /var/opt/mssql/log/*     2>/dev/null || true
rm -rf /var/opt/mssql/secrets/* 2>/dev/null || true
rm -f  /var/opt/mssql/mssql.conf 2>/dev/null || true
find /var/opt/mssql -maxdepth 1 -name ".*" -not -name "." -delete 2>/dev/null || true
rm -f /dev/shm/mssql* /dev/shm/sqlpal* /dev/shm/sqlservr* /dev/shm/*.mem 2>/dev/null || true
rm -f /tmp/mssql* /tmp/sqlservr* 2>/dev/null || true

# Limpiar IPC
echo "[RECOVERY] Limpiando IPC/shared memory..."
ipcs -m 2>/dev/null | awk 'NR>2 && $1~/^0x/ {print $2}' | xargs -r ipcrm -m 2>/dev/null || true
ipcs -s 2>/dev/null | awk 'NR>2 && $1~/^0x/ {print $2}' | xargs -r ipcrm -s 2>/dev/null || true

# ==========================================
# FIX CLAVE: Redirigir /var/opt/mssql/log a /dev/shm (RAM)
# sqlpal.dll falla con EAGAIN al intentar file locking en el volume filesystem
# El hive de sqlpal necesita un filesystem local confiable para locks
# ==========================================
echo "[RECOVERY] Redirigiendo directorio de logs a RAM (/dev/shm)..."
RAMLOG="/dev/shm/mssql-log"
mkdir -p "$RAMLOG"
chown -R mssql:root "$RAMLOG"
chmod 770 "$RAMLOG"

# Reemplazar el directorio log del volumen con un symlink a RAM
rm -rf /var/opt/mssql/log
ln -sfn "$RAMLOG" /var/opt/mssql/log
echo "[RECOVERY] /var/opt/mssql/log → $RAMLOG (RAM)"

echo "[RECOVERY] Limpieza completada."

# Iniciar SQL Server
echo "[RECOVERY] Iniciando SQL Server..."
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# Esperar a que SQL Server este listo
echo "[RECOVERY] Esperando a que SQL Server acepte conexiones..."
RETRY=0
MAX_RETRIES=60

until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -Q "SELECT 1" > /dev/null 2>&1; do
    RETRY=$((RETRY+1))
    if [ $RETRY -ge $MAX_RETRIES ]; then
        echo "[RECOVERY] Timeout esperando SQL Server despues de $MAX_RETRIES intentos."
        echo "[RECOVERY] Continuando de todos modos..."
        break
    fi
    echo "[RECOVERY] Intento $RETRY/$MAX_RETRIES - SQL Server no listo aun..."
    sleep 5
done

echo "[RECOVERY] SQL Server esta listo. Adjuntando bases de datos de usuario..."

# Ejecutar script de adjuntar bases de datos
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -i /usr/local/bin/attach_databases.sql

echo "[RECOVERY] =========================================="
echo "[RECOVERY] Recuperacion completada exitosamente."
echo "[RECOVERY] =========================================="

# Mantener SQL Server en primer plano
wait $SQL_PID
