-- Superstore Level 2, Phase 3: RFM customer segmentation
-- Run after star_schema.sql. Database: superstore.
USE superstore;

-- Step 1. Build one row per customer with Recency, Frequency, Monetary and 1-5 scores.
-- Reference date = the day after the last order in the data (2017-12-31).
-- Recency: days since the last order (fewer days = better, so it is scored in reverse).
-- Frequency: number of distinct orders. Monetary: total sales.
-- NTILE(5) splits customers into 5 equal groups (5 = best). Customer_ID is a tie-breaker
-- so the scores are the same every time the script runs.
DROP TABLE IF EXISTS customer_rfm;

CREATE TABLE customer_rfm AS
WITH ref AS (
    SELECT DATE_ADD(MAX(d.full_date), INTERVAL 1 DAY) AS ref_date
    FROM fact_sales f
    JOIN dim_date d ON f.order_date_key = d.date_key
),
cust AS (
    SELECT c.customer_key, c.Customer_ID, c.Customer_Name, c.Segment,
           MIN(od.full_date)          AS first_order_date,
           MAX(od.full_date)          AS last_order_date,
           COUNT(DISTINCT f.Order_ID) AS frequency,
           ROUND(SUM(f.Sales), 2)     AS monetary
    FROM fact_sales f
    JOIN dim_customer c ON f.customer_key = c.customer_key
    JOIN dim_date od    ON f.order_date_key = od.date_key
    GROUP BY c.customer_key, c.Customer_ID, c.Customer_Name, c.Segment
),
scored AS (
    SELECT cu.*,
           DATEDIFF(r.ref_date, cu.last_order_date) AS recency_days,
           NTILE(5) OVER (ORDER BY DATEDIFF(r.ref_date, cu.last_order_date) DESC, cu.Customer_ID) AS r_score,
           NTILE(5) OVER (ORDER BY cu.frequency, cu.Customer_ID) AS f_score,
           NTILE(5) OVER (ORDER BY cu.monetary,  cu.Customer_ID) AS m_score
    FROM cust cu
    CROSS JOIN ref r
)
SELECT s.*,
       CASE
           WHEN first_order_date >= '2017-01-01'   THEN 'New'        -- first order in 2017
           WHEN r_score >= 4 AND f_score >= 4      THEN 'Champions'  -- recent and frequent
           WHEN r_score >= 3 AND f_score >= 3      THEN 'Loyal'      -- fairly recent and frequent
           WHEN r_score <= 2 AND f_score >= 3      THEN 'At Risk'    -- used to buy often, gone quiet
           WHEN r_score <= 2 AND f_score <= 2      THEN 'Lost'       -- infrequent and long inactive
           ELSE                                         'Promising'  -- recent, but few orders so far
       END AS rfm_segment
FROM scored s;

-- Step 2. Checks. Expect 793 customers and score groups of 159, 159, 159, 158, 158.
SELECT COUNT(*) AS customers, COUNT(DISTINCT Customer_ID) AS unique_customers
FROM customer_rfm;

SELECT r_score, COUNT(*) AS customers
FROM customer_rfm
GROUP BY r_score
ORDER BY r_score;

-- Step 3. Segment summary: size and revenue share of each segment.
-- Expect: Champions 165, Loyal 164, At Risk 146, Promising 140, Lost 167, New 11 (total 793).
SELECT rfm_segment,
       COUNT(*)                                                              AS customers,
       ROUND(COUNT(*) / (SELECT COUNT(*) FROM customer_rfm) * 100, 1)        AS pct_customers,
       ROUND(SUM(monetary), 2)                                               AS revenue,
       ROUND(SUM(monetary) / (SELECT SUM(monetary) FROM customer_rfm) * 100, 1) AS pct_revenue,
       ROUND(AVG(recency_days), 0)                                           AS avg_days_since_order,
       ROUND(AVG(frequency), 1)                                              AS avg_orders,
       ROUND(AVG(monetary), 0)                                               AS avg_spend
FROM customer_rfm
GROUP BY rfm_segment
ORDER BY revenue DESC;
