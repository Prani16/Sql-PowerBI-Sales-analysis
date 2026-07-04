# Sales & Profitability Dashboard — SQL + Power BI

An end-to-end business intelligence project that models sales profitability from a
normalized OLTP database and presents it in an interactive Power BI dashboard.
Built on the **AdventureWorks** dataset with **MySQL** as the backend.



---

## Overview

The project tracks **Revenue, Profit, Margin %, and Year-over-Year growth** across
products, regions, and sales channels. It demonstrates a full analytics pipeline:
raw data ingestion, SQL modeling into a star schema, and dashboard delivery with
DAX time-intelligence measures.

**Pipeline:**

```
CSV extracts  ->  load_to_mysql.py  ->  MySQL base tables
              ->  sales_profitability.sql  ->  views + star schema + date table
              ->  Power BI (Import mode)  ->  data model + DAX + visuals
```

---

## Tech Stack

- **Database:** MySQL 8
- **Ingestion:** Python (pandas, SQLAlchemy, PyMySQL)
- **Modeling:** SQL (views, star schema, recursive CTE date dimension)
- **Visualization:** Power BI Desktop (Import mode, DAX measures)
- **Source data:** AdventureWorks OLTP (2011–2014)

---

## Data Model (Star Schema)

A single fact view surrounded by conformed dimensions.

| Object            | Type  | Role                                                      |
|-------------------|-------|-----------------------------------------------------------|
| `vw_salesprofit`  | View  | **Fact** — line-level revenue, cost, profit, channel      |
| `dim_product`     | View  | Product → Subcategory → Category hierarchy                |
| `dim_region`      | View  | Territory → Country → Sales group                         |
| `dim_customer`    | View  | Customer, store flag                                      |
| `dim_date`        | Table | Continuous calendar (2011–2014) for time intelligence     |

Relationships are one-to-many from each dimension to the fact, single-direction
filtering, with `dim_date` marked as the official Date Table in Power BI.

---

## Key Design Decisions

**Revenue = `linetotal`, not `unitprice * qty`.**
`linetotal` already nets out unit-price discounts, so it is the correct revenue
figure. Using price × quantity would overstate revenue on discounted lines.

**Profit modeled at line-item grain.**
Cost and profit are computed per order line (`standardcost * orderqty`) so they
aggregate correctly no matter how the data is sliced (by product, region, or channel)
in Power BI.

**Margin % computed as a DAX measure, not a SQL column.**
`Margin % = DIVIDE(SUM(profit), SUM(revenue))` recalculates at whatever grain the
user slices to. A per-row SQL margin averaged in a visual would be
revenue-unweighted and therefore wrong.

**LEFT JOINs on the product/category dimensions.**
Products missing a subcategory or category are preserved rather than silently
dropped, which an INNER JOIN would do — protecting against understated revenue.

**Import mode over DirectQuery.**
The dataset is static and small enough to cache in memory, so Import gives the full
DAX surface and faster visuals. DirectQuery would only be justified for real-time or
very large data — neither applies here.

---

## DAX Measures

```dax
Total Revenue = SUM(vw_salesprofit[revenue])
Total Profit  = SUM(vw_salesprofit[profit])
Margin %      = DIVIDE([Total Profit], [Total Revenue])

Revenue YoY % =
VAR Prior = CALCULATE([Total Revenue], DATEADD(dim_date[date], -1, YEAR))
RETURN DIVIDE([Total Revenue] - Prior, Prior)

Revenue MoM % =
VAR Prior = CALCULATE([Total Revenue], DATEADD(dim_date[date], -1, MONTH))
RETURN DIVIDE([Total Revenue] - Prior, Prior)

Revenue Rolling 3M =
CALCULATE(
    [Total Revenue],
    DATESINPERIOD(dim_date[date], MAX(dim_date[date]), -3, MONTH)
)
```

The rolling 3-month total smooths month-to-month volatility to reveal the underlying
revenue trend.

---

## Dashboard Features

- **KPI cards:** Total Revenue, Total Profit, Margin %, Revenue YoY %
- **Revenue trend** by month with a rolling 3-month overlay
- **Product drill-down** bar chart: Category → Subcategory → Product
- **Revenue by country** map (bubble size = revenue)
- **Revenue by channel** donut (Online vs Reseller), which also cross-filters the page
- **Year slicer** for interactive filtering
- **Decomposition tree** for ad-hoc exploration across any dimension

---

## Data Validation

The fact joins were validated by confirming that total modeled revenue equals total
raw source revenue — a check for join fan-out (duplicated or dropped rows):

```sql
SELECT SUM(linetotal) FROM salesorderdetail;   -- raw
SELECT SUM(revenue)   FROM vw_salesprofit;      -- modeled
```

Both returned **≈ 109,846,381.42**, confirming the joins are clean.

> **Note on the data:** 2014 is a *partial* year in AdventureWorks (orders end
> mid-year), so 2014 YoY appears to drop sharply. This is a data artifact, not a real
> decline, and is flagged rather than presented as a genuine trend.

---

## Challenges Solved

- **Text-stored dates imported as NULL.** `orderdate` arrived from CSV as text
  (`M/D/YYYY`). The Power BI MySQL connector read it as NULL, breaking all time
  intelligence. Fixed by parsing to a real `DATE` in the view with
  `STR_TO_DATE(orderdate, '%c/%e/%Y')`.
- **CTE recursion limit.** The recursive date table needs ~1,460 rows, above MySQL's
  default `cte_max_recursion_depth`. Raised the session limit before building it.
- **Rolling measure flatlining.** An `AVERAGEX` over daily dates averaged in empty
  days and collapsed to zero; switched to a `CALCULATE` 3-month total.
- **Chronological axis sorting.** A text `yearmonth` sorted alphabetically; added a
  numeric `yearmonth_sort` (year × 100 + month) and sorted by it.

---

## How to Reproduce

1. Load the AdventureWorks CSV extracts:
   ```bash
   pip install pandas sqlalchemy pymysql
   # edit folder path and password in load_to_mysql.py
   python load_to_mysql.py
   ```
2. Build the model:
   ```bash
   # run sales_profitability.sql in MySQL Workbench
   ```
3. Open the `.pbix` in Power BI Desktop, point the MySQL connection at your local
   instance, and refresh.

---

## Files

| File                       | Purpose                                            |
|----------------------------|----------------------------------------------------|
| `load_to_mysql.py`         | Loads CSV extracts into MySQL base tables          |
| `sales_profitability.sql`  | Builds views, star schema, date table, validation  |
| `dashboard.pbix`           | Power BI report                                    |
| `dashboard.png`            | Dashboard screenshot                               |
