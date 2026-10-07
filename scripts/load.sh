#!/usr/bin/env bash
# Create the schema and stream-load the generated files into StarRocks.
set -euo pipefail

cd "$(dirname "$0")/.."

FE_HTTP="${FE_HTTP:-http://127.0.0.1:8030}"
DATA_DIR="${DATA_DIR:-data}"
SQL() { docker exec -i starrocks mysql -h127.0.0.1 -P9030 -uroot "$@"; }

echo "Creating schema..."
SQL < sql/01_schema.sql

load() {
  local table="$1" file="$DATA_DIR/$1.csv" columns="$2"
  echo "Loading $table..."
  local resp
  resp=$(curl -s --location-trusted -u root: \
    -H "label:${table}_$(date +%s%N)" \
    -H "column_separator:|" \
    -H "columns:${columns}" \
    -H "Expect:100-continue" \
    -T "$file" \
    "$FE_HTTP/api/hvac_dw/${table}/_stream_load")
  echo "$resp" | grep -q '"Status": *"Success"' || { echo "$resp"; exit 1; }
  echo "$resp" | grep -E '"NumberLoadedRows"|"LoadTimeMs"' | tr -d ' ,'
}

load dim_date     "date_key,full_date,year,quarter,month,month_name,iso_week,day_of_week,day_name,is_weekend,fiscal_year"
load dim_branch   "branch_key,branch_name,region,state,opened_date"
load dim_product  "product_key,sku,product_name,category,subcategory,brand,unit_cost,list_price,is_active"
load dim_customer "customer_key,customer_name,segment,region,state,home_branch_key,credit_tier,customer_since"
load fact_sales   "sale_date,customer_key,order_id,line_number,date_key,product_key,branch_key,quantity,unit_price,discount_pct,net_amount,cost_amount"

echo "Collecting stats and building the materialized view..."
SQL -e "USE hvac_dw; ANALYZE FULL TABLE fact_sales; ANALYZE FULL TABLE dim_customer;" > /dev/null
SQL < sql/02_materialized_views.sql

echo "Done."
