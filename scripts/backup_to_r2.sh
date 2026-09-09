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
# --------------------------------------------------------------------------
# INCIDENTE 2026-09-06: EL VOLUMEN SE LLENO AL 100%
# --------------------------------------------------------------------------
# Que paso: las credenciales de R2 estaban mal puestas (el Account ID en
# RCLONE_CONFIG_R2_ACCESS_KEY_ID y el Access Key ID en el campo del secret).
# rclone devolvia 401 en cada subida. La version anterior de este script
# solo borraba el .bak local DESPUES de que la subida confirmara, asi que
# cada backup se quedaba en el volumen.
#
# Y habia un segundo fallo, independiente y mas grave, que tardo en verse:
# un BUCLE INFINITO al recorrer la lista de bases. El patron era este:
#
#     while IFS= read -r db; do
#         respaldar_una "$db"        # <-- aqui dentro se llama a sqlcmd
#     done <<< "$dbs"
#
# El here-string (<<<) es un descriptor de entrada que el bucle comparte con
# todo lo que lance dentro. sqlcmd toca ese descriptor y le deja la posicion
# al principio, asi que el siguiente 'read' vuelve a leer la PRIMERA linea.
# Para siempre. Comprobado en el contenedor: 6.174 iteraciones con el mismo
# valor antes de tumbar la conexion.
#
# Dos consecuencias, y la segunda es peor que la primera:
#
#   a) Se respaldaba la primera base una y otra vez cada ~2 minutos. Asi se
#      escribieron 43 copias de 790 MB en 80 minutos, dejando el volumen de
#      46 GB a 0 libres. A partir de ahi todo backup salia truncado.
#   b) EL BUCLE NUNCA PASABA DE LA PRIMERA BASE. De 6 bases de datos, 5 no
#      se respaldaron jamas. El log decia "OK=1 FALLOS=0" y parecia sano.
#
# La solucion es no depender del stdin para iterar: la lista se vuelca a un
# array ANTES de respaldar nada, y se recorre con un for. Ademas sqlcmd y
# rclone reciben < /dev/null, para que ningun hijo pueda volver a tocar la
# entrada de un bucle.
#
# Las cuatro defensas que se agregaron, cada una corta el fallo en un punto:
#
#   1. UNA VEZ AL DIA: marca de estado + lock. Aunque el planificador se
#      dispare de mas, no se puede respaldar dos veces el mismo dia.
#   2. ROTACION LOCAL SIEMPRE: se conservan MAX_LOCAL_BACKUPS copias y se
#      borran las viejas ANTES de escribir la nueva, funcione R2 o no. Que
#      la nube este caida no puede traducirse en un volumen lleno.
#   3. GUARDA DE ESPACIO: si el disco libre no alcanza, no se intenta el
#      backup. Un .bak truncado no es un backup, es basura que ocupa.
#   4. LIMPIEZA DE PARCIALES: si el backup falla o llega un SIGTERM (el
#      cron de suspension apaga el contenedor a la 01:00), se borra el
#      archivo a medio escribir en vez de dejarlo ocupando espacio.
# --------------------------------------------------------------------------
#
# VARIABLES REQUERIDAS (en Railway, no en la imagen):
#   MSSQL_SA_PASSWORD                  ya existe
#   R2_BUCKET                          ej: genovesa-sqlbackups
#   RCLONE_CONFIG_R2_TYPE=s3
#   RCLONE_CONFIG_R2_PROVIDER=Cloudflare
#   RCLONE_CONFIG_R2_ACCESS_KEY_ID     Access Key ID del token de R2 (32 hex)
#   RCLONE_CONFIG_R2_SECRET_ACCESS_KEY Secret Access Key del token (64 hex)
#   RCLONE_CONFIG_R2_ENDPOINT          https://<ACCOUNT_ID>.r2.cloudflarestorage.com
#   RCLONE_CONFIG_R2_REGION=auto
#
#   OJO: el ACCOUNT_ID del endpoint y el ACCESS_KEY_ID son valores DISTINTOS.
#   Los dos son 32 caracteres hex y se confunden con facilidad. Si los
#   intercambias, R2 responde 401 y no hay backup en la nube. El script
#   ahora lo detecta al arrancar y lo avisa.
#
# OPCIONALES:
#   BACKUP_HOUR=23        hora local (TZ=America/Lima)
#   BACKUP_MINUTE=40
#   BACKUP_RETENTION_DAYS=30    retencion en R2
#   MAX_LOCAL_BACKUPS=3         copias que se guardan en el volumen
#   BACKUP_MAX_PCT=25           techo de la carpeta de backups, en % del volumen
#   MIN_FREE_MARGIN_MB          colchon de disco libre. Si no lo defines se
#                               calcula solo: 5% del volumen, entre 256 MB y 2 GB.
#
# Sobre BACKUP_MAX_PCT: este repo se usa como plantilla y no hay forma de
# saber que tamano de volumen ni que tamano de base va a tener cada quien.
# Un limite por CANTIDAD de copias no protege a nadie: 3 backups de 1 GB
# llenan un volumen de 5 GB igual de rapido. El techo porcentual si escala
# solo, porque se mide contra el disco real que hay debajo.
#
# Sobre MIN_FREE_MARGIN_MB: por la misma razon NO puede ser un numero fijo.
# Un colchon de 2 GB es sensato en un volumen de 50 GB y absurdo en uno de 5:
# ahi bloquearia el backup para siempre y el usuario se quedaria sin ninguno,
# que es peor que el problema que el colchon intenta evitar. Por eso escala
# con el disco, con un piso para volumenes diminutos y un techo para grandes.
# ==========================================================================

set -uo pipefail

SQLCMD="/opt/mssql-tools18/bin/sqlcmd"
BACKUP_DIR="/var/opt/mssql/backup"
BUCKET="${R2_BUCKET:-genovesa-sqlbackups}"
HOUR="${BACKUP_HOUR:-23}"
MINUTE="${BACKUP_MINUTE:-40}"
RETENTION="${BACKUP_RETENTION_DAYS:-30}"
MAX_LOCAL="${MAX_LOCAL_BACKUPS:-3}"
MARGEN_MB_FIJO="${MIN_FREE_MARGIN_MB:-}"   # vacio = calcularlo segun el disco
MAX_PCT="${BACKUP_MAX_PCT:-25}"

STATE_FILE="${BACKUP_DIR}/.ultimo_backup"
LOCK_DIR="/tmp/backup_to_r2.lock"

log() { echo "[backup-r2] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# --- Limpieza de parciales -------------------------------------------------
# Si nos matan a mitad de un BACKUP DATABASE, el .bak queda truncado.
# Asi es como quedaron en el volumen un archivo de 8 KB y otro de 95 MB
# donde deberia haber 790 MB. Un parcial no sirve para restaurar: se borra.
ARCHIVO_EN_CURSO=""
limpiar_y_salir() {
    if [ -n "$ARCHIVO_EN_CURSO" ] && [ -f "$ARCHIVO_EN_CURSO" ]; then
        log "Senal de apagado durante el backup. Borrando parcial: $(basename "$ARCHIVO_EN_CURSO")"
        rm -f "$ARCHIVO_EN_CURSO"
    fi
    rmdir "$LOCK_DIR" 2>/dev/null
    exit 0
}
trap limpiar_y_salir SIGINT SIGTERM

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

# Error clasico: pegar el Account ID (el del endpoint) como Access Key ID.
# Da 401 en cada subida y el sintoma que se ve es "el volumen se llena",
# que no apunta a credenciales. Mejor decirlo aqui, con nombre y apellido.
if [ "$R2_LISTO" -eq 1 ]; then
    ACCOUNT_ID_ENDPOINT="$(echo "${RCLONE_CONFIG_R2_ENDPOINT:-}" | sed -E 's|^https://([^.]+)\..*|\1|')"
    if [ -n "$ACCOUNT_ID_ENDPOINT" ] && [ "$ACCOUNT_ID_ENDPOINT" = "${RCLONE_CONFIG_R2_ACCESS_KEY_ID}" ]; then
        log "!!! ERROR DE CONFIGURACION: RCLONE_CONFIG_R2_ACCESS_KEY_ID es igual al"
        log "!!! Account ID del endpoint. Son valores DISTINTOS. R2 respondera 401."
        log "!!! Corrigelo en Railway: Access Key ID (32 hex) y Secret (64 hex)"
        log "!!! salen los dos de R2 > API Tokens > Create API token."
    fi
    if [ "${#RCLONE_CONFIG_R2_SECRET_ACCESS_KEY}" -lt 40 ]; then
        log "!!! AVISO: el Secret Access Key parece corto (${#RCLONE_CONFIG_R2_SECRET_ACCESS_KEY} caracteres)."
        log "!!! El de R2 tiene 64. Puede que hayas pegado ahi el Access Key ID."
    fi
fi

# El < /dev/null NO es decorativo: sin el, sqlcmd se come la entrada de
# cualquier bucle que lo llame. Ver la explicacion del bucle infinito arriba.
sql() { "$SQLCMD" -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -h -1 -W "$@" < /dev/null; }

# --- Rotacion local --------------------------------------------------------
# Se ejecuta SIEMPRE, suba o no suba a R2. Esta es la defensa que faltaba:
# antes, con R2 caido, el volumen crecia 790 MB por noche sin techo.
# Se excluyen los PRE_REPAIR_*: son la copia forense que toma
# auto_repair_dataloss.sql antes de tocar paginas danadas.
rotar_locales() {
    local db="$1"
    local sobran

    # Etapa 1: por cantidad. Deja las MAX_LOCAL mas recientes.
    sobran="$(ls -1t "${BACKUP_DIR}/${db}_"*.bak 2>/dev/null | grep -v '/PRE_REPAIR_' | tail -n "+$((MAX_LOCAL + 1))")"
    if [ -n "$sobran" ]; then
        while IFS= read -r viejo; do
            [ -z "$viejo" ] && continue
            log "  rotacion (cantidad): elimino $(basename "$viejo")"
            rm -f "$viejo"
        done <<< "$sobran"
    fi

    # Etapa 2: por tamano. La cantidad sola no protege un volumen pequeno,
    # asi que ademas exigimos que la carpeta no pase de MAX_PCT del disco.
    # Se borra de la mas vieja a la mas nueva hasta entrar en el techo.
    local total_kb techo_kb usado_kb candidato
    total_kb="$(df -Pk "$BACKUP_DIR" | tail -1 | awk '{print $2}')"
    [ -z "$total_kb" ] && return 0
    techo_kb=$(( total_kb * MAX_PCT / 100 ))

    while true; do
        usado_kb="$(du -sk "$BACKUP_DIR" 2>/dev/null | cut -f1)"
        [ -z "$usado_kb" ] && break
        [ "$usado_kb" -le "$techo_kb" ] && break

        # El mas antiguo que no sea forense. Nunca bajamos de una copia:
        # quedarse sin ningun backup es peor que tener el disco justo.
        candidato="$(ls -1t "${BACKUP_DIR}/${db}_"*.bak 2>/dev/null | grep -v '/PRE_REPAIR_' | tail -1)"
        [ -z "$candidato" ] && break
        if [ "$(ls -1 "${BACKUP_DIR}/${db}_"*.bak 2>/dev/null | grep -cv '/PRE_REPAIR_')" -le 1 ]; then
            log "  rotacion (tamano): queda una sola copia de ${db}, no la borro."
            log "  rotacion (tamano): la carpeta usa $(( usado_kb / 1024 )) MB sobre un techo de $(( techo_kb / 1024 )) MB."
            break
        fi
        log "  rotacion (tamano): elimino $(basename "$candidato") para respetar el ${MAX_PCT}% del volumen."
        rm -f "$candidato"
    done
}

# --- Guarda de espacio -----------------------------------------------------
# Estimamos con el ultimo backup de esa base. Si no hay ninguno, pedimos
# el tamano de los datos de la base como referencia.
margen_kb() {
    # Si el usuario fijo un valor, manda el suyo. Si no, 5% del volumen
    # acotado entre 256 MB y 2 GB, para que escale con el disco real.
    if [ -n "$MARGEN_MB_FIJO" ]; then
        echo $(( MARGEN_MB_FIJO * 1024 ))
        return
    fi
    local total_kb m
    total_kb="$(df -Pk "$BACKUP_DIR" | tail -1 | awk '{print $2}')"
    [ -z "$total_kb" ] && { echo 262144; return; }
    m=$(( total_kb * 5 / 100 ))
    [ "$m" -lt 262144 ]  && m=262144     # piso: 256 MB
    [ "$m" -gt 2097152 ] && m=2097152    # techo: 2 GB
    echo "$m"
}

hay_espacio() {
    local db="$1"
    local ref_kb libre_kb necesario_kb margen
    ref_kb="$(du -k "${BACKUP_DIR}/${db}_"*.bak 2>/dev/null | sort -rn | head -1 | cut -f1)"
    if [ -z "$ref_kb" ]; then
        ref_kb="$(sql -Q "SET NOCOUNT ON; SELECT CAST(SUM(size)*8 AS BIGINT) FROM [${db}].sys.database_files WHERE type=0;" 2>/dev/null | tr -d '\r ' | grep -E '^[0-9]+$' | head -1)"
    fi
    [ -z "$ref_kb" ] && ref_kb=0

    libre_kb="$(df -Pk "$BACKUP_DIR" | tail -1 | awk '{print $4}')"
    margen="$(margen_kb)"
    necesario_kb=$(( ref_kb + margen ))

    if [ "$libre_kb" -lt "$necesario_kb" ]; then
        log "  ${db}: espacio insuficiente. Libre $(( libre_kb / 1024 )) MB, necesito $(( necesario_kb / 1024 )) MB"
        log "  ${db}: ($(( ref_kb / 1024 )) MB del backup + $(( margen / 1024 )) MB de colchon)."
        log "  ${db}: se omite. Un .bak truncado no sirve para restaurar y ocupa disco."
        return 1
    fi
    return 0
}

# --- Respaldo de una base --------------------------------------------------
respaldar_una() {
    local db="$1"
    local stamp; stamp="$(date '+%Y%m%d_%H%M')"
    local file="${BACKUP_DIR}/${db}_${stamp}.bak"

    # Primero rotamos y despues comprobamos: liberar antes de medir da una
    # lectura real del disco disponible.
    rotar_locales "$db"
    hay_espacio "$db" || return 1

    log "  ${db}: respaldando..."
    ARCHIVO_EN_CURSO="$file"
    if ! sql -Q "BACKUP DATABASE [${db}] TO DISK = N'${file}' WITH COMPRESSION, FORMAT, INIT;" >/dev/null; then
        log "  ${db}: FALLO el backup. Borro el archivo a medias."
        rm -f "$file"
        ARCHIVO_EN_CURSO=""
        return 1
    fi

    # Verificar antes de subir. Un backup sin verificar es una suposicion.
    if ! sql -Q "RESTORE VERIFYONLY FROM DISK = N'${file}';" >/dev/null; then
        log "  ${db}: FALLO la verificacion. El archivo no es fiable, lo borro."
        rm -f "$file"
        ARCHIVO_EN_CURSO=""
        return 1
    fi
    ARCHIVO_EN_CURSO=""

    local size; size="$(du -h "$file" 2>/dev/null | cut -f1)"
    log "  ${db}: verificado (${size})."

    if [ "$R2_LISTO" -eq 0 ]; then
        log "  ${db}: sin credenciales de R2, queda en local (rotacion: ${MAX_LOCAL} copias)."
        return 0
    fi

    if rclone copyto "$file" "r2:${BUCKET}/${db}/${db}_${stamp}.bak" \
            --s3-no-check-bucket --retries 3 --low-level-retries 5 < /dev/null 2>&1 | sed 's/^/[backup-r2]   rclone: /'; then
        log "  ${db}: subido a R2."
        # Ya esta en la nube, pero conservamos la copia local mas reciente:
        # restaurar desde el volumen es inmediato y no depende de la red.
        # La rotacion del proximo ciclo evita que se acumulen.
        return 0
    else
        log "  ${db}: FALLO la subida. Queda en local: $(basename "$file")"
        log "  ${db}: revisa las credenciales de R2 (401 = Access Key/Secret mal puestos)."
        return 1
    fi
}

# --- Ciclo completo --------------------------------------------------------
respaldar_todo() {
    log "=== Inicio del ciclo de backup ==="
    mkdir -p "$BACKUP_DIR"

    local lista
    lista="$(sql -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE database_id > 4 AND state_desc = 'ONLINE' AND is_read_only = 0;" 2>/dev/null | tr -d '\r' | grep -v '^$')"

    if [ -z "$lista" ]; then
        log "No se pudo listar bases (SQL Server no responde?). Se omite este ciclo."
        return 1
    fi

    # La lista se vuelca a un array ANTES de respaldar nada. Este bucle si
    # puede usar el here-string porque dentro no se lanza ningun proceso que
    # pueda tocar la entrada. El de abajo, que si respalda, ya no la usa.
    local -a dbs=()
    local linea
    while IFS= read -r linea; do
        [ -n "$linea" ] && dbs+=("$linea")
    done <<< "$lista"

    log "Bases encontradas: ${#dbs[@]} -> ${dbs[*]}"

    local ok=0 fail=0 db
    for db in "${dbs[@]}"; do
        if respaldar_una "$db"; then ok=$((ok+1)); else fail=$((fail+1)); fi
    done

    # Retencion en R2
    if [ "$R2_LISTO" -eq 1 ] && [ "$fail" -eq 0 ]; then
        log "Aplicando retencion de ${RETENTION} dias en R2..."
        rclone delete "r2:${BUCKET}" --min-age "${RETENTION}d" < /dev/null 2>&1 | sed 's/^/[backup-r2]   rclone: /'
    fi

    log "=== Fin. OK=${ok} FALLOS=${fail} ==="
    log "Uso del volumen: $(df -h "$BACKUP_DIR" | tail -1 | awk '{print $5" ("$4" libres)"}')"
    if [ "$fail" -gt 0 ]; then
        log "!!! ATENCION: ${fail} base(s) sin respaldar. Revisa los mensajes de arriba."
        return 1
    fi
    return 0
}

# --- Una vez al dia, pase lo que pase --------------------------------------
# El bucle de abajo no deberia dispararse de mas, pero el incidente demostro
# que si lo hace nadie lo frena. La marca de fecha es el freno: da igual
# cuantas veces se llame, solo el primer ciclo correcto del dia entra.
ya_se_hizo_hoy() {
    [ -f "$STATE_FILE" ] || return 1
    [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$(date '+%Y-%m-%d')" ]
}

ciclo_protegido() {
    if ya_se_hizo_hoy; then
        log "Hoy ya se respaldo (marca en $(basename "$STATE_FILE")). Se omite."
        return 0
    fi
    # Lock por si llegara a haber dos instancias del script vivas.
    # mkdir es atomico: o lo crea esta instancia, o ya existe.
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        log "Ya hay otro ciclo de backup en curso. Se omite."
        return 0
    fi
    respaldar_todo
    local r=$?
    # La marca se pone solo si el ciclo termino bien. Si fallo, se puede
    # reintentar mas tarde el mismo dia en vez de perder la noche entera.
    [ "$r" -eq 0 ] && date '+%Y-%m-%d' > "$STATE_FILE"
    rmdir "$LOCK_DIR" 2>/dev/null
    return $r
}

# --- Programador -----------------------------------------------------------
# Espera hasta la proxima HH:MM local y ejecuta. TZ ya es America/Lima.
segundos_hasta_proxima() {
    local ahora objetivo espera
    ahora="$(date +%s)"
    objetivo="$(date -d "today ${HOUR}:${MINUTE}" +%s 2>/dev/null)"
    if [ -z "$objetivo" ] || [ "$objetivo" -le "$ahora" ]; then
        objetivo="$(date -d "tomorrow ${HOUR}:${MINUTE}" +%s 2>/dev/null)"
    fi
    # Si 'date' fallara, objetivo queda vacio y la resta daria un negativo
    # que 'sleep' rechaza, dejando este bucle girando sin pausa. No fue la
    # causa del incidente (esa fue el here-string, ver cabecera), pero es un
    # camino real al mismo sintoma. Ante la duda, una hora de espera: se
    # pierde precision, no el disco.
    if [ -z "$objetivo" ]; then
        log "AVISO: no pude calcular la proxima hora de backup. Espero 1h."
        echo 3600
        return
    fi
    espera=$(( objetivo - ahora ))
    # Un piso de 60s es la red de seguridad final: aunque el calculo salga
    # cero o negativo, el bucle no puede girar mas rapido que un minuto.
    if [ "$espera" -lt 60 ]; then espera=60; fi
    echo "$espera"
}

log "Programado para las ${HOUR}:${MINUTE} (hora local, TZ=${TZ:-?})."
if [ "$R2_LISTO" -eq 1 ]; then
    log "Destino: r2:${BUCKET}. Retencion en la nube: ${RETENTION} dias."
else
    log "Sin R2 configurado: los backups se quedan en el volumen, pero acotados."
    log "Sirven ante un borrado por error; NO ante la perdida del volumen."
fi
log "Limite local: ${MAX_LOCAL} copias como maximo, y nunca mas del ${MAX_PCT}% del"
log "volumen. Colchon libre exigido: $(( $(margen_kb) / 1024 )) MB. Con estos dos"
log "topes, los backups no pueden llenar el disco aunque R2 nunca funcione."

while true; do
    espera="$(segundos_hasta_proxima)"
    log "Proximo backup en $(( espera / 3600 ))h $(( (espera % 3600) / 60 ))m."
    sleep "$espera" || sleep 300
    ciclo_protegido
    sleep 90   # evita disparar dos veces dentro del mismo minuto
done
