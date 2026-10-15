# Customer & Sales Analytics: Multi-Table SQL, Segmentation, Forecast & Power BI Data Model

Level 2 data analyst capstone. A star-schema database, a library of labelled SQL queries, RFM customer segments, a cohort retention analysis, a 3-month sales forecast with measured accuracy, and a 3-page Power BI report.

**Author:** Vaishnavi B. Gawande | **Project reference:** SG/PRJ/DA-02
**Level 1 project:** [superstore-capstone](https://github.com/twinklegawande169-sketch/superstore-capstone) (data cleaning and the discount finding)

## Business questions
1. Who are our best customers, and how much of our sales do they bring?
2. Are we keeping customers, and where do we lose them?
3. What will the next quarter look like, and how far can we trust the forecast?

## Key findings
1. **Sales are growing and strongly seasonal.** Yearly sales rose from $484K (2014) to $733K (2017), up 20% in 2017. September, November and December are the strongest months every year, and Q4 brings in about 38% of all sales.
2. **Customers are loyal, but 22% of sales sit with customers who have gone quiet.** 98.5% of customers order again, about every 188 days. Champions and Loyal customers (329 people) bring 53% of sales. The 146 At Risk customers hold $495K (22%) and have not ordered for about 7 months. Only 11 customers were new in 2017.
3. **Deep discounts destroy profit.** Order lines discounted above 20% lost $135K, while undiscounted lines earned $321K. Central discounts the most (24% average) and has the lowest margin (7.9%, against 14.9% in West).

## Recommendations
1. Cap discounts at 20% and require approval above it, starting with Tables and the Central region.
2. Win back the 146 At Risk customers now, and follow up new customers within 60 days.
3. Plan stock and staff around September to December, and plan with a forecast range: Q1 2018 sales about $148K, likely between $89K and $207K.

The full one-page version is in [`docs/Manager_Summary.docx`](docs/Manager_Summary.docx).

## Data and model
Dataset: Sample Superstore, 2014-2017 (9,994 order lines, 5,009 orders, 793 customers), reshaped from the flat file into a star schema. I chose it because its customers buy repeatedly (781 of 793 reorder), which RFM and cohort analysis need.

| Table | One row per | Rows |
|---|---|---|
| `fact_sales` | order line | 9,994 |
| `dim_customer` | customer | 793 |
| `dim_product` | product (ID and name) | 1,894 |
| `dim_geography` | location | 632 |
| `dim_date` | day, 2014-01-01 to 2018-01-31 | 1,492 |

Derived tables: `customer_rfm`, `cohort_activity`, `cohort_retention`, `monthly_sales`, `forecast_test`, `forecast_backtest`, `forecast_next_3_months`. Keys, relationships, DAX measures and data-quality findings are in [`docs/MODEL_NOTES.md`](docs/MODEL_NOTES.md).

## Repo structure
```
├── README.md
├── sql/
│   ├── star_schema.sql        <- builds the fact and dimension tables, with integrity checks
│   ├── level2_queries.sql     <- 10 labelled queries: joins, HAVING, CTEs, window functions, subquery
│   ├── rfm_segments.sql       <- recency, frequency, monetary scores and 6 segments
│   ├── cohort_retention.sql   <- cohorts, retention, repeat rate, time between orders
│   └── forecast.sql           <- 3 methods, accuracy (MAPE), backtest, Q1 2018 forecast
├── powerbi/
│   └── Superstore_Level2_Report.pbix
├── docs/
│   ├── Manager_Summary.docx
│   └── MODEL_NOTES.md
└── screenshots/               <- data model, DAX reconciliation, 3 report pages, drill-through
```

## Power BI report
- **Page 1, Executive summary:** KPI cards, monthly sales line, profit by sub-category, year and region slicers.
- **Page 2, Customers:** RFM segment sales, cohort retention heatmap (2014 cohorts), segment slicer. Right-click a segment bar and drill through to the **Customer list** page.
- **Page 3, Products and forecast:** Q1 2018 forecast with its range, top 10 products by profit, yearly sales growth, region slicer.

## Checks (SQL against Power BI)
| Measure | SQL | Power BI |
|---|---|---|
| Sales | 2,297,200.86 | 2,297,200.86 |
| Profit | 286,397.02 | 286,397.02 |
| Orders | 5,009 | 5,009 |
| Customers | 793 | 793 |
| Repeat rate | 98.5% | 98.49% |

## How to reproduce
1. Load the cleaned Superstore data into a MySQL table called `orders` in a database called `superstore` (the import script and cleaned CSV are in the Level 1 repo above).
2. Run the scripts in `sql/` in this order: `star_schema.sql`, `level2_queries.sql`, `rfm_segments.sql`, `cohort_retention.sql`, `forecast.sql`. Each script states the result to expect.
3. Open `powerbi/Superstore_Level2_Report.pbix`. The report reads CSV exports of the MySQL tables, so if you move them, update the file paths in Power Query.

## Caveats
- This is a sample dataset, not live company data.
- Discounts and losses occur together. This shows correlation, not proven cause.
- 75% of customers (595 of 793) first ordered in 2014, so the cohort heatmap shows the 2014 cohorts only, and trends for new customers rest on few people.
- The forecast is the same month last year times 1.20 growth. It was off by 22% on the last 3 months and by 26% on average across 22 earlier months, so it is shown as a range of plus or minus 40%.

## Tools
MySQL (SQL and star schema), Power BI Desktop (data model, DAX, drill-through), Microsoft Excel (checks), Python (checks).
