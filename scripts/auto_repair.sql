-- ==========================================================
-- SCRIPT DE AUTO-REPARACIÓN DE BASES DE DATOS (NIVEL 3)
-- ==========================================================
-- Este script se ejecuta en cada arranque del contenedor.
-- Busca BDs que estén en estado "SUSPECT" (Corruptas) y 
-- aplica un DBCC CHECKDB REPAIR_ALLOW_DATA_LOSS.
-- ¡ÚSESE BAJO SU PROPIO RIESGO, PUEDE HABER PÉRDIDA DE DATOS MENOR!

SET NOCOUNT ON;

-- ==========================================================
-- 0. CONFIGURACIÓN DE MEMORIA DINÁMICA (2GB - 8GB)
-- ==========================================================
PRINT 'Configurando límites de memoria dinámica (Min: 2048MB, Max: 8192MB)...';
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'min server memory (MB)', 2048;
EXEC sp_configure 'max server memory (MB)', 8192;
RECONFIGURE;
GO

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
    PRINT 'DETECTADA BASE DE DATOS CORRUPTA: ' + @DatabaseName + '... INTENTANDO REPARACIÓN DE EMERGENCIA.';

    -- 1. Ponerla en Emergency Mode
    SET @SQL = 'ALTER DATABASE [' + @DatabaseName + '] SET EMERGENCY;';
    EXEC sp_executesql @SQL;

    -- 2. Ponerla en Single User
    SET @SQL = 'ALTER DATABASE [' + @DatabaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    EXEC sp_executesql @SQL;

    -- 3. Intentar Reparación (Perderá transacciones incompletas)
    SET @SQL = 'DBCC CHECKDB ([' + @DatabaseName + '], REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS;';
    BEGIN TRY
        EXEC sp_executesql @SQL;
        PRINT 'Reparación Finalizada para: ' + @DatabaseName;
    END TRY
    BEGIN CATCH
        PRINT 'Error durante DBCC CHECKDB en: ' + @DatabaseName;
    END CATCH

    -- 4. Ponerla en Multi User
    SET @SQL = 'ALTER DATABASE [' + @DatabaseName + '] SET MULTI_USER;';
    EXEC sp_executesql @SQL;

    FETCH NEXT FROM SuspectDBCursor INTO @DatabaseName;
END

CLOSE SuspectDBCursor;
DEALLOCATE SuspectDBCursor;

PRINT 'Revisión de auto-reparación finalizada sin detectar más BDs corruptas.';
GO
