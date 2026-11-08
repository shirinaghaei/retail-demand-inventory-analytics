/* =====================================================================
   02_analysis.sql
   Project 2: Retail Demand and Inventory Analytics (SQL Server)
   Analysis window: 24 complete months, Dec 2009 to Nov 2011
   (Dec 2011 is incomplete and excluded).
   Run each block separately (select, F5).
   ===================================================================== */
USE RetailInventory;
GO

/* ---------- BLOCK 1: views ---------- */
IF OBJECT_ID('dbo.vw_sales_lines') IS NOT NULL DROP VIEW dbo.vw_sales_lines;
GO
CREATE VIEW dbo.vw_sales_lines AS
SELECT  p.VBELN                                   AS invoice_no,
        p.POSNR                                   AS line_no,
        k.FKDAT                                   AS invoice_date,
        DATEFROMPARTS(YEAR(k.FKDAT), MONTH(k.FKDAT), 1) AS month_start,
        k.KUNAG                                   AS customer_id,
        COALESCE(NULLIF(k.COUNTRY, ''), c.LAND1)   AS country, -- prefer invoice country
        p.MATNR                                   AS stock_code,
        m.MAKTX                                   AS product_name,
        p.FKIMG                                   AS units,
        p.NETPR                                   AS unit_price,
        p.NETWR                                   AS line_value
FROM dbo.vbrp p
JOIN dbo.vbrk k      ON k.VBELN = p.VBELN
LEFT JOIN dbo.makt m ON m.MATNR = p.MATNR
LEFT JOIN dbo.kna1 c ON c.KUNNR = k.KUNAG
WHERE p.MATNR <> 'C2';   -- C2 = CARRIAGE (shipping charge, not a product): 267 lines, GBP 13,426
GO

IF OBJECT_ID('dbo.vw_product_month') IS NOT NULL DROP VIEW dbo.vw_product_month;
GO
CREATE VIEW dbo.vw_product_month AS
SELECT  stock_code,
        month_start,
        SUM(units)      AS units,
        SUM(line_value) AS revenue
FROM dbo.vw_sales_lines
WHERE month_start BETWEEN '2009-12-01' AND '2011-11-01'
GROUP BY stock_code, month_start;
GO

/* ---------- BLOCK 2: monthly revenue with month-on-month change (LAG) ---------- */
WITH monthly AS (
    SELECT month_start, SUM(line_value) AS revenue
    FROM dbo.vw_sales_lines
    WHERE month_start BETWEEN '2009-12-01' AND '2011-11-01'
    GROUP BY month_start
)
SELECT  month_start,
        ROUND(revenue, 0) AS revenue,
        ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
              / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0), 1) AS mom_change_pct
FROM monthly
ORDER BY month_start;
GO

/* ---------- BLOCK 3: ABC analysis (revenue, cumulative share) ----------
   A = items that make the first 80% of revenue, B = next 15%, C = last 5%.
   An item that crosses a threshold stays in the higher class. */
IF OBJECT_ID('dbo.product_abc') IS NOT NULL DROP TABLE dbo.product_abc;
GO
WITH rev AS (
    SELECT stock_code, SUM(units) AS total_units, SUM(revenue) AS revenue
    FROM dbo.vw_product_month
    GROUP BY stock_code
),
ranked AS (
    SELECT  stock_code, total_units, revenue,
            SUM(revenue) OVER (ORDER BY revenue DESC, stock_code
                               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_revenue,
            SUM(revenue) OVER () AS total_revenue,
            RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
    FROM rev
)
SELECT  stock_code, total_units, revenue, revenue_rank,
        cum_revenue / total_revenue AS cum_share,
        CASE WHEN (cum_revenue - revenue) / total_revenue < 0.80 THEN 'A'
             WHEN (cum_revenue - revenue) / total_revenue < 0.95 THEN 'B'
             ELSE 'C' END AS abc_class
INTO dbo.product_abc
FROM ranked;
GO

/* ---------- BLOCK 4: XYZ analysis (demand variability) ----------
   Months with no sales count as 0, so a calendar grid is built first.
   CV = standard deviation / mean of monthly units.
   X: CV <= 0.5 (stable), Y: CV <= 1.0, Z: CV > 1.0 (erratic). */
IF OBJECT_ID('dbo.product_xyz') IS NOT NULL DROP TABLE dbo.product_xyz;
GO
WITH months AS (
    SELECT DISTINCT month_start FROM dbo.vw_product_month
),
prods AS (
    SELECT DISTINCT stock_code FROM dbo.vw_product_month
),
grid AS (
    SELECT p.stock_code, m.month_start
    FROM prods p CROSS JOIN months m
),
demand AS (
    SELECT g.stock_code, g.month_start, COALESCE(d.units, 0) AS units
    FROM grid g
    LEFT JOIN dbo.vw_product_month d
           ON d.stock_code = g.stock_code AND d.month_start = g.month_start
),
stats AS (
    SELECT  stock_code,
            AVG(CAST(units AS FLOAT))                      AS avg_monthly_units,
            STDEV(CAST(units AS FLOAT))                    AS sd_monthly_units,
            SUM(CASE WHEN units > 0 THEN 1 ELSE 0 END)     AS active_months
    FROM demand
    GROUP BY stock_code
)
SELECT  stock_code, avg_monthly_units, sd_monthly_units, active_months,
        sd_monthly_units / NULLIF(avg_monthly_units, 0) AS cv,
        CASE WHEN sd_monthly_units / NULLIF(avg_monthly_units, 0) <= 0.5 THEN 'X'
             WHEN sd_monthly_units / NULLIF(avg_monthly_units, 0) <= 1.0 THEN 'Y'
             ELSE 'Z' END AS xyz_class
INTO dbo.product_xyz
FROM stats;
GO

/* ---------- BLOCK 5: final product table (ABC + XYZ + name + cancellations) ---------- */
IF OBJECT_ID('dbo.product_abc_xyz') IS NOT NULL DROP TABLE dbo.product_abc_xyz;
GO
WITH canc AS (
    SELECT StockCode AS stock_code, SUM(CancelValue) AS cancelled_value, SUM(Units) AS cancelled_units
    FROM dbo.cancellations
    WHERE StockCode <> 'C2'
      AND InvoiceDate >= '2009-12-01' AND InvoiceDate < '2011-12-01'
    GROUP BY StockCode
)
SELECT  a.stock_code,
        m.MAKTX                                   AS product_name,
        a.total_units,
        a.revenue,
        a.revenue_rank,
        a.cum_share,
        a.abc_class,
        x.avg_monthly_units,
        x.sd_monthly_units,
        x.cv,
        x.active_months,
        x.xyz_class,
        a.abc_class + x.xyz_class                 AS abc_xyz,
        COALESCE(c.cancelled_value, 0)            AS cancelled_value,
        COALESCE(c.cancelled_units, 0)            AS cancelled_units,
        100.0 * COALESCE(c.cancelled_value, 0) / NULLIF(a.revenue, 0) AS cancel_rate_pct
INTO dbo.product_abc_xyz
FROM dbo.product_abc a
JOIN dbo.product_xyz x ON x.stock_code = a.stock_code
LEFT JOIN dbo.makt m   ON m.MATNR = a.stock_code
LEFT JOIN canc c       ON c.stock_code = a.stock_code;
GO

/* ---------- BLOCK 6: ABC x XYZ matrix (products, revenue share) ---------- */
SELECT  abc_xyz,
        COUNT(*)                                                    AS products,
        ROUND(SUM(revenue), 0)                                      AS revenue,
        ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)  AS revenue_share_pct,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS product_share_pct
FROM dbo.product_abc_xyz
GROUP BY abc_xyz
ORDER BY abc_xyz;
GO

/* ---------- BLOCK 7: top 3 products per country (RANK with PARTITION) ---------- */
WITH country_product AS (
    SELECT country, stock_code, MAX(product_name) AS product_name, SUM(line_value) AS revenue
    FROM dbo.vw_sales_lines
    WHERE country IS NOT NULL
      AND month_start BETWEEN '2009-12-01' AND '2011-11-01'
    GROUP BY country, stock_code
),
ranked AS (
    SELECT *, RANK() OVER (PARTITION BY country ORDER BY revenue DESC) AS rnk
    FROM country_product
)
SELECT country, rnk, stock_code, product_name, ROUND(revenue, 0) AS revenue
FROM ranked
WHERE rnk <= 3
  AND country IN (SELECT TOP 5 country FROM dbo.vw_sales_lines
                  WHERE country IS NOT NULL AND month_start >= '2009-12-01' AND month_start < '2011-12-01'
                  GROUP BY country ORDER BY SUM(line_value) DESC)
ORDER BY country, rnk, stock_code;
GO

/* ---------- BLOCK 8: A-class products with the highest cancellation rate ----------
   Only products sold in at least 12 of the 24 months (avoids tiny samples). */
SELECT TOP 15
        stock_code, product_name, abc_xyz,
        ROUND(revenue, 0)         AS revenue,
        ROUND(cancelled_value, 0) AS cancelled_value,
        ROUND(cancel_rate_pct, 1) AS cancel_rate_pct
FROM dbo.product_abc_xyz
WHERE abc_class = 'A' AND active_months >= 12
ORDER BY cancel_rate_pct DESC;
GO

/* ---------- BLOCK 9: quick validation ---------- */
SELECT COUNT(*) AS products,
       SUM(CASE WHEN abc_class = 'A' THEN 1 ELSE 0 END) AS a_products,
       ROUND(SUM(CASE WHEN abc_class = 'A' THEN revenue ELSE 0 END) / SUM(revenue) * 100, 1) AS a_revenue_pct
FROM dbo.product_abc_xyz;
GO
