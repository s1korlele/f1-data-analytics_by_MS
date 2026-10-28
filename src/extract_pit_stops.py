from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/pit"


def extract_year(year):
    sessions_path = PROCESSED_DIR / f"sessions_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"pit_stops_{year}.csv"

    # Pobieramy pit data dla wszystkich sesji GP. Decyzję, które
    # typy sesji analizować, pozostawiamy modelowi semantycznemu.
    sessions_df = pd.read_csv(sessions_path)
    session_keys = sessions_df["session_key"].tolist()
    pit_stops_clean = []

    for session_key in session_keys:
        pit_stops = fetch_openf1_json(
            url=f"{OPENF1_URL}?session_key={session_key}",
            key_name="session_key",
            key_value=session_key,
        )

        for pit_stop in pit_stops:
            pit_stops_clean.append(
                {
                    "meeting_key": pit_stop.get("meeting_key"),
                    "session_key": pit_stop.get("session_key"),
                    "driver_number": pit_stop.get("driver_number"),
                    "lap_number": pit_stop.get("lap_number"),
                    "date": pit_stop.get("date"),
                    "lane_duration": pit_stop.get("lane_duration"),
                    "stop_duration": pit_stop.get("stop_duration"),
                }
            )

    pit_stops_df = pd.DataFrame(pit_stops_clean)

    if pit_stops_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych o pit stopach dla {year}."
        )

    pit_stops_df["date"] = pd.to_datetime(
        pit_stops_df["date"],
        format="ISO8601",
        utc=True,
    )

    for column in [
        "meeting_key",
        "session_key",
        "driver_number",
        "lap_number",
    ]:
        pit_stops_df[column] = pd.to_numeric(
            pit_stops_df[column],
            errors="coerce",
        ).astype("Int64")

    duplicate_count = pit_stops_df.duplicated(
        subset=["session_key", "driver_number", "lap_number", "date"]
    ).sum()
    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów pit stopów."
        )

    pit_stops_df = pit_stops_df.sort_values(
        by=["session_key", "date", "driver_number"],
        na_position="last",
    ).reset_index(drop=True)

    pit_stops_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(pit_stops_df)} rekordów do "
        f"{processed_data_path.name}."
    )

    sessions_with_pit = pit_stops_df["session_key"].nunique()
    print(
        f"{year}: pit data występuje w {sessions_with_pit} "
        f"z {len(session_keys)} sesji."
    )


def main():
    for year in parse_years("Pobiera dane pit stopów z OpenF1."):
        print(f"\n=== Pit Stops {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
