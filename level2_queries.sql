-- Superstore Level 2: labelled SQL queries
-- Run after star_schema.sql. Database: superstore.
USE superstore;

-- Q1. JOIN + GROUP BY + HAVING: which sub-categories lose money?
-- Expect 3 rows: Tables, Bookcases, Supplies (all negative profit).
SELECT p.Category,
       p.Sub_Category,
       ROUND(SUM(f.Sales), 2)  AS total_sales,
       ROUND(SUM(f.Profit), 2) AS total_profit
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
GROUP BY p.Category, p.Sub_Category
HAVING SUM(f.Profit) < 0
ORDER BY total_profit;

-- Q2. CTE: which are the 5 strongest months by sales?
-- Expect Nov 2017 first at 118,447.83.
WITH monthly AS (
    SELECT d.year_num, d.month_num, d.month_name,
           ROUND(SUM(f.Sales), 2) AS sales
    FROM fact_sales f
    JOIN dim_date d ON f.order_date_key = d.date_key
    GROUP BY d.year_num, d.month_num, d.month_name
)
SELECT year_num, month_name, sales
FROM monthly
ORDER BY sales DESC
LIMIT 5;

-- Q3. Window function (LAG): month-over-month sales growth
-- Expect 2014-01 sales 14,236.90 (no previous month) and 2014-02 at -68.3%.
WITH monthly AS (
    SELECT d.month_label,
           ROUND(SUM(f.Sales), 2) AS sales
    FROM fact_sales f
    JOIN dim_date d ON f.order_date_key = d.date_key
    GROUP BY d.month_label
)
SELECT month_label,
       sales,
       LAG(sales) OVER (ORDER BY month_label) AS prev_month_sales,
       ROUND((sales - LAG(sales) OVER (ORDER BY month_label))
             / LAG(sales) OVER (ORDER BY month_label) * 100, 1) AS mom_growth_pct
FROM monthly
ORDER BY month_label;
