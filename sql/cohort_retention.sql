-- Superstore Level 2, Phase 4: cohort and retention analysis
-- Run after star_schema.sql. Database: superstore.
USE superstore;

-- Step 1. One row per customer per month in which they ordered.
-- cohort_month = month of the customer's first order; month_number = months since that month.
DROP TABLE IF EXISTS cohort_activity;

CREATE TABLE cohort_activity AS
WITH monthly_activity AS (
    SELECT DISTINCT f.customer_key,
           d.year_num * 12 + d.month_num AS order_idx
    FROM fact_sales f
    JOIN dim_date d ON f.order_date_key = d.date_key
),
first_order AS (
    SELECT f.customer_key, MIN(d.full_date) AS first_date
    FROM fact_sales f
    JOIN dim_date d ON f.order_date_key = d.date_key
    GROUP BY f.customer_key
)
SELECT a.customer_key,
       DATE_FORMAT(fo.first_date, '%Y-%m') AS cohort_month,
       a.order_idx - (YEAR(fo.first_date) * 12 + MONTH(fo.first_date)) AS month_number
FROM monthly_activity a
JOIN first_order fo ON a.customer_key = fo.customer_key;

-- Step 2. Retention in long format (used later for the Power BI heatmap).
-- retention_pct = % of the cohort that ordered in that month_number.
DROP TABLE IF EXISTS cohort_retention;

CREATE TABLE cohort_retention AS
WITH sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohort_activity
    WHERE month_number = 0
    GROUP BY cohort_month
)
SELECT a.cohort_month, s.cohort_size, a.month_number,
       COUNT(*) AS active_customers,
       ROUND(COUNT(*) / s.cohort_size * 100, 1) AS retention_pct
FROM cohort_activity a
JOIN sizes s ON s.cohort_month = a.cohort_month
GROUP BY a.cohort_month, s.cohort_size, a.month_number;

-- Step 3. How big are the cohorts? Most customers first ordered in 2014.
-- Expect 2014: 595, 2015: 136, 2016: 51, 2017: 11.
SELECT LEFT(cohort_month, 4) AS cohort_year, COUNT(*) AS customers
FROM cohort_activity
WHERE month_number = 0
GROUP BY cohort_year
ORDER BY cohort_year;

-- Step 4. Cohort table (heatmap data): 2014 cohorts, months 0 to 12.
-- Each cell = % of the cohort that ordered in that month after their first order.
-- Expect 2014-01: size 32, m0 100.0, m1 9.4, m2 0.0, m3 6.2, m6 6.2, m12 9.4.
SELECT cohort_month,
       MAX(cohort_size) AS cohort_size,
       COALESCE(MAX(CASE WHEN month_number = 0  THEN retention_pct END), 0) AS m0,
       COALESCE(MAX(CASE WHEN month_number = 1  THEN retention_pct END), 0) AS m1,
       COALESCE(MAX(CASE WHEN month_number = 2  THEN retention_pct END), 0) AS m2,
       COALESCE(MAX(CASE WHEN month_number = 3  THEN retention_pct END), 0) AS m3,
       COALESCE(MAX(CASE WHEN month_number = 4  THEN retention_pct END), 0) AS m4,
       COALESCE(MAX(CASE WHEN month_number = 5  THEN retention_pct END), 0) AS m5,
       COALESCE(MAX(CASE WHEN month_number = 6  THEN retention_pct END), 0) AS m6,
       COALESCE(MAX(CASE WHEN month_number = 7  THEN retention_pct END), 0) AS m7,
       COALESCE(MAX(CASE WHEN month_number = 8  THEN retention_pct END), 0) AS m8,
       COALESCE(MAX(CASE WHEN month_number = 9  THEN retention_pct END), 0) AS m9,
       COALESCE(MAX(CASE WHEN month_number = 10 THEN retention_pct END), 0) AS m10,
       COALESCE(MAX(CASE WHEN month_number = 11 THEN retention_pct END), 0) AS m11,
       COALESCE(MAX(CASE WHEN month_number = 12 THEN retention_pct END), 0) AS m12
FROM cohort_retention
WHERE cohort_month <= '2014-12'
GROUP BY cohort_month
ORDER BY cohort_month;

-- Step 5. Average retention by month for all 2014 cohorts together (595 customers).
-- Expect: m0 100.0, m1 11.3, m2 6.6, m3 8.9, m4 7.6, m5 7.6, m6 10.6,
--         m7 10.1, m8 10.8, m9 8.1, m10 10.8, m11 10.8, m12 11.3.
SELECT month_number,
       ROUND(SUM(active_customers) /
             (SELECT COUNT(*) FROM cohort_activity
              WHERE month_number = 0 AND cohort_month <= '2014-12') * 100, 1) AS retention_pct
FROM cohort_retention
WHERE cohort_month <= '2014-12' AND month_number BETWEEN 0 AND 12
GROUP BY month_number
ORDER BY month_number;

-- Step 6. Cumulative: % of 2014 customers who have ordered again by month n.
-- Expect: 1 -> 11.3, 2 -> 17.3, 3 -> 24.4, 6 -> 42.5, 9 -> 58.7, 12 -> 69.2.
WITH first_return AS (
    SELECT customer_key, MIN(month_number) AS first_return_month
    FROM cohort_activity
    WHERE month_number > 0
    GROUP BY customer_key
),
base AS (
    SELECT customer_key
    FROM cohort_activity
    WHERE month_number = 0 AND cohort_month <= '2014-12'
)
SELECT m.months_n AS months_after_first_order,
       ROUND(SUM(fr.first_return_month <= m.months_n) / COUNT(*) * 100, 1) AS pct_ordered_again
FROM base b
LEFT JOIN first_return fr ON fr.customer_key = b.customer_key
CROSS JOIN (SELECT 1 AS months_n UNION ALL SELECT 2 UNION ALL SELECT 3
            UNION ALL SELECT 6 UNION ALL SELECT 9 UNION ALL SELECT 12) m
GROUP BY m.months_n
ORDER BY m.months_n;

-- Step 7. Repeat-purchase rate (customers with 2 or more orders).
-- Expect 793 customers, 781 repeat customers, 98.5%.
SELECT COUNT(*) AS customers,
       SUM(orders > 1) AS repeat_customers,
       ROUND(SUM(orders > 1) / COUNT(*) * 100, 1) AS repeat_rate_pct
FROM (
    SELECT customer_key, COUNT(DISTINCT Order_ID) AS orders
    FROM fact_sales
    GROUP BY customer_key
) t;

-- Step 8. Average time between a customer's orders (window function LAG).
-- Expect 4,216 gaps and an average of 188.0 days.
WITH orders_by_customer AS (
    SELECT f.customer_key, f.Order_ID, MIN(d.full_date) AS order_date
    FROM fact_sales f
    JOIN dim_date d ON f.order_date_key = d.date_key
    GROUP BY f.customer_key, f.Order_ID
),
gaps AS (
    SELECT customer_key,
           DATEDIFF(order_date,
                    LAG(order_date) OVER (PARTITION BY customer_key ORDER BY order_date, Order_ID)) AS gap_days
    FROM orders_by_customer
)
SELECT COUNT(gap_days) AS gaps,
       ROUND(AVG(gap_days), 1) AS avg_days_between_orders
FROM gaps;
