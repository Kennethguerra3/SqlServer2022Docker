#!/bin/bash
# entrypoint.sh - Script de recuperación y arranque de SQL Server en Railway

echo "[RECOVERY] Iniciando secuencia de recuperación..."

# ==========================================
# 1. RETRASO DE SEGURIDAD
# ==========================================
echo "[RECOVERY] Esperando 5 segundos para estabilizar el entorno..."
sleep 5

# ==========================================
# 3. CORRECCIÓN DE PERMISOS
# ==========================================
echo "[RECOVERY] Ajustando permisos de /var/opt/mssql..."
chown -R mssql:root /var/opt/mssql
chmod -R 770 /var/opt/mssql

# ==========================================
# 4. RENOMBRAR TODOS LOS ARCHIVOS DE SISTEMA CORRUPTOS
#    SQL Server los recreará desde los templates del paquete
#    Los archivos .bak quedan conservados en el volumen
# ==========================================
SYSFILES=(
    "master.mdf"
    "mastlog.ldf"
    "model.mdf"
    "modellog.ldf"
    "msdbdata.mdf"
    "msdblog.ldf"
    "tempdb.mdf"
    "templog.ldf"
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
# 5. LIMPIAR ARCHIVOS RESIDUALES DE INSTANCIAS ANTERIORES
#    Estos bloquean el "persistent hive root" de sqlpal.dll
#    causando STATUS_ACCESS_DENIED (0xc0000022)
# ==========================================
echo "[RECOVERY] Limpiando archivos residuales de crashes anteriores..."

# Core dumps (pueden ocupar GB y bloquear el hive)
rm -f /var/opt/mssql/log/core.* 2>/dev/null || true

# Archivos de lock y PID de instancias anteriores
find /var/opt/mssql -name "*.pid" -delete 2>/dev/null || true
find /var/opt/mssql -name "*.lck" -delete 2>/dev/null || true

# Logs de error de instancias anteriores (SQL Server los recrea)
rm -f /var/opt/mssql/log/errorlog* 2>/dev/null || true
rm -f /var/opt/mssql/log/sqlagent.* 2>/dev/null || true
rm -f /var/opt/mssql/log/HkEngineEventFile* 2>/dev/null || true

# Secrets / hive de instancias anteriores que causan ACCESS_DENIED
# (SQL Server los recrea con la nueva master.mdf)
rm -f /var/opt/mssql/secrets/* 2>/dev/null || true

echo "[RECOVERY] Limpieza completada."

# ==========================================
# 5. ARRANCAR SQL SERVER EN SEGUNDO PLANO
# ==========================================
echo "[RECOVERY] Lanzando SQL Server (modo background para post-init)..."
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# ==========================================
# 6. ESPERAR A QUE SQL SERVER ESTÉ LISTO
# ==========================================
echo "[RECOVERY] Esperando a que SQL Server acepte conexiones..."
RETRY=0
MAX_RETRIES=30
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
# 7. RE-ADJUNTAR BASES DE DATOS DE USUARIO
# ==========================================
echo "[RECOVERY] Ejecutando script de adjuntar bases de datos..."
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" \
    -No -i /usr/local/bin/attach_databases.sql

# ==========================================
# 8. PASAR CONTROL A SQL SERVER (PID 1)
# ==========================================
echo "[RECOVERY] Recuperación completada. Pasando control a SQL Server..."
wait $SQL_PID
