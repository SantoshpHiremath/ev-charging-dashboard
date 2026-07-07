# EV Charging Station Utilization Dashboard (Power BI)

A Power BI dashboard analyzing real electric vehicle charging session data from the City of Boulder, Colorado's public charging network, to surface usage patterns, station utilization, and environmental impact.

## Data Source

**City of Boulder Open Data Portal** — Electric Vehicle Charging Station Data
https://open-data.bouldercolorado.gov/datasets/95992b3938be4622b07f0b05eba95d4c_0/about

Real charging session records from 50 city-owned Level 2 charging stations, covering January 2018 through November 2023. Publicly available, no authentication required.

## Data Cleaning

The raw export (148,136 rows) required real cleaning before it was usable for analysis. All issues below were found by inspection, not assumed:

**1. Duplicate sessions (62,385 rows removed).** Comparing rows after excluding the two ID columns (`ObjectID`, `ObjectId2`) showed that 42% of the raw file consisted of exact duplicate charging sessions — same station, same start/end time, same energy delivered — differing only in a sequential ID column that had clearly reset partway through the export. Verified this wasn't coincidental by checking that duplicate pairs matched on every substantive field, then deduplicated on all columns except the two ID fields, keeping the first occurrence.

**2. Corrupted sentinel-duration rows (3 rows removed).** Four rows had a duration of exactly `838:59:59` (a common sentinel/overflow value used by data-logging systems to represent "unknown" or "session never closed") paired with a missing `End_Date___Time`. These were dropped as invalid rather than treated as genuine 34-day charging sessions. (One of the four was also part of the duplicate set removed in step 1.)

**3. Mixed date formats in the same column (bug found and handled).** The `Start_Date___Time` and `End_Date___Time` columns silently mixed two different formats — most rows as `M/D/YYYY H:MM`, but 7,816 rows (all from June 2023 onward, suggesting a mid-export system or format change) as ISO `YYYY-MM-DD HH:MM:SS`. A naive single-format parse (`pd.to_datetime(..., format='%m/%d/%Y %H:%M')`) throws a `ValueError` on the ISO-formatted rows. Fixed using pandas' `format='mixed'` parsing after confirming both formats were unambiguous.

**4. Zero-energy sessions (9,969 rows, 11.6% — flagged, not removed).** These represent sessions where a vehicle was connected but no measurable energy was delivered (e.g., already fully charged, a faulty connection, or a very short test connection). Rather than silently dropping them — which would inflate average utilization — they're kept and flagged with a `Zero_Energy_Session` boolean column so the dashboard can filter or highlight them explicitly, since "station occupied but idle" is itself a meaningful utilization signal.

**5. Duration reformatting.** The original `Total_Duration__hh_mm_ss_` and `Charging_Time__hh_mm_ss_` columns were text strings with hour values that can exceed 24 (e.g. `95:06:31` for a multi-day session), which is not a standard time format and would not parse correctly as a time-of-day value in BI tools. Converted both to a single `_Minutes` numeric column instead.

Cleaning script: [`clean_data.py`](./clean_data.py)
Result: 85,748 verified, de-duplicated charging sessions, zero remaining nulls.

## Dashboard — Questions It Answers

1. **Usage over time**: How has charging session volume and total energy delivered changed month-over-month and year-over-year since 2018?
2. **Station utilization**: Which stations are busiest (by session count and by energy delivered), and which are underused?
3. **Time-of-day / day-of-week patterns**: When do people charge most — are there clear commuter-hour peaks, or is usage spread evenly?
4. **Session characteristics**: What's the typical charging session length and energy delivered per session, and how much does this vary by station?
5. **Environmental impact**: What's the cumulative estimated gasoline and GHG savings from this charging network, and how has that grown over time?
6. **Idle/zero-energy rate**: What share of sessions deliver no measurable charge, and does this vary meaningfully by station (a potential signal of faulty hardware or user behavior)?

## Tech Stack

- **Data cleaning**: Python (pandas)
- **Dashboard**: Power BI Desktop
- **Source data**: City of Boulder Open Data Portal (public, CSV export)

## Files

- `raw_data.csv` — original export from the City of Boulder open data portal (not included in repo due to size; download link above)
- `clean_data.py` — cleaning and transformation script
- `ev_charging_boulder_clean.csv` — cleaned dataset used in the dashboard
- `EV_Charging_Dashboard.pbix` — Power BI dashboard file

## Honest Limitations

- Data covers only city-owned Level 2 stations in Boulder, Colorado — not representative of private or DC fast-charging infrastructure.
- The mid-2023 date-format shift suggests a change in the city's data export system; there may be other undocumented changes around that boundary that weren't caught by this cleaning pass.
- Zero-energy sessions are flagged but their root cause (faulty port vs. already-full vehicle vs. user error) can't be determined from this data alone.
