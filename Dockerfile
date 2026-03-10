# ==========================================
# 1. IMAGEN BASE
# ==========================================
# Usamos la versión 2019 para máxima compatibilidad inicial.
# (Más tarde podrás cambiar esto a: 2022-latest para el Upgrade)
# IMPORTANTE: NO usar 2022-latest — fue actualizado a Ubuntu 22.04 con sqlpal package6
# que hace Stack Overflow con el storage de Railway (synchronous IO fallback bug).
# Ubuntu 20.04 (package4/sqlpal) funciona correctamente.
FROM mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-20.04

# ==========================================
# 2. PERMISOS
# ==========================================
# Elevamos a Root para poder manipular el sistema de archivos de Railway
USER root

# ==========================================
# 3. VARIABLES DE ENTORNO (CONFIGURACIÓN)
# ==========================================
# Aceptación de licencia y Edición Developer (Gratis y completa)
ENV ACCEPT_EULA=Y
ENV MSSQL_PID=Developer

# Zona Horaria (Perú)
ENV TZ=America/Lima

# Activar el Agente SQL (Vital para tus Jobs programados)
ENV MSSQL_AGENT_ENABLED=true

# ==========================================
# 4. VARIABLES DE ENTORNO (ROBUSTEZ Y MEMORIA)
# ==========================================
# Evita generar archivos de error y volcados gigantes que saturan los logs y el disco
ENV MSSQL_ENABLE_COREDUMP=0
ENV MSSQL_TELEMETRY_ENABLED=false
ENV MSSQL_DUMP_ON_ERROR=0

# Optimización de red para evitar cortes en la nube (Power BI / SSMS)
ENV MSSQL_TCP_KEEPALIVE=30000

# ==========================================
# 5. SISTEMA DE ARCHIVOS
# ==========================================
# Creamos la estructura de directorios blindada y asignamos permisos
# Cambiamos a UID 10001 (mssql) que es el estándar de seguridad
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && mkdir -p /var/opt/mssql/backup \
    && chown -R 10001:0 /var/opt/mssql \
    && chmod -R 770 /var/opt/mssql

# Copiamos los scripts de entrada y recuperación
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/attach_databases.sql /usr/local/bin/attach_databases.sql
RUN chmod +x /usr/local/bin/entrypoint.sh

# ==========================================
# 6. HEALTHCHECK (MONITOREO RELAJADO)
# ==========================================
# Relajamos los tiempos para evitar reinicios agresivos durante la carga inicial.
# - interval: 30s (más tiempo entre pruebas)
# - start-period: 60s (más tiempo para arrancar frío)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" > /dev/null 2>&1 || exit 1

# ==========================================
# 7. ARRANQUE
# ==========================================
EXPOSE 1433
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
