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

    # ------------------------------------------------------------------
    # POR QUE 'SHUTDOWN' Y NO 'SHUTDOWN WITH NOWAIT'
    #
    # Antes aqui habia 'SHUTDOWN WITH NOWAIT', que apaga sin hacer
    # checkpoint en las bases y sin esperar transacciones. Consecuencia:
    # el siguiente arranque tiene que hacer crash recovery de CADA base.
    #
    # Como el ciclo de encendido/apagado es programado (cron-job.org),
    # eso significaba forzar recovery dos veces al dia, todos los dias.
    # Y al fondo de una recovery fallida espera la reparacion destructiva.
    #
    # 'SHUTDOWN' a secas hace checkpoint en cada base y deja el siguiente
    # arranque limpio. Solo si tarda demasiado (Railway manda SIGKILL tras
    # su periodo de gracia) caemos al modo sucio, que es peor pero mejor
    # que un SIGKILL a medias.
    # ------------------------------------------------------------------
    SHUTDOWN_TIMEOUT="${MSSQL_SHUTDOWN_TIMEOUT:-20}"

    if [ -n "$MSSQL_SA_PASSWORD" ]; then
        echo "Intentando apagado limpio (checkpoint + shutdown, max ${SHUTDOWN_TIMEOUT}s)..."

        if timeout "$SHUTDOWN_TIMEOUT" /opt/mssql-tools18/bin/sqlcmd \
              -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C \
              -Q "SHUTDOWN"; then
            echo "Apagado limpio completado. El proximo arranque no necesita recovery. ✅"
        else
            echo "El apagado limpio excedio ${SHUTDOWN_TIMEOUT}s. Forzando WITH NOWAIT. ⚠️"
            echo "El proximo arranque hara crash recovery."
            /opt/mssql-tools18/bin/sqlcmd \
                -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C \
                -Q "SHUTDOWN WITH NOWAIT" 2>&1 || true
        fi
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
    # ------------------------------------------------------------------
    # AUTO-REPARACION EN DOS NIVELES
    #
    # Antes aqui habia UNA sola llamada, con la salida a /dev/null, que
    # aplicaba REPAIR_ALLOW_DATA_LOSS a cualquier base SUSPECT. Dos
    # problemas: usaba la opcion destructiva incluso cuando el fallo era
    # un permiso de volumen (el caso mas comun en Railway), y no dejaba
    # rastro de haberlo hecho.
    #
    # Ahora: siempre corre la escalera no destructiva, con logs visibles.
    # La destructiva es un archivo aparte que solo se invoca si tu lo
    # autorizas explicitamente.
    # ------------------------------------------------------------------
    echo "Ejecutando auto-reparación no destructiva..."
    /opt/mssql-tools18/bin/sqlcmd \
        -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -C \
        -i /usr/local/bin/auto_repair.sql 2>&1

    if [ "$MSSQL_ALLOW_DATA_LOSS_REPAIR" == "true" ] || [ "$MSSQL_ALLOW_DATA_LOSS_REPAIR" == "1" ]; then
        echo "⚠️  MSSQL_ALLOW_DATA_LOSS_REPAIR está activa: se permite reparación DESTRUCTIVA."
        echo "⚠️  Recuerda apagarla en cuanto termines."
        /opt/mssql-tools18/bin/sqlcmd \
            -S localhost -U sa -P "${MSSQL_SA_PASSWORD}" -C \
            -i /usr/local/bin/auto_repair_dataloss.sql 2>&1
    fi
fi

echo "Motor de base de datos listo."

# ----------------------------------------------------------------------
# El auto-escalador de memoria se eliminó a propósito.
#
# Decidía el límite mirando el CPU, que no dice nada sobre la memoria:
# un escaneo de Power BI es CPU bajo y memoria alta, así que encogía
# justo cuando no debía. Y cada ajuste vaciaba el buffer pool, obligando
# a releer del disco. SQL Server ya gestiona esto solo.
#
# Ahora el único dueño del límite es MSSQL_MEMORY_LIMIT_MB (Dockerfile),
# que además aplica desde el primer segundo del arranque — antes, había
# una ventana de 20 minutos en la que SQL creía tener 8 GB dentro de un
# contenedor de 5 GB.
# ----------------------------------------------------------------------

# Limpieza periódica de logs y backups antiguos.
if [ -f /usr/local/bin/clean_old_logs.sh ]; then
    /usr/local/bin/clean_old_logs.sh &
    echo "Limpieza automática de logs iniciada (cada 24h)."
else
    echo "AVISO: clean_old_logs.sh no está en la imagen. El volumen crecerá sin control."
fi

# ----------------------------------------------------------------------
# Backup diario a Cloudflare R2.
#
# Esta instancia NUNCA tuvo un backup (msdb.dbo.backupset estaba vacía)
# pese a guardar ~8.7 GB de datos de clientes. Esto lo resuelve.
#
# No usamos BACKUP TO URL nativo porque el conector S3 de SQL Server 2022
# falla contra R2 con "error de sistema operativo 1359", sin más detalle.
# El motor de backup sí funciona: respaldamos a disco y subimos con rclone.
# ----------------------------------------------------------------------
if [ -f /usr/local/bin/backup_to_r2.sh ]; then
    /usr/local/bin/backup_to_r2.sh &
    echo "Backup diario a R2 programado (${BACKUP_HOUR:-23}:${BACKUP_MINUTE:-40} hora local)."
else
    echo "AVISO: backup_to_r2.sh no está en la imagen. NO HAY BACKUPS."
fi

# Mantener el script vivo esperando por SQL Server
wait "$pid"

