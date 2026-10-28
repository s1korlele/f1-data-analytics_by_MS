from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/laps"


def extract_year(year):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    sessions_path = PROCESSED_DIR / f"sessions_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"laps_{year}.csv"

    meetings_df = pd.read_csv(meetings_path)
    laps_clean = []

    for meeting_key in meetings_df["meeting_key"].tolist():
        laps = fetch_openf1_json(
            url=f"{OPENF1_URL}?meeting_key={meeting_key}",
            key_name="meeting_key",
            key_value=meeting_key,
        )

        for lap in laps:
            laps_clean.append(
                {
                    "meeting_key": lap.get("meeting_key"),
                    "session_key": lap.get("session_key"),
                    "driver_number": lap.get("driver_number"),
                    "lap_number": lap.get("lap_number"),
                    "date_start": lap.get("date_start"),
                    "lap_duration": lap.get("lap_duration"),
                    "duration_sector_1": lap.get("duration_sector_1"),
                    "duration_sector_2": lap.get("duration_sector_2"),
                    "duration_sector_3": lap.get("duration_sector_3"),
                    "i1_speed": lap.get("i1_speed"),
                    "i2_speed": lap.get("i2_speed"),
                    "st_speed": lap.get("st_speed"),
                    "is_pit_out_lap": lap.get("is_pit_out_lap"),
                }
            )

    laps_df = pd.DataFrame(laps_clean)

    if laps_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych okrążeń dla {year}."
        )

    laps_df["date_start"] = pd.to_datetime(
        laps_df["date_start"],
        format="ISO8601",
        utc=True,
    )

    for column in ["i1_speed", "i2_speed", "st_speed"]:
        laps_df[column] = pd.to_numeric(
            laps_df[column],
            errors="coerce",
        ).astype("Int64")

    duplicate_count = laps_df.duplicated(
        subset=["session_key", "driver_number", "lap_number"]
    ).sum()
    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów okrążeń."
        )

    sessions_df = pd.read_csv(sessions_path)
    missing_session_keys = (
        set(sessions_df["session_key"])
        - set(laps_df["session_key"])
    )
    if missing_session_keys:
        print(
            f"{year}: ostrzeżenie - brak danych laps dla session_key: "
            f"{sorted(missing_session_keys)}"
        )

    laps_df = laps_df.sort_values(
        ["session_key", "driver_number", "lap_number"]
    ).reset_index(drop=True)

    laps_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(laps_df)} rekordów do "
        f"{processed_data_path.name}."
    )


def main():
    for year in parse_years("Pobiera dane okrążeń z OpenF1."):
        print(f"\n=== Laps {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
