# 1. Imagen Base (SQL Server 2022)
#FROM mcr.microsoft.com/mssql/server:2022-latest
FROM mcr.microsoft.com/mssql/server:2019-latest

# 2. Permisos Root (Obligatorio en Railway)
USER root

# --- CONFIGURACIÓN DE ENTORNO ---
ENV ACCEPT_EULA=Y
ENV MSSQL_PID=Developer
ENV TZ=America/Lima
ENV MSSQL_AGENT_ENABLED=true

# --- MEJORAS DE ROBUSTEZ ---
ENV MSSQL_ENABLE_COREDUMP=0
ENV MSSQL_TCP_KEEPALIVE=30000

# -------------------------------------------------------------------------
# 🔥 EL FIX CRÍTICO PARA ERROR 10054 (OpenSSL) 🔥
# Esto baja la seguridad interna del contenedor de Nivel 2 a Nivel 1.
# Permite que la negociación SSL pase a través del proxy de Railway sin cortarse.
RUN sed -i 's/SECLEVEL=2/SECLEVEL=1/g' /etc/ssl/openssl.cnf
# -------------------------------------------------------------------------

# 3. Preparación de Directorios (Blindaje)
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && mkdir -p /var/opt/mssql/backup \
    && chmod -R 777 /var/opt/mssql \
    && chown -R root:root /var/opt/mssql

# 4. HEALTHCHECK (Monitor de Signos Vitales)
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" || exit 1

# 5. Puerto
EXPOSE 1433

# 6. Inicio
CMD ["/opt/mssql/bin/sqlservr"]
