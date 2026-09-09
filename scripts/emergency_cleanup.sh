#!/bin/bash
# ==========================================================
# LIMPIEZA DE EMERGENCIA - CUANDO EL VOLUMEN ESTÁ LLENO
# ==========================================================
# Ejecuta esto en Railway cuando:
#   - El volumen esté >90% lleno
#   - Los usuarios reportan conexión lenta
#   - SQL Server se congela por falta de espacio
#
# NO EJECUTES ESTO mientras hay backups en progreso
# ==========================================================

set -euo pipefail

log() { echo "[EMERGENCY] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

log "================================="
log "LIMPIEZA DE EMERGENCIA INICIADA"
log "================================="

# Diagnostico antes de limpiar
log ""
log "=== ESPACIO ANTES ==="
df -h /var/opt/mssql | tail -1

# ===================================================================
# PASO 1: Limpiar archivos .trn (transaction logs) > 24 horas
# ===================================================================
log ""
log "Limpiando transaction logs (.trn) > 24h..."
DELETED_TRN=$(find /var/opt/mssql/backup -name "*.trn" -mtime +1 -type f -delete -print 2>/dev/null | wc -l)
log "  ✓ Eliminados $DELETED_TRN archivos .trn"

# ===================================================================
# PASO 2: Limpiar logs de SQL Server > 3 días
# ===================================================================
log ""
log "Limpiando logs de SQL Server (.log, .trc) > 3 días..."
DELETED_LOGS=0
for EXT in log trc txt; do
    COUNT=$(find /var/opt/mssql/log -name "*.${EXT}" -mtime +3 -type f -delete -print 2>/dev/null | wc -l)
    DELETED_LOGS=$((DELETED_LOGS + COUNT))
done
log "  ✓ Eliminados $DELETED_LOGS archivos de logs"

# ===================================================================
# PASO 3: Limpiar dumps > 5 días (son muy pesados)
# ===================================================================
log ""
log "Limpiando memory dumps (.dmp) > 5 días..."
DELETED_DMP=$(find /var/opt/mssql -name "*.dmp" -mtime +5 -type f -delete -print 2>/dev/null | wc -l)
log "  ✓ Eliminados $DELETED_DMP archivos .dmp"

# ===================================================================
# PASO 4: Limpiar backups EXCEPTO los PRE_REPAIR (forenses) > 3 días
# ===================================================================
log ""
log "Limpiando backups (.bak) > 3 días (excepto PRE_REPAIR_*)..."
DELETED_BAK=$(find /var/opt/mssql/backup -name "*.bak" \
    ! -name "PRE_REPAIR_*" \
    -mtime +3 -type f -delete -print 2>/dev/null | wc -l)
log "  ✓ Eliminados $DELETED_BAK archivos .bak"

# ===================================================================
# PASO 5: Limpiar /log del root (trazas del sistema)
# ===================================================================
log ""
log "Limpiando trazas del sistema (/log) > 3 días..."
DELETED_ROOT_LOGS=0
for EXT in log trc txt; do
    COUNT=$(find /log -name "*.${EXT}" -mtime +3 -type f -delete -print 2>/dev/null | wc -l)
    DELETED_ROOT_LOGS=$((DELETED_ROOT_LOGS + COUNT))
done
log "  ✓ Eliminados $DELETED_ROOT_LOGS archivos del /log"

# ===================================================================
# PASO 6: Reporte final
# ===================================================================
log ""
log "=== ESPACIO DESPUÉS ==="
df -h /var/opt/mssql | tail -1

TOTAL_FREED=$((DELETED_TRN + DELETED_LOGS + DELETED_DMP + DELETED_BAK + DELETED_ROOT_LOGS))
log ""
log "✅ Limpieza completada. Total archivos eliminados: $TOTAL_FREED"
log ""
log "🔧 PRÓXIMOS PASOS:"
log "   1. Ajustar variables de limpieza en Railway:"
log "      - CLEAN_RETENTION_DAYS=3 (más agresivo que 7)"
log "      - CLEAN_INTERVAL_SECONDS=43200 (cada 12 horas en lugar de 24)"
log "   2. Configurar backups a R2 para descargar del volumen:"
log "      - R2_BUCKET, RCLONE_CONFIG_R2_*"
log "   3. Aumentar tamaño del volumen si es necesario"
log ""
log "⚠️  Si el espacio vuelve a llenarse rápido, contacta a soporta"
log "================================="
