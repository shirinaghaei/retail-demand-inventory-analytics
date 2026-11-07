/* =====================================================================
   01_create_and_load.sql
   Project 2: Retail Demand and Inventory Analytics (SQL Server)
   Run in SSMS. Files must be in C:\retail_project\
   Run the blocks one after another (select a block, press F5).
   ===================================================================== */

-- BLOCK 1: create the database (run alone)
IF DB_ID('RetailInventory') IS NULL
    CREATE DATABASE RetailInventory;
GO

USE RetailInventory;
GO

-- BLOCK 2: create the tables (SAP SD naming for the sales data)
IF OBJECT_ID('dbo.vbrp') IS NOT NULL DROP TABLE dbo.vbrp;
IF OBJECT_ID('dbo.vbrk') IS NOT NULL DROP TABLE dbo.vbrk;
IF OBJECT_ID('dbo.kna1') IS NOT NULL DROP TABLE dbo.kna1;
IF OBJECT_ID('dbo.makt') IS NOT NULL DROP TABLE dbo.makt;
IF OBJECT_ID('dbo.cancellations') IS NOT NULL DROP TABLE dbo.cancellations;
GO

CREATE TABLE dbo.vbrk (            -- billing header
    VBELN NVARCHAR(20)  NOT NULL PRIMARY KEY,
    FKDAT DATETIME2(0)  NOT NULL,
    KUNAG INT           NULL,      -- customer id (empty for guest orders)
    NETWR DECIMAL(18,4) NOT NULL,
    WAERK CHAR(3)       NOT NULL
);

CREATE TABLE dbo.vbrp (            -- billing items
    VBELN NVARCHAR(20)  NOT NULL,
    POSNR INT           NOT NULL,
    MATNR NVARCHAR(30)  NOT NULL,
    ARKTX NVARCHAR(200) NULL,
    FKIMG INT           NOT NULL,
    NETPR DECIMAL(18,4) NOT NULL,
    NETWR DECIMAL(18,4) NOT NULL,
    WAERK CHAR(3)       NOT NULL,
    CONSTRAINT PK_vbrp PRIMARY KEY (VBELN, POSNR)
);

CREATE TABLE dbo.kna1 (            -- customer master
    KUNNR INT           NOT NULL PRIMARY KEY,
    LAND1 NVARCHAR(60)  NULL
);

CREATE TABLE dbo.makt (            -- material descriptions
    MATNR NVARCHAR(30)  NOT NULL PRIMARY KEY,
    MAKTX NVARCHAR(200) NULL
);

CREATE TABLE dbo.cancellations (   -- cancelled invoice lines
    Invoice     NVARCHAR(20)  NOT NULL,
    StockCode   NVARCHAR(30)  NOT NULL,
    InvoiceDate DATETIME2(0)  NOT NULL,
    CustomerID  INT           NULL,
    Units       INT           NOT NULL,
    Price       DECIMAL(18,4) NOT NULL,
    CancelValue DECIMAL(18,4) NOT NULL
);
GO

-- BLOCK 3: load the CSV files
BULK INSERT dbo.vbrk FROM 'C:\retail_project\vbrk.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', KEEPNULLS, TABLOCK);

BULK INSERT dbo.kna1 FROM 'C:\retail_project\kna1.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', KEEPNULLS, TABLOCK);

BULK INSERT dbo.makt FROM 'C:\retail_project\makt.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', KEEPNULLS, TABLOCK);

BULK INSERT dbo.vbrp FROM 'C:\retail_project\vbrp.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', KEEPNULLS, TABLOCK);

BULK INSERT dbo.cancellations FROM 'C:\retail_project\cancellations.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', CODEPAGE = '65001', KEEPNULLS, TABLOCK);
GO

-- BLOCK 4: reconciliation checks (compare with the control totals printed in Colab)
SELECT 'vbrk' AS table_name, COUNT(*) AS row_count FROM dbo.vbrk
UNION ALL SELECT 'vbrp', COUNT(*) FROM dbo.vbrp
UNION ALL SELECT 'kna1', COUNT(*) FROM dbo.kna1
UNION ALL SELECT 'makt', COUNT(*) FROM dbo.makt
UNION ALL SELECT 'cancellations', COUNT(*) FROM dbo.cancellations;

SELECT ROUND(SUM(NETWR), 2) AS sales_line_value FROM dbo.vbrp;        -- about 19,411,634
SELECT ROUND(SUM(CancelValue), 2) AS cancelled_value FROM dbo.cancellations;  -- about 471,063

-- Header total must equal the sum of its items (expect 0 mismatches)
SELECT COUNT(*) AS invoices_with_mismatch
FROM (
    SELECT k.VBELN
    FROM dbo.vbrk k
    JOIN dbo.vbrp p ON p.VBELN = k.VBELN
    GROUP BY k.VBELN, k.NETWR
    HAVING ABS(k.NETWR - SUM(p.NETWR)) > 0.05
) x;
GO
