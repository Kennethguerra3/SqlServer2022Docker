-- ==========================================================
-- SCRIPT DE AUTO-REPARACIÓN DE BASES DE DATOS (NIVEL 3)
-- ==========================================================
-- Optimizado para "Modo Silencioso" en Railway.
SET NOCOUNT ON;

-- 1. CONFIGURACIÓN DE MEMORIA DINÁMICA (Solo si es necesario)
DECLARE @MinMem INT = 2048;
DECLARE @MaxMem INT = 8192;

IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'min server memory (MB)' AND value_in_use <> @MinMem)
   OR EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'max server memory (MB)' AND value_in_use <> @MaxMem)
BEGIN
    EXEC sp_configure 'show advanced options', 1;
    RECONFIGURE;
    EXEC sp_configure 'min server memory (MB)', @MinMem;
    EXEC sp_configure 'max server memory (MB)', @MaxMem;
    RECONFIGURE;
END
GO

SET NOCOUNT ON;
DECLARE @DatabaseName NVARCHAR(128);
DECLARE @SQL NVARCHAR(MAX);

-- Cursor para iterar sobre cualquier BD que esté suspendida/sospechosa
DECLARE SuspectDBCursor CURSOR FOR 
    SELECT name 
    FROM sys.databases 
    WHERE state_desc = 'SUSPECT';

OPEN SuspectDBCursor;
FETCH NEXT FROM SuspectDBCursor INTO @DatabaseName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- 1. Ponerla en Emergency Mode
    SET @SQL = 'ALTER DATABASE [' + @DatabaseName + '] SET EMERGENCY;';
    EXEC sp_executesql @SQL;

    -- 2. Ponerla en Single User
    SET @SQL = 'ALTER DATABASE [' + @DatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    EXEC sp_executesql @SQL;

    -- 3. Intentar Reparación
    SET @SQL = 'DBCC CHECKDB ([' + @DatabaseName + '], REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS;';
    BEGIN TRY
        EXEC sp_executesql @SQL;
    END TRY
    BEGIN CATCH
        -- Solo loggeamos el error si ocurre algo crítico
        PRINT '!!! Error crítico reparando: ' + @DatabaseName;
    END CATCH

    -- 4. Ponerla en Multi User
    SET @SQL = 'ALTER DATABASE [' + @DatabaseName + '] SET MULTI_USER;';
    EXEC sp_executesql @SQL;

    FETCH NEXT FROM SuspectDBCursor INTO @DatabaseName;
END

CLOSE SuspectDBCursor;
DEALLOCATE SuspectDBCursor;
GO

