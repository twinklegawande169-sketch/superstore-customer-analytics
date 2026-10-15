-- Superstore Level 2: star schema build
-- Run after superstore_import.sql. The flat `orders` table is the staging table.
-- Result: fact_sales + dim_customer, dim_product, dim_geography, dim_date.

USE superstore;

-- Drop in dependency order so the script can be re-run safely
DROP TABLE IF EXISTS fact_sales;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_geography;
DROP TABLE IF EXISTS dim_date;

-- 1. Customer dimension (one row per customer, expect 793)
CREATE TABLE dim_customer (
    customer_key  INT AUTO_INCREMENT PRIMARY KEY,
    Customer_ID   VARCHAR(15) NOT NULL UNIQUE,
    Customer_Name VARCHAR(50),
    Segment       VARCHAR(20)
);
INSERT INTO dim_customer (Customer_ID, Customer_Name, Segment)
SELECT DISTINCT Customer_ID, Customer_Name, Segment FROM orders;

-- 2. Product dimension.
-- Data quality finding: 32 Product_IDs have more than one Product_Name, so Product_ID
-- alone is not a safe key. The key is the pair (Product_ID, Product_Name): expect 1,894 rows.
CREATE TABLE dim_product (
    product_key  INT AUTO_INCREMENT PRIMARY KEY,
    Product_ID   VARCHAR(20)  NOT NULL,
    Product_Name VARCHAR(255) NOT NULL,
    Category     VARCHAR(20),
    Sub_Category VARCHAR(20),
    UNIQUE KEY uq_product (Product_ID, Product_Name)
);
INSERT INTO dim_product (Product_ID, Product_Name, Category, Sub_Category)
SELECT DISTINCT Product_ID, Product_Name, Category, Sub_Category FROM orders;

-- 3. Geography dimension.
-- Data quality finding: one Postal_Code appears with two city/state/region combinations,
-- so the key is the full combination: expect 632 rows.
CREATE TABLE dim_geography (
    geo_key     INT AUTO_INCREMENT PRIMARY KEY,
    Postal_Code VARCHAR(10),
    City        VARCHAR(50),
    State       VARCHAR(30),
    Region      VARCHAR(10),
    UNIQUE KEY uq_geo (Postal_Code, City, State, Region)
);
INSERT INTO dim_geography (Postal_Code, City, State, Region)
SELECT DISTINCT Postal_Code, City, State, Region FROM orders;

-- 4. Date dimension, one row per day.
-- Ship dates run to 2018-01-05, so the calendar covers 2014-01-01 to 2018-01-31.
CREATE TABLE dim_date (
    date_key    INT PRIMARY KEY,          -- yyyymmdd
    full_date   DATE NOT NULL,
    year_num    INT,
    quarter_num INT,
    month_num   INT,
    month_name  VARCHAR(10),
    month_label CHAR(7),                  -- yyyy-mm
    day_name    VARCHAR(10),
    is_weekend  TINYINT
);
SET SESSION cte_max_recursion_depth = 2000;
INSERT INTO dim_date
WITH RECURSIVE cal AS (
    SELECT DATE('2014-01-01') AS dt
    UNION ALL
    SELECT dt + INTERVAL 1 DAY FROM cal WHERE dt < DATE('2018-01-31')
)
SELECT CAST(DATE_FORMAT(dt, '%Y%m%d') AS UNSIGNED), dt, YEAR(dt), QUARTER(dt), MONTH(dt),
       MONTHNAME(dt), DATE_FORMAT(dt, '%Y-%m'), DAYNAME(dt),
       IF(DAYOFWEEK(dt) IN (1, 7), 1, 0)
FROM cal;

-- 5. Fact table, one row per order line (grain = 9,994 rows)
CREATE TABLE fact_sales (
    Row_ID         INT PRIMARY KEY,
    Order_ID       VARCHAR(20) NOT NULL,
    customer_key   INT NOT NULL,
    product_key    INT NOT NULL,
    geo_key        INT NOT NULL,
    order_date_key INT NOT NULL,
    ship_date_key  INT NOT NULL,
    Ship_Mode      VARCHAR(20),
    Sales          DECIMAL(10,4),
    Quantity       INT,
    Discount       DECIMAL(4,2),
    Profit         DECIMAL(12,4),
    FOREIGN KEY (customer_key)   REFERENCES dim_customer(customer_key),
    FOREIGN KEY (product_key)    REFERENCES dim_product(product_key),
    FOREIGN KEY (geo_key)        REFERENCES dim_geography(geo_key),
    FOREIGN KEY (order_date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (ship_date_key)  REFERENCES dim_date(date_key)
);
INSERT INTO fact_sales
SELECT o.Row_ID, o.Order_ID, c.customer_key, p.product_key, g.geo_key,
       CAST(DATE_FORMAT(o.Order_Date, '%Y%m%d') AS UNSIGNED),
       CAST(DATE_FORMAT(o.Ship_Date,  '%Y%m%d') AS UNSIGNED),
       o.Ship_Mode, o.Sales, o.Quantity, o.Discount, o.Profit
FROM orders o
JOIN dim_customer  c ON o.Customer_ID = c.Customer_ID
JOIN dim_product   p ON o.Product_ID = p.Product_ID AND o.Product_Name = p.Product_Name
JOIN dim_geography g ON o.Postal_Code = g.Postal_Code AND o.City = g.City
                    AND o.State = g.State AND o.Region = g.Region;

-- 6. Integrity checks.
-- Expect: fact_rows 9994, fact_sales 2297200.86, fact_profit 286397.02,
--         customers 793, products 1894, geos 632, dates 1492, all orphan counts 0.
SELECT
    (SELECT COUNT(*) FROM fact_sales)                        AS fact_rows,
    (SELECT ROUND(SUM(Sales), 2)  FROM fact_sales)           AS fact_sales,
    (SELECT ROUND(SUM(Profit), 2) FROM fact_sales)           AS fact_profit,
    (SELECT COUNT(*) FROM dim_customer)                      AS customers,
    (SELECT COUNT(*) FROM dim_product)                       AS products,
    (SELECT COUNT(*) FROM dim_geography)                     AS geos,
    (SELECT COUNT(*) FROM dim_date)                          AS dates,
    (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_customer  d ON f.customer_key = d.customer_key
      WHERE d.customer_key IS NULL)                          AS orphan_customers,
    (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_product   d ON f.product_key = d.product_key
      WHERE d.product_key IS NULL)                           AS orphan_products,
    (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_geography d ON f.geo_key = d.geo_key
      WHERE d.geo_key IS NULL)                               AS orphan_geos,
    (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_date      d ON f.order_date_key = d.date_key
      WHERE d.date_key IS NULL)                              AS orphan_order_dates;
