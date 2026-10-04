from pathlib import Path

import pandas as pd
import requests


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = PROJECT_ROOT / "data" / "processed" / "meetings_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/sessions?year=2025"


# Pobranie danych o sesjach z OpenF1
response = requests.get(OPENF1_URL)
response.raise_for_status()
sessions = response.json()


# Wybór potrzebnych pól
sessions_clean = []

for session in sessions:
    clean_session = {
        "session_key": session["session_key"],
        "meeting_key": session["meeting_key"],
        "session_type": session["session_type"],
        "session_name": session["session_name"],
        "date_start": session["date_start"],
        "date_end": session["date_end"],
        "year": session["year"],
        "is_cancelled": session["is_cancelled"],
    }

    sessions_clean.append(clean_session)


# Utworzenie DataFrame
sessions_df = pd.DataFrame(sessions_clean)


# Pozostawienie sesji należących do weekendów Grand Prix
meetings_df = pd.read_csv(MEETINGS_PATH)

sessions_df = sessions_df[
    sessions_df["meeting_key"].isin(meetings_df["meeting_key"])
].copy()


# Konwersja dat
sessions_df["date_start"] = pd.to_datetime(sessions_df["date_start"], utc=True)
sessions_df["date_end"] = pd.to_datetime(sessions_df["date_end"], utc=True)


# Zapis przygotowanych danych do CSV
sessions_df.to_csv(PROCESSED_DATA_PATH, index=False)