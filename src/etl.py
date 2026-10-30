import pandas as pd
from sqlalchemy import create_engine
import os

print("--- Starting ETL Pipeline ---")

# 1. Load CSVs from data/
print("1. Loading raw CSV files...")
orders = pd.read_csv("data/olist_orders_dataset.csv")
items = pd.read_csv("data/olist_order_items_dataset.csv")
payments = pd.read_csv("data/olist_order_payments_dataset.csv")
reviews = pd.read_csv("data/olist_order_reviews_dataset.csv")
customers = pd.read_csv("data/olist_customers_dataset.csv")

# 2. Datetime parsing & handling missing delivery dates
print("2. Parsing timestamps and cleaning records...")
date_cols = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]
for col in date_cols:
    orders[col] = pd.to_datetime(orders[col])

# Filter out orders marked 'delivered' that lack an actual delivery date
orders = orders[
    ~(
        (orders["order_status"] == "delivered")
        & (orders["order_delivered_customer_date"].isna())
    )
]

# Calculate delivery delay vs promise date (positive = late, negative = early)
orders["delivery_delay_days"] = (
    orders["order_delivered_customer_date"]
    - orders["order_estimated_delivery_date"]
).dt.total_seconds() / 86400.0

# 3. Aggregate item, payment, and review metrics per order
print("3. Aggregating order items, payments, and reviews...")
item_agg = items.groupby("order_id").agg(
    total_freight=("freight_value", "sum"),
    total_item_value=("price", "sum"),
    item_count=("order_item_id", "count"),
).reset_index()

payment_agg = payments.groupby("order_id").agg(
    total_payment=("payment_value", "sum")
).reset_index()

review_agg = reviews.groupby("order_id").agg(
    review_score=("review_score", "mean")
).reset_index()

# 4. Build Fact Table
print("4. Merging star schema fact table...")
fact_orders = (
    orders.merge(item_agg, on="order_id", how="left")
    .merge(payment_agg, on="order_id", how="left")
    .merge(review_agg, on="order_id", how="left")
)

# 5. Export SQLite Database and Analytical CSV
print("5. Exporting SQLite database and flat analytical CSV...")
engine = create_engine("sqlite:///data/ecommerce_olap.db")
fact_orders.to_sql("fact_orders", engine, if_exists="replace", index=False)
customers.to_sql("dim_customers", engine, if_exists="replace", index=False)

export_df = fact_orders.merge(customers, on="customer_id", how="left")
export_df.to_csv("data/cleaned_orders_analytical.csv", index=False)

print("--- ETL Pipeline Completed Successfully! ---")
print("Generated:")
print(" - data/ecommerce_olap.db (SQLite Database)")
print(" - data/cleaned_orders_analytical.csv (Clean analytical file for Power BI / Tableau)")
