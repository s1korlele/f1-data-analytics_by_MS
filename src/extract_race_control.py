from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"race_control_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/race_control"


# Race Control występuje także poza głównym Race.
# Pobieramy wszystkie sesje i pozostawiamy filtrowanie modelowi.
sessions_df = pd.read_csv(SESSIONS_PATH)
session_keys = sessions_df["session_key"].tolist()


events_clean = []

for session_key in session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    race_control = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

    for event in race_control:
        clean_event = {
            "meeting_key": event.get("meeting_key"),
            "session_key": event.get("session_key"),
            "date": event.get("date"),
            "driver_number": event.get("driver_number"),
            "lap_number": event.get("lap_number"),
            "category": event.get("category"),
            "flag": event.get("flag"),
            "scope": event.get("scope"),
            "sector": event.get("sector"),
            "message": event.get("message"),
        }

        events_clean.append(clean_event)


race_control_df = pd.DataFrame(events_clean)

if race_control_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych komunikatów Race Control."
    )


race_control_df["date"] = pd.to_datetime(
    race_control_df["date"],
    format="ISO8601",
    utc=True,
)

for column in [
    "meeting_key",
    "session_key",
    "driver_number",
    "lap_number",
    "sector",
]:
    race_control_df[column] = pd.to_numeric(
        race_control_df[column],
        errors="coerce",
    ).astype("Int64")


# Kontrola jakości danych
duplicate_count = race_control_df.duplicated().sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} dokładnych duplikatów "
        "Race Control."
    )


race_control_df = race_control_df.sort_values(
    by=["session_key", "date"],
    na_position="last",
).reset_index(drop=True)

race_control_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(race_control_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)

sessions_with_events = race_control_df["session_key"].nunique()

print(
    f"Race Control występuje w {sessions_with_events} z "
    f"{len(session_keys)} sesji."
)
