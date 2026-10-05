from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "pit_stops_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/pit"


# Wczytanie sesji i wybór głównych wyścigów
sessions_df = pd.read_csv(SESSIONS_PATH)

race_sessions_df = sessions_df[
    sessions_df["session_name"] == "Race"
].copy()

race_session_keys = race_sessions_df["session_key"].tolist()


# Pobranie danych o pit stopach
pit_stops_clean = []

for session_key in race_session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    pit_stops = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

    for pit_stop in pit_stops:
        clean_pit_stop = {
            "meeting_key": pit_stop["meeting_key"],
            "session_key": pit_stop["session_key"],
            "driver_number": pit_stop["driver_number"],
            "lap_number": pit_stop["lap_number"],
            "date": pit_stop["date"],
            "lane_duration": pit_stop["lane_duration"],
            "stop_duration": pit_stop["stop_duration"],
        }

        pit_stops_clean.append(clean_pit_stop)


# Utworzenie DataFrame
pit_stops_df = pd.DataFrame(pit_stops_clean)

if pit_stops_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych o pit stopach.")


# Konwersja typów danych
pit_stops_df["date"] = pd.to_datetime(
    pit_stops_df["date"],
    format="ISO8601",
    utc=True,
)


# Kontrola jakości danych
duplicate_count = pit_stops_df.duplicated(
    subset=[
        "session_key",
        "driver_number",
        "lap_number",
        "date",
    ]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów pit stopów."
    )


# Zapis danych
pit_stops_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(pit_stops_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)
