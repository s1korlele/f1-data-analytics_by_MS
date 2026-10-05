from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"race_control_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/race_control"


# Wczytanie sesji i wybór głównych wyścigów
sessions_df = pd.read_csv(SESSIONS_PATH)

race_sessions_df = sessions_df[
    sessions_df["session_name"] == "Race"
].copy()

race_session_keys = race_sessions_df["session_key"].tolist()


# Pobranie komunikatów Race Control
events_clean = []

for session_key in race_session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    race_control = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

    for event in race_control:
        clean_event = {
            "meeting_key": event["meeting_key"],
            "session_key": event["session_key"],
            "date": event["date"],
            "driver_number": event["driver_number"],
            "lap_number": event["lap_number"],
            "category": event["category"],
            "flag": event["flag"],
            "scope": event["scope"],
            "sector": event["sector"],
            "message": event["message"],
        }

        events_clean.append(clean_event)


# Utworzenie DataFrame
race_control_df = pd.DataFrame(events_clean)

if race_control_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych komunikatów Race Control."
    )


# Konwersja typów danych
race_control_df["date"] = pd.to_datetime(
    race_control_df["date"],
    format="ISO8601",
    utc=True,
)

race_control_df["driver_number"] = (
    race_control_df["driver_number"].astype("Int64")
)

race_control_df["sector"] = (
    race_control_df["sector"].astype("Int64")
)


# Kontrola jakości danych
duplicate_count = race_control_df.duplicated().sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} dokładnych duplikatów "
        "Race Control."
    )

missing_session_keys = (
    set(race_session_keys)
    - set(race_control_df["session_key"])
)

if missing_session_keys:
    print(
        "Ostrzeżenie: brak danych race_control dla session_key: "
        f"{sorted(missing_session_keys)}"
    )


# Zapis danych
race_control_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(race_control_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)