"""
build_visuals.py
================
Renders every chart used in the README, business report, and dashboard from
the CSV outputs in ../sql/outputs/. Each chart has:
  * a clear title that names the finding (not just the variable),
  * axis labels with units,
  * a caption underneath summarising the business takeaway in one sentence.

Run from project root:  python visuals/build_visuals.py
"""
from __future__ import annotations

import os
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns

ROOT = Path(__file__).resolve().parents[1]
OUT  = ROOT / "sql" / "outputs"
VIS  = ROOT / "visuals"
VIS.mkdir(exist_ok=True)

# Visual identity — calm but professional. Avoids matplotlib defaults so
# stakeholders don't see "intern dashboard" colors.
sns.set_theme(style="whitegrid", context="talk", font_scale=0.85)
PALETTE = {
    "primary":   "#2E5BFF",   # confident blue
    "accent":    "#E8505B",   # warning red
    "neutral":   "#6C7A89",
    "success":   "#27AE60",
    "muted":     "#B0BEC5",
}
plt.rcParams.update({
    "figure.dpi": 110,
    "savefig.dpi": 160,
    "savefig.bbox": "tight",
    "axes.titleweight": "bold",
    "axes.titlepad": 14,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.labelweight": "regular",
    # DejaVu Sans ships with matplotlib and renders the ★ glyph reliably,
    # unlike Arial (the seaborn 'talk' default on macOS).
    "font.family": "DejaVu Sans",
})

def _caption(fig, text: str) -> None:
    """Place a one-line italic caption under the chart."""
    fig.text(0.02, -0.04, text, ha="left", va="top",
             fontsize=10, style="italic", color=PALETTE["neutral"])

def _save(fig, name: str) -> None:
    path = VIS / f"{name}.png"
    fig.savefig(path)
    plt.close(fig)
    print(f"  wrote {path.relative_to(ROOT)}")

# ---------------------------------------------------------------------------
# 1. The late-delivery cliff — THE headline chart of the project.
# ---------------------------------------------------------------------------
def chart_delivery_cliff() -> None:
    df = pd.read_csv(OUT / "04b_review_by_delay_bucket.csv")
    # Drop the -30 and 30 caps from the line chart for a cleaner cliff —
    # they're aggregations, not single days.
    body = df[(df["delay_day_bucket"] > -30) & (df["delay_day_bucket"] < 30)]

    fig, ax = plt.subplots(figsize=(11, 5.6))
    # Color the early-delivery section blue, late section red.
    early = body[body["delay_day_bucket"] <= 0]
    late  = body[body["delay_day_bucket"] >  0]

    ax.plot(early["delay_day_bucket"], early["avg_review_score"],
            color=PALETTE["primary"], lw=2.5, marker="o", ms=4,
            label="On time / early")
    ax.plot(late["delay_day_bucket"], late["avg_review_score"],
            color=PALETTE["accent"], lw=2.5, marker="o", ms=4,
            label="Late")

    # Annotate the cliff itself.
    ax.axvline(0, color="#444", lw=1, ls=":", alpha=0.6)
    ax.annotate(
        "Day 0 → Day 4:\nreview drops 4.03 → 2.50",
        xy=(4, 2.50), xytext=(8, 3.6),
        fontsize=11, color=PALETTE["accent"], fontweight="bold",
        arrowprops=dict(arrowstyle="->", color=PALETTE["accent"], lw=1.5),
    )
    ax.annotate("Promised date",
                xy=(0, 4.5), xytext=(-12, 4.65),
                fontsize=10, color="#444",
                arrowprops=dict(arrowstyle="->", color="#444", lw=1))

    ax.set_xlim(-30, 30)
    ax.set_ylim(1, 5)
    ax.set_xlabel("Days late vs. promised delivery date  (negative = delivered early)")
    ax.set_ylabel("Average review score (1–5 stars)")
    ax.set_title("The late-delivery cliff: one missed day collapses a 4.3-star order to 2.5 stars")
    ax.legend(loc="lower left", frameon=True, framealpha=0.92)

    _caption(fig,
        "Each point = average review for orders delivered N days vs. the date promised at checkout. "
        "Source: 95,560 in-window delivered orders · 2017-01 → 2018-08."
    )
    _save(fig, "01_delivery_cliff")

# ---------------------------------------------------------------------------
# 2. On-time vs late headline (single bar).
# ---------------------------------------------------------------------------
def chart_ontime_vs_late() -> None:
    df = pd.read_csv(OUT / "04a_review_by_ontime.csv")

    fig, ax = plt.subplots(figsize=(8, 5.2))
    bars = ax.bar(df["delivery_status"], df["avg_review_score"],
                  color=[PALETTE["success"] if s == "on_time" else PALETTE["accent"]
                         for s in df["delivery_status"]],
                  edgecolor="white", lw=1.5, width=0.55)
    for b, val, n, neg in zip(bars, df["avg_review_score"], df["orders"], df["pct_negative"]):
        ax.text(b.get_x() + b.get_width() / 2, val + 0.08,
                f"{val:.2f}★\n{n:,} orders\n{neg}% ≤ 2 stars",
                ha="center", va="bottom", fontsize=11, fontweight="bold")
    ax.set_ylim(0, 5.4)
    ax.set_ylabel("Average review score")
    ax.set_xlabel("")
    ax.set_xticks(range(len(df)))
    ax.set_xticklabels(["On time", "Late"])
    ax.set_title("A single missed promise costs Olist 1.7 stars on average")
    _caption(fig,
        "On-time orders convert to 4.29-star reviews; late orders collapse to 2.57. "
        "54% of late deliveries trigger a ≤2-star review."
    )
    _save(fig, "02_ontime_vs_late")

# ---------------------------------------------------------------------------
# 3. Seller Pareto concentration.
# ---------------------------------------------------------------------------
def chart_seller_pareto() -> None:
    df = pd.read_csv(OUT / "06a_seller_pareto.csv")
    # The CSV has *exclusive* bands ("Top 5%" excludes "Top 1%"). For the
    # cumulative chart we want them stacked.
    order = ["Top 1%", "Top 5%", "Top 10%", "Top 25%", "Top 50%", "Bottom 50%"]
    df["bucket"] = pd.Categorical(df["bucket"], order, ordered=True)
    df = df.sort_values("bucket")
    df["cumulative_pct"] = df["pct_of_total_gmv"].cumsum()

    fig, ax = plt.subplots(figsize=(10, 5.4))
    bars = ax.bar(df["bucket"].astype(str), df["pct_of_total_gmv"],
                  color=[PALETTE["accent"], "#F4A261", "#F4D35E",
                         "#A8DADC", PALETTE["primary"], PALETTE["muted"]],
                  edgecolor="white", lw=1.5)
    for b, pct, sellers in zip(bars, df["pct_of_total_gmv"], df["sellers"]):
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 0.6,
                f"{pct:.1f}%\n({sellers:,} sellers)",
                ha="center", va="bottom", fontsize=10, fontweight="bold")
    ax.set_ylim(0, 32)
    ax.set_ylabel("Share of total GMV (%)")
    ax.set_title("30 sellers (1% of the marketplace) generate 26% of Olist's GMV")
    _caption(fig,
        "The top 10% of sellers (306 cumulative) drive 67% of revenue. "
        "Concentration risk is real — strategic seller-success investment is justified."
    )
    _save(fig, "03_seller_pareto")

# ---------------------------------------------------------------------------
# 4. RFM segment treemap-style horizontal bar.
# ---------------------------------------------------------------------------
def chart_rfm_segments() -> None:
    df = pd.read_csv(OUT / "05a_rfm_segments.csv").sort_values("segment_total_gmv", ascending=True)

    color_map = {
        "Champions":          PALETTE["success"],
        "Loyal":              "#52B788",
        "At Risk Repeaters":  "#F4A261",
        "New & Promising":    PALETTE["primary"],
        "Recent One-Timers":  "#90CAF9",
        "Need Attention":     "#FFB74D",
        "Hibernating":        PALETTE["muted"],
        "High-Value Lost":    "#E76F51",
        "High-Value Burnt":   PALETTE["accent"],
    }
    fig, ax = plt.subplots(figsize=(11, 6))
    bars = ax.barh(df["segment"],
                   df["segment_total_gmv"] / 1e6,
                   color=[color_map.get(s, PALETTE["primary"]) for s in df["segment"]],
                   edgecolor="white", lw=1.5)
    for b, gmv, custs, share, score in zip(bars, df["segment_total_gmv"]/1e6,
                                            df["customers"], df["segment_share_of_gmv"],
                                            df["avg_review_score"]):
        ax.text(b.get_width() + 0.06, b.get_y() + b.get_height()/2,
                f"R$ {gmv:.2f}M  ·  {custs:,} customers  ·  {share}% GMV  ·  {score:.1f}★",
                va="center", fontsize=10)
    ax.set_xlabel("Lifetime GMV (R$ millions)")
    ax.set_xlim(0, df["segment_total_gmv"].max()/1e6 * 1.45)
    ax.set_title("RFM segments — High-Value Lost is the biggest reactivation prize (R$3.25M)")
    _caption(fig,
        "11,950 customers with R$272 average lifetime spend and a 4.58★ history have gone dark. "
        "2,139 'Burnt' customers spent R$305 each but rated 1.20★ — angry, lost, and currently un-targeted."
    )
    _save(fig, "04_rfm_segments")

# ---------------------------------------------------------------------------
# 5. Cohort retention heatmap.
# ---------------------------------------------------------------------------
def chart_cohort_heatmap() -> None:
    df = pd.read_csv(OUT / "08b_cohort_retention_pivot.csv")
    matrix = df.set_index("cohort")[["m1_pct", "m2_pct", "m3_pct", "m6_pct", "m9_pct", "m12_pct"]]
    matrix.columns = ["M+1", "M+2", "M+3", "M+6", "M+9", "M+12"]

    fig, ax = plt.subplots(figsize=(10, 9))
    sns.heatmap(matrix, annot=True, fmt=".2f", cmap="Reds",
                vmin=0, vmax=1.5, cbar_kws={"label": "Retention %"},
                linewidths=0.5, linecolor="white", ax=ax)
    ax.set_title("Repeat-purchase retention is < 1% for every cohort, every month")
    ax.set_xlabel("Months since first purchase")
    ax.set_ylabel("Acquisition cohort")
    _caption(fig,
        "Each cell = % of the cohort who returned to purchase in that month. "
        "All values are below 1% — Olist's growth is overwhelmingly acquisition-driven, not retention-driven."
    )
    _save(fig, "05_cohort_retention")

# ---------------------------------------------------------------------------
# 6. Monthly revenue trend (in-window only).
# ---------------------------------------------------------------------------
def chart_monthly_trend() -> None:
    df = pd.read_csv(OUT / "07_monthly_revenue_trend.csv")
    df = df[df["in_window"] == "t"].copy()
    df["month_dt"] = pd.to_datetime(df["month"])
    df["gmv_m"]    = df["gmv_brl"] / 1e6

    fig, ax = plt.subplots(figsize=(12, 5.4))
    ax.fill_between(df["month_dt"], 0, df["gmv_m"],
                    color=PALETTE["primary"], alpha=0.15)
    ax.plot(df["month_dt"], df["gmv_m"],
            color=PALETTE["primary"], lw=2.5, marker="o", ms=5)
    # Annotate Black Friday peak.
    bf = df[df["month"] == "2017-11"].iloc[0]
    ax.annotate(f"Black Friday\nR$ {bf.gmv_m:.2f}M",
                xy=(bf.month_dt, bf.gmv_m),
                xytext=(bf.month_dt - pd.Timedelta(days=120), bf.gmv_m + 0.08),
                fontsize=10, fontweight="bold", color=PALETTE["accent"],
                arrowprops=dict(arrowstyle="->", color=PALETTE["accent"]))
    # Annotate plateau.
    ax.axhspan(0.85, 1.0, color="#888", alpha=0.05)
    ax.text(pd.Timestamp("2018-04-01"), 0.55,
            "Mar–Aug 2018: GMV plateaus around R$0.9–1.0M/month",
            fontsize=10, color=PALETTE["neutral"], style="italic")

    ax.set_ylabel("GMV (R$ millions)")
    ax.set_xlabel("")
    ax.set_ylim(0, df["gmv_m"].max() * 1.15)
    ax.set_title("Olist marketplace GMV: 2017 hyper-growth → 2018 plateau")
    _caption(fig,
        "Window: 2017-01 → 2018-08 (sparse 2016 and Sept-Oct 2018 tails excluded). "
        "Growth from R$0.12M → R$1.0M in 12 months, then six straight months of R$0.85–1.0M."
    )
    _save(fig, "06_monthly_trend")

# ---------------------------------------------------------------------------
# 7. Top 15 categories by GMV with review-score overlay.
# ---------------------------------------------------------------------------
def chart_top_categories() -> None:
    df = pd.read_csv(OUT / "03_revenue_by_category.csv").head(15).iloc[::-1]

    fig, ax = plt.subplots(figsize=(11, 7))
    bars = ax.barh(df["category"], df["gmv_brl"] / 1e3,
                   color=PALETTE["primary"], edgecolor="white", lw=1.2)
    # Color bars red if avg_review_score < 4.0 (warning), green if >= 4.3.
    for b, score in zip(bars, df["avg_review_score"]):
        if score < 4.0:
            b.set_color(PALETTE["accent"])
        elif score >= 4.3:
            b.set_color(PALETTE["success"])

    for b, gmv, score in zip(bars, df["gmv_brl"] / 1e3, df["avg_review_score"]):
        ax.text(b.get_width() + 12, b.get_y() + b.get_height()/2,
                f"R$ {gmv:,.0f}K  ·  {score:.1f}★",
                va="center", fontsize=10)

    ax.set_xlabel("GMV (R$ thousands)")
    ax.set_xlim(0, df["gmv_brl"].max() / 1e3 * 1.25)
    ax.set_title("Top 15 categories — Health & Beauty leads, but watch reviews on Office Furniture")

    # Manual legend.
    from matplotlib.patches import Patch
    ax.legend(handles=[
        Patch(facecolor=PALETTE["success"], label="≥ 4.3★"),
        Patch(facecolor=PALETTE["primary"], label="4.0–4.3★"),
        Patch(facecolor=PALETTE["accent"],  label="< 4.0★"),
    ], loc="lower right", frameon=True, title="Avg review")

    _caption(fig,
        "Bar length = GMV. Color = average review score. Categories with red bars are revenue-rich "
        "but quality-fragile — review the supplier base before scaling marketing spend."
    )
    _save(fig, "07_top_categories")

# ---------------------------------------------------------------------------
# 8. Delivery performance by state — risk map.
# ---------------------------------------------------------------------------
def chart_delivery_by_state() -> None:
    df = pd.read_csv(OUT / "04c_delivery_by_state.csv")
    df = df.sort_values("avg_delivery_days", ascending=True)

    fig, ax = plt.subplots(figsize=(11, 8))
    # Color by on-time pct: green > 90, amber 80-90, red < 80.
    def color_for(pct):
        if pct >= 90: return PALETTE["success"]
        if pct >= 80: return "#F4A261"
        return PALETTE["accent"]
    colors = [color_for(p) for p in df["on_time_pct"]]
    bars = ax.barh(df["customer_state"], df["avg_delivery_days"],
                   color=colors, edgecolor="white", lw=1.2)
    for b, days, ot, sc in zip(bars, df["avg_delivery_days"],
                                df["on_time_pct"], df["avg_review_score"]):
        ax.text(b.get_width() + 0.4, b.get_y() + b.get_height()/2,
                f"{days:.1f}d  ·  {ot}% on-time  ·  {sc:.1f}★",
                va="center", fontsize=9)
    ax.set_xlabel("Average delivery days (purchase → customer doorstep)")
    ax.set_xlim(0, df["avg_delivery_days"].max() * 1.55)
    ax.set_title("Delivery performance by state — North/Northeast wait 3× longer than the South")

    from matplotlib.patches import Patch
    ax.legend(handles=[
        Patch(facecolor=PALETTE["success"], label="≥ 90% on-time"),
        Patch(facecolor="#F4A261",          label="80–90% on-time"),
        Patch(facecolor=PALETTE["accent"],  label="< 80% on-time"),
    ], loc="lower right", frameon=True, title="On-time rate")

    _caption(fig,
        "RR (Roraima), AP (Amapá), AM (Amazonas) average 28+ delivery days. "
        "These lanes are the operational source of Olist's late-delivery review damage."
    )
    _save(fig, "08_delivery_by_state")

# ---------------------------------------------------------------------------
def main() -> None:
    print("Building visuals...")
    chart_delivery_cliff()
    chart_ontime_vs_late()
    chart_seller_pareto()
    chart_rfm_segments()
    chart_cohort_heatmap()
    chart_monthly_trend()
    chart_top_categories()
    chart_delivery_by_state()
    print("Done.")

if __name__ == "__main__":
    main()
