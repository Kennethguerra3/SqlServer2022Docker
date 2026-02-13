#!/bin/bash
# entrypoint.sh - Script para estabilizar el arranque de SQL Server en Railway

echo "Iniciando secuencia de estabilización de Antigravity..."

# 1. Retraso de seguridad (Anti-Panic Attack)
# Esto evita que Railway entre en un bucle infinito de reinicios inmediatos
# si algo falla catastróficamente durante los primeros segundos.
echo "Esperando 5 segundos para estabilizar el entorno..."
sleep 5

# 2. Corrección de permisos en caliente
# SQL Server oficial usa el usuario 'mssql' (UID 10001)
# Si Railway montó el volumen como root, esto lo corrige.
echo "Ajustando permisos de /var/opt/mssql..."
chown -R mssql:root /var/opt/mssql

# 3. Arrancar SQL Server
echo "Lanzando SQL Server..."
# Usamos exec para que SQL Server sea el PID 1 y reciba las señales de apagado correctamente
exec /opt/mssql/bin/sqlservr
