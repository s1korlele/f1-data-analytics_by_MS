from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"pit_stops_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/pit"


# Pobieramy pit data dla wszystkich sesji Grand Prix.
# Warstwa źródłowa ma być kompletna; decyzję, które typy sesji
# analizować w raporcie, podejmiemy później w modelu.
sessions_df = pd.read_csv(SESSIONS_PATH)
session_keys = sessions_df["session_key"].tolist()


pit_stops_clean = []

for session_key in session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    pit_stops = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

    for pit_stop in pit_stops:
        clean_pit_stop = {
            "meeting_key": pit_stop.get("meeting_key"),
            "session_key": pit_stop.get("session_key"),
            "driver_number": pit_stop.get("driver_number"),
            "lap_number": pit_stop.get("lap_number"),
            "date": pit_stop.get("date"),
            "lane_duration": pit_stop.get("lane_duration"),
            "stop_duration": pit_stop.get("stop_duration"),
        }

        pit_stops_clean.append(clean_pit_stop)


pit_stops_df = pd.DataFrame(pit_stops_clean)

if pit_stops_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych o pit stopach.")


pit_stops_df["date"] = pd.to_datetime(
    pit_stops_df["date"],
    format="ISO8601",
    utc=True,
)

for column in [
    "meeting_key",
    "session_key",
    "driver_number",
    "lap_number",
]:
    pit_stops_df[column] = pd.to_numeric(
        pit_stops_df[column],
        errors="coerce",
    ).astype("Int64")


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


pit_stops_df = pit_stops_df.sort_values(
    by=["session_key", "date", "driver_number"],
    na_position="last",
).reset_index(drop=True)

pit_stops_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(pit_stops_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)

sessions_with_pit = pit_stops_df["session_key"].nunique()

print(
    f"Pit data występuje w {sessions_with_pit} z "
    f"{len(session_keys)} sesji."
)
