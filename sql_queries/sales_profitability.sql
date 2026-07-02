-- =====================================================================
-- Sales & Profitability Dashboard  |  SQL Modeling Layer (MySQL)
-- Source: AdventureWorks OLTP (loaded from CSV into MySQL)
-- Purpose: model profit & margin and shape a star schema for Power BI
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Database
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS Adventureworks;
USE Adventureworks;

-- Base tables (salesorderheader, salesorderdetail, product,
-- productsubcategory, productcategory, salesterritory, customer)
-- are loaded separately from CSV via the Python load script.


-- ---------------------------------------------------------------------
-- 1. Fact view: line-level revenue, cost, and profit
-- ---------------------------------------------------------------------
-- Design notes:
--   * revenue = linetotal (already nets unit-price discounts)
--   * profit modeled at line grain so it aggregates correctly at any slice
--   * orderdate is stored as text (M/D/YYYY) from the CSV import, so it is
--     parsed to a real DATE with STR_TO_DATE; without this the Power BI
--     MySQL connector imported the column as NULL.
--   * onlineorderflag loaded as 0/1 (int), so compared with = 1.
CREATE OR REPLACE VIEW vw_salesprofit AS
SELECT
    soh.salesorderid,
    STR_TO_DATE(soh.orderdate, '%c/%e/%Y')            AS orderdate,
    sod.productid,
    soh.territoryid,
    soh.customerid,
    CASE WHEN soh.onlineorderflag = 1
         THEN 'Online' ELSE 'Reseller' END            AS channel,
    sod.orderqty,
    sod.linetotal                                     AS revenue,
    (p.standardcost * sod.orderqty)                   AS cost,
    sod.linetotal - (p.standardcost * sod.orderqty)   AS profit
FROM salesorderheader soh
JOIN salesorderdetail sod ON soh.salesorderid = sod.salesorderid
JOIN product          p   ON sod.productid    = p.productid;


-- ---------------------------------------------------------------------
-- 2. Dimension views (star schema)
-- ---------------------------------------------------------------------
-- Product dimension: product -> subcategory -> category
-- LEFT JOINs so products without a subcategory/category are not dropped.
CREATE OR REPLACE VIEW dim_product AS
SELECT
    p.productid,
    p.name   AS productname,
    psc.name AS subcategory,
    pc.name  AS category
FROM product p
LEFT JOIN productsubcategory psc ON p.productsubcategoryid = psc.productsubcategoryid
LEFT JOIN productcategory    pc  ON psc.productcategoryid   = pc.productcategoryid;

-- Region dimension  (`group` is a reserved word -> backticks)
CREATE OR REPLACE VIEW dim_region AS
SELECT
    territoryid,
    name              AS region,
    countryregioncode AS country,
    `group`           AS sales_group
FROM salesterritory;

-- Customer dimension
CREATE OR REPLACE VIEW dim_customer AS
SELECT
    customerid,
    territoryid,
    (storeid IS NOT NULL) AS is_store
FROM customer;


-- ---------------------------------------------------------------------
-- 3. Date dimension (continuous calendar, 2011-2014)
-- ---------------------------------------------------------------------
-- Recursive CTE builds one row per day. Default recursion depth (~1000)
-- is below the ~1460 days needed, so raise it first.
SET SESSION cte_max_recursion_depth = 3000;

DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date AS
WITH RECURSIVE dates AS (
    SELECT DATE('2011-01-01') AS date
    UNION ALL
    SELECT date + INTERVAL 1 DAY FROM dates WHERE date < '2014-12-31'
)
SELECT
    date,
    YEAR(date)               AS year,
    QUARTER(date)            AS quarter,
    MONTH(date)              AS monthno,
    DATE_FORMAT(date, '%b')  AS month,
    DATE_FORMAT(date, '%Y-%m') AS yearmonth
FROM dates;


-- ---------------------------------------------------------------------
-- 4. Validation: model revenue must equal raw source revenue
-- ---------------------------------------------------------------------
-- If these two totals match, the fact joins produced no fan-out
-- (no duplicated or dropped rows). They matched at ~109,846,381.42.
SELECT SUM(linetotal) AS raw_revenue   FROM salesorderdetail;
SELECT SUM(revenue)   AS model_revenue FROM vw_salesprofit;

-- Yearly trend sanity check (note: 2014 is a partial year in the data).
SELECT YEAR(orderdate) AS yr,
       SUM(revenue) AS revenue,
       SUM(profit)  AS profit
FROM vw_salesprofit
GROUP BY YEAR(orderdate)
ORDER BY yr;
