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
# 4. DETECCIÓN Y REEMPLAZO DEL MASTER.MDF CORRUPTO
# ==========================================
MASTER_MDF="/var/opt/mssql/data/master.mdf"
MASTER_MDF_BAK="/var/opt/mssql/data/master.mdf.bak"
MASTER_LDF="/var/opt/mssql/data/mastlog.ldf"
MASTER_LDF_BAK="/var/opt/mssql/data/mastlog.ldf.bak"

if [ -f "$MASTER_MDF" ]; then
    echo "[RECOVERY] master.mdf detectado. Renombrando versión potencialmente corrupta..."
    mv "$MASTER_MDF" "$MASTER_MDF_BAK"
    echo "[RECOVERY] master.mdf renombrado a master.mdf.bak (conservado)"
fi

if [ -f "$MASTER_LDF" ]; then
    echo "[RECOVERY] mastlog.ldf detectado. Renombrando..."
    mv "$MASTER_LDF" "$MASTER_LDF_BAK"
    echo "[RECOVERY] mastlog.ldf renombrado a mastlog.ldf.bak (conservado)"
fi

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
