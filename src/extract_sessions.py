from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/sessions"


def extract_year(year):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"sessions_{year}.csv"

    sessions = fetch_openf1_json(
        url=f"{OPENF1_URL}?year={year}",
        key_name="year",
        key_value=year,
    )

    # Zachowujemy dokładnie session_type i session_name z OpenF1.
    sessions_clean = [
        {
            "session_key": session.get("session_key"),
            "meeting_key": session.get("meeting_key"),
            "session_type": session.get("session_type"),
            "session_name": session.get("session_name"),
            "date_start": session.get("date_start"),
            "date_end": session.get("date_end"),
            "year": session.get("year"),
            "is_cancelled": session.get("is_cancelled"),
        }
        for session in sessions
    ]

    sessions_df = pd.DataFrame(sessions_clean)

    if sessions_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych o sesjach dla {year}."
        )

    meetings_df = pd.read_csv(meetings_path)
    sessions_df = sessions_df[
        sessions_df["meeting_key"].isin(meetings_df["meeting_key"])
    ].copy()

    sessions_df["date_start"] = pd.to_datetime(
        sessions_df["date_start"],
        format="ISO8601",
        utc=True,
    )
    sessions_df["date_end"] = pd.to_datetime(
        sessions_df["date_end"],
        format="ISO8601",
        utc=True,
    )

    duplicate_count = sessions_df.duplicated(
        subset=["session_key"]
    ).sum()

    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów session_key."
        )

    sessions_df = sessions_df.sort_values(
        ["date_start", "session_key"]
    ).reset_index(drop=True)

    sessions_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(sessions_df)} rekordów do "
        f"{processed_data_path.name}."
    )

    print(f"{year}: typy i nazwy sesji znalezione w OpenF1:")
    session_summary = (
        sessions_df[["session_type", "session_name"]]
        .drop_duplicates()
        .sort_values(["session_type", "session_name"])
    )
    for row in session_summary.itertuples(index=False):
        print(
            f"- session_type='{row.session_type}', "
            f"session_name='{row.session_name}'"
        )


def main():
    for year in parse_years("Pobiera sesje F1 z OpenF1."):
        print(f"\n=== Sessions {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
