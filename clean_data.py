"""
EV Charging Station Data — Cleaning Script
Source: City of Boulder Open Data Portal
https://open-data.bouldercolorado.gov/datasets/95992b3938be4622b07f0b05eba95d4c_0/about

Cleans the raw export (148,136 rows) down to a verified, de-duplicated,
Power-BI-ready dataset. See README.md for a full explanation of each
issue found and why each cleaning decision was made.
"""

import pandas as pd

INPUT_FILE = "raw_data.csv"
OUTPUT_FILE = "ev_charging_boulder_clean.csv"


def parse_duration_to_minutes(duration_str: str) -> float:
    """Convert an 'H:MM:SS' string (hours can exceed 24) to total minutes."""
    hours, minutes, seconds = duration_str.split(":")
    return round(int(hours) * 60 + int(minutes) + int(seconds) / 60, 2)


def main():
    df = pd.read_csv(INPUT_FILE, encoding="utf-8-sig")
    original_count = len(df)
    print(f"Loaded {original_count} raw rows.")

    # 1. Remove exact duplicate sessions (the two ID columns are unreliable —
    #    ObjectID resets partway through the export, causing ~42% of rows
    #    to be exact duplicates of another row).
    id_cols = ["ObjectID", "ObjectId2"]
    compare_cols = [c for c in df.columns if c not in id_cols]
    before = len(df)
    df = df.drop_duplicates(subset=compare_cols, keep="first")
    print(f"Removed {before - len(df)} duplicate session rows.")

    # 2. Remove corrupted sentinel-duration rows (838:59:59 = system error
    #    code for "session never closed properly", not a real session).
    before = len(df)
    df = df[df["Total_Duration__hh_mm_ss_"] != "838:59:59"]
    print(f"Removed {before - len(df)} corrupted sentinel-duration rows.")

    # 3. Parse dates — the column silently mixes two formats:
    #    M/D/YYYY H:MM (most rows) and ISO YYYY-MM-DD HH:MM:SS (~7.8K rows
    #    from mid-2023 onward). A single fixed format throws a ValueError
    #    on the ISO rows, so we use pandas' mixed-format parsing.
    df["Start_Date___Time"] = pd.to_datetime(
        df["Start_Date___Time"], format="mixed", dayfirst=False
    )
    df["End_Date___Time"] = pd.to_datetime(
        df["End_Date___Time"], format="mixed", dayfirst=False
    )

    # 4. Convert duration strings to numeric minutes (hours can exceed 24,
    #    so these aren't valid time-of-day values).
    df["Total_Duration_Minutes"] = df["Total_Duration__hh_mm_ss_"].apply(
        parse_duration_to_minutes
    )
    df["Charging_Time_Minutes"] = df["Charging_Time__hh_mm_ss_"].apply(
        parse_duration_to_minutes
    )

    # 5. Flag zero-energy sessions instead of dropping them — a session with
    #    no energy delivered is still a real "station occupied" event.
    df["Zero_Energy_Session"] = df["Energy__kWh_"] <= 0
    zero_pct = df["Zero_Energy_Session"].mean() * 100
    print(f"Flagged {df['Zero_Energy_Session'].sum()} zero-energy sessions ({zero_pct:.1f}%).")

    # 6. Derived date/time fields for Power BI time intelligence.
    df["Start_Date"] = df["Start_Date___Time"].dt.date
    df["Year"] = df["Start_Date___Time"].dt.year
    df["Month"] = df["Start_Date___Time"].dt.month
    df["MonthName"] = df["Start_Date___Time"].dt.strftime("%b")
    df["DayOfWeek"] = df["Start_Date___Time"].dt.day_name()
    df["Hour"] = df["Start_Date___Time"].dt.hour

    # 7. Drop unreliable ID columns and the original string duration columns.
    df = df.drop(columns=id_cols + ["Total_Duration__hh_mm_ss_", "Charging_Time__hh_mm_ss_"])

    # 8. Assign a clean, reliable session ID.
    df = df.sort_values("Start_Date___Time").reset_index(drop=True)
    df.insert(0, "Session_ID", df.index + 1)

    df.to_csv(OUTPUT_FILE, index=False)
    print(f"\nDone: {original_count} raw rows -> {len(df)} clean sessions.")
    print(f"Saved to {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
