from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/meetings"


def extract_year(year):
    processed_data_path = PROCESSED_DIR / f"meetings_{year}.csv"

    meetings = fetch_openf1_json(
        url=f"{OPENF1_URL}?year={year}",
        key_name="year",
        key_value=year,
    )

    meetings_clean = []

    for meeting in meetings:
        # Testy przedsezonowe nie należą do kalendarza GP.
        if meeting.get("meeting_name") == "Pre-Season Testing":
            continue

        # Odwołane weekendy nie powinny trafiać do dalszego ETL.
        if bool(meeting.get("is_cancelled")):
            continue

        meetings_clean.append(
            {
                "meeting_key": meeting.get("meeting_key"),
                "meeting_name": meeting.get("meeting_name"),
                "location": meeting.get("location"),
                "country_code": meeting.get("country_code"),
                "country_name": meeting.get("country_name"),
                "country_flag": meeting.get("country_flag"),
                "circuit_key": meeting.get("circuit_key"),
                "circuit_short_name": meeting.get("circuit_short_name"),
                "circuit_type": meeting.get("circuit_type"),
                "circuit_image": meeting.get("circuit_image"),
                "date_start": meeting.get("date_start"),
                "date_end": meeting.get("date_end"),
                "year": meeting.get("year"),
                "is_cancelled": meeting.get("is_cancelled"),
            }
        )

    meetings_df = pd.DataFrame(meetings_clean)

    if meetings_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych weekendów Grand Prix dla {year}."
        )

    meetings_df["date_start"] = pd.to_datetime(
        meetings_df["date_start"],
        format="ISO8601",
        utc=True,
    )
    meetings_df["date_end"] = pd.to_datetime(
        meetings_df["date_end"],
        format="ISO8601",
        utc=True,
    )

    duplicate_count = meetings_df.duplicated(
        subset=["meeting_key"]
    ).sum()

    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów meeting_key."
        )

    meetings_df = meetings_df.sort_values(
        ["date_start", "meeting_key"]
    ).reset_index(drop=True)

    meetings_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(meetings_df)} rekordów do "
        f"{processed_data_path.name}."
    )


def main():
    for year in parse_years("Pobiera weekendy Grand Prix z OpenF1."):
        print(f"\n=== Meetings {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
