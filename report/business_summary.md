# Olist Marketplace — Business Summary

**Period analysed:** January 2017 – August 2018 (20 months)
**Scale:** 99,441 orders · 96,096 unique customers · 3,095 sellers · R$ 13.6M GMV

---

## Executive summary

Olist's marketplace is fundamentally healthy on the supply side — the catalogue is broad, the top sellers perform — but it is structurally weak on **delivery reliability** and **customer retention**. Three findings dominate the analysis and three recommendations follow.

| # | Finding | Recommended action |
|---|---|---|
| 1 | A single late delivery collapses average review from **4.29 ★ to 2.57 ★**. By day 7 late, 63% of customers leave 1-star reviews. | Make **on-time delivery rate** the single primary operations KPI, replacing "average delivery days." |
| 2 | The top 1% of sellers (30 of 3,095) generate **26% of GMV**; the top 10% generate 67%. | Stand up a **seller-success programme for the top 100 accounts**. Identify the 47 top-quartile sellers carrying quality risk flags and address them first. |
| 3 | M+1 retention is **< 1% in every cohort**. The "High-Value Lost" segment — 11,950 customers, 4.58 ★ history, R$272 lifetime spend — has gone dark. | Run a **win-back campaign for High-Value Lost** before next acquisition push. Reactivation CAC is structurally lower than new-customer CAC. |

---

## 1. The late-delivery cliff

### What we observed

- Olist's average review across all delivered orders is **4.09 ★** — superficially strong.
- Splitting by delivery promise: **on-time orders = 4.29 ★**, **late orders = 2.57 ★** — a 1.72-star delta.
- The drop is a step function, not a gradient. Day-by-day:
  - Day 0 (delivered exactly on time): 4.03 ★
  - Day +1 late: 3.73 ★ (one day late, 0.30 stars lost)
  - Day +4 late: 2.50 ★
  - Day +7 late: 1.91 ★, with 63% of customers leaving 1-star reviews
  - Day +14+ late: stabilises at ~1.6 ★ with 70%+ one-star

### Why it matters

The customer's emotional response is binary — *did Olist meet the promise it made me?* The actual number of days does not matter as much as crossing the threshold. This is a known pattern in operations research (the "promise-keeping effect") but it is rarely visible in this magnitude in a public dataset.

### Operational implication

Olist already pads delivery estimates by ~11 days on average (estimated_days mean: 23.4; actual mean: 12.1). This sandbagging is the right strategic posture — but it makes "average delivery days" a misleading KPI for the operations team. **Optimising for promise-keeping** (on-time rate ≥ 95%) is the right north star, even if it means promising slower delivery in distant lanes.

### State-level priorities

Brazilian states with the worst on-time rates and longest delivery times are concentrated in the North/Northeast: RR (Roraima), AP (Amapá), AM (Amazonas), and PA (Pará) routinely show 28+ delivery days. These are the lanes where the cliff causes the most review damage. Two strategic options:

1. **Lengthen estimates for distant lanes** to recover the on-time rate. Cheap to implement, may suppress conversion.
2. **Build regional fulfilment** (Northeast hub) to physically shorten lanes. Expensive but addresses the root cause.

---

## 2. Seller concentration and risk

### What we observed

| Seller bucket | Sellers | GMV | Share |
|---|---|---|---|
| Top 1% | 30 | R$ 3.48M | 25.7% |
| Top 5% | 153 cumulative | — | 53.1% cumulative |
| Top 10% | 306 cumulative | — | 67.4% cumulative |
| Top 25% | 767 cumulative | — | 87.0% cumulative |
| Bottom 50% | 1,534 | R$ 0.44M | 3.2% |

### Why it matters

- **Defection risk.** If even a handful of the top 30 sellers move to a competing platform (Mercado Livre, Magazine Luiza), Olist takes a measurable revenue hit that quarter.
- **Quality risk.** Of the top-quartile sellers by GMV, **47 carry a risk flag** — average review score below 4.0 or on-time rate below 85%. These sellers are the loudest source of bad reviews of *Olist itself*.
- **Long-tail economics.** The bottom 50% of sellers generate only 3.2% of GMV. Acquisition spend on that segment has poor unit economics.

### Recommended programme

1. **Top-100 account management.** Assign relationship managers to the top 100 sellers (representing ~50% of GMV). Quarterly business reviews, advance notice of platform changes, dedicated support SLA.
2. **Quality-risk remediation.** Engage the 47 risk sellers individually to diagnose root cause (logistics partner, packaging quality, listing accuracy). Set a 90-day remediation window.
3. **Long-tail self-service.** Move the bottom 50% to a fully self-service onboarding flow. Reduce per-seller cost-to-serve.

---

## 3. The repeat-purchase crisis

### What we observed

- Of 96,096 unique customers, **2,997 (3.12%) have ever placed a second order**.
- Cohort retention is < 1% in every monthly cohort, every retention month checked (M+1 through M+12).
- Customer segmentation (modified RFM) reveals the structure of the inactive base:

| Segment | Customers | Avg lifetime GMV | Avg review | Total GMV |
|---|---|---|---|---|
| New & Promising | 14,902 | R$ 268 | 4.10 ★ | R$ 3.99M |
| **High-Value Lost** | **11,950** | **R$ 272** | **4.58 ★** | **R$ 3.25M** |
| Need Attention | 18,523 | R$ 129 | 3.95 ★ | R$ 2.39M |
| Hibernating | 23,164 | R$ 54 | 4.10 ★ | R$ 1.26M |
| Recent One-Timers | 22,121 | R$ 55 | 4.19 ★ | R$ 1.22M |
| **High-Value Burnt** | **2,139** | **R$ 305** | **1.20 ★** | **R$ 0.65M** |
| Champions | 985 | R$ 330 | 4.20 ★ | R$ 0.32M |
| At Risk Repeaters | 1,056 | R$ 251 | 4.11 ★ | R$ 0.27M |
| Loyal | 934 | R$ 198 | 4.03 ★ | R$ 0.18M |

### Why it matters

The headline 3.12% repeat rate is well below the 25–35% benchmark for mature marketplaces. This means:

- **CAC compounds.** Every R$ spent on acquisition generates one transaction, not a relationship.
- **Marketing budget is structurally inefficient.** No baseline of free returning demand to amortise spend across.
- **Brand defensibility is fragile.** Customers have no relationship friction with switching to a competitor.

### The reactivation prize

The **High-Value Lost** segment is the highest-leverage marketing target identified by this analysis:

- **11,950 customers** (12.5% of the base, 24.0% of historical GMV).
- Average lifetime spend: R$ 272 — meaningfully above the R$ 138 mean order value.
- Average review score: **4.58 ★** — they liked Olist when they shopped.
- Average days since last purchase: **396** — they have not been actively engaged in over a year.

A win-back campaign targeting this segment (push notification, email, retargeted display) with a meaningful incentive (free shipping, R$20 credit) should outperform new-customer acquisition on cost-per-acquired-order. **Recommend running this as an A/B against equal-budget acquisition spend in the next quarter.**

The **High-Value Burnt** segment (2,139 customers, R$ 305 average spend, 1.20 ★ review) is the lower-priority second target — they spent meaningfully but had a bad experience. Reach-out should follow root-cause investigation of their original complaint (likely delivery-related, given finding #1).

---

## What this analysis does not address

Honest scope limits, for stakeholder transparency:

| Question | Why not yet |
|---|---|
| What is the contribution margin per order? | Cost-of-goods data is not in the dataset; only revenue. |
| What does the seller-acquisition funnel look like? | Seller table has no acquisition timestamp. |
| Are cancellations driven by stock-outs or by customer remorse? | The order_status field has 'canceled' but no reason code. |
| What is the customer-acquisition source mix? | No marketing attribution data. |
| How does competitor pricing affect Olist's category share? | No external pricing data. |

A v2 of this analysis with internal cost-of-goods, marketing attribution, and seller-cohort data could close most of these gaps.

---

## Methodology and reproducibility

All analyses are built on PostgreSQL 16 from the raw Kaggle CSVs, with cleaning logic documented inline in `sql/02_data_cleaning.sql`. Charts are rendered from SQL outputs by `visuals/build_visuals.py`. The full pipeline reproduces in approximately 2 minutes from a fresh clone.

The analysis window is restricted to **2017-01 → 2018-08** to exclude the sparse 2016 and Sept-Oct 2018 tails (each containing < 25 orders/month). The `in_analysis_window` flag in the cleaning views makes this filter explicit and reversible.

For full technical details and reproduction steps, see `README.md`.
