# 🗄️ SQL Server 2022 en Railway

**SQL Server 2022 listo para producción, con backups automáticos, apagado seguro y recuperación ante fallos. Desplegado en 10 minutos.**

La mayoría de las imágenes de SQL Server para contenedores te dejan a mitad de camino: arrancan, pero no respaldan nada, se apagan de golpe y "reparan" bases corruptas borrando datos sin avisar. Esta plantilla resuelve las tres cosas.

---

## ✨ Qué la diferencia

**🔐 Backups diarios y verificados**
Respalda todas tus bases comprimidas, **verifica cada archivo** con `RESTORE VERIFYONLY`, y lo sube a Cloudflare R2. Solo borra la copia local cuando la subida se confirmó. Con retención automática configurable.

**🛡️ Reparación que no destruye datos**
Si una base queda en estado `SUSPECT`, intenta recuperarla en tres niveles — todos no destructivos. La opción que borra páginas corruptas existe, pero **requiere que tú la autorices con una variable**. Nunca se ejecuta sola.

**⚡ Apagado limpio de verdad**
Al detener el contenedor ejecuta `SHUTDOWN` con checkpoint en cada base, no `SHUTDOWN WITH NOWAIT`. La diferencia importa: el modo rápido obliga a hacer *crash recovery* en cada arranque.

**💰 Apaga la base cuando no la usas**
Modo suspensión integrado: con un cron gratuito puedes apagarla de noche y bajar la factura a la mitad. El contenedor queda en menos de 1 MB de RAM.

**🏷️ Anclada a una imagen que funciona**
Usa `2022-CU23-ubuntu-20.04` a propósito. El tag `2022-latest` pasó a Ubuntu 22.04 (sqlpal package6), que **provoca un Stack Overflow con el almacenamiento de Railway** por un bug de I/O síncrono. Este detalle es la diferencia entre una base estable y uno que cae sin explicación.

**🧹 El disco no se llena solo**
Purga automática de logs, trazas y backups antiguos. Sin esto, un volumen de contenedor crece hasta romperse.

---

## 🌍 Deploy and Host

### About Hosting

Railway construye la imagen directamente desde el `Dockerfile` del repositorio en cada `push`, y monta un volumen persistente que sobrevive a los despliegues. El servicio queda en la red privada del proyecto, accesible solo por tus otros servicios, salvo que expongas explícitamente un proxy TCP.

Eso da tres cosas que un servidor tradicional no: aprovisionamiento reproducible, aislamiento del almacenamiento respecto al ciclo de vida del contenedor, y despliegues sin downtime manual.

### Why Deploy

**Control total del motor.** Tienes acceso `sa`, Agente SQL con Jobs, linked servers y configuración a nivel de sistema — cosas que los servicios gestionados como Azure SQL no permiten.

**Costo predecible.** Con el apagado programado incluido, pagas solo las horas que la base realmente trabaja.

**Sin dependencia de proveedor.** Al ser una imagen Docker estándar, migrar a Kubernetes u otro proveedor es mover el volumen y el contenedor.

### Common Use Cases

- **Business Intelligence** — origen de datos para Power BI, con colación en español y keep-alive configurado para conexiones largas.
- **Backend de aplicaciones** — capa de persistencia para APIs en Node.js, .NET o Next.js.
- **Staging y QA** — réplicas de producción para validar cambios antes de desplegarlos.
- **Consultoría** — entornos aislados por cliente, sin arquitecturas cloud complejas.

### Dependencies for

#### Deployment Dependencies

- **Cuenta de Railway con plan de pago.** SQL Server 2022 necesita ~2 GB de RAM; el plan gratuito no alcanza y el contenedor se reinicia en bucle.
- **Un volumen persistente.** Sin él pierdes las bases en cada despliegue. Se configura en un paso.
- **Cliente SQL** — SSMS, Azure Data Studio o DBeaver para conectarte.
- **Cuenta de Cloudflare R2** *(opcional)* — solo si quieres los backups automáticos fuera del volumen.

---

## 🚀 Configuración en 3 pasos

### 1. Contraseña de `sa`

Es la única variable obligatoria. **Debe** tener mínimo 8 caracteres, con mayúscula, minúscula, número y símbolo — si no, SQL Server no arranca.

✅ `MiClave@2024!` · `Peru#Lima2025`
❌ `password` · `12345678` · `Clave123`

### 2. Volumen persistente ⚠️

**Sin esto pierdes todas tus bases en cada actualización.**

**Settings → Volumes → Add Volume**, y en **Mount Path** exactamente:

```text
/var/opt/mssql
```

Empieza con 10 GB. Railway cobra el tamaño **reservado**, no el usado.

### 3. Abrir el puerto (si te conectas desde fuera)

**Settings → Networking → Add TCP Proxy → puerto `1433`**

Railway te devuelve un host y un puerto públicos. En SSMS se escriben separados por **coma**: `host,puerto`.

> Si tu aplicación vive en el mismo proyecto de Railway, no abras el puerto — usa la red privada. Un SQL Server con `sa` expuesto a internet es de los objetivos más escaneados que existen.

---

## ⚙️ Variables

### Obligatoria

| Variable | Ejemplo |
|---|---|
| `MSSQL_SA_PASSWORD` | `MiClave@2024!` |

### Ajustables

| Variable | Por defecto | Qué hace |
|---|---|---|
| `MSSQL_MEMORY_LIMIT_MB` | `3500` | RAM del motor. **Ponlo en ~70% de la RAM de tu contenedor.** |
| `TZ` | `America/Lima` | Zona horaria |
| `MSSQL_PID` | `Developer` | Edición — ver aviso de licencia abajo |
| `MSSQL_SUSPEND` | `false` | `true` deja la base dormida para ahorrar |
| `MSSQL_SHUTDOWN_TIMEOUT` | `20` | Segundos de espera al apagar antes de forzar |

### Backups a R2 (opcional)

Si las omites, el backup se hace igual pero se queda en el volumen.

| Variable | Ejemplo |
|---|---|
| `R2_BUCKET` | `mis-backups-sql` |
| `RCLONE_CONFIG_R2_TYPE` | `s3` |
| `RCLONE_CONFIG_R2_PROVIDER` | `Cloudflare` |
| `RCLONE_CONFIG_R2_REGION` | `auto` |
| `RCLONE_CONFIG_R2_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| `RCLONE_CONFIG_R2_ACCESS_KEY_ID` | *(token de R2)* |
| `RCLONE_CONFIG_R2_SECRET_ACCESS_KEY` | *(token de R2)* |
| `BACKUP_HOUR` / `BACKUP_MINUTE` | `23` / `40` |
| `BACKUP_RETENTION_DAYS` | `30` |

### Ya configuradas en la imagen

`ACCEPT_EULA`, `MSSQL_LCID` (3082), `MSSQL_COLLATION` (`Modern_Spanish_CI_AS`), `MSSQL_AGENT_ENABLED`, las rutas de datos/log/backup/secretos, `MSSQL_ENABLE_COREDUMP`, `MSSQL_DUMP_ON_ERROR` y el keep-alive TCP. No hace falta repetirlas.

---

## ⚠️ Aviso de licencia

Esta plantilla usa la edición **Developer**: gratuita, con todas las funciones de Enterprise, pero **Microsoft solo permite usarla para desarrollo y pruebas.**

Si vas a guardar datos reales de clientes, cambia `MSSQL_PID`:

| Valor | Costo | Límites |
|---|---|---|
| `Developer` | Gratis | Solo desarrollo y pruebas |
| `Express` | Gratis | 10 GB por base, 1.4 GB de RAM |
| `Standard` | Licencia de pago | Sin límites prácticos |

No es una sugerencia técnica, es una obligación legal.

---

## ⚡ Compatibilidad con Power BI

| Configuración | Valor | Para qué |
|---|---|---|
| Colación | `Modern_Spanish_CI_AS` | Acentos correctos en reportes |
| LCID | `3082` | Mensajes del servidor en español |
| TLS | Habilitado | Requerido por Power BI Gateway |
| Keep-alive TCP | 30 s + 1 s | Evita cortes por inactividad |

En la cadena de conexión usa `TrustServerCertificate=True` — Power BI Gateway rechaza certificados autofirmados.

> 💡 **Configura la actualización como incremental.** Un refresco completo diario sobre una base de varios GB mueve muchísimos datos sin necesidad y encarece la factura.

---

## 🏥 Qué pasa si algo se rompe

### Base marcada como `SUSPECT`

El contenedor intenta recuperarla al arrancar, en tres niveles seguros:

| # | Acción | ¿Pierde datos? |
|---|---|---|
| 1 | `SET ONLINE` | ❌ No |
| 2 | `CHECKDB` de diagnóstico (solo lectura) | ❌ No |
| 3 | `REPAIR_REBUILD` | ❌ No |

En Railway, la causa más común de `SUSPECT` **no es corrupción real** sino que el volumen montó tarde o con permisos incorrectos — y el nivel 1 lo resuelve sin tocar una sola página.

Si los tres fallan, **se detiene y te avisa en los logs**. La reparación destructiva (`REPAIR_ALLOW_DATA_LOSS`) solo corre si creas `MSSQL_ALLOW_DATA_LOSS_REPAIR=true`, y aun entonces hace una copia forense antes de destruir nada.

### Problemas frecuentes

| Síntoma | Causa habitual |
|---|---|
| Se reinicia en bucle | Contraseña sin símbolo/mayúscula, o `MSSQL_MEMORY_LIMIT_MB` mayor que la RAM del plan |
| Perdí las bases al actualizar | Falta el volumen, o el Mount Path no es exacto |
| SSMS no conecta | Usaste `host:puerto` en vez de `host,puerto`, o falta *Trust server certificate* |
| Unhealthy al inicio | Normal los primeros 60 s |
| El disco se llena | Bases en recovery `FULL` sin backups de log — pásalas a `SIMPLE` |

---

## 📁 Qué hay dentro

```text
.
├── Dockerfile                          # Imagen anclada a 2022-CU23-ubuntu-20.04
└── scripts/
    ├── entrypoint.sh                   # Apagado limpio, reparación, tareas de fondo
    ├── auto_repair.sql                 # Escalera de reparación NO destructiva
    ├── auto_repair_dataloss.sql        # Reparación destructiva (tras variable explícita)
    ├── backup_to_r2.sh                 # Backup diario comprimido y verificado
    └── clean_old_logs.sh               # Purga de logs y backups antiguos
```

---

## 🔗 Enlaces

- 📖 **[Documentación completa en GitHub](https://github.com/Kennethguerra3/SqlServer2022Docker)** — guía paso a paso, configuración de backups, apagado programado y restauración
- 🧪 **[Versión SQL Server 2025](https://github.com/Kennethguerra3/SqlServer2025Docker)** — solo para entornos de prueba
- [SQL Server en Docker — Microsoft](https://learn.microsoft.com/es-es/sql/linux/sql-server-linux-docker-container-deployment)
- [Railway — documentación](https://docs.railway.app)
