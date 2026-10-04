from pathlib import Path
import time

import pandas as pd
import requests


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "drivers_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/drivers"


# Wczytanie sesji i wybór głównych wyścigów
sessions_df = pd.read_csv(SESSIONS_PATH)

race_sessions_df = sessions_df[
    sessions_df["session_name"] == "Race"
].copy()

race_session_keys = race_sessions_df["session_key"].tolist()


# Pobranie kierowców dla każdego głównego wyścigu
# Jednosekundowa przerwa ogranicza ryzyko przekroczenia limitu API.
drivers_clean = []

for session_key in race_session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"
    response = requests.get(url)
    response.raise_for_status()
    drivers = response.json()

    for driver in drivers:
        clean_driver = {
            "meeting_key": driver["meeting_key"],
            "session_key": driver["session_key"],
            "driver_number": driver["driver_number"],
            "full_name": driver["full_name"],
            "name_acronym": driver["name_acronym"],
            "first_name": driver["first_name"],
            "last_name": driver["last_name"],
            "team_name": driver["team_name"],
            "team_colour": driver["team_colour"],
            "headshot_url": driver["headshot_url"],
        }

        drivers_clean.append(clean_driver)

    time.sleep(1)


# Utworzenie DataFrame i zapis danych do CSV
drivers_df = pd.DataFrame(drivers_clean)
drivers_df.to_csv(PROCESSED_DATA_PATH, index=False)