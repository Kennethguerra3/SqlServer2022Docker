#!/bin/bash
# ==========================================================================
# BACKUP DIARIO A CLOUDFLARE R2
# ==========================================================================
# Por que este script y no BACKUP TO URL nativo:
# el conector S3 de SQL Server 2022 falla contra R2 con
# "Error de sistema operativo 1359 (Error interno)", sin mas detalle,
# incluso con la credencial recien creada y el comando mas simple.
# El motor de backup SI funciona: a disco local respalda sin problema.
# Asi que respaldamos a disco y subimos con rclone.
#
# Si algun dia el backup nativo empieza a funcionar (p.ej. porque la
# actualizacion de ca-certificates que hicimos en el Dockerfile era el
# problema), puedes volver a la ruta nativa y borrar este script.
#
# VARIABLES REQUERIDAS (en Railway, no en la imagen):
#   MSSQL_SA_PASSWORD                  ya existe
#   R2_BUCKET                          ej: genovesa-sqlbackups
#   RCLONE_CONFIG_R2_TYPE=s3
#   RCLONE_CONFIG_R2_PROVIDER=Cloudflare
#   RCLONE_CONFIG_R2_ACCESS_KEY_ID     access key del token de R2
#   RCLONE_CONFIG_R2_SECRET_ACCESS_KEY secret key del token de R2
#   RCLONE_CONFIG_R2_ENDPOINT          https://<ACCOUNT_ID>.r2.cloudflarestorage.com
#   RCLONE_CONFIG_R2_REGION=auto
#
# OPCIONALES:
#   BACKUP_HOUR=23        hora local (TZ=America/Lima)
#   BACKUP_MINUTE=40
#   BACKUP_RETENTION_DAYS=30
# ==========================================================================

set -uo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
BACKUP_DIR="/var/opt/mssql/backup"
BUCKET="${R2_BUCKET:-genovesa-sqlbackups}"
HOUR="${BACKUP_HOUR:-23}"
MINUTE="${BACKUP_MINUTE:-40}"
RETENTION="${BACKUP_RETENTION_DAYS:-30}"

log() { echo "[backup-r2] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# --- Comprobaciones de arranque -------------------------------------------
if [ -z "${MSSQL_SA_PASSWORD:-}" ]; then
    log "ERROR: MSSQL_SA_PASSWORD no definida. El backup no puede correr."
    exit 0
fi

if [ -z "${RCLONE_CONFIG_R2_ACCESS_KEY_ID:-}" ] || [ -z "${RCLONE_CONFIG_R2_SECRET_ACCESS_KEY:-}" ]; then
    log "AVISO: faltan credenciales de R2. Los backups se haran SOLO en local."
    log "AVISO: define RCLONE_CONFIG_R2_* en Railway para subirlos a la nube."
    R2_LISTO=0
else
    R2_LISTO=1
fi

sql() { "$SQLCMD" -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -h -1 -W "$@"; }

# --- Respaldo de una base --------------------------------------------------
respaldar_una() {
    local db="$1"
    local stamp; stamp="$(date '+%Y%m%d_%H%M')"
    local file="${BACKUP_DIR}/${db}_${stamp}.bak"

    log "  ${db}: respaldando..."
    if ! sql -Q "BACKUP DATABASE [${db}] TO DISK = N'${file}' WITH COMPRESSION, FORMAT, INIT;" >/dev/null; then
        log "  ${db}: FALLO el backup."
        return 1
    fi

    # Verificar antes de subir. Un backup sin verificar es una suposicion.
    if ! sql -Q "RESTORE VERIFYONLY FROM DISK = N'${file}';" >/dev/null; then
        log "  ${db}: FALLO la verificacion. Se conserva el archivo local para revision."
        return 1
    fi

    local size; size="$(du -h "$file" 2>/dev/null | cut -f1)"
    log "  ${db}: verificado (${size})."

    if [ "$R2_LISTO" -eq 0 ]; then
        log "  ${db}: sin credenciales de R2, queda en local."
        return 0
    fi

    if rclone copyto "$file" "r2:${BUCKET}/${db}/${db}_${stamp}.bak" \
            --s3-no-check-bucket --retries 3 --low-level-retries 5 2>&1 | sed 's/^/[backup-r2]   rclone: /'; then
        log "  ${db}: subido a R2."
        rm -f "$file"           # solo se borra si la subida confirmo
        return 0
    else
        log "  ${db}: FALLO la subida. El archivo queda en local: ${file}"
        return 1
    fi
}

# --- Ciclo completo --------------------------------------------------------
respaldar_todo() {
    log "=== Inicio del ciclo de backup ==="
    mkdir -p "$BACKUP_DIR"

    local dbs
    dbs="$(sql -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE' AND is_read_only = 0;" 2>/dev/null | tr -d '\r' | grep -v '^$')"

    if [ -z "$dbs" ]; then
        log "No se pudo listar bases (SQL Server no responde?). Se omite este ciclo."
        return
    fi

    local ok=0 fail=0
    while IFS= read -r db; do
        [ -z "$db" ] && continue
        if respaldar_una "$db"; then ok=$((ok+1)); else fail=$((fail+1)); fi
    done <<< "$dbs"

    # Retencion en R2
    if [ "$R2_LISTO" -eq 1 ] && [ "$fail" -eq 0 ]; then
        log "Aplicando retencion de ${RETENTION} dias en R2..."
        rclone delete "r2:${BUCKET}" --min-age "${RETENTION}d" 2>&1 | sed 's/^/[backup-r2]   rclone: /'
    fi

    log "=== Fin. OK=${ok} FALLOS=${fail} ==="
    if [ "$fail" -gt 0 ]; then
        log "!!! ATENCION: ${fail} base(s) sin respaldar. Revisa los mensajes de arriba."
    fi
}

# --- Programador -----------------------------------------------------------
# Espera hasta la proxima HH:MM local y ejecuta. TZ ya es America/Lima.
segundos_hasta_proxima() {
    local ahora objetivo
    ahora="$(date +%s)"
    objetivo="$(date -d "today ${HOUR}:${MINUTE}" +%s 2>/dev/null)"
    if [ -z "$objetivo" ] || [ "$objetivo" -le "$ahora" ]; then
        objetivo="$(date -d "tomorrow ${HOUR}:${MINUTE}" +%s)"
    fi
    echo $(( objetivo - ahora ))
}

log "Programado para las ${HOUR}:${MINUTE} (hora local, TZ=${TZ:-?}). Retencion ${RETENTION}d."
if [ "$R2_LISTO" -eq 1 ]; then
    log "Destino: r2:${BUCKET}"
fi

while true; do
    espera="$(segundos_hasta_proxima)"
    log "Proximo backup en $(( espera / 3600 ))h $(( (espera % 3600) / 60 ))m."
    sleep "$espera"
    respaldar_todo
    sleep 90   # evita disparar dos veces dentro del mismo minuto
done
