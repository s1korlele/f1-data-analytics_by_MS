from pathlib import Path

import pandas as pd
import requests


PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "meetings_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/meetings?year=2025"


# Pobranie danych o weekendach wyścigowych z OpenF1
response = requests.get(OPENF1_URL)
response.raise_for_status()
meetings = response.json()


# Wybór potrzebnych pól i pominięcie testów przedsezonowych
meetings_clean = []

for meeting in meetings:
    if meeting["meeting_name"] != "Pre-Season Testing":
        clean_meeting = {
            "meeting_key": meeting["meeting_key"],
            "meeting_name": meeting["meeting_name"],
            "location": meeting["location"],
            "country_code": meeting["country_code"],
            "country_name": meeting["country_name"],
            "country_flag": meeting["country_flag"],
            "circuit_key": meeting["circuit_key"],
            "circuit_short_name": meeting["circuit_short_name"],
            "circuit_type": meeting["circuit_type"],
            "circuit_image": meeting["circuit_image"],
            "date_start": meeting["date_start"],
            "date_end": meeting["date_end"],
            "year": meeting["year"],
            "is_cancelled": meeting["is_cancelled"],
        }

        meetings_clean.append(clean_meeting)


# Utworzenie DataFrame i konwersja dat
meetings_df = pd.DataFrame(meetings_clean)

meetings_df["date_start"] = pd.to_datetime(meetings_df["date_start"], utc=True)
meetings_df["date_end"] = pd.to_datetime(meetings_df["date_end"], utc=True)


# Zapis przygotowanych danych do CSV
meetings_df.to_csv(PROCESSED_DATA_PATH, index=False)