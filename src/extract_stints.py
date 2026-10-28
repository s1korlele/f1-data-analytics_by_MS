from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/stints"


def extract_year(year):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"stints_{year}.csv"

    meetings_df = pd.read_csv(meetings_path)
    stints_clean = []

    for meeting_key in meetings_df["meeting_key"].tolist():
        stints = fetch_openf1_json(
            url=f"{OPENF1_URL}?meeting_key={meeting_key}",
            key_name="meeting_key",
            key_value=meeting_key,
        )

        for stint in stints:
            stints_clean.append(
                {
                    "meeting_key": stint.get("meeting_key"),
                    "session_key": stint.get("session_key"),
                    "driver_number": stint.get("driver_number"),
                    "stint_number": stint.get("stint_number"),
                    "compound": stint.get("compound"),
                    "lap_start": stint.get("lap_start"),
                    "lap_end": stint.get("lap_end"),
                    "tyre_age_at_start": stint.get("tyre_age_at_start"),
                }
            )

    stints_df = pd.DataFrame(stints_clean)

    if stints_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych o stintach dla {year}."
        )

    for column in [
        "stint_number",
        "lap_start",
        "lap_end",
        "tyre_age_at_start",
    ]:
        stints_df[column] = pd.to_numeric(
            stints_df[column],
            errors="coerce",
        ).astype("Int64")

    duplicate_count = stints_df.duplicated(
        subset=["session_key", "driver_number", "stint_number"]
    ).sum()
    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów stintów."
        )

    stints_df = stints_df.sort_values(
        ["session_key", "driver_number", "stint_number"]
    ).reset_index(drop=True)

    stints_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(stints_df)} rekordów do "
        f"{processed_data_path.name}."
    )


def main():
    for year in parse_years("Pobiera dane stintów z OpenF1."):
        print(f"\n=== Stints {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
