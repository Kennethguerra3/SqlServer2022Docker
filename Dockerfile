# 1. Usamos la imagen oficial de SQL Server 2022 (Latest)
FROM mcr.microsoft.com/mssql/server:2022-latest

# 2. Nos convertimos en Superusuario (Root)
# OBLIGATORIO en Railway para evitar problemas de permisos con el volumen
USER root

# --- CONFIGURACIÓN ROBUSTA ---

# Aceptamos la licencia
ENV ACCEPT_EULA=Y

# Edición Developer (Gratis y completa, no caduca)
ENV MSSQL_PID=Developer

# Zona Horaria (Para que los Jobs corran a la hora de Perú, no la de Londres)
ENV TZ=America/Lima

# 🔥 ACTIVAR EL AGENTE SQL (CRÍTICO PARA JOBS) 🔥
ENV MSSQL_AGENT_ENABLED=true

# 3. Preparación de Directorios y Permisos (Blindado)
# Creamos la estructura completa y damos permisos al usuario root
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && chmod -R 777 /var/opt/mssql \
    && chown -R root:root /var/opt/mssql

# 4. Exponemos el puerto
EXPOSE 1433

# 5. Comando de inicio
CMD ["/opt/mssql/bin/sqlservr"]
