# SQL Server en Railway (Optimizado)

Este proyecto contiene la configuración necesaria para desplegar SQL Server en **Railway.app** de manera optimizada, reduciendo costos mediante un sistema de **encendido/apagado automático**.

## 🚀 Características

1.  **Ahorro de Costos:** El servidor se apaga automáticamente fuera de horario laboral.
2.  **Control Manual:** Script de "Emergencia" para encender el servidor desde tu escritorio en cualquier momento.
3.  **Horario Automático:** Gestión desatendida mediante GitHub Actions.

---

## 🛠️ Configuración Inicial

Para que el sistema funcione, necesitas configurar las credenciales de Railway tanto en tu entorno local como en GitHub.

### 1. Variables Necesarias
Obtén estos datos desde tu panel de Railway:
*   **RAILWAY_TOKEN:** (Settings -> Tokens -> New Token)
*   **RAILWAY_SERVICE_ID:** (SQL Server -> Settings -> Service ID)

---

## 💻 Modo Manual (Desde tu PC)

Permite encender/apagar el servidor bajo demanda con un doble clic, ideal para trabajar fuera de horario.

### Instalación
1.  Ve a la carpeta `scripts/`.
2.  Copia el archivo `railway_secrets.template.ps1` y renómbralo a `railway_secrets.ps1`.
3.  Edita el nuevo archivo `railway_secrets.ps1` y coloca tus credenciales reales:
    ```powershell
    $env:RAILWAY_TOKEN = "tu-token-real-aqui"
    $env:RAILWAY_SERVICE_ID = "tu-service-id-real-aqui"
    ```
    *(Nota: Este archivo es ignorado por Git para proteger tus claves).*

4.  Ejecuta el script de instalación del acceso directo:
    *   Clic derecho en `scripts/setup_shortcut.ps1` -> **"Run with PowerShell"**.

### Uso
*   Busca el icono **"Encender SQL Server"** en tu Escritorio.
*   Haz **Doble Clic**.
*   Espera ~1 minuto antes de conectar tu SQL Server Management Studio (SSMS) o Power BI.

---

## 🤖 Modo Automático (GitHub Actions)

El servidor seguirá este horario de Lunes a Domingo sin que tengas que hacer nada.

### Horario Programado (Hora Perú)
| Acción | Hora PE | Hora UTC |
| :--- | :--- | :--- |
| **ON** | 03:00 AM | 08:00 |
| **OFF** | 04:00 AM | 09:00 |
| **ON** | 06:00 AM | 11:00 |
| **OFF** | 07:00 AM | 12:00 |
| **ON** | 11:20 PM | 04:20 (+1) |
| **OFF** | 12:20 AM | 05:20 (+1) |

### Activación
Para activar este horario, debes guardar tus claves en GitHub:
1.  Ve a tu repositorio en GitHub.
2.  Clic en **Settings** > **Secrets and variables** > **Actions**.
3.  Crea dos "Repository Secrets":
    *   `RAILWAY_TOKEN`
    *   `RAILWAY_SERVICE_ID`

---

## ⚠️ Solución de Problemas常见

### Error "Not Authenticated" o "400 Bad Request"
*   Verifica que el Token en `railway_secrets.ps1` (PC) o en GitHub Secrets sea correcto.
*   Asegúrate de no tener espacios en blanco al copiar el ID.

### El acceso directo no hace nada
*   Abre una terminal de PowerShell en la carpeta del proyecto.
*   Ejecuta manualmente: `.\scripts\railway_control.ps1 -Action Start`.
*   Lee el error que aparece en pantalla.
