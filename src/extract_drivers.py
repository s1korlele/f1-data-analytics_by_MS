from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/drivers"


def extract_year(year):
    sessions_path = PROCESSED_DIR / f"sessions_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"drivers_{year}.csv"

    sessions_df = pd.read_csv(sessions_path)
    session_keys = sessions_df["session_key"].tolist()
    drivers_clean = []

    for session_key in session_keys:
        drivers = fetch_openf1_json(
            url=f"{OPENF1_URL}?session_key={session_key}",
            key_name="session_key",
            key_value=session_key,
        )

        for driver in drivers:
            drivers_clean.append(
                {
                    "meeting_key": driver.get("meeting_key"),
                    "session_key": driver.get("session_key"),
                    "driver_number": driver.get("driver_number"),
                    "full_name": driver.get("full_name"),
                    "name_acronym": driver.get("name_acronym"),
                    "first_name": driver.get("first_name"),
                    "last_name": driver.get("last_name"),
                    "team_name": driver.get("team_name"),
                    "team_colour": driver.get("team_colour"),
                    "headshot_url": driver.get("headshot_url"),
                }
            )

    drivers_df = pd.DataFrame(drivers_clean)

    if drivers_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych o kierowcach dla {year}."
        )

    duplicate_count = drivers_df.duplicated(
        subset=["session_key", "driver_number"]
    ).sum()

    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów kierowców "
            "w obrębie sesji."
        )

    missing_session_keys = (
        set(sessions_df["session_key"])
        - set(drivers_df["session_key"])
    )

    if missing_session_keys:
        print(
            f"{year}: ostrzeżenie - brak danych drivers dla session_key: "
            f"{sorted(missing_session_keys)}"
        )

    drivers_df = drivers_df.sort_values(
        ["session_key", "driver_number"]
    ).reset_index(drop=True)

    drivers_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(drivers_df)} rekordów do "
        f"{processed_data_path.name}."
    )


def main():
    for year in parse_years("Pobiera kierowców F1 z OpenF1."):
        print(f"\n=== Drivers {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
