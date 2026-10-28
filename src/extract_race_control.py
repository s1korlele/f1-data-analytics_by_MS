from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/race_control"


def extract_year(year):
    sessions_path = PROCESSED_DIR / f"sessions_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"race_control_{year}.csv"

    # Race Control występuje również poza głównym Race.
    # Pobieramy wszystkie sesje GP i pozostawiamy filtrowanie modelowi.
    sessions_df = pd.read_csv(sessions_path)
    session_keys = sessions_df["session_key"].tolist()
    events_clean = []

    for session_key in session_keys:
        race_control = fetch_openf1_json(
            url=f"{OPENF1_URL}?session_key={session_key}",
            key_name="session_key",
            key_value=session_key,
        )

        for event in race_control:
            events_clean.append(
                {
                    "meeting_key": event.get("meeting_key"),
                    "session_key": event.get("session_key"),
                    "date": event.get("date"),
                    "driver_number": event.get("driver_number"),
                    "lap_number": event.get("lap_number"),
                    "category": event.get("category"),
                    "flag": event.get("flag"),
                    "scope": event.get("scope"),
                    "sector": event.get("sector"),
                    "message": event.get("message"),
                }
            )

    race_control_df = pd.DataFrame(events_clean)

    if race_control_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych komunikatów Race Control dla {year}."
        )

    race_control_df["date"] = pd.to_datetime(
        race_control_df["date"],
        format="ISO8601",
        utc=True,
    )

    # lap_number jest konwertowany jawnie do Int64. Bez tego pandas
    # może zapisać wartości jako 1.0/2.0 przy NULL-ach, co powoduje
    # błąd konwersji w SSIS Flat File Source.
    for column in [
        "meeting_key",
        "session_key",
        "driver_number",
        "lap_number",
        "sector",
    ]:
        race_control_df[column] = pd.to_numeric(
            race_control_df[column],
            errors="coerce",
        ).astype("Int64")

    duplicate_count = race_control_df.duplicated().sum()
    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} dokładnych duplikatów "
            "Race Control."
        )

    race_control_df = race_control_df.sort_values(
        by=["session_key", "date"],
        na_position="last",
    ).reset_index(drop=True)

    race_control_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(race_control_df)} rekordów do "
        f"{processed_data_path.name}."
    )

    sessions_with_events = race_control_df["session_key"].nunique()
    print(
        f"{year}: Race Control występuje w {sessions_with_events} "
        f"z {len(session_keys)} sesji."
    )


def main():
    for year in parse_years("Pobiera komunikaty Race Control z OpenF1."):
        print(f"\n=== Race Control {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
