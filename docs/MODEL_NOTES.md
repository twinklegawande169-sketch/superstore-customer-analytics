# Model notes

## Grain
`fact_sales` has one row per order line (9,994 rows). One order (`Order_ID`) can have several lines; there are 5,009 orders.

## Tables and keys
| Table | Key | Rows | Notes |
|---|---|---|---|
| `fact_sales` | `Row_ID` | 9,994 | Measures: Sales, Quantity, Discount, Profit. Foreign keys to the four dimensions. |
| `dim_customer` | `customer_key` (from `Customer_ID`) | 793 | Name and the Superstore segment (Consumer, Corporate, Home Office). |
| `dim_product` | `product_key` (from `Product_ID` and `Product_Name`) | 1,894 | Category and sub-category. |
| `dim_geography` | `geo_key` (from postal code, city, state, region) | 632 | |
| `dim_date` | `date_key` (yyyymmdd) | 1,492 | Calendar from 2014-01-01 to 2018-01-31. Marked as the date table in Power BI. |

## Data-quality findings that shaped the model
1. **32 Product_IDs have more than one product name.** Joining on the ID alone would duplicate revenue, so a product is the pair of ID and name (1,894 products).
2. **One postal code appears with two city, state and region combinations**, so a location is the full combination (632 locations).
3. **Ship dates run to 5 January 2018**, so the date dimension extends to 31 January 2018. Otherwise the ship-date relationship would have orphans.

## Relationships (Power BI)
| From (many) | To (one) | Active |
|---|---|---|
| `fact_sales[customer_key]` | `dim_customer[customer_key]` | Yes |
| `fact_sales[product_key]` | `dim_product[product_key]` | Yes |
| `fact_sales[geo_key]` | `dim_geography[geo_key]` | Yes |
| `fact_sales[order_date_key]` | `dim_date[date_key]` | Yes |
| `fact_sales[ship_date_key]` | `dim_date[date_key]` | No (only one active relationship is allowed between two tables) |
| `customer_rfm[customer_key]` | `dim_customer[customer_key]` | Yes, one-to-one |

`cohort_retention`, `monthly_sales`, `forecast_next_3_months` and `Forecast Chart Data` (a DAX table that stacks actual sales and the forecast for the chart) stand alone.

## Integrity checks (after `star_schema.sql`)
9,994 fact rows, sales 2,297,200.86, profit 286,397.02, 793 customers, 1,894 products, 632 locations, 1,492 dates, and no fact row without a matching customer, product, location or order date.

## Derived tables
| Table | Built by | Purpose |
|---|---|---|
| `customer_rfm` | `rfm_segments.sql` | R, F and M scores (1 to 5, using NTILE) and the segment per customer |
| `cohort_activity`, `cohort_retention` | `cohort_retention.sql` | Customer-months by first-purchase cohort; retention % by cohort and month |
| `monthly_sales` | `forecast.sql` | 48 monthly sales totals |
| `forecast_test`, `forecast_backtest`, `forecast_next_3_months` | `forecast.sql` | Accuracy test, rolling backtest and the Q1 2018 forecast |

## RFM rules
Reference date is 2017-12-31 (the day after the last order). Recency is scored in reverse so a score of 5 is always best. Customer_ID breaks ties so scores repeat.

| Segment | Rule | Customers | Share of sales |
|---|---|---|---|
| New | first order in 2017 | 11 | 0.3% |
| Champions | recency 4-5 and frequency 4-5 | 165 | 29.1% |
| Loyal | recency 3-5 and frequency 3-5 | 164 | 23.5% |
| At Risk | recency 1-2 and frequency 3-5 | 146 | 21.6% |
| Promising | recency 3-5 and frequency 1-2 | 140 | 12.9% |
| Lost | recency 1-2 and frequency 1-2 | 167 | 12.5% |

Promising is a sixth segment added to cover recent customers with few orders, who would otherwise have no segment.

## Forecast method
Forecast = sales in the same month last year x growth, where growth = last 12 months of sales divided by the 12 months before.

| Method | Error on the last 3 months (MAPE) |
|---|---|
| 3-month moving average | 27.5% |
| Same month last year | 24.0% |
| Same month last year x growth | 21.7% |

A rolling backtest of the chosen method (22 forecasts, March 2016 to December 2017) gave a MAPE of 26.3%, with 68.2% of forecasts within 40% of the actual. The Q1 2018 range is therefore plus or minus 40%.

| Month | Forecast | Range |
|---|---|---|
| Jan 2018 | 52,922 | 31,753 to 74,091 |
| Feb 2018 | 24,434 | 14,660 to 34,208 |
| Mar 2018 | 70,856 | 42,514 to 99,198 |

## DAX measures
| Measure | Definition |
|---|---|
| Total Sales | `SUM(fact_sales[Sales])` |
| Total Profit | `SUM(fact_sales[Profit])` |
| Orders | `DISTINCTCOUNT(fact_sales[Order_ID])` |
| Customers | `DISTINCTCOUNT(fact_sales[customer_key])` |
| AOV | `DIVIDE([Total Sales], [Orders])` |
| Profit Margin % | `DIVIDE([Total Profit], [Total Sales])` |
| Sales LY | `CALCULATE([Total Sales], SAMEPERIODLASTYEAR(dim_date[full_date]))` |
| YoY % | `DIVIDE([Total Sales] - [Sales LY], [Sales LY])` |
| Repeat Customers | customers with more than one distinct order |
| Repeat Rate | `DIVIDE([Repeat Customers], [Customers])` |
| Segment Customers | `DISTINCTCOUNT(customer_rfm[customer_key])` |

Repeat Rate is calculated within the current filter, so it drops when a single region is selected (a customer's orders in other regions are not counted).
