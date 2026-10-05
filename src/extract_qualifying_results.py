from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"
PROCESSED_DATA_PATH = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "qualifying_results_2025.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/session_result"


def get_phase_value(values, index):
    """
    Zwraca wartość dla wybranej fazy kwalifikacji.
    """
    if isinstance(values, list):
        if len(values) > index:
            return values[index]
        return None

    if index == 0:
        return values

    return None


# Wczytanie sesji i wybór kwalifikacji
sessions_df = pd.read_csv(SESSIONS_PATH)

qualifying_sessions_df = sessions_df[
    sessions_df["session_type"] == "Qualifying"
].copy()

qualifying_session_keys = (
    qualifying_sessions_df["session_key"].tolist()
)


# Pobranie wyników kwalifikacji
qualifying_results_clean = []

for session_key in qualifying_session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    results = fetch_openf1_json(
        url=url,
        key_name="session_key",
        key_value=session_key,
    )

    for result in results:
        durations = result.get("duration")
        gaps = result.get("gap_to_leader")

        clean_result = {
            "meeting_key": result["meeting_key"],
            "session_key": result["session_key"],
            "driver_number": result["driver_number"],
            "position": result["position"],
            "number_of_laps": result["number_of_laps"],
            "phase_1_duration": get_phase_value(durations, 0),
            "phase_2_duration": get_phase_value(durations, 1),
            "phase_3_duration": get_phase_value(durations, 2),
            "phase_1_gap_to_leader": get_phase_value(gaps, 0),
            "phase_2_gap_to_leader": get_phase_value(gaps, 1),
            "phase_3_gap_to_leader": get_phase_value(gaps, 2),
            "dnf": result["dnf"],
            "dns": result["dns"],
            "dsq": result["dsq"],
        }

        qualifying_results_clean.append(clean_result)


# Utworzenie DataFrame
qualifying_results_df = pd.DataFrame(
    qualifying_results_clean
)

if qualifying_results_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych wyników kwalifikacji."
    )


# Konwersja typów danych
qualifying_results_df["position"] = (
    qualifying_results_df["position"].astype("Int64")
)

qualifying_results_df["number_of_laps"] = (
    qualifying_results_df["number_of_laps"].astype("Int64")
)


# Kontrola jakości danych
duplicate_count = qualifying_results_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów wyników kwalifikacji."
    )


# Zapis danych
qualifying_results_df.to_csv(
    PROCESSED_DATA_PATH,
    index=False,
)

print(
    f"Zapisano {len(qualifying_results_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)
