-- ==========================================================
-- REPARACION DESTRUCTIVA - ULTIMO RECURSO
-- ==========================================================
-- Este script BORRA DATOS. Desasigna paginas corruptas para
-- devolver consistencia a la base. Lo que habia en esas paginas
-- se pierde y no se puede recuperar.
--
-- Solo se ejecuta si MSSQL_ALLOW_DATA_LOSS_REPAIR=true.
-- El entrypoint no lo invoca en ningun otro caso.
--
-- ANTES de correrlo, evalua restaurar desde un backup sano.
-- Un backup de ayer casi siempre es mejor que una base "reparada"
-- a la que le faltan filas que nadie sabe cuales eran.
--
-- Este script SI hace una copia previa (COPY_ONLY + CONTINUE_AFTER_ERROR)
-- para que quede un archivo con los datos ANTES de la destruccion.
-- ==========================================================
SET NOCOUNT ON;
GO

SET NOCOUNT ON;

PRINT '[dataloss] ############################################################';
PRINT '[dataloss] REPARACION DESTRUCTIVA AUTORIZADA POR VARIABLE DE ENTORNO';
PRINT '[dataloss] Se perderan los datos de las paginas corruptas.';
PRINT '[dataloss] ############################################################';

DECLARE @Db SYSNAME, @SQL NVARCHAR(MAX), @BackupFile NVARCHAR(500);
DECLARE @Stamp NVARCHAR(30) = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(19), GETDATE(), 126), '-', ''), ':', ''), 'T', '_');

DECLARE BadDbCursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE state_desc <> 'ONLINE' AND database_id > 4;

OPEN BadDbCursor;
FETCH NEXT FROM BadDbCursor INTO @Db;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '[dataloss] --- Procesando ' + @Db + ' ---';

    -- ------------------------------------------------------
    -- PASO 1: copia forense ANTES de destruir nada.
    -- CONTINUE_AFTER_ERROR permite respaldar una base dañada.
    -- El archivo resultante conserva los datos que el repair
    -- esta a punto de borrar; un especialista puede extraerlos.
    -- ------------------------------------------------------
    SET @BackupFile = '/var/opt/mssql/backup/PRE_REPAIR_' + @Db + '_' + @Stamp + '.bak';

    BEGIN TRY
        PRINT '[dataloss] ' + @Db + ': copia forense en ' + @BackupFile;
        SET @SQL = 'BACKUP DATABASE ' + QUOTENAME(@Db)
                 + ' TO DISK = ''' + @BackupFile + ''''
                 + ' WITH COPY_ONLY, CONTINUE_AFTER_ERROR, INIT, COMPRESSION;';
        EXEC sp_executesql @SQL;
        PRINT '[dataloss] ' + @Db + ': copia forense OK.';
    END TRY
    BEGIN CATCH
        PRINT '[dataloss] ' + @Db + ': la copia forense FALLO -> ' + ERROR_MESSAGE();
        PRINT '[dataloss] ' + @Db + ': se continua igualmente porque la reparacion fue autorizada.';
    END CATCH

    -- ------------------------------------------------------
    -- PASO 2: reparacion destructiva.
    -- ------------------------------------------------------
    BEGIN TRY
        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET EMERGENCY;';
        EXEC sp_executesql @SQL;

        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
        EXEC sp_executesql @SQL;

        PRINT '[dataloss] ' + @Db + ': ejecutando REPAIR_ALLOW_DATA_LOSS...';
        SET @SQL = 'DBCC CHECKDB (' + QUOTENAME(@Db) + ', REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS;';
        EXEC sp_executesql @SQL;

        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET MULTI_USER;';
        EXEC sp_executesql @SQL;

        SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET ONLINE;';
        EXEC sp_executesql @SQL;

        PRINT '[dataloss] ' + @Db + ': reparada. REVISA INTEGRIDAD Y CONTEOS DE FILAS.';
        PRINT '[dataloss] ' + @Db + ': apaga MSSQL_ALLOW_DATA_LOSS_REPAIR ahora que termino.';
    END TRY
    BEGIN CATCH
        PRINT '[dataloss] ' + @Db + ': la reparacion FALLO -> ' + ERROR_MESSAGE();
        BEGIN TRY
            SET @SQL = 'ALTER DATABASE ' + QUOTENAME(@Db) + ' SET MULTI_USER;';
            EXEC sp_executesql @SQL;
        END TRY
        BEGIN CATCH
            PRINT '[dataloss] ' + @Db + ': no se pudo devolver a MULTI_USER.';
        END CATCH
    END CATCH

    FETCH NEXT FROM BadDbCursor INTO @Db;
END

CLOSE BadDbCursor;
DEALLOCATE BadDbCursor;

PRINT '[dataloss] === Terminado. Apaga MSSQL_ALLOW_DATA_LOSS_REPAIR. ===';
GO
