from pathlib import Path
import time

import pandas as pd
import requests


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "race_control_2025.csv"

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
    response = requests.get(url)

    if response.status_code == 200:
        race_control = response.json()

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

    else:
        print(
            f"Błąd dla session_key {session_key}: "
            f"{response.status_code}"
        )

    time.sleep(2.1)


# Utworzenie DataFrame
race_control_df = pd.DataFrame(events_clean)


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


# Zapis danych
race_control_df.to_csv(PROCESSED_DATA_PATH, index=False)