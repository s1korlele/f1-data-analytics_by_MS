from pathlib import Path
import time

import pandas as pd
import requests


YEAR = 2025

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"meetings_{YEAR}.csv"
)
SESSIONS_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"sessions_{YEAR}.csv"
)
PROCESSED_DATA_PATH = (
    PROJECT_ROOT / "data" / "processed" / f"starting_grid_{YEAR}.csv"
)

JOLPICA_BASE_URL = f"https://api.jolpi.ca/ergast/f1/{YEAR}"
USER_AGENT = "f1-data-analytics-by-MS/1.0"
PAGE_LIMIT = 100
REQUEST_DELAY = 0.5
MAX_ATTEMPTS = 3
REQUEST_TIMEOUT = 30


def fetch_jolpica_page(resource, offset):
    """Pobiera jedną stronę danych Jolpica z retry i rate-limit handling."""
    url = f"{JOLPICA_BASE_URL}/{resource}/"

    params = {
        "limit": PAGE_LIMIT,
        "offset": offset,
    }

    headers = {
        "User-Agent": USER_AGENT,
    }

    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            response = requests.get(
                url,
                params=params,
                headers=headers,
                timeout=REQUEST_TIMEOUT,
            )

            if response.status_code == 200:
                time.sleep(REQUEST_DELAY)
                return response.json()

            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After")
                wait_seconds = (
                    float(retry_after)
                    if retry_after
                    else 10 * attempt
                )

                print(
                    f"Limit API Jolpica dla {resource}, offset {offset}. "
                    f"Próba {attempt}/{MAX_ATTEMPTS}. "
                    f"Ponowienie za {wait_seconds:.0f} s."
                )

                time.sleep(wait_seconds)
                continue

            print(
                f"Błąd Jolpica dla {resource}, offset {offset}: "
                f"HTTP {response.status_code}"
            )
            return None

        except requests.exceptions.RequestException as error:
            print(
                f"Problem z połączeniem dla {resource}, offset {offset}. "
                f"Próba {attempt}/{MAX_ATTEMPTS}: {error}"
            )

            if attempt < MAX_ATTEMPTS:
                time.sleep(5 * attempt)

    return None


def collect_results(resource, results_key, session_name, round_to_meeting_key, session_lookup):
    """
    Pobiera Race/Sprint results z Jolpica i wyciąga z nich grid.

    resource:
      - results -> Race
      - sprint  -> Sprint
    """
    records = []
    offset = 0
    total_results = None

    while total_results is None or offset < total_results:
        data = fetch_jolpica_page(resource, offset)

        if data is None:
            raise RuntimeError(
                f"Nie udało się pobrać danych Jolpica: {resource}, "
                f"offset={offset}."
            )

        mr_data = data["MRData"]
        race_table = mr_data["RaceTable"]
        races = race_table.get("Races", [])

        total_results = int(mr_data.get("total", 0))

        for race in races:
            round_number = int(race["round"])

            meeting_key = round_to_meeting_key.get(round_number)

            if meeting_key is None:
                raise ValueError(
                    f"Nie znaleziono meeting_key dla rundy "
                    f"{round_number}: {race.get('raceName')}."
                )

            session_key = session_lookup.get(
                (meeting_key, session_name)
            )

            if session_key is None:
                # Dla resource='sprint' jest to normalne na weekendach bez Sprintu.
                if session_name == "Sprint":
                    continue

                raise ValueError(
                    f"Nie znaleziono sesji '{session_name}' dla "
                    f"meeting_key={meeting_key}, round={round_number}."
                )

            for result in race.get(results_key, []):
                driver = result.get("Driver", {})
                constructor = result.get("Constructor", {})

                grid_position = result.get("grid")

                records.append(
                    {
                        "meeting_key": meeting_key,
                        "session_key": session_key,
                        "round": round_number,
                        "race_name": race.get("raceName"),
                        "driver_number": result.get("number"),
                        "driver_code": driver.get("code"),
                        "driver_name": (
                            f"{driver.get('givenName', '')} "
                            f"{driver.get('familyName', '')}"
                        ).strip(),
                        "team_name": constructor.get("name"),
                        "grid_position": grid_position,
                    }
                )

        offset += PAGE_LIMIT

    return records


# =====================================================
# Źródła pomocnicze
# =====================================================

meetings_df = pd.read_csv(MEETINGS_PATH)
sessions_df = pd.read_csv(SESSIONS_PATH)

meetings_df["date_start"] = pd.to_datetime(
    meetings_df["date_start"],
    format="ISO8601",
    utc=True,
)

# Zachowujemy dotychczasowe mapowanie rundy na meeting_key:
# kolejność weekendów według date_start.
meetings_ordered_df = meetings_df.sort_values(
    ["date_start", "meeting_key"]
).reset_index(drop=True)

meetings_ordered_df["round"] = (
    meetings_ordered_df.index + 1
)

round_to_meeting_key = dict(
    zip(
        meetings_ordered_df["round"],
        meetings_ordered_df["meeting_key"],
    )
)

# Mapujemy konkretne sesje Race i Sprint do ich OpenF1 session_key.
race_sessions_df = sessions_df[
    sessions_df["session_name"].isin(["Race", "Sprint"])
].copy()

session_lookup = {
    (int(row.meeting_key), str(row.session_name)): int(row.session_key)
    for row in race_sessions_df.itertuples(index=False)
}


# =====================================================
# Race starting grid
# =====================================================

print("Pobieranie starting grid dla Race z Jolpica...")

race_grid_records = collect_results(
    resource="results",
    results_key="Results",
    session_name="Race",
    round_to_meeting_key=round_to_meeting_key,
    session_lookup=session_lookup,
)

print(
    f"Race grid: pobrano {len(race_grid_records)} rekordów."
)


# =====================================================
# Sprint starting grid
# =====================================================

print("Pobieranie starting grid dla Sprint z Jolpica...")

sprint_grid_records = collect_results(
    resource="sprint",
    results_key="SprintResults",
    session_name="Sprint",
    round_to_meeting_key=round_to_meeting_key,
    session_lookup=session_lookup,
)

print(
    f"Sprint grid: pobrano {len(sprint_grid_records)} rekordów."
)


# =====================================================
# Połączenie i walidacja
# =====================================================

starting_grid_df = pd.DataFrame(
    race_grid_records + sprint_grid_records
)

if starting_grid_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych danych pól startowych z Jolpica."
    )

for column in [
    "meeting_key",
    "session_key",
    "round",
    "driver_number",
    "grid_position",
]:
    starting_grid_df[column] = pd.to_numeric(
        starting_grid_df[column],
        errors="coerce",
    ).astype("Int64")

# Grain: 1 kierowca x 1 sesja startowa.
duplicate_count = starting_grid_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    duplicate_sample = starting_grid_df[
        starting_grid_df.duplicated(
            subset=["session_key", "driver_number"],
            keep=False,
        )
    ][
        [
            "meeting_key",
            "session_key",
            "round",
            "driver_number",
            "grid_position",
        ]
    ].head(20)

    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów "
        "session_key + driver_number w starting_grid.\n"
        f"Przykłady:\n{duplicate_sample.to_string(index=False)}"
    )

missing_grid_count = starting_grid_df[
    "grid_position"
].isna().sum()

if missing_grid_count > 0:
    print(
        f"Ostrzeżenie: {missing_grid_count} rekordów "
        "nie ma grid_position."
    )

starting_grid_df = starting_grid_df.sort_values(
    by=["round", "session_key", "grid_position"],
    na_position="last",
).reset_index(drop=True)

starting_grid_df.to_csv(
    PROCESSED_DATA_PATH,
    index=False,
)

race_session_count = starting_grid_df[
    starting_grid_df["session_key"].isin(
        race_sessions_df.loc[
            race_sessions_df["session_name"] == "Race",
            "session_key",
        ]
    )
]["session_key"].nunique()

sprint_session_count = starting_grid_df[
    starting_grid_df["session_key"].isin(
        race_sessions_df.loc[
            race_sessions_df["session_name"] == "Sprint",
            "session_key",
        ]
    )
]["session_key"].nunique()

print(
    f"Zapisano {len(starting_grid_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)

print(
    f"Sesje z gridem: Race={race_session_count}, "
    f"Sprint={sprint_session_count}."
)
