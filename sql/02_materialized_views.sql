USE hvac_dw;

-- Monthly sales rolled up by region, segment, and product category.
-- With query rewrite on (the default), dashboards that ask for these
-- grains hit the MV automatically. Nobody has to know it exists.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_monthly_sales
DISTRIBUTED BY HASH (region) BUCKETS 1
REFRESH ASYNC EVERY (INTERVAL 1 HOUR)
PROPERTIES ("replication_num" = "1")
AS
SELECT
    date_trunc('month', f.sale_date) AS sale_month,
    b.region,
    c.segment,
    p.category,
    SUM(f.net_amount)                AS revenue,
    SUM(f.cost_amount)               AS cost,
    SUM(f.quantity)                  AS units,
    COUNT(*)                         AS order_lines
FROM fact_sales f
JOIN dim_branch   b ON f.branch_key   = b.branch_key
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_product  p ON f.product_key  = p.product_key
GROUP BY 1, 2, 3, 4;

REFRESH MATERIALIZED VIEW mv_monthly_sales WITH SYNC MODE;
