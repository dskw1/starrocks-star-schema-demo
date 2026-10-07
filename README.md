# StarRocks Star Schema Demo

A small, runnable data warehouse on [StarRocks](https://www.starrocks.io/) for a fictional HVAC parts distributor. One fact table, four dimensions, 2 million order lines, and a set of analytical queries that join across all of it. Run `scripts/benchmark.sh` to time them on your machine.

It's built to show the modeling and physical design choices I'd make on a real MPP warehouse, not just the SQL.

## Quick start

You need Docker and Python 3. No other dependencies.

```bash
docker compose up -d                 # StarRocks FE + BE in one container
python3 scripts/generate_data.py     # ~2M fact rows, takes a minute or so
bash scripts/load.sh                 # schema, stream load, stats, MV
bash scripts/benchmark.sh            # run the queries and time them
```

Connect with any MySQL client to run queries yourself:

```bash
mysql -h127.0.0.1 -P9030 -uroot hvac_dw
```

Want more data? `python3 scripts/generate_data.py --rows 20000000` works fine, it just takes longer to generate and load.

## The model

```
                 dim_date
                    |
dim_product --- fact_sales --- dim_branch
                    |
               dim_customer
```

| Table | Grain | Default rows |
|---|---|---|
| `fact_sales` | one order line | 2,000,000 |
| `dim_customer` | one contractor account | 50,000 |
| `dim_product` | one SKU | 5,000 |
| `dim_date` | one calendar day (2023-2025) | 1,096 |
| `dim_branch` | one branch location | 120 |

The data isn't uniform random. It has summer-heavy seasonality, 8% annual growth, slow weekends, a Pareto spread where a small share of contractors buy most of the volume, and discounts that vary by segment and credit tier. That gives the queries something real to find.

## Design choices

**Colocated join on the biggest dimension.** `fact_sales` and `dim_customer` are both hash-distributed on `customer_key` with the same bucket count and share a colocation group. The customer join runs locally on each tablet with no network shuffle. In a multi-node cluster this is the difference between moving the fact table across the network and not moving it at all.

**Broadcast for the small dimensions.** Date, branch, and product are tiny, so they sit in a single bucket and the optimizer broadcasts them to every fact tablet. No reason to over-engineer those.

**Monthly expression partitioning.** `PARTITION BY date_trunc('month', sale_date)` creates partitions automatically on load. A query filtered to 2025 reads 12 of 36 partitions.

**Sort key that matches the filters.** The duplicate key `(sale_date, customer_key, order_id)` keeps zone maps tight for date range and customer lookups.

**Declared foreign keys.** They aren't enforced, but they tell the optimizer the joins are lossless, which lets it eliminate joins a query doesn't actually need.

**Async materialized view with transparent rewrite.** `mv_monthly_sales` pre-aggregates revenue by month, region, segment, and category. Queries at that grain get rewritten to hit the MV automatically. Dashboards don't need to know it exists.

**Stats before querying.** `ANALYZE FULL TABLE` runs after load so the cost-based optimizer picks join order and strategy from real cardinalities.

## The queries

All in [`sql/03_queries.sql`](sql/03_queries.sql):

1. Revenue and gross margin by region and year
2. Monthly seasonality by category (shows partition pruning)
3. Top 10 customers with YoY growth (colocated join)
4. Revenue concentration in the top 1%, 5%, and 20% of customers
5. Branch scorecard with rank inside each region
6. Discount leakage by segment and credit tier
7. A query that gets rewritten to the materialized view

To see what the optimizer did, prefix any of them with `EXPLAIN`. Look for `COLOCATE` on the customer join, `BROADCAST` on the small dims, `partitions=12/36` on Q2, and `mv_monthly_sales` as the scan target on Q7.

## Repo layout

```
docker-compose.yml           StarRocks all-in-one container
scripts/generate_data.py     synthetic data generator (stdlib only)
scripts/load.sh              schema + stream load + stats + MV
scripts/benchmark.sh         times each query
sql/01_schema.sql            tables, distribution, partitioning, FKs
sql/02_materialized_views.sql
sql/03_queries.sql
```

## Clean up

```bash
docker compose down -v
rm -rf data/
```

All data is synthetic. Company, customer, and brand names are made up.
