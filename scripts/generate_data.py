#!/usr/bin/env python3
"""
Generate a synthetic HVAC parts distributor dataset for the StarRocks star schema demo.

Writes pipe-delimited files (no header) to ./data:
  dim_date.csv, dim_branch.csv, dim_product.csv, dim_customer.csv, fact_sales.csv

Standard library only. Deterministic for a given --seed.
"""
import argparse
import datetime as dt
import os
import random

START = dt.date(2023, 1, 1)
END = dt.date(2025, 12, 31)

REGIONS = {
    "Southeast": ["GA", "FL", "AL", "SC", "NC", "TN"],
    "South Central": ["TX", "OK", "LA", "AR"],
    "Mid-Atlantic": ["VA", "MD", "PA", "DE"],
    "Midwest": ["IL", "OH", "IN", "MI"],
    "Mountain West": ["CO", "UT", "AZ", "NV"],
}

# category -> (subcategories, (min_cost, max_cost), purchase weight, (min_qty, max_qty))
CATEGORIES = {
    "Equipment": (["Condensers", "Furnaces", "Air Handlers", "Heat Pumps", "Mini Splits"], (650, 4200), 0.10, (1, 3)),
    "Parts": (["Motors", "Capacitors", "Contactors", "Compressors", "Coils"], (8, 900), 0.38, (1, 12)),
    "Supplies": (["Refrigerant", "Line Sets", "Duct", "Filters", "Fittings"], (2, 180), 0.34, (2, 60)),
    "Controls": (["Thermostats", "Zoning", "Sensors"], (15, 350), 0.12, (1, 10)),
    "Tools": (["Gauges", "Vacuum Pumps", "Recovery Machines", "Hand Tools"], (10, 1400), 0.06, (1, 3)),
}

BRANDS = ["Arcticline", "Northwind Comfort", "Heliotemp", "Corvane", "Bluepeak", "Ridgeway Air", "Thermaxis", "Polaris Supply Co"]

SEGMENTS = [("Residential Contractor", 0.55), ("Commercial Contractor", 0.25),
            ("Builder", 0.12), ("Facilities / Government", 0.08)]
SEGMENT_DISCOUNT = {"Residential Contractor": 0.04, "Commercial Contractor": 0.08,
                    "Builder": 0.10, "Facilities / Government": 0.06}
CREDIT_TIERS = [("A", 0.35, 0.03), ("B", 0.45, 0.01), ("C", 0.20, 0.0)]  # tier, share, extra discount

NAME_A = ["Summit", "Precision", "Allied", "Comfort", "Coastal", "Frontier", "Liberty", "Ironwood",
          "Valley", "Keystone", "Cardinal", "Evergreen", "Pioneer", "Redline", "Blue Ridge", "Lakeshore"]
NAME_B = ["Heating & Air", "Mechanical", "HVAC", "Climate Services", "Air Systems", "Comfort Co",
          "Refrigeration", "Building Services"]

# HVAC sells hardest in summer, with a smaller heating bump in winter
MONTH_WEIGHT = [0.80, 0.75, 0.85, 0.95, 1.15, 1.40, 1.50, 1.45, 1.10, 0.90, 0.85, 0.95]
ANNUAL_GROWTH = 0.08


def write(path, rows):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for r in rows:
            fh.write("|".join(str(v) for v in r) + "\n")


def daterange(a, b):
    d = a
    while d <= b:
        yield d
        d += dt.timedelta(days=1)


def build_dates():
    rows = []
    for d in daterange(START, END):
        iso = d.isocalendar()
        rows.append((
            int(d.strftime("%Y%m%d")), d.isoformat(), d.year, (d.month - 1) // 3 + 1, d.month,
            d.strftime("%B"), iso[1], d.isoweekday(), d.strftime("%A"),
            1 if d.isoweekday() >= 6 else 0,
            d.year + 1 if d.month >= 10 else d.year,  # fiscal year starts in October
        ))
    return rows


def build_branches(rng, n):
    rows, by_region = [], {r: [] for r in REGIONS}
    regions = list(REGIONS)
    for k in range(1, n + 1):
        region = regions[(k - 1) % len(regions)]
        state = rng.choice(REGIONS[region])
        opened = START - dt.timedelta(days=rng.randint(200, 9000))
        rows.append((k, f"{state} Branch {k:03d}", region, state, opened.isoformat()))
        by_region[region].append(k)
    return rows, by_region


def build_products(rng, n):
    rows = []
    cats = list(CATEGORIES)
    weights = [CATEGORIES[c][2] for c in cats]
    for k in range(1, n + 1):
        cat = rng.choices(cats, weights)[0]
        subs, (lo, hi), _, _ = CATEGORIES[cat]
        sub = rng.choice(subs)
        brand = rng.choice(BRANDS)
        cost = round(rng.uniform(lo, hi), 2)
        markup = rng.uniform(1.22, 1.55)
        active = 0 if rng.random() < 0.06 else 1
        sku = f"{cat[:3].upper()}-{sub[:3].upper()}-{k:05d}"
        rows.append((k, sku, f"{brand} {sub[:-1] if sub.endswith('s') else sub} {k:05d}",
                     cat, sub, brand, f"{cost:.2f}", f"{cost * markup:.2f}", active))
    return rows


def build_customers(rng, n, branches_by_region, branch_state):
    rows = []
    segs, seg_w = zip(*SEGMENTS)
    tiers = [t[0] for t in CREDIT_TIERS]
    tier_w = [t[1] for t in CREDIT_TIERS]
    regions = list(REGIONS)
    for k in range(1, n + 1):
        region = rng.choice(regions)
        home = rng.choice(branches_by_region[region])
        seg = rng.choices(segs, seg_w)[0]
        tier = rng.choices(tiers, tier_w)[0]
        since = START - dt.timedelta(days=rng.randint(0, 6000))
        name = f"{rng.choice(NAME_A)} {rng.choice(NAME_B)} {k:05d}"
        rows.append((k, name, seg, region, branch_state[home], home, tier, since.isoformat()))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", type=int, default=2_000_000, help="approximate fact_sales line count")
    ap.add_argument("--customers", type=int, default=50_000)
    ap.add_argument("--products", type=int, default=5_000)
    ap.add_argument("--branches", type=int, default=120)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", default="data")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    os.makedirs(args.out, exist_ok=True)

    dates = build_dates()
    branches, branches_by_region = build_branches(rng, args.branches)
    branch_state = {b[0]: b[3] for b in branches}
    products = build_products(rng, args.products)
    customers = build_customers(rng, args.customers, branches_by_region, branch_state)

    write(os.path.join(args.out, "dim_date.csv"), dates)
    write(os.path.join(args.out, "dim_branch.csv"), branches)
    write(os.path.join(args.out, "dim_product.csv"), products)
    write(os.path.join(args.out, "dim_customer.csv"), customers)

    # Day weights: seasonality x growth, weekends are slow
    days = list(daterange(START, END))
    day_w = []
    for d in days:
        w = MONTH_WEIGHT[d.month - 1] * (1 + ANNUAL_GROWTH) ** (d.year - START.year)
        w *= 0.25 if d.isoweekday() >= 6 else 1.0
        day_w.append(w)

    # A few customers buy a lot (Pareto-ish)
    cust_w = [rng.paretovariate(1.3) for _ in customers]
    prod_w = [CATEGORIES[p[3]][2] * (0.2 if p[8] == 0 else 1.0) * rng.uniform(0.3, 1.7) for p in products]

    def cum(ws):
        out, s = [], 0.0
        for w in ws:
            s += w
            out.append(s)
        return out

    day_cw, cust_cw, prod_cw = cum(day_w), cum(cust_w), cum(prod_w)
    tier_extra = {t[0]: t[2] for t in CREDIT_TIERS}

    fact_path = os.path.join(args.out, "fact_sales.csv")
    lines_written, order_id = 0, 100_000_000
    batch = 20_000
    with open(fact_path, "w", encoding="utf-8", newline="\n") as fh:
        while lines_written < args.rows:
            order_days = rng.choices(days, cum_weights=day_cw, k=batch)
            order_custs = rng.choices(customers, cum_weights=cust_cw, k=batch)
            buf = []
            for d, c in zip(order_days, order_custs):
                order_id += 1
                seg, region, home, tier = c[2], c[3], c[5], c[6]
                branch = home if rng.random() < 0.85 else rng.choice(branches_by_region[region])
                n_lines = rng.choices([1, 2, 3, 4, 5, 6], [30, 25, 18, 12, 9, 6])[0]
                for ln, p in enumerate(rng.choices(products, cum_weights=prod_cw, k=n_lines), start=1):
                    qlo, qhi = CATEGORIES[p[3]][3]
                    qty = rng.randint(qlo, qhi)
                    disc = SEGMENT_DISCOUNT[seg] + tier_extra[tier] + rng.choice([0, 0, 0, 0.02, 0.05])
                    list_price, unit_cost = float(p[7]), float(p[6])
                    unit_price = round(list_price * (1 - disc), 2)
                    buf.append(
                        f"{d.isoformat()}|{c[0]}|{order_id}|{ln}|{d.strftime('%Y%m%d')}|{p[0]}|{branch}|"
                        f"{qty}|{unit_price:.2f}|{disc:.4f}|{qty * unit_price:.2f}|{qty * unit_cost:.2f}\n"
                    )
                    lines_written += 1
                if lines_written >= args.rows:
                    break
            fh.write("".join(buf))

    print(f"dim_date      {len(dates):>10,}")
    print(f"dim_branch    {len(branches):>10,}")
    print(f"dim_product   {len(products):>10,}")
    print(f"dim_customer  {len(customers):>10,}")
    print(f"fact_sales    {lines_written:>10,}")
    print(f"written to {args.out}")


if __name__ == "__main__":
    main()
