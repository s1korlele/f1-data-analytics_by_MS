from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = PROJECT_ROOT / "data" / "processed" / "meetings_2025.csv"
SESSIONS_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "laps_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/laps"


# Wczytanie weekendów Grand Prix
meetings_df = pd.read_csv(MEETINGS_PATH)
meeting_keys = meetings_df["meeting_key"].tolist()


# Pobranie danych okrążeń
laps_clean = []

for meeting_key in meeting_keys:
    url = f"{OPENF1_URL}?meeting_key={meeting_key}"

    laps = fetch_openf1_json(
        url=url,
        key_name="meeting_key",
        key_value=meeting_key,
    )

    for lap in laps:
        clean_lap = {
            "meeting_key": lap["meeting_key"],
            "session_key": lap["session_key"],
            "driver_number": lap["driver_number"],
            "lap_number": lap["lap_number"],
            "date_start": lap["date_start"],
            "lap_duration": lap["lap_duration"],
            "duration_sector_1": lap["duration_sector_1"],
            "duration_sector_2": lap["duration_sector_2"],
            "duration_sector_3": lap["duration_sector_3"],
            "i1_speed": lap["i1_speed"],
            "i2_speed": lap["i2_speed"],
            "st_speed": lap["st_speed"],
            "is_pit_out_lap": lap["is_pit_out_lap"],
        }

        laps_clean.append(clean_lap)


# Utworzenie DataFrame
laps_df = pd.DataFrame(laps_clean)

if laps_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych okrążeń.")


# Konwersja typów danych
laps_df["date_start"] = pd.to_datetime(
    laps_df["date_start"],
    format="ISO8601",
    utc=True,
)

laps_df["i1_speed"] = laps_df["i1_speed"].astype("Int64")
laps_df["i2_speed"] = laps_df["i2_speed"].astype("Int64")
laps_df["st_speed"] = laps_df["st_speed"].astype("Int64")


# Kontrola jakości danych
duplicate_count = laps_df.duplicated(
    subset=[
        "session_key",
        "driver_number",
        "lap_number",
    ]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów okrążeń."
    )

sessions_df = pd.read_csv(SESSIONS_PATH)

missing_session_keys = (
    set(sessions_df["session_key"])
    - set(laps_df["session_key"])
)

if missing_session_keys:
    print(
        "Ostrzeżenie: brak danych laps dla session_key: "
        f"{sorted(missing_session_keys)}"
    )


# Zapis danych
laps_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(laps_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)
