#!/bin/bash
# entrypoint.sh - SQL Server 2022 con System DBs en RAM
# 
# PROBLEMA: Railway volume filesystem no soporta IO aligned (misaligned log IOs)
#   → Stack Overflow en sqlpal.dll al hacer recovery de master.mdf
#   → EAGAIN al intentar file locking para el "persistent hive root"
#
# SOLUCIÓN:
#   1. ulimit -c 0              → evita que core dumps llenen /dev/shm
#   2. symlink log → /dev/shm  → fix "Unable to set persistent hive root" (EAGAIN)
#   3. mssql.conf filelocation  → system DBs (master/model/msdb/tempdb) en RAM
#   4. attach_databases.sql    → user DBs se adjuntan desde el volumen

set -e

echo "[RECOVERY] =========================================="
echo "[RECOVERY] SQL Server 2022 - System DBs en RAM"
echo "[RECOVERY] =========================================="

# 1. Deshabilitar core dumps (no llenar /dev/shm)
ulimit -c 0

# 2. Estabilizar volumen
echo "[RECOVERY] Esperando 5 segundos..."
sleep 5

# 3. Permisos
chown -R mssql:root /var/opt/mssql 2>/dev/null || true
chmod -R 770 /var/opt/mssql 2>/dev/null || true

# 4. Borrar system DB files del volumen (se recrearán en RAM)
echo "[RECOVERY] Limpiando system DB files del volumen..."
rm -f /var/opt/mssql/data/master.*   2>/dev/null || true
rm -f /var/opt/mssql/data/mastlog.*  2>/dev/null || true
rm -f /var/opt/mssql/data/model.*    2>/dev/null || true
rm -f /var/opt/mssql/data/modellog.* 2>/dev/null || true
rm -f /var/opt/mssql/data/msdb*      2>/dev/null || true
rm -f /var/opt/mssql/data/tempdb*    2>/dev/null || true
rm -f /var/opt/mssql/data/templog.*  2>/dev/null || true
rm -f /var/opt/mssql/data/*.bak      2>/dev/null || true

# 5. Limpiar residuos y IPC
rm -f /var/opt/mssql/mssql.conf           2>/dev/null || true
rm -rf /var/opt/mssql/secrets/*           2>/dev/null || true
find /var/opt/mssql -maxdepth 1 -name ".*" -not -name "." -delete 2>/dev/null || true
rm -rf /dev/shm/mssql-log /dev/shm/mssql-sys /dev/shm/sqlsys  2>/dev/null || true
rm -f /dev/shm/mssql* /dev/shm/sqlpal* /dev/shm/sqlservr* /dev/shm/*.mem 2>/dev/null || true
rm -f /tmp/mssql* /tmp/sqlservr*          2>/dev/null || true
ipcs -m 2>/dev/null | awk 'NR>2 && $1~/^0x/ {print $2}' | xargs -r ipcrm -m 2>/dev/null || true
ipcs -s 2>/dev/null | awk 'NR>2 && $1~/^0x/ {print $2}' | xargs -r ipcrm -s 2>/dev/null || true
echo "[RECOVERY] Limpieza completada."

# 6. Crear dirs RAM
echo "[RECOVERY] Creando directorios en RAM (/dev/shm)..."
mkdir -p /dev/shm/mssql-sys
mkdir -p /dev/shm/mssql-log
chown -R mssql:root /dev/shm/mssql-sys /dev/shm/mssql-log
chmod 770 /dev/shm/mssql-sys /dev/shm/mssql-log

# 7. FIX hive root: /var/opt/mssql/log → /dev/shm/mssql-log
echo "[RECOVERY] Redirigiendo log dir a RAM (fix hive root)..."
rm -rf /var/opt/mssql/log
ln -sfn /dev/shm/mssql-log /var/opt/mssql/log

# 8. FIX Stack Overflow: mssql.conf apunta defaultdatadir a RAM
#    SQL Server creará master/model/msdb/tempdb en /dev/shm/mssql-sys (no en el volumen)
#    Las user DBs se adjuntan explícitamente desde /var/opt/mssql/data/ más adelante
echo "[RECOVERY] Configurando mssql.conf (system DBs en /dev/shm/mssql-sys)..."
cat > /var/opt/mssql/mssql.conf << 'EOF'
[EULA]
accepteula = Y

[sqltrace]
traceflags = 1800

[memory]
memorylimitmb = 3500

[network]
tcpport = 1433

[filelocation]
defaultdatadir = /dev/shm/mssql-sys
defaultlogdir  = /dev/shm/mssql-sys
defaultdumpdir = /var/opt/mssql/data
EOF
chown mssql:root /var/opt/mssql/mssql.conf
echo "[RECOVERY] mssql.conf listo. System DBs → /dev/shm/mssql-sys"

# 9. Iniciar SQL Server
echo "[RECOVERY] Lanzando SQL Server..."
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# 10. Esperar a que SQL Server esté listo
echo "[RECOVERY] Esperando a que SQL Server acepte conexiones..."
RETRY=0
MAX_RETRIES=60
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -Q "SELECT 1" > /dev/null 2>&1; do
    RETRY=$((RETRY+1))
    if [ $RETRY -ge $MAX_RETRIES ]; then
        echo "[RECOVERY] Timeout. SQL Server no responde. Continuando..."
        break
    fi
    echo "[RECOVERY] Intento $RETRY/$MAX_RETRIES..."
    sleep 5
done

# 11. Adjuntar user databases desde el volumen
echo "[RECOVERY] Adjuntando bases de datos de usuario desde el volumen..."
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -i /usr/local/bin/attach_databases.sql || true

echo "[RECOVERY] =========================================="
echo "[RECOVERY] Recuperacion completada."
echo "[RECOVERY] =========================================="

wait $SQL_PID
