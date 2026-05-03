"""
Olist Marketplace Dashboard
===========================
Streamlit app that surfaces the six headline analyses interactively. Reads
straight from the CSV outputs in ../sql/outputs/ so it has zero database
dependency at runtime — just point and ship.

Run from project root:
    streamlit run dashboard/dashboard.py
"""
from __future__ import annotations

from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parents[1]
OUT  = ROOT / "sql" / "outputs"
VIS  = ROOT / "visuals"

st.set_page_config(
    page_title="Olist Marketplace · Analyst Dashboard",
    page_icon="📦",
    layout="wide",
    initial_sidebar_state="expanded",
)

PALETTE = {
    "primary": "#2E5BFF",
    "accent":  "#E8505B",
    "neutral": "#6C7A89",
    "success": "#27AE60",
    "muted":   "#B0BEC5",
}

@st.cache_data
def load(name: str) -> pd.DataFrame:
    return pd.read_csv(OUT / f"{name}.csv")

# ---------------------------------------------------------------------------
# Sidebar navigation
# ---------------------------------------------------------------------------
st.sidebar.title("📦 Olist Marketplace")
st.sidebar.caption("Senior-analyst breakdown · 2017-01 → 2018-08")

PAGE = st.sidebar.radio(
    "Section",
    [
        "🏠 Overview",
        "📈 Monthly trend",
        "🛒 Categories",
        "🚚 Delivery & satisfaction",
        "👥 Customer segments (RFM)",
        "🏪 Seller performance",
        "🔁 Cohort retention",
    ],
)

st.sidebar.markdown("---")
st.sidebar.markdown(
    "**Data:** Olist Brazilian E-Commerce dataset  \n"
    "**Stack:** PostgreSQL · pandas · plotly · streamlit  \n"
    "**Source SQL:** `sql/0X_*.sql`  \n"
    "**Source CSVs:** `sql/outputs/*.csv`"
)

# ---------------------------------------------------------------------------
# 0. Overview
# ---------------------------------------------------------------------------
if PAGE.startswith("🏠"):
    st.title("Olist Brazilian Marketplace — Analyst Dashboard")
    st.markdown(
        "A senior-analyst breakdown of **99,441 orders, 96,096 customers, and 3,095 sellers** "
        "transacted between January 2017 and August 2018. "
        "Use the sidebar to jump into any of the six headline analyses."
    )

    trend = load("07_monthly_revenue_trend").query("in_window == 't'")
    pareto = load("06a_seller_pareto")
    rfm    = load("05a_rfm_segments")
    ontime = load("04a_review_by_ontime")

    on_time_score = ontime.loc[ontime["delivery_status"] == "on_time", "avg_review_score"].iloc[0]
    late_score    = ontime.loc[ontime["delivery_status"] == "late",    "avg_review_score"].iloc[0]

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("In-window GMV (R$)",   f"{trend['gmv_brl'].sum()/1e6:.2f}M")
    c2.metric("Orders",               f"{int(trend['order_count'].sum()):,}")
    c3.metric("Avg review (on-time)", f"{on_time_score:.2f} ★")
    c4.metric("Avg review (late)",    f"{late_score:.2f} ★",
              delta=f"{late_score - on_time_score:.2f}",
              delta_color="inverse")

    st.markdown("---")
    st.subheader("Three findings that change the conversation")
    col1, col2, col3 = st.columns(3)
    with col1:
        st.markdown("### 🚚 The late-delivery cliff")
        st.markdown(
            "**4.29 ★** on-time → **2.57 ★** late.  \n"
            "By day +7 late, average review collapses to **1.91 ★** with 63% of customers leaving 1-star reviews. "
            "On-time rate matters more than delivery speed."
        )
    with col2:
        st.markdown("### 🏪 Seller concentration")
        top1 = pareto.loc[pareto["bucket"] == "Top 1%"].iloc[0]
        top1_sellers = int(top1["sellers"])
        top1_pct     = top1["pct_of_total_gmv"]
        st.markdown(
            f"**{top1_sellers} sellers (the top 1%)** generate **{top1_pct:.1f}%** of GMV.  \n"
            "Top 10% cumulative = **67%** of revenue. Bottom 50% = just 3.2%. "
            "A seller-success programme on the top 100 has more leverage than acquiring 1,000 new sellers."
        )
    with col3:
        st.markdown("### 🔁 The repeat-purchase crisis")
        hvl = rfm.loc[rfm["segment"] == "High-Value Lost"].iloc[0]
        hvl_n     = int(hvl["customers"])
        hvl_avg   = hvl["avg_lifetime_gmv"]
        hvl_score = hvl["avg_review_score"]
        st.markdown(
            "M+1 retention < 1% for every cohort.  \n"
            f"**High-Value Lost** segment: **{hvl_n:,}** customers, "
            f"R$ {hvl_avg:.0f} average lifetime spend, **{hvl_score:.2f} ★** review. "
            "They liked Olist and have not returned — biggest reactivation prize."
        )

# ---------------------------------------------------------------------------
# 1. Monthly trend
# ---------------------------------------------------------------------------
elif PAGE.startswith("📈"):
    st.title("📈 Monthly revenue trend")
    df = load("07_monthly_revenue_trend").copy()
    df["month_dt"]  = pd.to_datetime(df["month"])
    df["in_window"] = df["in_window"].map({"t": "In analysis window", "f": "Outside window (sparse)"})

    c1, c2 = st.columns([1, 3])
    show_outside = c1.checkbox("Show out-of-window months (Sept-2016 / Sept-Oct 2018)", False)
    metric = c1.selectbox("Metric", ["gmv_brl", "order_count", "unique_customers", "aov_brl", "items_sold"], index=0,
                          format_func=lambda s: {
                              "gmv_brl":          "GMV (R$)",
                              "order_count":      "Order count",
                              "unique_customers": "Unique customers",
                              "aov_brl":          "Average order value (R$)",
                              "items_sold":       "Items sold",
                          }[s])

    plot_df = df if show_outside else df[df["in_window"] == "In analysis window"]
    fig = px.line(plot_df, x="month_dt", y=metric, markers=True,
                  color_discrete_sequence=[PALETTE["primary"]])
    fig.update_traces(line_width=3)
    fig.update_layout(height=450, xaxis_title="", yaxis_title=metric, margin=dict(t=30))
    c2.plotly_chart(fig, use_container_width=True)

    st.markdown("### Month-by-month numbers")
    st.dataframe(
        df.assign(gmv_brl=lambda d: d["gmv_brl"].round(0)).drop(columns=["month_dt"]),
        use_container_width=True, hide_index=True,
    )

# ---------------------------------------------------------------------------
# 2. Categories
# ---------------------------------------------------------------------------
elif PAGE.startswith("🛒"):
    st.title("🛒 Revenue by category")
    df = load("03_revenue_by_category")
    n  = st.slider("Top N categories", 5, 40, 15)
    top = df.head(n).iloc[::-1]

    fig = px.bar(top, x="gmv_brl", y="category", orientation="h",
                 color="avg_review_score",
                 color_continuous_scale=["#E8505B", "#F4D35E", "#27AE60"],
                 range_color=[3.5, 4.6],
                 hover_data=["orders", "items_sold", "sellers_active",
                             "freight_pct_of_gmv", "on_time_pct"])
    fig.update_layout(height=max(450, n * 24),
                      xaxis_title="GMV (R$)", yaxis_title="",
                      coloraxis_colorbar=dict(title="Avg review"),
                      margin=dict(t=30))
    st.plotly_chart(fig, use_container_width=True)

    st.markdown("Bars colored red have **avg review < 4.0** — revenue-rich but quality-fragile.")
    st.dataframe(df, use_container_width=True, hide_index=True)

# ---------------------------------------------------------------------------
# 3. Delivery & satisfaction
# ---------------------------------------------------------------------------
elif PAGE.startswith("🚚"):
    st.title("🚚 The late-delivery cliff")

    ontime = load("04a_review_by_ontime")
    delay  = load("04b_review_by_delay_bucket")
    state  = load("04c_delivery_by_state")

    c1, c2 = st.columns([2, 1])
    with c1:
        st.subheader("Average review score by delivery delay")
        body = delay[(delay["delay_day_bucket"] > -30) & (delay["delay_day_bucket"] < 30)]
        fig = go.Figure()
        early = body[body["delay_day_bucket"] <= 0]
        late  = body[body["delay_day_bucket"] >  0]
        fig.add_trace(go.Scatter(x=early["delay_day_bucket"], y=early["avg_review_score"],
                                 mode="lines+markers", name="On time / early",
                                 line=dict(color=PALETTE["primary"], width=3)))
        fig.add_trace(go.Scatter(x=late["delay_day_bucket"], y=late["avg_review_score"],
                                 mode="lines+markers", name="Late",
                                 line=dict(color=PALETTE["accent"], width=3)))
        fig.add_vline(x=0, line_dash="dot", line_color="#444",
                      annotation_text="Promised date")
        fig.update_layout(height=450, xaxis_title="Days vs. promised date",
                          yaxis_title="Avg review score", yaxis_range=[1, 5],
                          margin=dict(t=30))
        st.plotly_chart(fig, use_container_width=True)
    with c2:
        st.subheader("Headline numbers")
        st.dataframe(ontime, hide_index=True, use_container_width=True)
        on_time_score = ontime.loc[ontime["delivery_status"] == "on_time", "avg_review_score"].iloc[0]
        late_score    = ontime.loc[ontime["delivery_status"] == "late",    "avg_review_score"].iloc[0]
        late_neg      = ontime.loc[ontime["delivery_status"] == "late",    "pct_negative"].iloc[0]
        st.markdown(
            f"- **{on_time_score:.2f} ★** when on-time  \n"
            f"- **{late_score:.2f} ★** when late  \n"
            f"- **{late_neg:.0f}%** of late orders → ≤2-star review"
        )

    st.markdown("---")
    st.subheader("Delivery performance by customer state")
    st.markdown("Sorted by average delivery days — the long lanes are where review damage concentrates.")
    fig2 = px.bar(state.sort_values("avg_delivery_days"),
                  x="avg_delivery_days", y="customer_state", orientation="h",
                  color="on_time_pct",
                  color_continuous_scale=["#E8505B", "#F4D35E", "#27AE60"],
                  range_color=[60, 100],
                  hover_data=["delivered_orders", "avg_estimated_days", "avg_review_score"])
    fig2.update_layout(height=750, xaxis_title="Avg delivery days", yaxis_title="State",
                       coloraxis_colorbar=dict(title="On-time %"))
    st.plotly_chart(fig2, use_container_width=True)

# ---------------------------------------------------------------------------
# 4. RFM segments
# ---------------------------------------------------------------------------
elif PAGE.startswith("👥"):
    st.title("👥 Customer segments (modified RFM)")
    rfm = load("05a_rfm_segments").sort_values("segment_total_gmv", ascending=False)
    total_customers = rfm["customers"].sum()

    repeat_segments = ["Champions", "Loyal", "At Risk Repeaters"]
    repeat_customers = int(rfm.loc[rfm["segment"].isin(repeat_segments), "customers"].sum())
    hvl_gmv = rfm.loc[rfm["segment"] == "High-Value Lost", "segment_total_gmv"].iloc[0]

    c1, c2, c3 = st.columns(3)
    c1.metric("Customers segmented", f"{total_customers:,}")
    c2.metric("Repeat customers (≥ 2 orders)", f"{repeat_customers:,}")
    c3.metric("High-Value Lost segment GMV", f"R$ {hvl_gmv/1e6:.2f}M")

    fig = px.bar(rfm, x="segment_total_gmv", y="segment", orientation="h",
                 color="avg_review_score",
                 color_continuous_scale=["#E8505B", "#F4D35E", "#27AE60"],
                 range_color=[1, 5],
                 hover_data=["customers", "pct_of_base", "avg_lifetime_gmv",
                             "avg_recency_days", "avg_orders"])
    fig.update_layout(height=500, xaxis_title="Segment GMV (R$)", yaxis_title="",
                      coloraxis_colorbar=dict(title="Avg review"),
                      margin=dict(t=30))
    st.plotly_chart(fig, use_container_width=True)

    st.markdown(
        "**Reactivation priority order:**\n"
        "1. **High-Value Lost** (11,950 customers, 4.58 ★, R$ 272 avg) — they liked Olist and disappeared. Biggest prize.\n"
        "2. **High-Value Burnt** (2,139 customers, 1.20 ★, R$ 305 avg) — angry but spent. Fix the operational complaint first, then reach out.\n"
        "3. **Champions** (985 customers, 4.20 ★, 2.2 orders avg) — keep them. Cheap to retain, expensive to replace."
    )
    st.dataframe(rfm, use_container_width=True, hide_index=True)

# ---------------------------------------------------------------------------
# 5. Seller performance
# ---------------------------------------------------------------------------
elif PAGE.startswith("🏪"):
    st.title("🏪 Seller performance")
    pareto = load("06a_seller_pareto")
    top    = load("06b_top_sellers")
    risk   = load("06c_risk_sellers")

    st.subheader("Concentration: 30 sellers carry 26% of GMV")
    order = ["Top 1%", "Top 5%", "Top 10%", "Top 25%", "Top 50%", "Bottom 50%"]
    pareto["bucket"] = pd.Categorical(pareto["bucket"], order, ordered=True)
    pareto = pareto.sort_values("bucket")
    fig = px.bar(pareto, x="bucket", y="pct_of_total_gmv",
                 color="bucket",
                 color_discrete_sequence=["#E8505B", "#F4A261", "#F4D35E",
                                          "#A8DADC", "#2E5BFF", "#B0BEC5"],
                 text="sellers")
    fig.update_layout(height=400, yaxis_title="% of total GMV", xaxis_title="",
                      showlegend=False, margin=dict(t=30))
    fig.update_traces(texttemplate="%{text} sellers", textposition="outside")
    st.plotly_chart(fig, use_container_width=True)

    c1, c2 = st.columns(2)
    with c1:
        st.subheader("Top 25 sellers by GMV")
        st.dataframe(top.head(25), use_container_width=True, hide_index=True)
    with c2:
        st.subheader(f"Risk sellers (top quartile + quality issues): {len(risk)}")
        st.markdown(
            "Top-revenue sellers whose review score < 4.0 or on-time rate < 85%. "
            "These are the accounts where a seller-success conversation is most urgent."
        )
        st.dataframe(risk.head(25), use_container_width=True, hide_index=True)

# ---------------------------------------------------------------------------
# 6. Cohort retention
# ---------------------------------------------------------------------------
elif PAGE.startswith("🔁"):
    st.title("🔁 Cohort retention")
    pivot = load("08b_cohort_retention_pivot").set_index("cohort")
    matrix = pivot[["m1_pct", "m2_pct", "m3_pct", "m6_pct", "m9_pct", "m12_pct"]]
    matrix.columns = ["M+1", "M+2", "M+3", "M+6", "M+9", "M+12"]

    fig = px.imshow(
        matrix,
        labels=dict(x="Months since first purchase", y="Acquisition cohort", color="Retention %"),
        x=matrix.columns, y=matrix.index,
        color_continuous_scale="Reds",
        zmin=0, zmax=1.5,
        text_auto=".2f",
        aspect="auto",
    )
    fig.update_layout(height=700, margin=dict(t=30))
    st.plotly_chart(fig, use_container_width=True)

    st.markdown(
        "**Reading the heatmap:** every value is below 1.5%, and most are below 0.5%. "
        "Olist customers are not coming back — the marketplace is a single-purchase funnel. "
        "Until M+1 retention crosses ~5%, growth will remain entirely acquisition-driven."
    )

    st.subheader("Per-cohort, per-month retention (long format)")
    long = load("08a_cohort_retention")
    st.dataframe(long, use_container_width=True, hide_index=True)
