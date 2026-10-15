-- Superstore Level 2, Phase 5: 3-month sales forecast with measured accuracy
-- Run after star_schema.sql. Database: superstore.
USE superstore;

-- Step 1. Monthly sales (48 months, Jan 2014 to Dec 2017).
-- Expect 48 rows; the check query should total 2,297,200.86.
DROP TABLE IF EXISTS monthly_sales;

CREATE TABLE monthly_sales AS
SELECT STR_TO_DATE(CONCAT(d.month_label, '-01'), '%Y-%m-%d') AS month_start,
       d.month_label,
       ROUND(SUM(f.Sales), 2) AS sales
FROM fact_sales f
JOIN dim_date d ON f.order_date_key = d.date_key
GROUP BY d.month_label;

SELECT COUNT(*) AS months, ROUND(SUM(sales), 2) AS total_sales FROM monthly_sales;

-- Step 2. Train/test split. Training = Jan 2014 to Sep 2017. Test = the last 3 months (Oct to Dec 2017).
-- Three simple methods:
--   moving average   = average of the last 3 training months (Jul to Sep 2017), same value every month
--   seasonal naive   = sales in the same month last year
--   seasonal + growth = same month last year x growth (last 12 training months / the 12 before)
DROP TABLE IF EXISTS forecast_test;

CREATE TABLE forecast_test AS
WITH growth AS (
    SELECT (SELECT SUM(sales) FROM monthly_sales WHERE month_start BETWEEN '2016-10-01' AND '2017-09-01')
         / (SELECT SUM(sales) FROM monthly_sales WHERE month_start BETWEEN '2015-10-01' AND '2016-09-01') AS g
),
ma AS (
    SELECT AVG(sales) AS ma3
    FROM monthly_sales
    WHERE month_start BETWEEN '2017-07-01' AND '2017-09-01'
)
SELECT t.month_label,
       t.sales                    AS actual,
       ROUND(ma.ma3, 2)           AS f_moving_avg,
       ly.sales                   AS f_seasonal_naive,
       ROUND(ly.sales * gr.g, 2)  AS f_seasonal_growth
FROM monthly_sales t
JOIN monthly_sales ly ON ly.month_start = DATE_SUB(t.month_start, INTERVAL 1 YEAR)
CROSS JOIN growth gr
CROSS JOIN ma
WHERE t.month_start BETWEEN '2017-10-01' AND '2017-12-01';

-- Forecast vs actual for the 3 test months.
-- Expect actuals 77,776.92 / 118,447.83 / 83,829.32; seasonal + growth about 74,073 / 98,551 / 120,376.
SELECT * FROM forecast_test ORDER BY month_label;

-- Step 3. Accuracy on the test months (MAPE = average % error; lower is better).
-- Expect: moving average 27.5, seasonal naive 24.0, seasonal + growth 21.7.
SELECT ROUND(AVG(ABS(actual - f_moving_avg)     / actual) * 100, 1) AS mape_moving_avg,
       ROUND(AVG(ABS(actual - f_seasonal_naive) / actual) * 100, 1) AS mape_seasonal_naive,
       ROUND(AVG(ABS(actual - f_seasonal_growth) / actual) * 100, 1) AS mape_seasonal_growth
FROM forecast_test;

-- Step 4. Is 3 test months enough? Re-run the seasonal + growth method for every month
-- from Mar 2016 to Dec 2017, each time forecasting 3 months ahead using only older data.
-- Expect 22 forecasts, MAPE 26.3, and about 68.2% of forecasts within 40% of the actual.
DROP TABLE IF EXISTS forecast_backtest;

CREATE TABLE forecast_backtest AS
WITH t AS (
    SELECT month_start, month_label, sales AS actual
    FROM monthly_sales
    WHERE month_start BETWEEN '2016-03-01' AND '2017-12-01'
)
SELECT t.month_label,
       t.actual,
       ROUND(
           (SELECT sales FROM monthly_sales
             WHERE month_start = DATE_SUB(t.month_start, INTERVAL 12 MONTH))
         * (SELECT SUM(sales) FROM monthly_sales
             WHERE month_start BETWEEN DATE_SUB(t.month_start, INTERVAL 14 MONTH)
                                   AND DATE_SUB(t.month_start, INTERVAL 3 MONTH))
         / (SELECT SUM(sales) FROM monthly_sales
             WHERE month_start BETWEEN DATE_SUB(t.month_start, INTERVAL 26 MONTH)
                                   AND DATE_SUB(t.month_start, INTERVAL 15 MONTH))
       , 2) AS forecast
FROM t;

SELECT COUNT(*) AS forecasts,
       ROUND(AVG(ABS(actual - forecast) / actual) * 100, 1)                AS mape_pct,
       ROUND(SUM(ABS(actual - forecast) / actual <= 0.4) / COUNT(*) * 100, 1) AS pct_within_40
FROM forecast_backtest;

-- Step 5. Forecast for Jan to Mar 2018 with a range.
-- Growth = 2017 sales / 2016 sales. The range is +/-40% because about two thirds of past
-- forecasts landed within 40% of the actual (Step 4).
-- Expect about: 2018-01 52,922 (31,753 to 74,091); 2018-02 24,434 (14,660 to 34,208);
--               2018-03 70,856 (42,514 to 99,198).
DROP TABLE IF EXISTS forecast_next_3_months;

CREATE TABLE forecast_next_3_months AS
WITH growth AS (
    SELECT (SELECT SUM(sales) FROM monthly_sales WHERE month_start BETWEEN '2017-01-01' AND '2017-12-01')
         / (SELECT SUM(sales) FROM monthly_sales WHERE month_start BETWEEN '2016-01-01' AND '2016-12-01') AS g
),
future AS (
    SELECT DATE('2018-01-01') AS month_start
    UNION ALL SELECT DATE('2018-02-01')
    UNION ALL SELECT DATE('2018-03-01')
)
SELECT DATE_FORMAT(fu.month_start, '%Y-%m')   AS month_label,
       ROUND(ly.sales * gr.g, 0)              AS forecast,
       ROUND(ly.sales * gr.g * 0.6, 0)        AS low,
       ROUND(ly.sales * gr.g * 1.4, 0)        AS high
FROM future fu
JOIN monthly_sales ly ON ly.month_start = DATE_SUB(fu.month_start, INTERVAL 1 YEAR)
CROSS JOIN growth gr;

SELECT * FROM forecast_next_3_months ORDER BY month_label;
