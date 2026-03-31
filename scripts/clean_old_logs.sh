#!/bin/bash
# Limpieza automática de logs antiguos de SQL Server y sistema
# Elimina logs mayores a 7 días para evitar llenar el disco

# Directorios de logs
LOG_DIRS=(
    "/var/opt/mssql/log"
    "/log"
)

# Días de antigüedad para borrar
DAYS=7

for DIR in "${LOG_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        find "$DIR" -type f -name "*.log" -mtime +$DAYS -exec rm -f {} \;
        find "$DIR" -type f -name "*.trc" -mtime +$DAYS -exec rm -f {} \;
        find "$DIR" -type f -name "*.txt" -mtime +$DAYS -exec rm -f {} \;
    fi
    # Opcional: limpiar archivos de backup viejos
    if [[ "$DIR" == "/var/opt/mssql/backup" ]]; then
        find "$DIR" -type f -name "*.bak" -mtime +$DAYS -exec rm -f {} \;
    fi
    # Opcional: limpiar dumps
    if [[ "$DIR" == "/var/opt/mssql/log" ]]; then
        find "$DIR" -type f -name "*.dmp" -mtime +$DAYS -exec rm -f {} \;
    fi
    # Puedes agregar más extensiones si lo deseas
    # find "$DIR" -type f -name "*.old" -mtime +$DAYS -exec rm -f {} \;
done
