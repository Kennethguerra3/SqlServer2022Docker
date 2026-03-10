#!/bin/bash
# Nivel 3: Apagado Seguro y Auto-Reparación

echo "Arrancando contenedor de SQL Server..."

# NOTA SOBRE PERMISOS EN RAILWAY:
# Railway a veces monta los volúmenes con propietario root:root (UID 0).
# Como ejecutamos el contenedor con USER 10001 (por requerimiento de SQL Server),
# no tenemos permisos de sudo/chown en runtime para arreglar el montaje de /var/opt/mssql.
# Por tanto, dependemos de que los subdirectorios tengan los permisos correctos
# O de crear la estructura ANTES de iniciar sqlservr localmente.

# Intentamos crear la carpeta oculta .system que a veces falla en volúmenes limpios
mkdir -p /var/opt/mssql/.system 2>/dev/null || true

# Función para propagar el apagado limpio (SIGTERM)
function graceful_shutdown() {
    echo "Recibida señal SIGTERM de Railway. Apagando SQL Server de forma segura..."
    kill -TERM "$pid"
    wait "$pid"
    echo "SQL Server apagado correctamente."
    exit 0
}

# Atrapamos SIGTERM (STOPSIGNAL)
trap graceful_shutdown SIGTERM

# Iniciamos SQL Server en segundo plano
/opt/mssql/bin/sqlservr &
pid=$!

echo "Esperando a que SQL Server inicie..."
for i in {1..60}; do
    if /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -Q "SELECT 1" -C -t 1 &> /dev/null; then
        echo "SQL Server está arriba."
        break
    fi
    sleep 1
done

if [ "$i" -eq 60 ]; then
    echo "SQL Server tardó demasiado. Abortando auto-reparación (Nivel 3)."
else
    echo "================================================================"
    echo "Ejecutando script de auto-reparación (Protección Nivel 3)..."
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -C -i /usr/local/bin/auto_repair.sql
    echo "Revisión finalizada."
    echo "================================================================"
fi

# Mantener el script vivo esperando por SQL Server
wait "$pid"
