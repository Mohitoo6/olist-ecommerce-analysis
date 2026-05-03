# Raw data

The 9 source CSVs are excluded from version control (the geolocation file alone is 58MB and the directory totals ~120MB).

## How to populate this folder

Download the **Brazilian E-Commerce Public Dataset by Olist** from Kaggle and unzip into this directory:

- Kaggle: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Direct CLI:
  ```bash
  pip install kaggle  # one-time
  kaggle datasets download -d olistbr/brazilian-ecommerce -p data/raw --unzip
  ```

After unzip you should have these 9 files:

| File | Rows | Size |
|---|---:|---:|
| `olist_customers_dataset.csv`              | 99,441 | 8.6M |
| `olist_geolocation_dataset.csv`            | 1,000,163 | 58M |
| `olist_order_items_dataset.csv`            | 112,650 | 15M |
| `olist_order_payments_dataset.csv`         | 103,886 | 5.5M |
| `olist_order_reviews_dataset.csv`          | 99,224 | 14M |
| `olist_orders_dataset.csv`                 | 99,441 | 17M |
| `olist_products_dataset.csv`               | 32,951 | 2.3M |
| `olist_sellers_dataset.csv`                | 3,095 | 172K |
| `product_category_name_translation.csv`    | 71 | 4.0K |

Once present, run `psql -d olist -f sql/load_data.sql` from the project root to bulk-load all 9 tables.
