# 🗄️ SQL Server 2022 en Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/sql-server-2022-en-railway-optimizado?referralCode=DFuuA2&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Una base de datos SQL Server 2022 completa, en la nube, en unos 10 minutos.**

No necesitas saber Docker ni Linux. Solo seguir los pasos de abajo en orden.

Incluye apagado seguro, recuperación automática ante fallos, backups diarios y una forma de apagar la base por las noches para pagar menos.

---

## 📖 Índice

1. [Antes de empezar](#-antes-de-empezar)
2. [Guía rápida: desplegar paso a paso](#-guía-rápida-desplegar-paso-a-paso)
3. [Cómo saber si funcionó](#-cómo-saber-si-funcionó)
4. [Conectarte desde SSMS o Power BI](#-conectarte-desde-ssms-o-power-bi)
5. [Backups automáticos (opcional pero muy recomendado)](#-backups-automáticos)
6. [Pagar menos: apagar la base por las noches](#-pagar-menos-apagar-la-base-por-las-noches)
7. [Tabla de variables](#-tabla-de-variables)
8. [Qué hace el contenedor cuando algo se rompe](#-qué-hace-el-contenedor-cuando-algo-se-rompe)
9. [Problemas comunes](#-problemas-comunes)
10. [Para desarrolladores](#-para-desarrolladores)

---

## 🚦 Antes de empezar

### Lo que necesitas

| Requisito | Por qué |
|---|---|
| Cuenta en [Railway](https://railway.app) **con plan de pago** | SQL Server necesita ~2 GB de RAM. El plan gratuito no alcanza y el contenedor se reinicia solo. |
| Una herramienta para conectarte | [SSMS](https://learn.microsoft.com/es-es/ssms/download-sql-server-management-studio-ssms) (gratis, Windows), [Azure Data Studio](https://learn.microsoft.com/es-es/azure-data-studio/download) o DBeaver |
| ~10 minutos | En serio, es rápido |

### ⚠️ Aviso importante sobre la licencia

Esta plantilla usa la edición **Developer** de SQL Server. Es gratuita y tiene todas las funciones de la edición Enterprise, **pero Microsoft solo permite usarla para desarrollo y pruebas — no para producción.**

Si vas a guardar datos reales de clientes o de tu empresa, tienes que cambiar la variable `MSSQL_PID`:

| Valor | Costo | Límites |
|---|---|---|
| `Developer` | Gratis | Solo desarrollo y pruebas |
| `Express` | Gratis | 10 GB por base, 1.4 GB de RAM |
| `Standard` | Requiere licencia de pago | Sin límites prácticos |

**No es una recomendación técnica, es una obligación legal.** Ignorarlo te expone a un problema de licenciamiento.

---

## 🚀 Guía rápida: desplegar paso a paso

### Paso 1 — Crear el servicio

Haz clic en el botón morado **Deploy on Railway** que está arriba de este documento.

Se abrirá Railway y te mostrará la plantilla. Haz clic en **Deploy**.

### Paso 2 — Poner la contraseña de `sa`

Railway te va a pedir **una sola variable**: `MSSQL_SA_PASSWORD`.

`sa` es el usuario administrador de SQL Server. Esta será su contraseña.

**La contraseña DEBE cumplir estas reglas** o SQL Server no arranca:

- Mínimo 8 caracteres
- Al menos una MAYÚSCULA
- Al menos una minúscula
- Al menos un número
- Al menos un símbolo (`@ # $ % ! * . -`)

✅ Ejemplos válidos: `MiClave@2024!`, `Peru#Lima2025`, `Xk9$mQz7Ab`

❌ Ejemplos inválidos: `password` (sin mayúscula ni número ni símbolo), `12345678` (solo números), `Clave123` (sin símbolo)

> 💡 Guarda esa contraseña en tu gestor de contraseñas **ahora**. La vas a necesitar en el Paso 5 y no se puede recuperar después.

### Paso 3 — Añadir el volumen ⚠️ NO TE SALTES ESTE PASO

**Si no haces esto, pierdes todas tus bases de datos cada vez que actualices el servicio.**

Un "volumen" es un disco que sobrevive a los reinicios. Sin él, todo lo que guardes desaparece.

1. Entra a tu servicio en Railway
2. Ve a la pestaña **Settings**
3. Busca la sección **Volumes**
4. Haz clic en **Add Volume**
5. En el campo **Mount Path** escribe exactamente esto, sin espacios:

```text
/var/opt/mssql
```

6. Guarda

> ⚠️ Tiene que ser **exactamente** `/var/opt/mssql`. Si escribes `/var/opt/mssql/` con barra al final, o `/data`, o cualquier otra cosa, no funciona.

**¿Qué tamaño le pongo?** Empieza con 10 GB. Railway te cobra por el tamaño que reservas, no por el que usas, así que no pongas 100 GB "por si acaso". Puedes agrandarlo después.

### Paso 4 — Esperar a que arranque

Railway va a construir la imagen y arrancar el contenedor. **La primera vez tarda entre 5 y 10 minutos** porque descarga SQL Server completo.

Ve a la pestaña **Deployments** y espera a que el estado pase de `Building` a `Success`.

Es **normal** que durante el primer minuto Railway muestre el servicio como *unhealthy*. SQL Server tarda en inicializarse. Si sigue así después de 3 minutos, ve a [Problemas comunes](#-problemas-comunes).

### Paso 5 — Abrir el puerto para conectarte desde tu PC

Por defecto la base **solo es visible desde dentro de Railway**. Para conectarte desde tu computadora hay que abrir un puerto.

1. En tu servicio, ve a **Settings**
2. Baja a la sección **Networking** → **Public Networking**
3. Haz clic en **Add TCP Proxy**
4. Donde dice *Enter your application port* escribe: **`1433`**
5. Clic en **Add Proxy**

Railway te devuelve dos datos, algo así:

```text
Host:   metro.proxy.rlwy.net
Puerto: 38350
```

**Anótalos.** Son tu dirección de conexión.

> 🔒 **Advertencia de seguridad:** al abrir este puerto, tu base queda accesible desde todo internet. Los bots escanean constantemente buscando SQL Servers con usuario `sa`. Por eso el Paso 2 insistía en una contraseña fuerte.
>
> Si tu aplicación vive dentro del mismo proyecto de Railway, **no abras el puerto** — usa la red privada y ya. Solo ábrelo si necesitas conectarte desde fuera (Power BI, SSMS desde tu casa, etc.).

---

## ✅ Cómo saber si funcionó

Ve a la pestaña **Deploy Logs** de tu servicio. Deberías ver, más o menos en este orden:

```text
Arrancando contenedor de SQL Server...
Iniciando como mssql (UID 10001): Configurando permisos del volumen...
Permisos configurados. Iniciando SQL Server (Silent Mode)...
Ejecutando auto-reparación no destructiva...
[auto_repair] === Revision de estado de bases de datos ===
[auto_repair] Todas las bases de usuario estan ONLINE. Nada que hacer.
[auto_repair] === Revision terminada ===
Motor de base de datos listo.
Limpieza automática de logs iniciada (cada 24h).
Backup diario a R2 programado (23:40 hora local).
[backup-r2] Proximo backup en 4h 12m.
```

**Si ves eso, ya está funcionando.** Pasa al siguiente apartado.

Si ves otra cosa, busca tu mensaje en [Problemas comunes](#-problemas-comunes).

---

## 🔌 Conectarte desde SSMS o Power BI

### Desde SSMS (SQL Server Management Studio)

Abre SSMS y en la ventana de conexión pon:

| Campo | Qué escribir |
|---|---|
| **Server name** | `metro.proxy.rlwy.net,38350` ← *tu host, una **coma**, tu puerto* |
| **Authentication** | `SQL Server Authentication` |
| **Login** | `sa` |
| **Password** | La contraseña del Paso 2 |

Luego haz clic en **Options** → pestaña **Connection Properties** → marca la casilla **Trust server certificate**.

> ⚠️ El error más común aquí: usar **dos puntos** en vez de **coma** entre el host y el puerto. SSMS usa coma: `host,puerto`. No `host:puerto`.

### Desde Power BI

| Campo | Qué escribir |
|---|---|
| **Servidor** | `metro.proxy.rlwy.net,38350` |
| **Base de datos** | *(déjalo vacío o pon el nombre de tu base)* |
| **Modo** | Import o DirectQuery, según tu caso |

En **Opciones avanzadas** o en la cadena de conexión, agrega:

```text
TrustServerCertificate=True
```

Sin eso, Power BI Gateway rechaza la conexión porque SQL Server usa un certificado autofirmado.

> 💡 **Si usas actualización programada en Power BI, configúrala como incremental.** Un refresco completo diario sobre una base de varios GB mueve muchísimos datos sin necesidad y encarece tu factura.

---

## 🔐 Backups automáticos

**Esto es opcional, pero si guardas algo que te importe, hazlo.**

Sin backups, si el volumen se corrompe o borras algo por error, no hay vuelta atrás.

### Qué hace el sistema de backups

Todos los días a la hora que configures, el contenedor:

1. Respalda cada base de datos, comprimida (ocupa ~5 veces menos)
2. **Verifica** que el archivo de backup sea válido
3. Lo sube a Cloudflare R2
4. Borra la copia local **solo si la subida se confirmó**
5. Elimina de R2 los backups más viejos que los días que configures

Si cualquier paso falla, el archivo se queda en el volumen y el error aparece en los logs. **Nunca borra algo que no llegó a destino.**

### Configurarlo, paso a paso

**A) Crear la cuenta y el bucket en Cloudflare**

1. Entra a [dash.cloudflare.com](https://dash.cloudflare.com) y crea una cuenta si no tienes
2. En el menú lateral busca **R2 Object Storage**
3. Clic en **Create bucket**
4. Ponle un nombre, por ejemplo `mis-backups-sql`
5. Deja la ubicación en **Automático** y clic en **Create bucket**

**B) Copiar tu Account ID**

Estando en la sección R2, mira la **barra de direcciones de tu navegador**. Se ve así:

```text
dash.cloudflare.com/5a439b04d2defeef988bd221415bf1b4/r2/overview
                    └──────── esto es tu Account ID ────────┘
```

Es esa cadena larga de letras y números. Cópiala.

**C) Crear el token de acceso**

1. En R2, busca el botón **Manage API Tokens** (arriba a la derecha)
2. Clic en **Create API Token**
3. En **Permissions** elige **Object Read & Write**
4. En **Specify bucket(s)** elige **solo tu bucket** (no "todos")
5. Clic en **Create API Token**

Cloudflare te muestra **dos valores**:

```text
Access Key ID:      abc123... (unos 32 caracteres)
Secret Access Key:  xyz789... (unos 64 caracteres)
```

> ⚠️ **Cópialos ahora mismo a un lugar seguro.** El Secret Access Key **solo se muestra una vez**. Si cierras la ventana, tienes que crear un token nuevo.

> ⚠️ **No confundas esto con un "Cloudflare API Token"** de los que empiezan con formato de bearer. Necesitas específicamente estas dos llaves de R2.

**D) Poner las variables en Railway**

En tu servicio → pestaña **Variables** → botón **New Variable**. Añade estas siete:

| Nombre de la variable | Valor |
|---|---|
| `R2_BUCKET` | `mis-backups-sql` *(el nombre que le pusiste)* |
| `RCLONE_CONFIG_R2_TYPE` | `s3` |
| `RCLONE_CONFIG_R2_PROVIDER` | `Cloudflare` |
| `RCLONE_CONFIG_R2_REGION` | `auto` |
| `RCLONE_CONFIG_R2_ENDPOINT` | `https://TU_ACCOUNT_ID.r2.cloudflarestorage.com` |
| `RCLONE_CONFIG_R2_ACCESS_KEY_ID` | *el Access Key ID del paso C* |
| `RCLONE_CONFIG_R2_SECRET_ACCESS_KEY` | *el Secret Access Key del paso C* |

En `RCLONE_CONFIG_R2_ENDPOINT` reemplaza `TU_ACCOUNT_ID` por lo que copiaste en el paso B. Queda algo así:

```text
https://5a439b04d2defeef988bd221415bf1b4.r2.cloudflarestorage.com
```

**E) Elegir la hora**

| Variable | Por defecto | Qué es |
|---|---|---|
| `BACKUP_HOUR` | `23` | Hora (formato 24h, hora local del contenedor) |
| `BACKUP_MINUTE` | `40` | Minuto |
| `BACKUP_RETENTION_DAYS` | `30` | Días que se guardan los backups antes de borrarse |

Con los valores por defecto, el backup corre todos los días a las **23:40**.

**F) Comprobar que funciona**

Al día siguiente, mira los **Deploy Logs**. Deberías ver:

```text
[backup-r2] === Inicio del ciclo de backup ===
[backup-r2]   MiBase: respaldando...
[backup-r2]   MiBase: verificado (245M).
[backup-r2]   MiBase: subido a R2.
[backup-r2] === Fin. OK=1 FALLOS=0 ===
```

Y en el bucket de Cloudflare deberías ver una carpeta por cada base con el archivo `.bak` dentro.

**Si NO pusiste las credenciales**, verás esto — y no es un error, es un aviso:

```text
[backup-r2] AVISO: faltan credenciales de R2. Los backups se haran SOLO en local.
```

El backup se hace igual, pero se queda dentro del volumen. Sirve para recuperar de un error humano, pero no te salva si el volumen se pierde.

### Cómo restaurar un backup

**Hazlo una vez ahora, con una base de prueba.** Un backup que nunca probaste restaurar no es un backup, es una suposición.

Desde SSMS, conectado a tu servidor:

```sql
-- 1. Ver qué archivos contiene el backup
RESTORE FILELISTONLY
FROM DISK = '/var/opt/mssql/backup/MiBase_20260905_2340.bak';
```

Eso te devuelve dos nombres lógicos, normalmente `MiBase` y `MiBase_log`. Úsalos aquí:

```sql
-- 2. Restaurar con OTRO nombre, para no pisar la base original
RESTORE DATABASE [MiBase_PRUEBA]
FROM DISK = '/var/opt/mssql/backup/MiBase_20260905_2340.bak'
WITH MOVE 'MiBase'     TO '/var/opt/mssql/data/MiBase_PRUEBA.mdf',
     MOVE 'MiBase_log' TO '/var/opt/mssql/data/MiBase_PRUEBA_log.ldf',
     RECOVERY;
```

```sql
-- 3. Comprobar que tiene datos
SELECT COUNT(*) FROM MiBase_PRUEBA.sys.tables;

-- 4. Borrar la prueba para no ocupar espacio
DROP DATABASE [MiBase_PRUEBA];
```

Si el backup está en R2 y no en el volumen, primero descárgalo desde el panel de Cloudflare y súbelo al servidor, o usa `rclone copy` desde el contenedor.

---

## ⏳ Pagar menos: apagar la base por las noches

Railway te cobra por las horas que el contenedor está encendido. Si tu base solo se usa de día, apagarla de noche puede reducir la factura a la mitad o menos.

Esta plantilla trae un "modo dormido": cuando la variable `MSSQL_SUSPEND` vale `true`, el contenedor arranca pero **no inicia SQL Server**, quedándose en menos de 1 MB de RAM.

> ❌ **El modo Serverless de Railway NO sirve para esto.** Railway detecta inactividad mirando si el contenedor envía paquetes de red, y SQL Server nunca deja de enviarlos (sincronización de hora, Agente SQL, healthcheck). Nunca llegaría a dormirse. Por eso hay que apagarlo desde fuera.

### Configurarlo con cron-job.org (gratis)

**A) Conseguir los datos que necesitas**

1. **Token de Railway:** entra a tu cuenta de Railway → **Account Settings** → **Tokens** → crea uno nuevo y cópialo.

2. **Los tres IDs:** entra a tu servicio de SQL Server y mira la barra de direcciones:

```text
railway.app/project/AAAA-1111/service/BBBB-2222?environmentId=CCCC-3333
                    └ProjectID┘        └ServiceID┘             └EnvironmentID┘
```

**B) Crear el trabajo de APAGADO**

1. Entra a [cron-job.org](https://console.cron-job.org) y crea una cuenta
2. Clic en **Create cronjob**
3. En la pestaña **COMMON**:
   - **Title:** `Apagar SQL Server`
   - **URL:** `https://backboard.railway.app/graphql/v2`
   - **Schedule:** elige la hora a la que quieres apagar (ej. 01:00)
4. En la pestaña **ADVANCED**:
   - **Request method:** `POST`
   - En **Headers**, añade dos:
     - Nombre `Authorization`, valor `Bearer TU_TOKEN` ← *la palabra `Bearer`, un espacio, y luego el token*
     - Nombre `Content-Type`, valor `application/json`
   - En **Request body** pega esto, reemplazando los tres IDs:

```json
{
  "query": "mutation variableUpsert($input: VariableUpsertInput!) { variableUpsert(input: $input) }",
  "variables": {
    "input": {
      "projectId": "AAAA-1111",
      "environmentId": "CCCC-3333",
      "serviceId": "BBBB-2222",
      "name": "MSSQL_SUSPEND",
      "value": "true"
    }
  }
}
```

5. Guarda

**C) Crear el trabajo de ENCENDIDO**

Repite todo igual, pero:
- **Title:** `Encender SQL Server`
- **Schedule:** la hora de encendido (ej. 08:00)
- En el JSON, cambia `"value": "true"` por **`"value": "false"`**

### ⚠️ Coordina el backup con el apagado

Si el backup corre a las 23:40 pero tu cron apaga la base a las 23:45, **el backup se corta a la mitad**.

Deja al menos **30 minutos** entre el backup y el apagado. Ejemplo que funciona bien:

```text
08:00  enciende
23:40  backup automático
01:00  apaga            ← 1h20 de margen, de sobra
```

---

## 📋 Tabla de variables

### Las que sí o sí tienes que poner

| Variable | Ejemplo |
|---|---|
| `MSSQL_SA_PASSWORD` | `MiClave@2024!` |

### Las que quizás quieras ajustar

| Variable | Por defecto | Qué hace |
|---|---|---|
| `MSSQL_MEMORY_LIMIT_MB` | `3500` | Cuánta RAM puede usar SQL Server. **Ponlo en ~70% de la RAM de tu contenedor.** Si tu plan da 2 GB, pon `1400`. |
| `TZ` | `America/Lima` | Zona horaria. Cámbiala a la tuya, ej. `America/Mexico_City`, `Europe/Madrid`. |
| `MSSQL_PID` | `Developer` | Edición. Lee el [aviso de licencia](#️-aviso-importante-sobre-la-licencia). |
| `MSSQL_COLLATION` | `Modern_Spanish_CI_AS` | Cómo ordena y compara texto. La de por defecto es correcta para español. |
| `MSSQL_SUSPEND` | `false` | `true` deja la base dormida. La maneja el cron. |
| `MSSQL_SHUTDOWN_TIMEOUT` | `20` | Segundos que espera al apagar antes de forzar. Súbelo si tus bases son muy grandes. |

### Las de backup

Ver la sección de [backups](#-backups-automáticos).

### La que NO debes poner

| Variable | Por qué |
|---|---|
| `MSSQL_ALLOW_DATA_LOSS_REPAIR` | Autoriza a **borrar datos** durante una reparación. No la crees salvo que sepas exactamente por qué la necesitas. Lee la sección siguiente. |

---

## 🏥 Qué hace el contenedor cuando algo se rompe

### Si una base queda dañada (`SUSPECT`)

A veces, tras un corte de energía o un reinicio brusco, SQL Server marca una base como `SUSPECT` y deja de servirla.

Al arrancar, el contenedor intenta arreglarla **sin borrar nada**, en tres intentos:

| # | Qué prueba | ¿Puede perder datos? |
|---|---|---|
| 1 | Volver a ponerla en línea | ❌ No |
| 2 | Revisarla en modo solo lectura para ver qué tiene | ❌ No |
| 3 | Reconstruir índices (`REPAIR_REBUILD`) | ❌ No |

En Railway, la causa más común de `SUSPECT` **no es corrupción real**, sino que el disco tardó en montarse. El intento 1 resuelve ese caso sin tocar nada.

**Si los tres fallan, el contenedor se detiene ahí y te avisa en los logs.** No hace nada más.

### El botón rojo: reparación que borra datos

Existe un cuarto nivel, `REPAIR_ALLOW_DATA_LOSS`, que arregla la base **borrando las partes dañadas**. Lo que había ahí se pierde para siempre.

**No se ejecuta nunca de forma automática.** Para usarlo tienes que crear la variable `MSSQL_ALLOW_DATA_LOSS_REPAIR` con valor `true` y redesplegar.

Antes de hacer eso:

1. **Intenta restaurar un backup.** Un backup de ayer casi siempre es mejor que una base "reparada" a la que le faltan filas que nadie sabe cuáles eran.
2. Si aun así lo necesitas, el script hace una copia del archivo dañado antes de tocarlo, para que un especialista pueda intentar rescatar datos después.
3. **Apaga la variable en cuanto termines.**

### Al apagar

Cuando Railway detiene el contenedor (por un despliegue o por tu cron), el sistema le pide a SQL Server que se cierre ordenadamente, guardando todo en disco. Solo si tarda más de lo permitido lo fuerza.

Esto importa: un cierre brusco obliga a SQL Server a hacer una recuperación de emergencia en el siguiente arranque, y hacerlo dos veces al día es tentar a la suerte.

---

## 🐛 Problemas comunes

### «El servicio se reinicia solo, una y otra vez»

**Causa más probable:** la contraseña de `sa` no cumple los requisitos, o `MSSQL_MEMORY_LIMIT_MB` es mayor que la RAM de tu plan.

**Solución:** revisa que la contraseña tenga mayúscula, minúscula, número y símbolo. Y baja `MSSQL_MEMORY_LIMIT_MB` a ~70% de tu RAM.

### «Perdí todas mis bases de datos tras actualizar»

**Causa:** no añadiste el volumen, o lo montaste en una ruta distinta a `/var/opt/mssql`.

**Solución:** no hay forma de recuperarlas si no había volumen. Añádelo ahora (Paso 3) para que no vuelva a pasar.

### «SSMS no se conecta»

Revisa en este orden:

1. ¿Usaste **coma** entre host y puerto? `host,puerto`, no `host:puerto`
2. ¿Marcaste **Trust server certificate** en Options → Connection Properties?
3. ¿Creaste el TCP Proxy en el Paso 5?
4. ¿El servicio está encendido? Si usas el cron de ahorro, quizás está dormido
5. ¿El usuario es `sa` exactamente, en minúsculas?

### «Login failed for user 'sa'»

La contraseña es incorrecta. Si la olvidaste, cambia `MSSQL_SA_PASSWORD` en Railway y redespliega — SQL Server la actualiza al arrancar.

### «El healthcheck falla al principio»

Normal durante los primeros 60 segundos. Si sigue después de 3 minutos, mira los Deploy Logs para ver el error real.

### «Error de sistema operativo 1359» al hacer backup

Aparece si intentas usar `BACKUP TO URL` nativo de SQL Server contra Cloudflare R2. **Ese camino no funciona.** Usa el sistema de backups incluido en la plantilla, que hace lo mismo por otra vía.

### «El backup se corta a la mitad»

Tu cron de apagado dispara antes de que termine. Sepáralos al menos 30 minutos.

### «El disco se llena»

1. Verifica en los logs que aparezca `Limpieza automática de logs iniciada`
2. Si tienes bases en modo de recuperación `FULL` sin backups de log, el archivo de log crece sin parar. O programas backups de log, o las pasas a `SIMPLE`:

```sql
ALTER DATABASE [MiBase] SET RECOVERY SIMPLE;
```

### «Power BI corta la conexión sola»

Verifica que `MSSQL_TCP_KEEPALIVE` valga `30000`. Si sigue, configura también el keep-alive del lado de Power BI.

---

## 🔧 Para desarrolladores

### Estructura del proyecto

```text
.
├── Dockerfile                          # Imagen optimizada para Railway
└── scripts/
    ├── entrypoint.sh                   # Arranque, apagado limpio, lanza tareas de fondo
    ├── auto_repair.sql                 # Escalera de reparación NO destructiva
    ├── auto_repair_dataloss.sql        # Reparación destructiva (tras variable explícita)
    ├── backup_to_r2.sh                 # Backup diario comprimido y verificado
    └── clean_old_logs.sh               # Purga de logs y backups antiguos
```

### Por qué un tag fijo y no `2022-latest`

El tag `2022-latest` pasó a **Ubuntu 22.04** (sqlpal package6), que provoca un **Stack Overflow** con el almacenamiento de Railway por un bug de I/O síncrono. El tag `2022-CU23-ubuntu-20.04` usa Ubuntu 20.04 (package4) y funciona bien.

### Detalles de implementación

- El contenedor arranca **nativamente como UID 10001**, no con `gosu`, para preservar el flag `PR_SET_DUMPABLE` del kernel. Sin él, SQL Server no puede leer su propio `/proc/self/maps` y el sistema de memoria de SQLOS colapsa.
- El Dockerfile reinstala `ca-certificates` durante el build. El bundle de Ubuntu 20.04 queda congelado en la fecha del tag, y uno viejo hace fallar los handshakes TLS hacia servicios externos.
- Los backups usan `rclone` en lugar de `BACKUP TO URL`, porque el conector S3 de SQL Server 2022 falla contra R2 con `Error de sistema operativo 1359` sin más detalle. El motor de backup a disco funciona perfectamente.
- La memoria se controla **solo** desde `MSSQL_MEMORY_LIMIT_MB`. No configures `max server memory` por T-SQL: tener dos fuentes de verdad hace que SQL arranque apuntando a un valor y lo cambie después, con un hueco peligroso en medio.
- Traceflags activos: `3979` (I/O), `1800` (alineación de sector 4K, correcto en almacenamiento de nube), `3226`, `1706`, `2505`, `3023`, `3656`.

### Notas de facturación en Railway

- El **volumen se cobra por el tamaño reservado**, no por el usado. No lo sobredimensiones.
- El contenedor se cobra por tiempo encendido. De ahí la sección de apagado programado.

---

## 🔗 Referencias

- [SQL Server en Docker — documentación oficial](https://learn.microsoft.com/es-es/sql/linux/sql-server-linux-docker-container-deployment)
- [Railway — documentación](https://docs.railway.app)
- [Railway — Serverless](https://docs.railway.com/deployments/serverless)
- [Cloudflare R2 — API S3](https://developers.cloudflare.com/r2/api/s3/api/)
- [DBCC CHECKDB — opciones de reparación](https://learn.microsoft.com/es-es/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql)
- [Política de contraseñas de SQL Server](https://learn.microsoft.com/es-es/sql/relational-databases/security/password-policy)
- [Ediciones y licenciamiento de SQL Server](https://www.microsoft.com/es-es/sql-server/sql-server-2022-comparison)
