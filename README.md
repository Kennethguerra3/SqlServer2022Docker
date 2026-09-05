# 🗄️ SQL Server 2022 en Railway (Optimizado)

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/sql-server-2022-en-railway-optimizado?referralCode=DFuuA2&utm_medium=integration&utm_source=template&utm_campaign=generic)

Configuración Docker lista para producción para desplegar **SQL Server 2022** en [Railway.app](https://railway.app), con apagado limpio, auto-reparación no destructiva, backups automáticos a Cloudflare R2 y control de costos mediante encendido/apagado programado.

---

## 🌍 Deploy and Host

El despliegue de bases de datos relacionales en entornos contenerizados requiere una estrategia que priorice la persistencia de datos y la disponibilidad. Esta configuración está diseñada para ser desplegada mediante un flujo de Integración Continua (CI) directamente desde un repositorio de Git hacia un entorno de Plataforma como Servicio (PaaS), garantizando paridad entre el entorno de desarrollo local y producción.

### About Hosting

Railway es una plataforma de alojamiento en la nube que simplifica el despliegue de aplicaciones y bases de datos a través de contenedores Docker. Para este motor de base de datos, Railway ofrece ventajas arquitectónicas clave:

* **Aprovisionamiento Declarativo:** El entorno se construye de forma predecible usando nuestro `Dockerfile` personalizado, eliminando el problema de "en mi máquina sí funciona".
* **Gestión de Volúmenes:** Permite aislar el almacenamiento físico (archivos `.mdf`, `.ldf` y backups) del ciclo de vida efímero del contenedor, asegurando que las actualizaciones de la imagen no destruyan los datos.
* **Redes Privadas por Defecto:** La base de datos se despliega en una red interna segura, accesible solo por otros servicios dentro del mismo proyecto, a menos que expongas explícitamente un proxy TCP.

### Why Deploy

Desplegar SQL Server 2022 bajo este modelo contenerizado en lugar de optar por servicios gestionados tradicionales responde a decisiones de control y costos:

1. **Reducción de Costos Operativos:** Con el encendido/apagado programado que documentamos más abajo, pagas solo por las horas que realmente usas la base.
2. **Control Total del Motor:** Tienes acceso `sa`, jobs del Agente SQL, linked servers y dependencias a nivel de sistema operativo.
3. **Portabilidad:** Al estar empaquetado en Docker, migrar a Kubernetes u otro proveedor es mover el volumen y el contenedor.

### Common Use Cases

* **Business Intelligence:** Origen de datos para Power BI, con colación en español y keep-alive configurado para conexiones de larga duración.
* **Backends Full-Stack:** Capa de persistencia para APIs en Node.js, .NET o Next.js.
* **Entornos de Staging y QA:** Réplicas de producción para validar cambios antes de desplegarlos.
* **Consultoría y PoCs:** Levantar entornos aislados por cliente sin arquitecturas cloud complejas.

### Dependencies for

#### Deployment Dependencies

* **Cuenta de Railway (Plan de Pago):** SQL Server 2022 necesita ~1.5–2 GB de RAM para operar de forma estable.
* **Repositorio Git:** Railway construye la imagen en cada `push`.
* **Herramienta de Administración:** SSMS, Azure Data Studio o DBeaver para conectarte al proxy TCP.
* **Cuenta de Cloudflare R2** *(opcional)*: solo si quieres backups automáticos fuera del volumen.

---

## ⚠️ Antes de usar esto en producción

Este template usa **`MSSQL_PID=Developer`**. La edición Developer es funcionalmente idéntica a Enterprise, pero **su licencia la limita a desarrollo y pruebas** — no está permitida en producción.

Si vas a servir datos reales de clientes, cambia `MSSQL_PID` a una edición con licencia (`Standard`, `Enterprise`) o a `Express`, que es gratuita para producción pero limita cada base a 10 GB y el motor a 1.4 GB de RAM.

---

## 🚀 Características

| Característica | Detalle |
|---|---|
| **Imagen base** | `mcr.microsoft.com/mssql/server:2022-CU23-ubuntu-20.04` (Ubuntu 20.04 / sqlpal package4) |
| **Edición** | Developer — *ver aviso de licencia arriba* |
| **Agente SQL** | Habilitado — soporta Jobs y tareas programadas |
| **Zona horaria** | `America/Lima` (ajustable) |
| **Apagado limpio** | `SHUTDOWN` con checkpoint, con fallback por timeout |
| **Auto-reparación** | Escalera **no destructiva**; la opción que borra datos requiere autorización explícita |
| **Backups** | Diarios a Cloudflare R2, comprimidos y verificados |
| **Limpieza de disco** | Purga automática de logs y backups antiguos |
| **Memoria** | Fuente única de verdad en `MSSQL_MEMORY_LIMIT_MB` |
| **Anti-crash** | Core dumps y telemetría deshabilitados |
| **Seguridad** | Ejecuta como `mssql` (UID 10001), preservando `PR_SET_DUMPABLE` |

---

## 🏷️ Por qué un tag específico y no `2022-latest`

El tag `2022-latest` fue actualizado a **Ubuntu 22.04** (sqlpal package6), que provoca un **Stack Overflow** con el almacenamiento de Railway por un bug de I/O síncrono.

El tag `2022-CU23-ubuntu-20.04` usa **Ubuntu 20.04** (sqlpal package4) y funciona correctamente. CU23 es además la actualización acumulativa más reciente.

> El Dockerfile reinstala `ca-certificates` durante el build. El bundle de CAs de Ubuntu 20.04 queda congelado en la fecha de publicación del tag, y uno desactualizado hace fallar los handshakes TLS hacia servicios externos — SQL Server lo reporta como un opaco `Error de sistema operativo 1359`.

---

## 🛠️ Variables de Entorno

### Obligatoria

| Variable | Ejemplo | Descripción |
|---|---|---|
| `MSSQL_SA_PASSWORD` | `MiClave@2024!` | Contraseña del usuario `sa` |

> Mínimo 8 caracteres, con mayúscula, minúscula, número y símbolo.

### Control de apagado y reparación

| Variable | Por defecto | Descripción |
|---|---|---|
| `MSSQL_SUSPEND` | *(vacío)* | `true` deja el contenedor dormido sin arrancar SQL Server. Ver sección de costos. |
| `MSSQL_SHUTDOWN_TIMEOUT` | `20` | Segundos que espera el apagado limpio antes de forzar `WITH NOWAIT`. |
| `MSSQL_ALLOW_DATA_LOSS_REPAIR` | *(vacío)* | `true` habilita `REPAIR_ALLOW_DATA_LOSS`. **Déjala apagada.** Ver sección de auto-reparación. |
| `MSSQL_MEMORY_LIMIT_MB` | `3500` | Límite de memoria del motor. Ajústalo a ~70% de la RAM del contenedor. |

### Backups a Cloudflare R2 (opcional)

Si no las defines, el backup diario se hace igual pero se queda en el volumen.

| Variable | Ejemplo |
|---|---|
| `R2_BUCKET` | `mis-backups-sql` |
| `RCLONE_CONFIG_R2_TYPE` | `s3` |
| `RCLONE_CONFIG_R2_PROVIDER` | `Cloudflare` |
| `RCLONE_CONFIG_R2_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| `RCLONE_CONFIG_R2_REGION` | `auto` |
| `RCLONE_CONFIG_R2_ACCESS_KEY_ID` | *(token de R2)* |
| `RCLONE_CONFIG_R2_SECRET_ACCESS_KEY` | *(token de R2)* |
| `BACKUP_HOUR` | `23` |
| `BACKUP_MINUTE` | `40` |
| `BACKUP_RETENTION_DAYS` | `30` |

### Ya definidas en el Dockerfile

No hace falta repetirlas en Railway: `ACCEPT_EULA`, `MSSQL_PID`, `TZ`, `MSSQL_LCID`, `MSSQL_COLLATION`, `MSSQL_AGENT_ENABLED`, `MSSQL_DATA_DIR`, `MSSQL_LOG_DIR`, `MSSQL_BACKUP_DIR`, `MSSQL_SECRETS_DIR`, `MSSQL_ENABLE_COREDUMP`, `MSSQL_DUMP_ON_ERROR`, `MSSQL_TCP_KEEPALIVE`, `MSSQL_TCP_KEEPALIVE_INTERVAL`.

---

## 💾 Volumen Persistente (Importante)

Sin volumen, **pierdes las bases en cada despliegue**. En Railway ve a **Volumes → Add Volume** y usa exactamente este Mount Path:

```text
/var/opt/mssql
```

Ahí viven `data/`, `log/`, `backup/` y `secrets/`.

> Railway factura el tamaño **aprovisionado** del volumen, no el usado. No lo sobredimensiones.

---

## 🔐 Backups automáticos a Cloudflare R2

Un contenedor sin backups es un accidente esperando ocurrir: el volumen puede corromperse, y una reparación de emergencia puede borrar datos. Este template respalda todas las bases de usuario cada día.

### Cómo funciona

Por cada base, en orden:

1. `BACKUP DATABASE ... WITH COMPRESSION` al volumen
2. `RESTORE VERIFYONLY` — un backup sin verificar es una suposición
3. Subida a R2 con `rclone`
4. **Borrado del archivo local solo si la subida confirmó**

Si cualquier paso falla, el archivo se conserva en el volumen y el fallo queda registrado en los logs. Nunca se borra algo que no llegó a destino.

Al final aplica retención en R2 según `BACKUP_RETENTION_DAYS`.

### Por qué rclone y no `BACKUP TO URL`

SQL Server 2022 soporta backup nativo a almacenamiento S3, pero **contra R2 falla** con `Error de sistema operativo 1359 (Error interno)`, sin más detalle, incluso con credenciales recién creadas y el comando más simple. El motor de backup funciona correctamente a disco.

Si en tu entorno el backup nativo sí funciona, puedes usarlo y eliminar `backup_to_r2.sh`.

### Crear el token de R2

En **R2 → Manage API Tokens → Create API Token**, con permiso **Object Read & Write** limitado a tu bucket. Cloudflare te muestra un **Access Key ID** y un **Secret Access Key**; ambos van en las variables de arriba.

> Un "Cloudflare API Token" del tipo bearer **no sirve** — necesitas credenciales S3.

### Restaurar

```sql
RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/backup/MiBase_20260905_2340.bak';

RESTORE DATABASE [MiBase_PRUEBA]
FROM DISK = '/var/opt/mssql/backup/MiBase_20260905_2340.bak'
WITH MOVE 'MiBase'     TO '/var/opt/mssql/data/MiBase_PRUEBA.mdf',
     MOVE 'MiBase_log' TO '/var/opt/mssql/data/MiBase_PRUEBA_log.ldf',
     RECOVERY;
```

**Prueba la restauración al menos una vez.** Un backup que nunca restauraste no es un backup.

---

## 🏥 Auto-reparación (no destructiva por defecto)

Si una base queda en estado `SUSPECT`, el contenedor intenta recuperarla al arrancar. La escalera está diseñada para que **no pueda perder datos**:

| Paso | Acción | ¿Pierde datos? |
|---|---|---|
| 1 | `SET ONLINE` | No |
| 2 | `DBCC CHECKDB` de diagnóstico (solo lectura) | No |
| 3 | `DBCC CHECKDB ... REPAIR_REBUILD` | No |
| 4 | `REPAIR_ALLOW_DATA_LOSS` | **Sí** — requiere autorización |

En Railway, la causa más frecuente de `SUSPECT` no es corrupción real sino que el volumen montó tarde o con permisos incorrectos. El paso 1 resuelve ese caso sin tocar una sola página.

Si los tres primeros pasos fallan, el script **se detiene** y lo reporta en los logs. Para autorizar el paso 4, define `MSSQL_ALLOW_DATA_LOSS_REPAIR=true` y redespliega. Ese script toma una copia forense (`COPY_ONLY` + `CONTINUE_AFTER_ERROR`) antes de destruir nada.

> Antes de recurrir al paso 4, considera restaurar desde un backup. Un backup de ayer casi siempre es mejor que una base reparada a la que le faltan filas que nadie sabe cuáles eran.

---

## ⏳ Optimización de Costos: Encendido y Apagado Automático

Puedes reducir la factura apagando la base fuera del horario de uso, con un servicio gratuito como [cron-job.org](https://cron-job.org) llamando a la API de Railway.

Al cambiar `MSSQL_SUSPEND`, Railway reinicia el contenedor y el `entrypoint.sh` bloquea el arranque de SQL Server, dejándolo en menos de 1 MB de RAM.

> **Nota:** el modo Serverless nativo de Railway **no sirve** para SQL Server. Detecta inactividad por paquetes salientes, y SQL Server nunca calla (NTP, Agente SQL, healthcheck). Nunca llegaría a dormirse.

### Configuración

1. **Obtén el token y los IDs.** Genera un API Token en los ajustes de tu cuenta de Railway. Los IDs están en la URL del servicio:
   `https://railway.app/project/<PROJECT_ID>/service/<SERVICE_ID>?environmentId=<ENVIRONMENT_ID>`

2. **Job de apagado.** URL `https://backboard.railway.app/graphql/v2`, método `POST`, headers `Authorization: Bearer TU_TOKEN` y `Content-Type: application/json`:

   ```json
   {
     "query": "mutation variableUpsert($input: VariableUpsertInput!) { variableUpsert(input: $input) }",
     "variables": {
       "input": {
         "projectId": "TU_PROJECT_ID",
         "environmentId": "TU_ENVIRONMENT_ID",
         "serviceId": "TU_SERVICE_ID",
         "name": "MSSQL_SUSPEND",
         "value": "true"
       }
     }
   }
   ```

3. **Job de encendido.** Idéntico, con `"value": "false"`.

### ⚠️ Coordina el backup con el apagado

El backup corre a `BACKUP_HOUR:BACKUP_MINUTE` (hora local del contenedor). **Si tu cron apaga la base antes de que termine, el backup se corta.** Deja al menos 30 minutos de margen entre el backup y el apagado.

Ejemplo coherente:

```text
20:45  enciende
23:00  tus jobs del Agente SQL
23:40  backup a R2
01:00  apaga
```

> **Sobre la seguridad del apagado:** el `entrypoint.sh` captura `SIGTERM` y ejecuta `SHUTDOWN` — con checkpoint en cada base — no `SHUTDOWN WITH NOWAIT`. La diferencia importa: `WITH NOWAIT` fuerza crash recovery en el siguiente arranque, y hacerlo dos veces al día es tentar a la suerte. Si el apagado limpio excede `MSSQL_SHUTDOWN_TIMEOUT`, cae al modo forzado como último recurso.

---

## 📁 Estructura del Proyecto

```text
.
├── Dockerfile                          # Imagen optimizada para Railway
└── scripts/
    ├── entrypoint.sh                   # Apagado limpio, reparación, lanza tareas de fondo
    ├── auto_repair.sql                 # Escalera de reparación NO destructiva
    ├── auto_repair_dataloss.sql        # Reparación destructiva (requiere variable)
    ├── backup_to_r2.sh                 # Backup diario comprimido y verificado
    └── clean_old_logs.sh               # Purga de logs y backups antiguos
```

---

## 🔌 Conexión Externa (TCP Proxy)

Los servicios de Railway son privados por defecto. Para conectar Power BI, SSMS o DBeaver:

1. **Settings → Networking → Public Networking → Add TCP Proxy**
2. Puerto de la aplicación: **`1433`**
3. Railway genera un host y un puerto público para tu cadena de conexión.

> **Seguridad:** un SQL Server con `sa` habilitado en un puerto público es de los objetivos más escaneados que existen. Si tus consumidores viven dentro de Railway, usa la red privada y no expongas el proxy. Si necesitas acceso externo, considera un túnel de Cloudflare en lugar del proxy abierto.

---

## 🏥 Healthcheck

```bash
/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -Q "SELECT 1" -C
```

| Parámetro | Valor | Razón |
|---|---|---|
| `interval` | 30s | Evita sobrecarga de chequeos |
| `timeout` | 10s | Tiempo máximo de respuesta |
| `start-period` | 60s | Margen para el arranque en frío |
| `retries` | 3 | Reintentos antes de marcar unhealthy |

---

## ⚡ Compatibilidad con Power BI

| Configuración | Valor | Propósito |
|---|---|---|
| **Colación** | `Modern_Spanish_CI_AS` | Sin problemas de acentos en reportes |
| **LCID** | `3082` | Mensajes del servidor en español |
| **TLS** | Habilitado | Requerido por Power BI Gateway desde sept 2024 |
| **TCP Keep-alive** | 30s + 1s | Evita cortes por inactividad |

> Power BI Gateway rechaza certificados autofirmados. Usa `TrustServerCertificate=True` en la cadena de conexión.

**Si usas actualización programada, configúrala como incremental.** Un refresco completo diario sobre una base de varios GB genera un volumen de transferencia desproporcionado.

---

## 🐛 Solución de Problemas

### Base marcada como `SUSPECT`

El contenedor intenta recuperarla sola en cada arranque con la escalera no destructiva. Revisa los logs: cada paso deja rastro con el prefijo `[auto_repair]`. Si los tres pasos seguros fallan, la base queda como está y tú decides entre restaurar un backup o autorizar la reparación destructiva.

### `Error de sistema operativo 1359` al hacer backup a URL

El conector S3 de SQL Server 2022 no funciona contra R2. Usa el `backup_to_r2.sh` incluido, que respalda a disco y sube con rclone.

### El backup se corta a la mitad

Tu cron de apagado está disparando antes de que termine. Ajusta `BACKUP_HOUR`/`BACKUP_MINUTE` o retrasa el apagado.

### El volumen crece sin control

Verifica en los logs que aparezca `Limpieza automática de logs iniciada`. Si tienes bases en recovery `FULL` sin backups de log, el archivo de log crece indefinidamente: o programas backups de log, o pasas esas bases a `SIMPLE`.

### Error de permisos en volumen

El Dockerfile hace `chown -R 10001:0` durante el build y el `entrypoint.sh` lo repite en runtime vía `sudo`. Verifica que no hayas sobrescrito `USER` en la configuración de Railway.

### Healthcheck falla al inicio

Es normal durante los primeros 60 segundos. Si persiste, revisa los logs del contenedor.

### La conexión desde SSMS o Power BI se cae

Verifica que `MSSQL_TCP_KEEPALIVE=30000` esté activo y configura también el keep-alive en el cliente.

---

## 🔗 Referencias

- [SQL Server en Docker — documentación oficial](https://learn.microsoft.com/es-es/sql/linux/sql-server-linux-docker-container-deployment)
- [Railway — documentación de servicios](https://docs.railway.app)
- [Railway — Serverless](https://docs.railway.com/deployments/serverless)
- [Cloudflare R2 — API S3](https://developers.cloudflare.com/r2/api/s3/api/)
- [DBCC CHECKDB — opciones de reparación](https://learn.microsoft.com/es-es/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql)
- [Política de contraseñas de SQL Server](https://learn.microsoft.com/es-es/sql/relational-databases/security/password-policy)
