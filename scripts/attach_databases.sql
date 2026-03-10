-- ============================================================
-- attach_databases.sql
-- Detecta y re-adjunta TODAS las bases de datos de usuario
-- cuyos archivos .mdf existan en /var/opt/mssql/data/
-- Excluye bases de datos del sistema (master, model, msdb, tempdb)
-- ============================================================
PRINT '[RECOVERY] Iniciando adjuntar bases de datos de usuario...';

-- Bases de datos del sistema a ignorar
DECLARE @SysDatabases TABLE (name NVARCHAR(255));
INSERT INTO @SysDatabases VALUES ('master'), ('model'), ('msdb'), ('tempdb');

-- Tabla temporal para archivos .mdf encontrados
CREATE TABLE #MdfFiles (
    id        INT IDENTITY(1,1),
    filepath  NVARCHAR(500),
    dbname    NVARCHAR(255)
);

-- Leer directorio de datos usando xp_cmdshell
-- (habilitamos temporalmente solo para este script)
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;

INSERT INTO #MdfFiles (filepath)
EXEC xp_cmdshell 'ls /var/opt/mssql/data/*.mdf 2>/dev/null';

-- Desactivar xp_cmdshell inmediatamente después
EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE;

-- Extraer nombre de base de datos del path (quitar ruta y extensión)
UPDATE #MdfFiles
SET dbname = REVERSE(SUBSTRING(REVERSE(filepath), 5, CHARINDEX('/', REVERSE(filepath)) - 5))
WHERE filepath IS NOT NULL AND filepath NOT LIKE '%master%';

-- Eliminar filas inútiles (nulls, master)
DELETE FROM #MdfFiles
WHERE filepath IS NULL
   OR filepath LIKE '%master%'
   OR dbname IS NULL
   OR dbname = '';

PRINT '[RECOVERY] Archivos .mdf encontrados:';
SELECT filepath, dbname FROM #MdfFiles;

-- ==========================================
-- RECORRER Y ADJUNTAR CADA BASE DE DATOS
-- ==========================================
DECLARE @id       INT = 1;
DECLARE @maxId    INT;
DECLARE @dbname   NVARCHAR(255);
DECLARE @mdf      NVARCHAR(500);
DECLARE @ldf      NVARCHAR(500);
DECLARE @sql      NVARCHAR(MAX);

SELECT @maxId = MAX(id) FROM #MdfFiles;

WHILE @id <= @maxId
BEGIN
    SELECT @dbname = dbname, @mdf = filepath FROM #MdfFiles WHERE id = @id;

    -- Solo procesar si la base de datos NO existe ya
    IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = @dbname)
       AND NOT EXISTS (SELECT name FROM @SysDatabases WHERE name = @dbname)
    BEGIN
        SET @ldf = REPLACE(@mdf, '.mdf', '_log.ldf');

        PRINT '[RECOVERY] Intentando adjuntar: ' + @dbname;

        -- Intento 1: adjuntar con .mdf + .ldf
        BEGIN TRY
            SET @sql = N'CREATE DATABASE ' + QUOTENAME(@dbname) +
                       N' ON (FILENAME = ''' + @mdf + N'''),' +
                       N'    (FILENAME = ''' + @ldf + N''')' +
                       N' FOR ATTACH;';
            EXEC sp_executesql @sql;
            PRINT '[RECOVERY] OK: ' + @dbname + ' adjuntada correctamente.';
        END TRY
        BEGIN CATCH
            PRINT '[RECOVERY] Fallo con .ldf, intentando ATTACH_REBUILD_LOG para: ' + @dbname;
            -- Intento 2: solo .mdf, reconstruir log
            BEGIN TRY
                SET @sql = N'CREATE DATABASE ' + QUOTENAME(@dbname) +
                           N' ON (FILENAME = ''' + @mdf + N''')' +
                           N' FOR ATTACH_REBUILD_LOG;';
                EXEC sp_executesql @sql;
                PRINT '[RECOVERY] OK: ' + @dbname + ' adjuntada con log reconstruido.';
            END TRY
            BEGIN CATCH
                PRINT '[RECOVERY] ERROR TOTAL en ' + @dbname + ': ' + ERROR_MESSAGE();
            END CATCH
        END CATCH
    END
    ELSE
        PRINT '[RECOVERY] Omitiendo (ya existe o es sistema): ' + ISNULL(@dbname, 'NULL');

    SET @id = @id + 1;
END

-- ==========================================
-- BACKUP INMEDIATO DE TODAS LAS BDs ADJUNTADAS
-- ==========================================
PRINT '[RECOVERY] Iniciando backups de seguridad...';

DECLARE @bkpName NVARCHAR(255);
DECLARE @bkpPath NVARCHAR(500);

DECLARE cur CURSOR FOR
    SELECT name FROM sys.databases
    WHERE name NOT IN ('master','model','msdb','tempdb')
      AND state_desc = 'ONLINE';

OPEN cur;
FETCH NEXT FROM cur INTO @bkpName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @bkpPath = '/var/opt/mssql/backup/' + @bkpName + '_recovery.bak';
    BEGIN TRY
        SET @sql = N'BACKUP DATABASE ' + QUOTENAME(@bkpName) +
                   N' TO DISK = ''' + @bkpPath + N'''' +
                   N' WITH FORMAT, COMPRESSION, STATS = 25;';
        EXEC sp_executesql @sql;
        PRINT '[RECOVERY] Backup completado: ' + @bkpName;
    END TRY
    BEGIN CATCH
        PRINT '[RECOVERY] No se pudo hacer backup de ' + @bkpName + ': ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM cur INTO @bkpName;
END

CLOSE cur;
DEALLOCATE cur;

DROP TABLE #MdfFiles;
PRINT '[RECOVERY] Proceso completo para todas las bases de datos.';
GO
