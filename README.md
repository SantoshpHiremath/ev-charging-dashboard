# EV Charging Station Utilization Dashboard (Power BI)

## What it does

A Power BI dashboard I built to analyze real electric vehicle charging session data from the City of Boulder, Colorado's public charging network. It surfaces usage patterns, station utilization, and environmental impact, and is backed by a Python cleaning script and eight SQL analysis queries.

## Data

**City of Boulder Open Data Portal** — Electric Vehicle Charging Station Data
https://open-data.bouldercolorado.gov/datasets/95992b3938be4622b07f0b05eba95d4c_0/about

Real charging session records from 50 city-owned Level 2 charging stations, covering January 2018 through November 2023. Publicly available, no authentication required. The data covers city-owned Level 2 stations in Boulder, so it describes that network rather than private or DC fast-charging infrastructure.

### Data cleaning

The raw export (148,136 rows) needed cleaning before analysis. I found each issue below by inspection:

**1. Duplicate sessions (62,385 rows removed).** Comparing rows after excluding the two ID columns (`ObjectID`, `ObjectId2`) showed that 42% of the raw file consisted of exact duplicate charging sessions: same station, same start/end time, same energy delivered, differing only in a sequential ID column that had reset partway through the export. I checked that duplicate pairs matched on every substantive field, then deduplicated on all columns except the two ID fields, keeping the first occurrence.

**2. Corrupted sentinel-duration rows (3 rows removed).** Four rows had a duration of exactly `838:59:59` (a common sentinel/overflow value used by data-logging systems to represent "unknown" or "session never closed") paired with a missing `End_Date___Time`. I dropped these as invalid rather than treating them as genuine 34-day charging sessions. (One of the four was also part of the duplicate set removed in step 1.)

**3. Mixed date formats in the same column.** The `Start_Date___Time` and `End_Date___Time` columns mixed two formats: most rows as `M/D/YYYY H:MM`, but 7,816 rows (all from June 2023 onward, suggesting a mid-export system or format change) as ISO `YYYY-MM-DD HH:MM:SS`. A single-format parse (`pd.to_datetime(..., format='%m/%d/%Y %H:%M')`) throws a `ValueError` on the ISO-formatted rows. I used pandas' `format='mixed'` parsing after confirming both formats were unambiguous.

**4. Zero-energy sessions (9,969 rows, 11.6%, flagged and kept).** These are sessions where a vehicle was connected but no measurable energy was delivered (e.g., already fully charged, a faulty connection, or a very short test connection). Dropping them would inflate average utilization, so I kept them and flagged them with a `Zero_Energy_Session` boolean column. The dashboard can filter or highlight them, since "station occupied but idle" is itself a meaningful utilization signal. The data alone does not show the root cause (faulty port, already-full vehicle, or user behavior).

**5. Duration reformatting.** The original `Total_Duration__hh_mm_ss_` and `Charging_Time__hh_mm_ss_` columns were text strings with hour values that can exceed 24 (e.g. `95:06:31` for a multi-day session), which is not a standard time format and would not parse as a time-of-day value in BI tools. I converted both to a single `_Minutes` numeric column.

Cleaning script: [`clean_data.py`](./clean_data.py)
Result: 85,748 verified, de-duplicated charging sessions, zero remaining nulls.

## Dashboard: questions it answers

1. **Usage over time**: How has charging session volume and total energy delivered changed month-over-month and year-over-year since 2018?
2. **Station utilization**: Which stations are busiest (by session count and by energy delivered), and which are underused?
3. **Time-of-day / day-of-week patterns**: When do people charge most, and are there clear commuter-hour peaks or is usage spread evenly?
4. **Session characteristics**: What's the typical charging session length and energy delivered per session, and how much does this vary by station?
5. **Environmental impact**: What's the cumulative estimated gasoline and GHG savings from this charging network, and how has that grown over time?
6. **Idle/zero-energy rate**: What share of sessions deliver no measurable charge, and does this vary by station (a potential signal of faulty hardware or user behavior)?

## Results: SQL analysis

Eight analytical queries written in standard SQL (SQLite 3.45, window functions fully supported). All queries run against the cleaned CSV via `run_queries.py`, with no database server required.

| Query | What it answers |
|---|---|
| Q1 — Year-over-year growth | Sessions and energy by year with `LAG()` window function for YoY % change |
| Q2 — Top 10 busiest stations | Ranked by session count using `RANK()` window function |
| Q3 — Peak demand heatmap | Sessions by day-of-week × hour; reveals clear 8 am–5 pm commuter pattern |
| Q4 — Zero-energy rate by station | `CASE`/`SUM` to compute per-station idle rate; `COMM VITALITY / 2200 BROADWAY` highest at 35.7% |
| Q5 — Session duration buckets | `CASE` bucketing + `SUM() OVER()` for % of total per bucket |
| Q6 — Monthly cumulative energy | Running total with `SUM(SUM(...)) OVER (ORDER BY Year, Month)` |
| Q7 — Cumulative environmental impact | Cumulative gasoline (91,165 gal) and GHG savings (463,669 kg CO₂) by year |
| Q8 — Highest avg energy per session | `DENSE_RANK()` on avg kWh; excludes zero-energy sessions and low-volume stations |

**Selected findings from Q7 (environmental impact):**

| Year | Annual GHG saved (kg) | Cumulative GHG saved (kg) |
|---|---|---|
| 2018 | 20,215 | 20,215 |
| 2020 | 17,459 | 74,272 (COVID dip visible) |
| 2022 | 121,494 | 257,903 |
| 2023 | 205,767 | **463,669** |

## Running it

```bash
python run_queries.py
```

## Project structure

- `raw_data.csv` — original export from the City of Boulder open data portal (not included in repo due to size; download link above)
- `clean_data.py` — cleaning and transformation script
- `ev_charging_boulder_clean.csv` — cleaned dataset used in the dashboard (not included due to size; run `clean_data.py` to generate)
- `queries.sql` — 8 analytical SQL queries (window functions, CTEs, aggregation)
- `run_queries.py` — executes `queries.sql` against the CSV; no database server needed
- `EV_Charging_Dashboard.pbix` — Power BI dashboard file

Tech stack: Python (pandas) for cleaning, SQLite (via Python `sqlite3`) for SQL analysis, Power BI Desktop for the dashboard.

## Notes

The mid-2023 date-format shift suggests a change in the city's data export system. I handled the two formats explicitly in the cleaning pass.

## Possible extensions

- Compare against private or DC fast-charging data for a fuller view of regional infrastructure.
- Investigate zero-energy sessions per station against maintenance records to separate hardware faults from user behavior.
