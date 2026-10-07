USE hvac_dw;

-- Q1. Revenue and gross margin by region and year (4-way join)
SELECT
    d.year,
    b.region,
    ROUND(SUM(f.net_amount), 2)                                    AS revenue,
    ROUND(SUM(f.net_amount - f.cost_amount) / SUM(f.net_amount), 4) AS gross_margin
FROM fact_sales f
JOIN dim_date   d ON f.date_key   = d.date_key
JOIN dim_branch b ON f.branch_key = b.branch_key
GROUP BY d.year, b.region
ORDER BY d.year, revenue DESC;

-- Q2. Seasonality: monthly revenue by category for one year
--     (partition pruning keeps this to 12 of 36 partitions)
SELECT
    date_trunc('month', f.sale_date) AS sale_month,
    p.category,
    ROUND(SUM(f.net_amount), 2)      AS revenue
FROM fact_sales f
JOIN dim_product p ON f.product_key = p.product_key
WHERE f.sale_date >= '2025-01-01' AND f.sale_date < '2026-01-01'
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-- Q3. Top 10 customers by 2025 revenue, with YoY growth
--     (colocated join to dim_customer, no shuffle)
WITH yearly AS (
    SELECT
        f.customer_key,
        SUM(CASE WHEN f.sale_date >= '2025-01-01' THEN f.net_amount ELSE 0 END) AS rev_2025,
        SUM(CASE WHEN f.sale_date <  '2025-01-01' THEN f.net_amount ELSE 0 END) AS rev_2024
    FROM fact_sales f
    WHERE f.sale_date >= '2024-01-01' AND f.sale_date < '2026-01-01'
    GROUP BY f.customer_key
)
SELECT
    c.customer_name,
    c.segment,
    c.region,
    ROUND(y.rev_2025, 2)                                    AS rev_2025,
    ROUND((y.rev_2025 - y.rev_2024) / NULLIF(y.rev_2024, 0), 4) AS yoy_growth
FROM yearly y
JOIN dim_customer c ON y.customer_key = c.customer_key
ORDER BY y.rev_2025 DESC
LIMIT 10;

-- Q4. Customer concentration: what share of revenue comes from the top 1%, 5%, 20%?
WITH cust AS (
    SELECT customer_key, SUM(net_amount) AS revenue
    FROM fact_sales
    GROUP BY customer_key
),
ranked AS (
    SELECT
        revenue,
        PERCENT_RANK() OVER (ORDER BY revenue DESC) AS pct_rank
    FROM cust
)
SELECT
    ROUND(SUM(CASE WHEN pct_rank <= 0.01 THEN revenue END) / SUM(revenue), 4) AS top_1pct_share,
    ROUND(SUM(CASE WHEN pct_rank <= 0.05 THEN revenue END) / SUM(revenue), 4) AS top_5pct_share,
    ROUND(SUM(CASE WHEN pct_rank <= 0.20 THEN revenue END) / SUM(revenue), 4) AS top_20pct_share
FROM ranked;

-- Q5. Branch scorecard: revenue, margin, and rank within region
SELECT
    b.region,
    b.branch_name,
    ROUND(SUM(f.net_amount), 2)                                     AS revenue,
    ROUND(SUM(f.net_amount - f.cost_amount) / SUM(f.net_amount), 4) AS gross_margin,
    RANK() OVER (PARTITION BY b.region ORDER BY SUM(f.net_amount) DESC) AS rank_in_region
FROM fact_sales f
JOIN dim_branch b ON f.branch_key = b.branch_key
WHERE f.sale_date >= '2025-01-01'
GROUP BY b.region, b.branch_name
ORDER BY b.region, rank_in_region
LIMIT 25;

-- Q6. Discount leakage: margin by segment and credit tier
SELECT
    c.segment,
    c.credit_tier,
    ROUND(AVG(f.discount_pct), 4)                                   AS avg_discount,
    ROUND(SUM(f.net_amount - f.cost_amount) / SUM(f.net_amount), 4) AS gross_margin,
    ROUND(SUM(f.net_amount), 2)                                     AS revenue
FROM fact_sales f
JOIN dim_customer c ON f.customer_key = c.customer_key
GROUP BY c.segment, c.credit_tier
ORDER BY c.segment, c.credit_tier;

-- Q7. Hits the materialized view through automatic rewrite.
--     Run EXPLAIN on it and look for mv_monthly_sales in the plan.
SELECT
    date_trunc('month', f.sale_date) AS sale_month,
    b.region,
    ROUND(SUM(f.net_amount), 2)      AS revenue
FROM fact_sales f
JOIN dim_branch   b ON f.branch_key   = b.branch_key
JOIN dim_customer c ON f.customer_key = c.customer_key
JOIN dim_product  p ON f.product_key  = p.product_key
GROUP BY 1, 2
ORDER BY 1, 2;
