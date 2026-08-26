"""
run_queries.py — Execute queries.sql against the cleaned EV charging dataset.

Usage:
    python run_queries.py

Requires: pandas (pip install pandas)
No other dependencies — uses Python's built-in sqlite3 module.

The script loads ev_charging_boulder_clean.csv into an in-memory SQLite
database and runs each query from queries.sql, printing results to stdout.
"""

import sqlite3
import textwrap
import pandas as pd

CSV_FILE = "ev_charging_boulder_clean.csv"
SQL_FILE = "queries.sql"


def load_data(conn: sqlite3.Connection) -> int:
    """Load the cleaned CSV into an in-memory SQLite table."""
    df = pd.read_csv(CSV_FILE)
    # SQLite stores booleans as integers; convert True/False → 1/0
    df["Zero_Energy_Session"] = df["Zero_Energy_Session"].astype(int)
    df.to_sql("ev_charging", conn, index=False, if_exists="replace")
    return len(df)


def split_queries(sql_text: str) -> list[tuple[str, str]]:
    """
    Split the SQL file into (label, query) pairs.
    Labels are extracted from '-- Q<n>: ...' comment lines.
    """
    queries = []
    current_label = "Unnamed"
    current_sql: list[str] = []

    for line in sql_text.splitlines():
        stripped = line.strip()

        # New query block starts with '-- Q<digit>'
        if stripped.startswith("-- Q") and ":" in stripped:
            # Save the previous query if any
            sql = "\n".join(current_sql).strip()
            if sql:
                queries.append((current_label, sql))
            current_label = stripped.lstrip("- ").split(":")[0].strip()
            current_sql = []
        else:
            current_sql.append(line)

    # Flush the last query
    sql = "\n".join(current_sql).strip()
    if sql:
        queries.append((current_label, sql))

    # Drop the preamble (first item before any Q-block)
    return [(lbl, sql) for lbl, sql in queries if lbl.startswith("Q")]


def run_all(conn: sqlite3.Connection, queries: list[tuple[str, str]]) -> None:
    pd.set_option("display.max_columns", 20)
    pd.set_option("display.width", 120)
    pd.set_option("display.float_format", "{:,.2f}".format)

    for label, sql in queries:
        print(f"\n{'=' * 70}")
        print(f"  {label}")
        print("=" * 70)
        try:
            result = pd.read_sql_query(sql, conn)
            print(result.to_string(index=False))
        except Exception as exc:
            print(f"  ERROR: {exc}")


def main() -> None:
    print(f"Loading {CSV_FILE} ...")
    conn = sqlite3.connect(":memory:")
    n = load_data(conn)
    print(f"  {n:,} rows loaded into SQLite.\n")

    with open(SQL_FILE, "r", encoding="utf-8") as f:
        sql_text = f.read()

    queries = split_queries(sql_text)
    print(f"Found {len(queries)} queries in {SQL_FILE}. Running ...\n")
    run_all(conn, queries)
    conn.close()
    print(f"\n{'=' * 70}")
    print("  All queries complete.")
    print("=" * 70)


if __name__ == "__main__":
    main()
