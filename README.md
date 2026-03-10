# 🗄️ SQL Server 2022 en Railway (Optimizado)

Configuración Docker lista para producción para desplegar **SQL Server 2022** en [Railway.app](https://railway.app), optimizada para estabilidad, compatibilidad y mantenimiento de bases de datos persistentes.

---

## 🚀 Características

| Característica | Detalle |
|---|---|
| **Imagen base** | `mcr.microsoft.com/mssql/server:2022-CU23-ubuntu-20.04` (Ubuntu 20.04 / sqlpal package4) |
| **Edición** | Developer (gratuita y completa) |
| **Agente SQL** | Habilitado — soporta Jobs y tareas programadas |
| **Zona horaria** | `America/Lima` (Perú) |
| **Healthcheck** | Relajado (60s inicio, 30s intervalo) para arranques en frío |
| **Anti-crash** | Core dumps y telemetría deshabilitados |
| **Seguridad** | Permisos `770` con usuario `mssql` (UID 10001) |
| **Auto-Reparación** | Detecta y repara automáticamente BDs corruptas (`SUSPECT`) al arrancar |
| **Apagado Seguro** | Gestiona señales `SIGTERM` para evitar corrupción de datos en reinicios |

---

## 🏷️ Por qué usamos un tag específico y no `2022-latest`

Estamos usando **SQL Server 2022** — pero con el tag `2022-CU23-ubuntu-20.04` en lugar del genérico `2022-latest`.

El motivo: el tag `2022-latest` fue actualizado a **Ubuntu 22.04** (sqlpal package6), que provoca un **Stack Overflow** con el almacenamiento de Railway por un bug de I/O síncrono.

El tag `2022-CU23-ubuntu-20.04` usa **Ubuntu 20.04** (sqlpal package4) y funciona correctamente. Además, CU23 es la actualización acumulativa más reciente, por lo que tienes la versión más actualizada del motor.

---

## 🛠️ Variables de Entorno en Railway

En el panel **Variables** de tu servicio en Railway, solo debes agregar **una variable**:

| Variable | Ejemplo | Descripción |
|---|---|---|
| `MSSQL_SA_PASSWORD` | `MiClave@2024!` | Contraseña del usuario administrador `sa` |

> **Requisitos de contraseña:** mínimo 8 caracteres, con al menos una mayúscula, una minúscula, un número y un símbolo (ej: `MiClave@2024!`).

El resto de variables (`ACCEPT_EULA`, `MSSQL_PID`, zona horaria, agente SQL, etc.) ya están configuradas dentro del `Dockerfile` y **no necesitan repetirse en Railway**.

---

## 💾 Volumen Persistente (Importante)

Para que tus bases de datos no se borren cuando el contenedor se reinicie o se actualice, **debes añadir un volumen** a tu servicio en Railway.

En la configuración del servicio, ve a **Volumes**, haz clic en **Add Volume** y en el campo **Mount Path** coloca exactamente esto:

```text
/var/opt/mssql
```

Esta carpeta es donde residirán tus bases de datos (`data/`), archivos de registro (`log/`), backups (`backup/`) y secretos instalados en el contenedor.

---

## 📁 Estructura del Proyecto

```
.
├── Dockerfile                       # Imagen principal optimizada para Railway
└── scripts/
    ├── entrypoint.sh                # Maneja apagado seguro y dispara auto-reparación
    └── auto_repair.sql              # T-SQL para recuperar BDs en modo SUSPECT
```

---

## 🔌 Conexión Externa y Puertos (TCP Proxy)

Por defecto, los servicios de Railway son privados. Para conectar Power BI, SQL Server Management Studio (SSMS) o DBeaver desde tu computadora, **tienes que exponer el puerto**.

1. Ve a la pestaña **Settings** de tu servicio en Railway.
2. Baja hasta la sección **Networking** > **Public Networking**.
3. Haz clic en **Add TCP Proxy**.
4. En el campo que dice `Enter your application port`, escribe **`1433`** (el puerto por defecto de SQL Server) y dale a **Add Proxy**.
5. Railway te generará una URL (ej: `tcp.railway.app`) y un puerto público (ej: `50123`). Esos son el **Subdominio o IP** y el **Puerto** que usarás en Power BI o SSMS para conectarte.

---

## 🏥 Healthcheck

El contenedor verifica su estado con:

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" -C
```

| Parámetro | Valor | Razón |
|---|---|---|
| `interval` | 30s | Evita sobrecarga de chequeos continuos |
| `timeout` | 10s | Tiempo máximo de respuesta |
| `start-period` | 60s | Margen para el arranque en frío |
| `retries` | 3 | Reintentos antes de marcar como unhealthy |

---

## ⚡ Compatibilidad con Power Services (Power BI / Power Apps / Power Automate)

Este contenedor está optimizado para usarse como **fuente de datos de nube** desde Power Services:

| Configuración | Valor | Propósito |
|---|---|---|
| **Colación** | `Modern_Spanish_CI_AS` | Sin problemas de acentos en reportes en español |
| **LCID** | `3082` (Spanish Spain) | Mensajes de error en español en logs de Power BI |
| **TLS** | Habilitado (`-C` en sqlcmd) | Requerido por Power BI Gateway desde sept 2024 |
| **TCP Keep-alive** | 30s + 1s intervalo | Evita que Power BI corte la conexión por inactividad |
| **Límite de RAM** | 3500 MB | Prevents Railway from killing the container |

> **Nota TLS:** Power BI Gateway rechaza certificados autofirmados de SQL Server. En la cadena de conexión de Power BI usa `TrustServerCertificate=True` o configura `SqlTrustedServers` en el archivo de configuración del gateway.

---

## ⚙️ Variables de Entorno Internas (ya configuradas en el Dockerfile)

Estas variables ya están definidas en el `Dockerfile` y **no necesitan repetirse en Railway**:

| Variable | Valor | Descripción |
|---|---|---|
| `TZ` | `America/Lima` | Zona horaria del servidor |
| `MSSQL_LCID` | `3082` | Idioma del servidor (Español España) |
| `MSSQL_COLLATION` | `Modern_Spanish_CI_AS` | Colación compatible con español y Power BI |
| `MSSQL_AGENT_ENABLED` | `true` | Habilita el Agente SQL (Jobs) |
| `MSSQL_BACKUP_DIR` | `/var/opt/mssql/backup` | Directorio de backup para el Agente SQL |
| `MSSQL_MEMORY_LIMIT_MB` | `1500` | Límite de RAM *(ajustar según plan Railway)* |
| `MSSQL_ENABLE_COREDUMP` | `0` | Deshabilita volcados de memoria |
| `MSSQL_DUMP_ON_ERROR` | `0` | Evita archivos de error grandes |
| `MSSQL_TCP_KEEPALIVE` | `30000` | Keep-alive TCP inicial en ms |
| `MSSQL_TCP_KEEPALIVE_INTERVAL` | `1000` | Intervalo entre retransmisiones keep-alive en ms |

---

## 🐛 Solución de Problemas

### Base de datos marcada como "Suspect" (Sospechosa)

Si Railway sufre un apagón físico severo y una transacción queda a medias, el archivo `.mdf` puede corromperse y SQL Server pondrá la base de datos en estado `SUSPECT`.
**Solución automática:** No tienes que hacer nada. El script `entrypoint.sh` revisa el estado de todas las BDs en cada arranque. Si detecta una BD sospechosa, ejecutará `auto_repair.sql` que realiza un `DBCC CHECKDB` de emergencia para intentar recuperar la base de datos y ponerla online de nuevo.

### Error de permisos en volumen

Railway despliega los contenedores con un usuario genérico, pero SQL Server requiere ejecutarse como el usuario `mssql` (UID 10001). El Dockerfile ya contiene las instrucciones `mkdir -p` y `chown -R 10001:0` para los directorios críticos (`data`, `log`, `secrets`, `backup`) durante el build. Si aún tienes problemas, verifica que no hayas sobrescrito el `USER` en la configuración de Railway.

### Healthcheck falla al inicio

Es normal que Railway marque el contenedor como *unhealthy* durante los primeros 60 segundos mientras SQL Server inicializa. Si persiste después de ese tiempo, revisa los logs del contenedor.

### Ruta de `sqlcmd` no encontrada

En algunas versiones de la imagen, `sqlcmd` puede estar en `/opt/mssql-tools18/bin/sqlcmd`. Verificar con:

```bash
docker exec <container_id> find /opt -name sqlcmd
```

### Conexión desde SSMS / Power BI cae

Verificar que `MSSQL_TCP_KEEPALIVE=30000` esté activo. Si el problema persiste, configura también el keep-alive en el cliente de conexión.

---

## 🔗 Referencias

- [Documentación oficial SQL Server en Docker](https://learn.microsoft.com/es-es/sql/linux/sql-server-linux-docker-container-deployment)
- [Railway.app — Documentación de servicios](https://docs.railway.app)
- [Política de contraseñas SQL Server](https://learn.microsoft.com/es-es/sql/relational-databases/security/password-policy)
