#!/bin/bash
# ==========================================================
# LIMPIEZA PERIODICA DE LOGS Y BACKUPS ANTIGUOS
# ==========================================================
# Corregidos tres bugs que hacian que esto no limpiara nada:
#
#  1. El Dockerfile no copiaba este archivo -> el entrypoint
#     lo buscaba en dos rutas y ninguna existia. Ahora se copia.
#  2. No tenia bucle: corria una vez al arrancar y moria. Ahora
#     repite cada CLEAN_INTERVAL.
#  3. La rama de backups era codigo muerto: preguntaba
#     if [[ "$DIR" == "/var/opt/mssql/backup" ]] pero ese
#     directorio no estaba en LOG_DIRS, asi que la condicion
#     nunca podia ser cierta y los .bak jamas se borraban.
#     Como data, log y backup comparten el mismo volumen,
#     un .bak olvidado le come espacio a la base.
# ==========================================================

DAYS="${CLEAN_RETENTION_DAYS:-7}"
BACKUP_DAYS="${CLEAN_BACKUP_RETENTION_DAYS:-7}"
CLEAN_INTERVAL="${CLEAN_INTERVAL_SECONDS:-86400}"

LOG_DIR="/var/opt/mssql/log"
BACKUP_DIR="/var/opt/mssql/backup"
ROOT_LOG_DIR="/log"

clean_once() {
    echo "[clean_logs] Iniciando barrido (logs > ${DAYS}d, backups > ${BACKUP_DAYS}d)..."

    # --- Logs, trazas y dumps ---
    for DIR in "$LOG_DIR" "$ROOT_LOG_DIR"; do
        [ -d "$DIR" ] || continue
        for EXT in log trc txt dmp; do
            find "$DIR" -type f -name "*.${EXT}" -mtime "+${DAYS}" -delete 2>/dev/null
        done
    done

    # --- Backups ---
    # Se excluyen los PRE_REPAIR_*: son la copia forense que toma
    # auto_repair_dataloss.sql antes de destruir paginas. Borrarlos
    # automaticamente eliminaria la unica copia de esos datos.
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -type f -name "*.bak" \
            ! -name "PRE_REPAIR_*" \
            -mtime "+${BACKUP_DAYS}" -delete 2>/dev/null
        find "$BACKUP_DIR" -type f -name "*.trn" \
            -mtime "+${BACKUP_DAYS}" -delete 2>/dev/null
    fi

    USED="$(du -sh /var/opt/mssql 2>/dev/null | cut -f1)"
    echo "[clean_logs] Barrido terminado. Uso actual de /var/opt/mssql: ${USED:-desconocido}"
}

# Primer barrido al arrancar, luego cada CLEAN_INTERVAL.
while true; do
    clean_once
    sleep "$CLEAN_INTERVAL"
done
