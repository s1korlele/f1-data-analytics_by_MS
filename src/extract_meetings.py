from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"meetings_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/meetings"


# Pobranie danych o weekendach Grand Prix
url = f"{OPENF1_URL}?year={YEAR}"

meetings = fetch_openf1_json(
    url=url,
    key_name="year",
    key_value=YEAR,
)


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


# Utworzenie DataFrame
meetings_df = pd.DataFrame(meetings_clean)

if meetings_df.empty:
    raise RuntimeError("Nie pobrano żadnych weekendów Grand Prix.")


# Konwersja typów danych
meetings_df["date_start"] = pd.to_datetime(
    meetings_df["date_start"],
    format="ISO8601",
    utc=True,
)

meetings_df["date_end"] = pd.to_datetime(
    meetings_df["date_end"],
    format="ISO8601",
    utc=True,
)


# Kontrola jakości danych
duplicate_count = meetings_df.duplicated(
    subset=["meeting_key"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów meeting_key."
    )


# Zapis danych
meetings_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(meetings_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)