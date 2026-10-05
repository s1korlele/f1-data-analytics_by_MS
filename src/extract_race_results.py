from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"race_results_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/session_result"


# Wczytanie sesji i wybór głównych wyścigów
sessions_df = pd.read_csv(SESSIONS_PATH)

race_sessions_df = sessions_df[
    sessions_df["session_name"] == "Race"
].copy()

race_session_keys = race_sessions_df["session_key"].tolist()


# Pobranie wyników wyścigów
results_clean = []

for session_key in race_session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    race_results = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

    for result in race_results:
        clean_result = {
            "meeting_key": result["meeting_key"],
            "session_key": result["session_key"],
            "driver_number": result["driver_number"],
            "position": result["position"],
            "number_of_laps": result["number_of_laps"],
            "points": result["points"],
            "dnf": result["dnf"],
            "dns": result["dns"],
            "dsq": result["dsq"],
            "duration": result["duration"],
            "gap_to_leader": result["gap_to_leader"],
        }

        results_clean.append(clean_result)


# Utworzenie DataFrame
race_results_df = pd.DataFrame(results_clean)

if race_results_df.empty:
    raise RuntimeError("Nie pobrano żadnych wyników wyścigów.")


# Konwersja typów danych
race_results_df["position"] = (
    race_results_df["position"].astype("Int64")
)

race_results_df["number_of_laps"] = (
    race_results_df["number_of_laps"].astype("Int64")
)


# Kontrola jakości danych
duplicate_count = race_results_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów wyników wyścigów."
    )

missing_session_keys = (
    set(race_session_keys)
    - set(race_results_df["session_key"])
)

if missing_session_keys:
    print(
        "Ostrzeżenie: brak wyników dla session_key: "
        f"{sorted(missing_session_keys)}"
    )

invalid_missing_positions = race_results_df[
    race_results_df["position"].isna()
    & ~race_results_df[["dnf", "dns", "dsq"]].any(axis=1)
]

if not invalid_missing_positions.empty:
    raise ValueError(
        "Wykryto brak pozycji bez statusu DNF/DNS/DSQ."
    )


# Zapis danych
race_results_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(race_results_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)