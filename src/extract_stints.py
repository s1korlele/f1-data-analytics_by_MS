from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = PROJECT_ROOT / "data" / "processed" / "meetings_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "stints_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/stints"


# Wczytanie weekendów Grand Prix
meetings_df = pd.read_csv(MEETINGS_PATH)
meeting_keys = meetings_df["meeting_key"].tolist()


# Pobranie danych o stintach
stints_clean = []

for meeting_key in meeting_keys:
    url = f"{OPENF1_URL}?meeting_key={meeting_key}"

    stints = fetch_openf1_json(
        url=url,
        key_name="meeting_key",
        key_value=meeting_key,
    )

    for stint in stints:
        clean_stint = {
            "meeting_key": stint["meeting_key"],
            "session_key": stint["session_key"],
            "driver_number": stint["driver_number"],
            "stint_number": stint["stint_number"],
            "compound": stint["compound"],
            "lap_start": stint["lap_start"],
            "lap_end": stint["lap_end"],
            "tyre_age_at_start": stint["tyre_age_at_start"],
        }

        stints_clean.append(clean_stint)


# Utworzenie DataFrame
stints_df = pd.DataFrame(stints_clean)

if stints_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych o stintach.")


# Konwersja typów danych
for column in [
    "stint_number",
    "lap_start",
    "lap_end",
    "tyre_age_at_start",
]:
    stints_df[column] = stints_df[column].astype("Int64")


# Kontrola jakości danych
duplicate_count = stints_df.duplicated(
    subset=[
        "session_key",
        "driver_number",
        "stint_number",
    ]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów stintów."
    )


# Zapis danych
stints_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(stints_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)
