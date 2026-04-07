#!/bin/bash
# Nivel 3: Apagado Seguro y Auto-Reparación

if [ "$MSSQL_SUSPEND" == "true" ] || [ "$MSSQL_SUSPEND" == "1" ]; then
    echo "💤 Modo Suspensión Automática Activado (Cron)."
    echo "El contenedor está durmiendo y consumirá casi 0 RAM."
    echo "Para reanudar SQL Server, cambia MSSQL_SUSPEND a false o elimínala."
    # Atrapamos SIGTERM para apagar limpio si Railway reinicia
    trap 'exit 0' SIGINT SIGTERM
    sleep infinity
    exit 0
fi

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
sudo /usr/bin/chown -R 10001:0 /var/opt/mssql /.system /log &> /dev/null
sudo /usr/bin/chmod -R 770 /var/opt/mssql /.system /log &> /dev/null

echo "Permisos configurados. Iniciando SQL Server (Silent Mode)..."

# =========================================================================
# Ejecución nativa de SQL Server como 'mssql'
# =========================================================================

# Función para propagar el apagado limpio (SIGTERM)
function graceful_shutdown() {
    echo "Recibida señal SIGTERM. Apagando SQL Server..."
    
    if [ -n "$MSSQL_SA_PASSWORD" ]; then
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SHUTDOWN WITH NOWAIT" -C &> /dev/null
        echo "SHUTDOWN ejecutado. 🛑"
    else
        kill -s TERM $pid
    fi
    
    wait $pid
    exit 0
}

# 1. Atrapamos las señales de detención (Railway matando el contenedor)
trap "graceful_shutdown" SIGINT SIGTERM

# 1.5. Forzar mssql.conf explícitamente sin depender de la utilidad de python
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

[errorlog]
severitylevel = 3

[traceflag]
traceflag0 = 3979
traceflag1 = 1800
traceflag2 = 3226
traceflag3 = 1706
traceflag4 = 2505
traceflag5 = 3023
traceflag6 = 3656
EOF

# Traceflags: 3979 (I/O), 1800 (4K), 3226 (Backup), 1706 (Agent), 2505 (DB warnings), 3023 (Backup/Restore), 3656 (Suppress Agent info)
export MSSQL_TRACE_FLAGS="3979,1800,3226,1706,2505,3023,3656"

# 2. Iniciamos el motor de SQL en background
/opt/mssql/bin/sqlservr &
pid=$!

# Esperar a que SQL Server inicie de forma silenciosa
for i in {1..60}; do
    if /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -Q "SELECT 1" -C -t 1 &> /dev/null; then
        break
    fi
    sleep 1
done

if [ "$i" -lt 60 ]; then
    # Ejecutamos auto-reparación redirigiendo salida a /dev/null para no saturar Railway
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -C -i /usr/local/bin/auto_repair.sql &> /dev/null
fi

echo "Motor de base de datos listo."


# Iniciar auto-escalador de memoria en background (Hack de Railway)
if [ -f /usr/local/bin/auto_scale_memory.sh ]; then
    chmod +x /usr/local/bin/auto_scale_memory.sh
    /usr/local/bin/auto_scale_memory.sh &
elif [ -f /scripts/auto_scale_memory.sh ]; then
    chmod +x /scripts/auto_scale_memory.sh
    /scripts/auto_scale_memory.sh &
fi

# Iniciar limpieza automática de logs antiguos en background
if [ -f /usr/local/bin/clean_old_logs.sh ]; then
    chmod +x /usr/local/bin/clean_old_logs.sh
    /usr/local/bin/clean_old_logs.sh &
elif [ -f /scripts/clean_old_logs.sh ]; then
    chmod +x /scripts/clean_old_logs.sh
    /scripts/clean_old_logs.sh &
fi

# Mantener el script vivo esperando por SQL Server
wait "$pid"

