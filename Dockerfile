# ==========================================
# 1. IMAGEN BASE
# ==========================================
# Usamos la versión 2019 para máxima compatibilidad inicial.
# (Más tarde podrás cambiar esto a: 2022-latest para el Upgrade)
FROM mcr.microsoft.com/mssql/server:2019-latest

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
# 4. VARIABLES DE ENTORNO (ROBUSTEZ)
# ==========================================
# Evita generar archivos de error gigantes que llenan el disco
ENV MSSQL_ENABLE_COREDUMP=0

# Optimización de red para evitar cortes en la nube (Power BI / SSMS)
ENV MSSQL_TCP_KEEPALIVE=30000

# ==========================================
# 5. SISTEMA DE ARCHIVOS
# ==========================================
# Creamos la estructura de directorios blindada y asignamos permisos
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && mkdir -p /var/opt/mssql/backup \
    && chmod -R 777 /var/opt/mssql \
    && chown -R root:root /var/opt/mssql

# ==========================================
# 6. HEALTHCHECK (MONITOREO)
# ==========================================
# Verifica cada 15s que el servidor responda. Si falla 3 veces, reinicia.
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" || exit 1

# ==========================================
# 7. ARRANQUE
# ==========================================
EXPOSE 1433
CMD ["/opt/mssql/bin/sqlservr"]
