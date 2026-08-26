-- ============================================================
-- EV Charging Station Utilization — SQL Analytics
-- Dataset: City of Boulder, CO Public Charging Network
-- Source:  https://open-data.bouldercolorado.gov/datasets/95992b3938be4622b07f0b05eba95d4c_0/about
-- Cleaned: 85,748 sessions | 50 stations | Jan 2018 – Nov 2023
-- Engine:  SQLite 3.45 (window functions supported)
-- ============================================================


-- ──────────────────────────────────────────────────────────────
-- Q1: Year-over-year growth in sessions and energy delivered
--     Shows whether EV adoption is accelerating over time.
-- ──────────────────────────────────────────────────────────────
SELECT
    Year,
    COUNT(*)                                AS total_sessions,
    ROUND(SUM(Energy__kWh_), 0)            AS total_energy_kWh,
    ROUND(AVG(Energy__kWh_), 2)            AS avg_energy_per_session_kWh,
    LAG(COUNT(*)) OVER (ORDER BY Year)     AS prev_year_sessions,
    ROUND(
        100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY Year))
        / LAG(COUNT(*)) OVER (ORDER BY Year),
        1
    )                                      AS yoy_growth_pct
FROM ev_charging
GROUP BY Year
ORDER BY Year;


-- ──────────────────────────────────────────────────────────────
-- Q2: Top 10 busiest stations by session count
--     Identifies which stations carry the most load.
-- ──────────────────────────────────────────────────────────────
SELECT
    Station_Name,
    COUNT(*)                                        AS total_sessions,
    ROUND(SUM(Energy__kWh_), 1)                    AS total_energy_kWh,
    ROUND(AVG(Energy__kWh_), 2)                    AS avg_energy_kWh,
    ROUND(AVG(Total_Duration_Minutes), 1)           AS avg_duration_min,
    RANK() OVER (ORDER BY COUNT(*) DESC)            AS session_rank
FROM ev_charging
GROUP BY Station_Name
ORDER BY total_sessions DESC
LIMIT 10;


-- ──────────────────────────────────────────────────────────────
-- Q3: Peak demand — sessions by day of week and hour
--     Reveals commuter patterns and off-peak windows.
-- ──────────────────────────────────────────────────────────────
SELECT
    DayOfWeek,
    Hour,
    COUNT(*)                AS session_count,
    ROUND(AVG(Energy__kWh_), 2) AS avg_energy_kWh
FROM ev_charging
GROUP BY DayOfWeek, Hour
ORDER BY
    CASE DayOfWeek
        WHEN 'Monday'    THEN 1
        WHEN 'Tuesday'   THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday'  THEN 4
        WHEN 'Friday'    THEN 5
        WHEN 'Saturday'  THEN 6
        WHEN 'Sunday'    THEN 7
    END,
    Hour;


-- ──────────────────────────────────────────────────────────────
-- Q4: Zero-energy session rate by station
--     Flags stations with unusually high idle-connection rates
--     (possible hardware fault or user-behaviour signal).
-- ──────────────────────────────────────────────────────────────
SELECT
    Station_Name,
    COUNT(*)                                                    AS total_sessions,
    SUM(CASE WHEN Zero_Energy_Session = 1 THEN 1 ELSE 0 END)  AS zero_energy_count,
    ROUND(
        100.0 * SUM(CASE WHEN Zero_Energy_Session = 1 THEN 1 ELSE 0 END)
        / COUNT(*), 1
    )                                                           AS zero_energy_rate_pct
FROM ev_charging
GROUP BY Station_Name
HAVING total_sessions >= 100          -- exclude low-volume stations from ranking
ORDER BY zero_energy_rate_pct DESC
LIMIT 15;


-- ──────────────────────────────────────────────────────────────
-- Q5: Session duration distribution — short vs. long sessions
--     Categorises sessions into buckets to understand
--     how long vehicles typically stay connected.
-- ──────────────────────────────────────────────────────────────
SELECT
    CASE
        WHEN Total_Duration_Minutes <  30  THEN '< 30 min'
        WHEN Total_Duration_Minutes <  60  THEN '30–60 min'
        WHEN Total_Duration_Minutes < 120  THEN '1–2 hrs'
        WHEN Total_Duration_Minutes < 240  THEN '2–4 hrs'
        WHEN Total_Duration_Minutes < 480  THEN '4–8 hrs'
        ELSE                                    '> 8 hrs'
    END                         AS duration_bucket,
    COUNT(*)                    AS session_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM ev_charging
GROUP BY duration_bucket
ORDER BY
    CASE duration_bucket
        WHEN '< 30 min'  THEN 1
        WHEN '30–60 min' THEN 2
        WHEN '1–2 hrs'   THEN 3
        WHEN '2–4 hrs'   THEN 4
        WHEN '4–8 hrs'   THEN 5
        ELSE                  6
    END;


-- ──────────────────────────────────────────────────────────────
-- Q6: Monthly energy delivered with running cumulative total
--     Tracks network growth and seasonality simultaneously.
-- ──────────────────────────────────────────────────────────────
SELECT
    Year,
    Month,
    MonthName,
    COUNT(*)                                            AS sessions,
    ROUND(SUM(Energy__kWh_), 1)                        AS monthly_energy_kWh,
    ROUND(
        SUM(SUM(Energy__kWh_)) OVER (ORDER BY Year, Month),
        1
    )                                                   AS cumulative_energy_kWh
FROM ev_charging
GROUP BY Year, Month, MonthName
ORDER BY Year, Month;


-- ──────────────────────────────────────────────────────────────
-- Q7: Cumulative environmental impact by year
--     Estimates total gasoline and GHG savings from the network.
-- ──────────────────────────────────────────────────────────────
SELECT
    Year,
    ROUND(SUM(Gasoline_Savings__gallons_), 0)           AS annual_gasoline_saved_gal,
    ROUND(SUM(GHG_Savings__kg_), 0)                     AS annual_ghg_saved_kg,
    ROUND(
        SUM(SUM(Gasoline_Savings__gallons_)) OVER (ORDER BY Year),
        0
    )                                                    AS cumulative_gasoline_gal,
    ROUND(
        SUM(SUM(GHG_Savings__kg_)) OVER (ORDER BY Year),
        0
    )                                                    AS cumulative_ghg_kg
FROM ev_charging
GROUP BY Year
ORDER BY Year;


-- ──────────────────────────────────────────────────────────────
-- Q8: Stations with the highest average energy per session
--     (minimum 200 sessions to filter noise) — identifies
--     locations where EVs arrive with lower state-of-charge.
-- ──────────────────────────────────────────────────────────────
SELECT
    Station_Name,
    COUNT(*)                            AS total_sessions,
    ROUND(AVG(Energy__kWh_), 2)        AS avg_energy_kWh,
    ROUND(AVG(Charging_Time_Minutes), 1) AS avg_charging_min,
    DENSE_RANK() OVER (
        ORDER BY AVG(Energy__kWh_) DESC
    )                                   AS energy_rank
FROM ev_charging
WHERE Zero_Energy_Session = 0          -- exclude idle sessions from energy averages
GROUP BY Station_Name
HAVING COUNT(*) >= 200                 -- minimum 200 sessions to filter low-volume stations
ORDER BY avg_energy_kWh DESC;
