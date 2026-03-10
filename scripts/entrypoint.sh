#!/bin/bash
# entrypoint.sh - Estrategia: System DBs en RAM, User DBs en volumen
# Soluciona: Stack Overflow en sqlpal.dll por IO misalignment en Railway volume

echo "[RECOVERY] Iniciando secuencia de recuperación..."

# ==========================================
# 1. RETRASO DE SEGURIDAD
# ==========================================
echo "[RECOVERY] Esperando 5 segundos para estabilizar el entorno..."
sleep 5

# ==========================================
# 2. CORRECCIÓN DE PERMISOS
# ==========================================
echo "[RECOVERY] Ajustando permisos de /var/opt/mssql..."
chown -R mssql:root /var/opt/mssql
chmod -R 770 /var/opt/mssql

# ==========================================
# 3. RENOMBRAR TODOS LOS ARCHIVOS DE SISTEMA
#    (Si existen — .bak indica ya fueron renombrados antes)
# ==========================================
SYSFILES=(
    "master.mdf" "mastlog.ldf"
    "model.mdf"  "modellog.ldf"
    "msdbdata.mdf" "msdblog.ldf"
    "tempdb.mdf"   "templog.ldf"
)
for f in "${SYSFILES[@]}"; do
    SRC="/var/opt/mssql/data/${f}"
    DST="/var/opt/mssql/data/${f}.bak"
    if [ -f "$SRC" ]; then
        mv "$SRC" "$DST"
        echo "[RECOVERY] Renombrado: ${f} → ${f}.bak"
    fi
done

# ==========================================
# 4. LIMPIEZA PROFUNDA DE RECURSOS RESIDUALES
# ==========================================
echo "[RECOVERY] Limpieza profunda de recursos del sistema..."
rm -rf /var/opt/mssql/log/*  2>/dev/null || true
rm -rf /var/opt/mssql/secrets/* 2>/dev/null || true
rm -f  /var/opt/mssql/mssql.conf 2>/dev/null || true
find /var/opt/mssql -maxdepth 1 -name ".*" -not -name "." -delete 2>/dev/null || true
find /var/opt/mssql -name "*.pid" -o -name "*.lck" | xargs rm -f 2>/dev/null || true
rm -f /dev/shm/mssql* /dev/shm/sqlpal* /dev/shm/sqlservr* /dev/shm/*.mem 2>/dev/null || true
ipcs -m 2>/dev/null | awk 'NR>2 && $1~/^0x/ {print $2}' | xargs -r ipcrm -m 2>/dev/null || true
ipcs -s 2>/dev/null | awk 'NR>2 && $1~/^0x/ {print $2}' | xargs -r ipcrm -s 2>/dev/null || true
rm -f /tmp/mssql* /tmp/sqlservr* 2>/dev/null || true
echo "[RECOVERY] Limpieza completada."

# ==========================================
# 5. PREPARAR DIRECTORIO RAM PARA SYSTEM DBs
#    /dev/shm es un tmpfs (RAM) → sin problemas de IO alignment
#    SQL Server arrancará con system DBs en RAM y user DBs en volumen
# ==========================================
echo "[RECOVERY] Preparando directorio RAM para bases de datos del sistema..."
RAMDIR="/dev/shm/sqlsys"
mkdir -p "$RAMDIR"
chown mssql:root "$RAMDIR"
chmod 770 "$RAMDIR"

# ==========================================
# 6. CREAR MSSQL.CONF APUNTANDO AL DIRECTORIO RAM
# ==========================================
echo "[RECOVERY] Configurando SQL Server para usar RAM como data directory..."
cat > /var/opt/mssql/mssql.conf << EOF
[EULA]
accepteula = Y

[sqltrace]
traceflags = 1800

[memory]
memorylimitmb = 3800

[network]
tcpport = 1433
ipaddress = 0.0.0.0

[filelocation]
defaultdatadir = ${RAMDIR}
defaultlogdir = ${RAMDIR}
defaultdumpdir = /var/opt/mssql/log
EOF
chown mssql:root /var/opt/mssql/mssql.conf

# ==========================================
# 7. ARRANCAR SQL SERVER EN SEGUNDO PLANO
#    Con system DBs en RAM no habrá IO misalignment ni Stack Overflow
# ==========================================
echo "[RECOVERY] Lanzando SQL Server (system DBs en RAM)..."
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# ==========================================
# 8. ESPERAR A QUE SQL SERVER ESTÉ LISTO
# ==========================================
echo "[RECOVERY] Esperando a que SQL Server acepte conexiones..."
RETRY=0
MAX_RETRIES=40
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -Q "SELECT 1" > /dev/null 2>&1; do
    RETRY=$((RETRY+1))
    if [ $RETRY -ge $MAX_RETRIES ]; then
        echo "[RECOVERY] Timeout esperando SQL Server. Continuando de todos modos..."
        break
    fi
    echo "[RECOVERY] Intento $RETRY/$MAX_RETRIES - SQL Server no listo aún..."
    sleep 5
done

# ==========================================
# 9. RE-ADJUNTAR BASES DE DATOS DE USUARIO DESDE EL VOLUMEN
# ==========================================
echo "[RECOVERY] Ejecutando script de adjuntar bases de datos..."
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -i /usr/local/bin/attach_databases.sql

# ==========================================
# 10. PASAR CONTROL A SQL SERVER (PID 1)
# ==========================================
echo "[RECOVERY] Recuperación completada. Pasando control a SQL Server..."
wait $SQL_PID
