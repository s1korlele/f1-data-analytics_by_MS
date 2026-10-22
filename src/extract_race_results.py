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


# Wczytanie sesji i wybór wszystkich sesji typu Race.
# OpenF1 używa session_type='Race' zarówno dla głównego Race,
# jak i dla Sprintu. Nie filtrujemy po session_name.
sessions_df = pd.read_csv(SESSIONS_PATH)

race_sessions_df = sessions_df[
    sessions_df["session_type"] == "Race"
].copy()

race_session_keys = race_sessions_df["session_key"].tolist()


# Pobranie oficjalnych wyników Race i Sprint.
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
            "meeting_key": result.get("meeting_key"),
            "session_key": result.get("session_key"),
            "driver_number": result.get("driver_number"),
            "position": result.get("position"),
            "number_of_laps": result.get("number_of_laps"),
            "points": result.get("points"),
            "dnf": result.get("dnf"),
            "dns": result.get("dns"),
            "dsq": result.get("dsq"),
            "duration": result.get("duration"),
            "gap_to_leader": result.get("gap_to_leader"),
        }

        results_clean.append(clean_result)


race_results_df = pd.DataFrame(results_clean)

if race_results_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych wyników sesji typu Race."
    )


for column in [
    "meeting_key",
    "session_key",
    "driver_number",
    "position",
    "number_of_laps",
]:
    race_results_df[column] = pd.to_numeric(
        race_results_df[column],
        errors="coerce",
    ).astype("Int64")


# Kontrola jakości danych
duplicate_count = race_results_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów wyników "
        "Race/Sprint."
    )

missing_session_keys = (
    set(race_session_keys)
    - set(race_results_df["session_key"].dropna().astype(int))
)

if missing_session_keys:
    missing_sessions = race_sessions_df[
        race_sessions_df["session_key"].isin(missing_session_keys)
    ][
        ["session_key", "session_name", "is_cancelled"]
    ]

    print(
        "Ostrzeżenie: brak session_result dla części "
        "sesji typu Race:"
    )

    for row in missing_sessions.itertuples(index=False):
        print(
            f"- session_key={row.session_key}, "
            f"session_name='{row.session_name}', "
            f"cancelled={row.is_cancelled}"
        )

invalid_missing_positions = race_results_df[
    race_results_df["position"].isna()
    & ~race_results_df[["dnf", "dns", "dsq"]]
        .fillna(False)
        .any(axis=1)
]

if not invalid_missing_positions.empty:
    raise ValueError(
        "Wykryto brak pozycji bez statusu DNF/DNS/DSQ."
    )


race_results_df = race_results_df.sort_values(
    by=["session_key", "position", "driver_number"],
    na_position="last",
).reset_index(drop=True)

race_results_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(race_results_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)

print(
    "Pobrane sesje typu Race: "
    + ", ".join(
        sorted(
            race_sessions_df["session_name"]
            .dropna()
            .unique()
        )
    )
)
