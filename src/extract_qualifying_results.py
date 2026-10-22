from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / f"qualifying_results_{YEAR}.csv"
)

OPENF1_URL = "https://api.openf1.org/v1/session_result"
QUALIFYING_SESSION_TYPES = {
    "Qualifying",
    "Sprint Qualifying",
}


def get_phase_value(values, index):
    """
    Zwraca wartość dla wybranej fazy kwalifikacji.
    Dla wartości skalarnej zwraca ją tylko jako fazę 1.
    """
    if isinstance(values, list):
        if len(values) > index:
            return values[index]
        return None

    if index == 0:
        return values

    return None


# Wczytanie wszystkich sesji kwalifikacyjnych.
# Nie filtrujemy po nazwie konkretnej sesji; opieramy się
# na źródłowym session_type.
sessions_df = pd.read_csv(SESSIONS_PATH)

qualifying_sessions_df = sessions_df[
    sessions_df["session_type"].isin(
        QUALIFYING_SESSION_TYPES
    )
].copy()

qualifying_session_keys = (
    qualifying_sessions_df["session_key"].tolist()
)


# Pobranie wyników Qualifying i Sprint Qualifying.
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
            "meeting_key": result.get("meeting_key"),
            "session_key": result.get("session_key"),
            "driver_number": result.get("driver_number"),
            "position": result.get("position"),
            "number_of_laps": result.get("number_of_laps"),
            "phase_1_duration": get_phase_value(durations, 0),
            "phase_2_duration": get_phase_value(durations, 1),
            "phase_3_duration": get_phase_value(durations, 2),
            "phase_1_gap_to_leader": get_phase_value(gaps, 0),
            "phase_2_gap_to_leader": get_phase_value(gaps, 1),
            "phase_3_gap_to_leader": get_phase_value(gaps, 2),
            "dnf": result.get("dnf"),
            "dns": result.get("dns"),
            "dsq": result.get("dsq"),
        }

        qualifying_results_clean.append(clean_result)


qualifying_results_df = pd.DataFrame(
    qualifying_results_clean
)

if qualifying_results_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych wyników sesji kwalifikacyjnych."
    )


for column in [
    "meeting_key",
    "session_key",
    "driver_number",
    "position",
    "number_of_laps",
]:
    qualifying_results_df[column] = pd.to_numeric(
        qualifying_results_df[column],
        errors="coerce",
    ).astype("Int64")


# Kontrola jakości danych
duplicate_count = qualifying_results_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów wyników "
        "Qualifying/Sprint Qualifying."
    )

missing_session_keys = (
    set(qualifying_session_keys)
    - set(
        qualifying_results_df["session_key"]
        .dropna()
        .astype(int)
    )
)

if missing_session_keys:
    missing_sessions = qualifying_sessions_df[
        qualifying_sessions_df["session_key"].isin(
            missing_session_keys
        )
    ][
        ["session_key", "session_name", "is_cancelled"]
    ]

    print(
        "Ostrzeżenie: brak session_result dla części "
        "sesji kwalifikacyjnych:"
    )

    for row in missing_sessions.itertuples(index=False):
        print(
            f"- session_key={row.session_key}, "
            f"session_name='{row.session_name}', "
            f"cancelled={row.is_cancelled}"
        )


qualifying_results_df = qualifying_results_df.sort_values(
    by=["session_key", "position", "driver_number"],
    na_position="last",
).reset_index(drop=True)

qualifying_results_df.to_csv(
    PROCESSED_DATA_PATH,
    index=False,
)

print(
    f"Zapisano {len(qualifying_results_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)

print(
    "Pobrane typy kwalifikacji: "
    + ", ".join(
        sorted(
            qualifying_sessions_df["session_type"]
            .dropna()
            .unique()
        )
    )
)
