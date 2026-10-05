from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"drivers_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/drivers"


# Wczytanie wszystkich sesji
sessions_df = pd.read_csv(SESSIONS_PATH)
session_keys = sessions_df["session_key"].tolist()


# Pobranie kierowców dla każdej sesji
drivers_clean = []

for session_key in session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    drivers = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

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


# Utworzenie DataFrame
drivers_df = pd.DataFrame(drivers_clean)

if drivers_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych o kierowcach.")


# Kontrola jakości danych
duplicate_count = drivers_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów kierowców "
        "w obrębie sesji."
    )

missing_session_keys = (
    set(sessions_df["session_key"])
    - set(drivers_df["session_key"])
)

if missing_session_keys:
    print(
        "Ostrzeżenie: brak danych drivers dla session_key: "
        f"{sorted(missing_session_keys)}"
    )


# Zapis danych
drivers_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(drivers_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)