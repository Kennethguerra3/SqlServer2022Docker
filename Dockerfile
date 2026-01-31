# 1. Imagen Base
FROM mcr.microsoft.com/mssql/server:2022-latest
#FROM mcr.microsoft.com/mssql/server:2019-latest

# 2. Permisos Root (Obligatorio en Railway)
USER root

# --- CONFIGURACIÓN DE ENTORNO ---

# Licencia y Edición
ENV ACCEPT_EULA=Y
ENV MSSQL_PID=Developer

# Zona Horaria (Perú)
ENV TZ=America/Lima

# Agente SQL (Para tus Jobs)
ENV MSSQL_AGENT_ENABLED=true

# --- MEJORAS DE ROBUSTEZ ---

# A. Desactivar Dumps para no llenar el disco duro con basura
ENV MSSQL_ENABLE_COREDUMP=0

# B. Optimización de TCP para la nube (Evita desconexiones de Power BI)
ENV MSSQL_TCP_KEEPALIVE=30000

# 3. Preparación de Directorios (Blindaje)
# Creamos carpetas, damos permisos y aseguramos que el dueño sea root
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && mkdir -p /var/opt/mssql/backup \
    && chmod -R 777 /var/opt/mssql \
    && chown -R root:root /var/opt/mssql

# 4. HEALTHCHECK (El Monitor de Signos Vitales)
# Docker intentará hacer un Login cada 15s. Si falla, marca el contenedor como "Unhealthy".
# Nota: Usamos una consulta simple "SELECT 1" para no cargar el sistema.
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" || exit 1

# 5. Puerto
EXPOSE 1433

# 6. Inicio
CMD ["/opt/mssql/bin/sqlservr"]
