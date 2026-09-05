-- ==========================================================
-- AUTO-REPARACION NO DESTRUCTIVA
-- ==========================================================
-- Corre en CADA arranque. Por diseño no puede perder datos:
-- solo intenta ONLINE y, como maximo, REPAIR_REBUILD.
--
-- La reparacion destructiva (REPAIR_ALLOW_DATA_LOSS) vive en
-- auto_repair_dataloss.sql y solo se invoca si la variable
-- MSSQL_ALLOW_DATA_LOSS_REPAIR esta en true. Nunca por defecto.
--
-- NOTA: la configuracion de memoria salio de aqui a proposito.
-- El unico dueño del limite es MSSQL_MEMORY_LIMIT_MB (Dockerfile).
-- Tener dos sitios configurando lo mismo causaba que SQL arrancara
-- apuntando a 8 GB dentro de un contenedor de 5 GB -> OOMKill.
-- ==========================================================
SET NOCOUNT ON;
GO

SET NOCOUNT ON;

PRINT '[auto_repair] === Revision de estado de bases de datos ===';

DECLARE @Bad INT = (
    SELECT COUNT(*) FROM sys.databases
    WHERE state_desc <> 'ONLINE' AND database_id > 4
);

IF @Bad = 0
BEGIN
    PRINT '[auto_repair] Todas las bases de usuario estan ONLINE. Nada que hacer.';
END
ELSE
BEGIN
    PRINT '[auto_repair] ATENCION: ' + CAST(@Bad AS NVARCHAR(10))
        + ' base(s) fuera de linea. Iniciando escalera no destructiva.';

    DECLARE @Db SYSNAME, @State NVARCHAR(60), @SQL NVARCHAR(MAX);

    DECLARE BadDbCursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name, state_desc
        FROM sys.databases
        WHERE state_desc <> 'ONLINE' AND database_id > 4;

    OPEN BadDbCursor;
    FETCH NEXT FROM BadDbCursor INTO @Db, @State;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        PRINT '[auto_repair] --- ' + @Db + ' (estado: ' + @State + ') ---';

        -- ------------------------------------------------------
        -- PELDAÑO 1: intentar ONLINE directo.
        -- Cubre el caso mas comun en Railway: el volumen monto tarde
        -- o con permisos incorrectos y SQL no pudo abrir los archivos.
        -- No hay corrupcion real; solo hay que reintentar.
        -- ------------------------------------------------------
        BEGIN TRY
            SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET ONLINE;';
            EXEC sp_executesql @SQL;
            PRINT '[auto_repair] ' + @Db + ': recuperada con SET ONLINE. Sin perdida de datos.';
        END TRY
        BEGIN CATCH
            PRINT '[auto_repair] ' + @Db + ': SET ONLINE fallo -> ' + ERROR_MESSAGE();

            -- ------------------------------------------------------
            -- PELDAÑO 2: diagnosticar antes de tocar nada.
            -- CHECKDB en modo solo lectura: dice si hay corrupcion real
            -- y de que nivel, sin modificar una sola pagina.
            -- ------------------------------------------------------
            BEGIN TRY
                PRINT '[auto_repair] ' + @Db + ': ejecutando CHECKDB de diagnostico (solo lectura)...';
                SET @SQL = 'DBCC CHECKDB (' + QUOTENAME(@Db) + ') WITH NO_INFOMSGS, ALL_ERRORMSGS;';
                EXEC sp_executesql @SQL;
                PRINT '[auto_repair] ' + @Db + ': CHECKDB no reporto errores de consistencia.';
            END TRY
            BEGIN CATCH
                PRINT '[auto_repair] ' + @Db + ': CHECKDB reporto -> ' + ERROR_MESSAGE();
            END CATCH

            -- ------------------------------------------------------
            -- PELDAÑO 3: REPAIR_REBUILD.
            -- Reconstruye indices y corrige lo reparable SIN borrar datos.
            -- Es el limite de lo que este script puede hacer solo.
            -- ------------------------------------------------------
            BEGIN TRY
                PRINT '[auto_repair] ' + @Db + ': intentando REPAIR_REBUILD (no destructivo)...';

                SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET EMERGENCY;';
                EXEC sp_executesql @SQL;

                SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
                EXEC sp_executesql @SQL;

                SET @SQL = 'DBCC CHECKDB (' + QUOTENAME(@Db) + ', REPAIR_REBUILD) WITH NO_INFOMSGS;';
                EXEC sp_executesql @SQL;

                SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET MULTI_USER;';
                EXEC sp_executesql @SQL;

                SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET ONLINE;';
                EXEC sp_executesql @SQL;

                PRINT '[auto_repair] ' + @Db + ': REPAIR_REBUILD completado. Sin perdida de datos.';
            END TRY
            BEGIN CATCH
                PRINT '[auto_repair] ' + @Db + ': REPAIR_REBUILD fallo -> ' + ERROR_MESSAGE();

                -- Dejarla en MULTI_USER para no bloquear un acceso manual.
                BEGIN TRY
                    SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET MULTI_USER;';
                    EXEC sp_executesql @SQL;
                END TRY
                BEGIN CATCH
                    PRINT '[auto_repair] ' + @Db + ': no se pudo devolver a MULTI_USER.';
                END CATCH

                PRINT '[auto_repair] !!! ' + @Db + ' SIGUE DAÑADA.';
                PRINT '[auto_repair] !!! Recuperarla requiere REPAIR_ALLOW_DATA_LOSS, que BORRA datos.';
                PRINT '[auto_repair] !!! Esa operacion NO se ejecuta automaticamente.';
                PRINT '[auto_repair] !!! Para autorizarla: MSSQL_ALLOW_DATA_LOSS_REPAIR=true y redesplegar.';
                PRINT '[auto_repair] !!! Antes de hacerlo, considera restaurar desde backup.';
            END CATCH
        END CATCH

        FETCH NEXT FROM BadDbCursor INTO @Db, @State;
    END

    CLOSE BadDbCursor;
    DEALLOCATE BadDbCursor;
END

PRINT '[auto_repair] === Revision terminada ===';
GO
