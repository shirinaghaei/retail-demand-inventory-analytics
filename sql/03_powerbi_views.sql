/* =====================================================================
   03_powerbi_views.sql
   Small, clean tables for Power BI (same window as the analysis:
   Dec 2009 - Nov 2011, C2 carriage excluded). Run the whole file once (F5).
   ===================================================================== */
USE RetailInventory;
GO

IF OBJECT_ID('dbo.vw_pbi_monthly_country') IS NOT NULL DROP VIEW dbo.vw_pbi_monthly_country;
GO
CREATE VIEW dbo.vw_pbi_monthly_country AS
SELECT  month_start,
        COALESCE(country, 'Unknown') AS country,
        SUM(line_value)              AS revenue,
        SUM(units)                   AS units,
        COUNT(DISTINCT invoice_no)   AS invoices
FROM dbo.vw_sales_lines
WHERE month_start BETWEEN '2009-12-01' AND '2011-11-01'
GROUP BY month_start, COALESCE(country, 'Unknown');
GO

IF OBJECT_ID('dbo.vw_pbi_monthly_cancel') IS NOT NULL DROP VIEW dbo.vw_pbi_monthly_cancel;
GO
CREATE VIEW dbo.vw_pbi_monthly_cancel AS
SELECT  DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1) AS month_start,
        SUM(CancelValue) AS cancelled_value,
        SUM(Units)       AS cancelled_units
FROM dbo.cancellations
WHERE StockCode <> 'C2'
  AND InvoiceDate >= '2009-12-01' AND InvoiceDate < '2011-12-01'
GROUP BY DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1);
GO

-- Quick check: both should return 24 rows
SELECT COUNT(DISTINCT month_start) AS months_sales  FROM dbo.vw_pbi_monthly_country;
SELECT COUNT(*)                    AS months_cancel FROM dbo.vw_pbi_monthly_cancel;
GO
