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
sudo /usr/bin/mkdir -p /var/opt/mssql/data /var/opt/mssql/log/mssql-conf /var/opt/mssql/backup /var/opt/mssql/secrets /log /.system

# 2. Forzamos el owner para que SQL Server (mssql) pueda escribir sin Access Denied
sudo /usr/bin/chown -v -R 10001:0 /var/opt/mssql /.system /log || echo "WARNING: Fallo en chown"
sudo /usr/bin/chmod -v -R 770 /var/opt/mssql /.system /log || echo "WARNING: Fallo en chmod"

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

# 1.5. Forzar mssql.conf explícitamente sin depender de la utilidad de python
echo "Generando mssql.conf estricto para rutas seguras y compatibilidad O_DIRECT..."
cat <<EOF > /var/opt/mssql/mssql.conf
[filelocation]
defaultdatadir = /var/opt/mssql/data
defaultlogdir = /var/opt/mssql/log
errorlogfile = /var/opt/mssql/log/errorlog
defaultbackupdir = /var/opt/mssql/backup
defaultdumpdir = /var/opt/mssql/log

[control]
writethrough = 1
alternateosync = 1

[traceflag]
traceflag0 = 3979
traceflag1 = 1800
traceflag2 = 3226
EOF

# Imprimir por consola para validar en Railway
cat /var/opt/mssql/mssql.conf

# Adicionalmente pasamos los traceflags globales al entorno (3979=I/O alternativo seguro, 1800=Optimización 4K, 3226=Suprimir Logs Backup)
export MSSQL_TRACE_FLAGS="3979,1800,3226"

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
