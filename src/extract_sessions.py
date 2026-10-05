from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"meetings_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/sessions"


# Pobranie danych o sesjach
url = f"{OPENF1_URL}?year={YEAR}"

sessions = fetch_openf1_json(
    url=url,
    key_name="year",
    key_value=YEAR,
)


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

if sessions_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych o sesjach.")


# Pozostawienie sesji należących do weekendów Grand Prix
meetings_df = pd.read_csv(MEETINGS_PATH)

sessions_df = sessions_df[
    sessions_df["meeting_key"].isin(
        meetings_df["meeting_key"]
    )
].copy()


# Konwersja typów danych
sessions_df["date_start"] = pd.to_datetime(
    sessions_df["date_start"],
    format="ISO8601",
    utc=True,
)

sessions_df["date_end"] = pd.to_datetime(
    sessions_df["date_end"],
    format="ISO8601",
    utc=True,
)


# Kontrola jakości danych
duplicate_count = sessions_df.duplicated(
    subset=["session_key"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów session_key."
    )


# Zapis danych
sessions_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(sessions_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)