# 1. Usamos la imagen oficial de SQL Server 2022 (Latest)
FROM mcr.microsoft.com/mssql/server:2022-latest

# 2. Nos convertimos en Superusuario (Root)
# Esto es OBLIGATORIO en Railway para evitar el error "Access Denied" en el volumen
USER root

# --- CONFIGURACIÓN ROBUSTA ---

# Aceptamos la licencia automáticamente
ENV ACCEPT_EULA=Y

# Definimos la edición "Developer" (Gratis, completa y no caduca)
# Si no pones esto, a veces instala "Evaluation" y se apaga en 6 meses.
ENV MSSQL_PID=Developer

# Configuración de Zona Horaria (Para que los logs salgan con hora de Perú)
ENV TZ=America/Lima

# 3. Preparación de Directorios y Permisos (Blindado)
# Creamos la estructura completa explícitamente y damos permisos totales
RUN mkdir -p /var/opt/mssql/data \
    && mkdir -p /var/opt/mssql/log \
    && mkdir -p /var/opt/mssql/secrets \
    && chmod -R 777 /var/opt/mssql \
    && chown -R root:root /var/opt/mssql

# 4. Exponemos el puerto estándar
EXPOSE 1433

# 5. Comando de inicio
CMD ["/opt/mssql/bin/sqlservr"]
