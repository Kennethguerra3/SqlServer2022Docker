#!/bin/bash
# Nivel 4: Auto-Escalador de Memoria (Railway Serverless Hack)
# Este script monitorea conexiones activas y ajusta la RAM dinámicamente.
# - Inactividad (60s): Baja max_memory a 2GB y limpia caché.
# - Actividad (1+ req): Sube max_memory a 8GB.

echo "Iniciando Auto-Escalador de Memoria (2GB - 8GB)..."

IDLE_SECONDS=0
MAX_IDLE_SECONDS=60
CURRENT_STATE="HIGH" # Asumimos alto al iniciar

while true; do
    # 1. Contar solicitudes activas que NO sean del sistema (session_id > 50) y que NO estén durmiendo
    # Usamos sqlcmd de forma silenciosa. Si falla, asumimos 0 para no colgar el script.
    ACTIVE_REQUESTS=$(/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_requests WHERE session_id > 50 AND status NOT IN ('background', 'sleeping');" 2>/dev/null | tr -d ' ' | tr -d '\r' | tr -d '\n')
    
    # Validar que sea un número. Si sqlcmd falla (ej. arrancando), será vacío
    if ! [[ "$ACTIVE_REQUESTS" =~ ^[0-9]+$ ]]; then
        ACTIVE_REQUESTS=0
    fi

    if [ "$ACTIVE_REQUESTS" -gt 0 ]; then
        # HAY ACTIVIDAD
        IDLE_SECONDS=0
        
        if [ "$CURRENT_STATE" == "LOW" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Detectada actividad ($ACTIVE_REQUESTS req). Escalando a 8GB..."
            # Escalar a 8GB inmediatamente
            /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE; EXEC sp_configure 'max server memory (MB)', 8192; RECONFIGURE WITH OVERRIDE;" > /dev/null 2>&1
            CURRENT_STATE="HIGH"
        fi
    else
        # NO HAY ACTIVIDAD
        IDLE_SECONDS=$((IDLE_SECONDS + 5))
        
        if [ "$IDLE_SECONDS" -ge "$MAX_IDLE_SECONDS" ] && [ "$CURRENT_STATE" == "HIGH" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Inactividad por ${MAX_IDLE_SECONDS}s. Reduciendo a 2GB y limpiando caché..."
            # Reducir a 2GB y forzar limpieza de buffers para devolver RAM a Linux/Railway
            /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE; EXEC sp_configure 'max server memory (MB)', 2048; RECONFIGURE WITH OVERRIDE; DBCC DROPCLEANBUFFERS; DBCC FREEPROCCACHE;" > /dev/null 2>&1
            CURRENT_STATE="LOW"
        fi
    fi
    
    # Revisar cada 5 segundos
    sleep 5
done
