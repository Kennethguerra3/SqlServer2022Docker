#!/bin/bash
# Nivel 4: Auto-Escalador de Memoria (Railway Serverless Hack)
# Este script monitorea conexiones activas y ajusta la RAM dinámicamente.
# - Inactividad (60s): Baja max_memory a 2GB y limpia caché.
# - Actividad (1+ req): Sube max_memory a 8GB.
            /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE WITH OVERRIDE; EXEC sp_configure 'max server memory (MB)', 2048; RECONFIGURE WITH OVERRIDE; DBCC DROPCLEANBUFFERS; DBCC FREEPROCCACHE;" > /dev/null 2>&1
#!/bin/bash

# Script para autoajustar la memoria máxima de SQL Server según la carga
# Autor: GitHub Copilot

SQL_USER="sa"
SQL_PASS="@Guerra33"
SQL_HOST="localhost"
SQL_PORT="1433"

# Límites de memoria en MB
LOW_LIMIT=2000
HIGH_LIMIT=4000

# Umbral de carga de CPU (%) para cambiar el límite
CPU_THRESHOLD=10

while true; do
    # Obtiene el uso de CPU de sqlservr
    CPU_USAGE=$(top -b -n1 | grep sqlservr | awk '{print $9}' | head -n1 | cut -d. -f1)
    if [ -z "$CPU_USAGE" ]; then
        CPU_USAGE=0
    fi

    if [ "$CPU_USAGE" -lt "$CPU_THRESHOLD" ]; then
        # Baja la memoria si la carga es baja
        /opt/mssql-tools/bin/sqlcmd -S $SQL_HOST,$SQL_PORT -U $SQL_USER -P $SQL_PASS -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'max server memory', $LOW_LIMIT; RECONFIGURE;"
    else
        # Sube la memoria si la carga es alta
        /opt/mssql-tools/bin/sqlcmd -S $SQL_HOST,$SQL_PORT -U $SQL_USER -P $SQL_PASS -Q "EXEC sp_configure 'show advanced options', 1; RECONFIGURE; EXEC sp_configure 'max server memory', $HIGH_LIMIT; RECONFIGURE;"
    fi

    sleep 300 # Espera 5 minutos
done
            CURRENT_STATE="LOW"
        fi
    fi
    
    # Revisar cada 5 segundos
    sleep 5
done
