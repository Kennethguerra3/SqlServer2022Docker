# ==========================================
# 1. IMAGEN BASE
# ==========================================
# Usamos el tag específico de CU23 con Ubuntu 20.04.
# IMPORTANTE: NO usar 2022-latest — fue actualizado a Ubuntu 22.04 con sqlpal package6
# que hace Stack Overflow con el storage de Railway (synchronous IO fallback bug).
# Ubuntu 20.04 (package4/sqlpal) funciona correctamente con Railway.
# Tag seguro: 2022-CU23-ubuntu-20.04 (SQL Server 2022 + Ubuntu 20.04)
FROM mcr.microsoft.com/mssql/server:2022-CU23-ubuntu-20.04

# ==========================================
# METADATA
# ==========================================
LABEL maintainer="kenneth" \
      version="2022-CU23" \
      base-os="ubuntu-20.04" \
      description="SQL Server 2022 optimizado para Railway"

# ==========================================
# 2. SHELL — pipefail activo
# ==========================================
# Cualquier fallo en un pipe dentro de RUN es detectado y aborta el build
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ==========================================
# 3. PERMISOS
# ==========================================
# Elevamos a Root para poder manipular el sistema de archivos de Railway
USER root

# ==========================================
# 4. VARIABLES DE ENTORNO (CONFIGURACIÓN)
# ==========================================
ENV ACCEPT_EULA=Y \
    MSSQL_PID=Developer \
    # Zona Horaria (Perú)
    TZ=America/Lima \
    # Idioma servidor español (LCID 3082 = Spanish - Spain)
    MSSQL_LCID=3082 \
    # Colación estándar para datos en español, compatible con Power BI
    MSSQL_COLLATION=Modern_Spanish_CI_AS \
    # Agente SQL: vital para Jobs y tareas programadas
    MSSQL_AGENT_ENABLED=true \
    # Directorio de backup por defecto para el Agente SQL
    MSSQL_BACKUP_DIR=/var/opt/mssql/backup

# ==========================================
# 5. VARIABLES DE ENTORNO (ROBUSTEZ Y MEMORIA)
# ==========================================
ENV MSSQL_ENABLE_COREDUMP=0 \
    MSSQL_DUMP_ON_ERROR=0 \
    # Límite de RAM — AJUSTAR según plan Railway: 2GB→1500, 4GB→3500, 8GB→6000
    # Sin límite, SQL Server toma el 90% de RAM y Railway mata el contenedor
    MSSQL_MEMORY_LIMIT_MB=3500 \
    # TCP Keepalive: evita cortes de conexión desde Power BI / SSMS en la nube
    # Tiempo antes del primer paquete keep-alive (ms)
    MSSQL_TCP_KEEPALIVE=30000 \
    # Intervalo entre retransmisiones keep-alive si no hay respuesta (ms)
    MSSQL_TCP_KEEPALIVE_INTERVAL=1000

# ==========================================
# 6. SISTEMA DE ARCHIVOS Y SCRIPTS
# ==========================================
# Copiamos primero los scripts de arranque y auto-reparación (Nivel 3)
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/auto_repair.sql /usr/local/bin/auto_repair.sql

# Creamos la estructura de directorios con permisos correctos
# para el usuario mssql (UID 10001) — todo en un solo RUN para minimizar capas
# IMPORTANTE 1: Hacemos chown al propio punto de montaje /var/opt/mssql 
# para que si Railway monta un volumen ahí, herede/acepte los permisos.
# IMPORTANTE 2: Creamos /.system en la raíz porque SQL Server lo usa 
# internamente y dará Access Denied si no existe y es propiedad de 10001.
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && mkdir -p /var/opt/mssql/backup \
    && chown -R 10001:0 /var/opt/mssql \
    && chmod -R 775 /var/opt/mssql \
    && mkdir -p /.system \
    && chown -R 10001:0 /.system \
    && chmod -R 775 /.system \
    && chmod +x /usr/local/bin/entrypoint.sh

# ==========================================
# 7. HEALTHCHECK (MONITOREO RELAJADO)
# ==========================================
# start-period: 60s para dar margen al arranque en frío de Railway
# -C: acepta el certificado TLS autofirmado (requerido en mssql-tools18)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" -C > /dev/null 2>&1 || exit 1

# ==========================================
# 8. ARRANQUE
# ==========================================
EXPOSE 1433

# Señal de apagado explícita — garantiza que SQL Server cierra conexiones
# y guarda logs antes de terminar (apagado graceful)
STOPSIGNAL SIGTERM

# Regresamos al usuario mssql (UID 10001) por seguridad
USER 10001

# Arrancamos usando nuestro script personalizado que incluye
# manejo de SIGTERM y la auto-reparación de Nivel 3
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
