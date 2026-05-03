# Olist E-Commerce Analysis Project

## Project Goal
Portfolio project for data analyst job applications.
Target audience: Technical recruiters and hiring managers at MNCs.
This project must look like professional, production-grade work.

## Tech Stack
- Database: PostgreSQL (local)
- SQL Client: psql via terminal
- Python: pandas, matplotlib, seaborn, plotly, streamlit
- Version Control: GitHub

## Quality Standards
- Every SQL file must have a business purpose comment at the top
- Every query output must be saved as markdown table in sql/outputs/
- Every chart must have title, axis labels, and a business insight caption
- All comments must explain WHY decisions were made, not just WHAT
- README must sound like a professional analyst, not a student
- All findings must include real numbers from the data

## Folder Structure
olist-ecommerce-analysis/
├── README.md
├── CLAUDE.md
├── requirements.txt
├── data/
│   ├── raw/          ← original CSVs
│   └── cleaned/      ← cleaned exports
├── sql/
│   ├── 01_schema_setup.sql
│   ├── 02_data_cleaning.sql
│   ├── 03_revenue_by_category.sql
│   ├── 04_delivery_vs_satisfaction.sql
│   ├── 05_rfm_segmentation.sql
│   ├── 06_seller_performance.sql
│   ├── 07_monthly_revenue_trend.sql
│   ├── 08_cohort_retention.sql
│   └── outputs/
│       ├── *.csv
│       └── *_preview.md
├── notebooks/
│   └── eda_analysis.ipynb
├── visuals/
│   └── *.png
├── dashboard/
│   └── dashboard.py
└── report/
    └── business_summary.md
