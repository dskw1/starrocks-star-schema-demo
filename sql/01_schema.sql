-- Star schema for a fictional HVAC parts distributor.
-- One fact table (order lines) and four conformed dimensions.

CREATE DATABASE IF NOT EXISTS hvac_dw;
USE hvac_dw;

-- ---------------------------------------------------------------
-- Dimensions
-- Small dims get one bucket. The optimizer broadcasts them to every
-- fact tablet at join time, so there's no shuffle of the big table.
-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_date (
    date_key      INT          NOT NULL,
    full_date     DATE         NOT NULL,
    year          SMALLINT     NOT NULL,
    quarter       TINYINT      NOT NULL,
    month         TINYINT      NOT NULL,
    month_name    VARCHAR(12)  NOT NULL,
    iso_week      TINYINT      NOT NULL,
    day_of_week   TINYINT      NOT NULL,
    day_name      VARCHAR(12)  NOT NULL,
    is_weekend    BOOLEAN      NOT NULL,
    fiscal_year   SMALLINT     NOT NULL
)
PRIMARY KEY (date_key)
DISTRIBUTED BY HASH (date_key) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS dim_branch (
    branch_key    INT          NOT NULL,
    branch_name   VARCHAR(64)  NOT NULL,
    region        VARCHAR(32)  NOT NULL,
    state         CHAR(2)      NOT NULL,
    opened_date   DATE
)
PRIMARY KEY (branch_key)
DISTRIBUTED BY HASH (branch_key) BUCKETS 1
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS dim_product (
    product_key   INT           NOT NULL,
    sku           VARCHAR(32)   NOT NULL,
    product_name  VARCHAR(128)  NOT NULL,
    category      VARCHAR(32)   NOT NULL,
    subcategory   VARCHAR(32)   NOT NULL,
    brand         VARCHAR(32)   NOT NULL,
    unit_cost     DECIMAL(12,2) NOT NULL,
    list_price    DECIMAL(12,2) NOT NULL,
    is_active     BOOLEAN       NOT NULL
)
PRIMARY KEY (product_key)
DISTRIBUTED BY HASH (product_key) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- dim_customer is the one dimension big enough to matter (50K rows by
-- default). It's colocated with fact_sales on customer_key, so the
-- customer join runs locally on each tablet with no network shuffle.
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_key     INT          NOT NULL,
    customer_name    VARCHAR(128) NOT NULL,
    segment          VARCHAR(32)  NOT NULL,
    region           VARCHAR(32)  NOT NULL,
    state            CHAR(2)      NOT NULL,
    home_branch_key  INT          NOT NULL,
    credit_tier      CHAR(1)      NOT NULL,
    customer_since   DATE
)
PRIMARY KEY (customer_key)
DISTRIBUTED BY HASH (customer_key) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "colocate_with"   = "grp_customer"
);

-- ---------------------------------------------------------------
-- Fact: one row per order line
-- * Monthly partitions, so date filters prune whole partitions.
-- * Sort key (sale_date, customer_key) keeps the zone maps tight
--   for the most common filters.
-- * Same bucket column and count as dim_customer for colocation.
-- ---------------------------------------------------------------

CREATE TABLE IF NOT EXISTS fact_sales (
    sale_date     DATE          NOT NULL,
    customer_key  INT           NOT NULL,
    order_id      BIGINT        NOT NULL,
    line_number   TINYINT       NOT NULL,
    date_key      INT           NOT NULL,
    product_key   INT           NOT NULL,
    branch_key    INT           NOT NULL,
    quantity      INT           NOT NULL,
    unit_price    DECIMAL(12,2) NOT NULL,
    discount_pct  DECIMAL(6,4)  NOT NULL,
    net_amount    DECIMAL(14,2) NOT NULL,
    cost_amount   DECIMAL(14,2) NOT NULL
)
DUPLICATE KEY (sale_date, customer_key, order_id)
PARTITION BY date_trunc('month', sale_date)
DISTRIBUTED BY HASH (customer_key) BUCKETS 8
PROPERTIES (
    "replication_num" = "1",
    "colocate_with"   = "grp_customer"
);

-- ---------------------------------------------------------------
-- Foreign keys aren't enforced, but declaring them lets the optimizer
-- drop joins it doesn't need (e.g. a join to dim_date that only
-- filters on a column the fact already has).
-- ---------------------------------------------------------------
ALTER TABLE fact_sales SET (
    "foreign_key_constraints" = "(date_key) REFERENCES dim_date(date_key);(product_key) REFERENCES dim_product(product_key);(branch_key) REFERENCES dim_branch(branch_key);(customer_key) REFERENCES dim_customer(customer_key)"
);
