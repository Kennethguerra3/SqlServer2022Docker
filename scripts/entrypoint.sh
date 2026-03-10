#!/bin/bash
# Nivel 3: Apagado Seguro y Auto-Reparación

echo "Arrancando contenedor de SQL Server..."

# NOTA SOBRE PERMISOS DE VOLÚMENES EN RAILWAY:
# Railway monta los volúmenes persistentes con el propietario root (UID 0).
# Como iniciamos nativamente como el usuario mssql (UID 10001) para preservar el flag 
# PR_SET_DUMPABLE del kernel (vital para que SQL Server no colapse al leer su memoria),
# usamos 'sudo' (cuyos comandos están permitidos sin password) para arreglar el volumen en runtime.

echo "Iniciando como mssql (UID 10001): Configurando permisos del volumen de Railway via sudo..."

# 1. Creamos la estructura dentro del volumen por si Railway lo entregó vacío
sudo mkdir -p /var/opt/mssql/data /var/opt/mssql/log /var/opt/mssql/backup /var/opt/mssql/secrets /log /.system

# 2. Forzamos el owner para que SQL Server (mssql) pueda escribir sin Access Denied
sudo chown -R 10001:0 /var/opt/mssql /.system /log || true
sudo chmod -R 770 /var/opt/mssql /.system /log || true

echo "Permisos arreglados ✅ Iniciando SQL Server de forma nativa..."

# =========================================================================
# Ejecución nativa de SQL Server como 'mssql'
# =========================================================================

# Función para propagar el apagado limpio (SIGTERM)
function graceful_shutdown() {
    echo "Recibida señal SIGTERM de Railway. Apagando SQL Server de forma segura..."
    
    if [ -n "$MSSQL_SA_PASSWORD" ]; then
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SHUTDOWN WITH NOWAIT" -C
        echo "SHUTDOWN ejecutado pacíficamente. 🛑"
    else
        kill -s TERM $pid
    fi
    
    wait $pid
    exit 0
}

# 1. Atrapamos las señales de detención (Railway matando el contenedor)
trap "graceful_shutdown" SIGINT SIGTERM

# (El paso 1.3 de pre-crear directorios ya fue manejado por el bloque ROOT de gosu arriba)

# 1.5. Forzar las rutas correctas para evitar errores de permisos 
# (Error: The log directory [/log] could not be created)
echo "Configurando rutas seguras para SQL Server..."
/opt/mssql/bin/mssql-conf set filelocation.defaultdatadir /var/opt/mssql/data 2>/dev/null || true
/opt/mssql/bin/mssql-conf set filelocation.defaultlogdir /var/opt/mssql/log 2>/dev/null || true
/opt/mssql/bin/mssql-conf set filelocation.errorlogfile /var/opt/mssql/log/errorlog 2>/dev/null || true
/opt/mssql/bin/mssql-conf set filelocation.defaultbackupdir /var/opt/mssql/backup 2>/dev/null || true
/opt/mssql/bin/mssql-conf set filelocation.defaultdumpdir /var/opt/mssql/log 2>/dev/null || true

# 2. Iniciamos el motor de SQL en background
echo "Iniciando SQL Server en segundo plano..."
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
