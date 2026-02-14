# SQL Server en Railway (Optimizado)

Este proyecto contiene la configuración necesaria para desplegar SQL Server en **Railway.app**.

## 🚀 Características

1. **Imagen Docker Optimizada:** Basada en `mssql:2022-latest` con ajustes de permisos y entorno.
2. **Persistencia:** Configurado para usar volúmenes de Railway.
3. **Configuración Regional:** Zona horaria configurada para Perú (`America/Lima`).

---

## 🛠️ Configuración Inicial

Para que el sistema funcione, necesitas configurar las variables de entorno en Railway.

### 1. Variables Necesarias

Configura estas variables en tu proyecto de Railway:

* `ACCEPT_EULA`: `Y`
* `MSSQL_PID`: `Developer` or `Express`
* `MSSQL_SA_PASSWORD`: Tu contraseña segura.

---

## ⚠️ Solución de Problemas

### Error de Permisos

Si tienes problemas con permisos de volumen, el script `entrypoint.sh` se encarga de ajustar los permisos al inicio.
