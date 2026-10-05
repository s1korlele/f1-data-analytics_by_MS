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

JOLPICA_URL = f"https://api.jolpi.ca/ergast/f1/{YEAR}/results/"
USER_AGENT = "f1-data-analytics-by-MS/1.0"
PAGE_LIMIT = 100
REQUEST_DELAY = 0.5
MAX_ATTEMPTS = 3
REQUEST_TIMEOUT = 30


def fetch_jolpica_page(offset):
    """
    Pobiera jedną stronę wyników Jolpica z obsługą
    timeoutów, limitu API i ponawiania zapytań.
    """
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
                JOLPICA_URL,
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
                    f"Limit API Jolpica dla offset {offset}. "
                    f"Próba {attempt}/{MAX_ATTEMPTS}. "
                    f"Ponowienie za {wait_seconds:.0f} s."
                )

                time.sleep(wait_seconds)
                continue

            print(
                f"Błąd Jolpica dla offset {offset}: "
                f"{response.status_code}"
            )

            return None

        except requests.exceptions.RequestException as error:
            print(
                f"Problem z połączeniem dla offset {offset}. "
                f"Próba {attempt}/{MAX_ATTEMPTS}: {error}"
            )

            if attempt < MAX_ATTEMPTS:
                time.sleep(5 * attempt)

    return None


# Wczytanie weekendów Grand Prix i głównych sesji Race
meetings_df = pd.read_csv(MEETINGS_PATH)
sessions_df = pd.read_csv(SESSIONS_PATH)

meetings_df["date_start"] = pd.to_datetime(
    meetings_df["date_start"],
    format="ISO8601",
    utc=True,
)

meetings_ordered_df = meetings_df.sort_values(
    "date_start"
).reset_index(drop=True)

meetings_ordered_df["round"] = (
    meetings_ordered_df.index + 1
)

race_sessions_df = sessions_df[
    sessions_df["session_name"] == "Race"
].copy()

round_to_meeting_key = dict(
    zip(
        meetings_ordered_df["round"],
        meetings_ordered_df["meeting_key"],
    )
)

meeting_to_session_key = dict(
    zip(
        race_sessions_df["meeting_key"],
        race_sessions_df["session_key"],
    )
)

# Pobranie wyników wyścigów z Jolpica
starting_grid_clean = []
offset = 0
total_results = None

while total_results is None or offset < total_results:
    data = fetch_jolpica_page(offset)

    if data is None:
        raise RuntimeError(
            f"Nie udało się pobrać danych Jolpica "
            f"dla offset {offset}."
        )

    mr_data = data["MRData"]
    race_table = mr_data["RaceTable"]
    races = race_table["Races"]

    total_results = int(mr_data["total"])

    for race in races:
        round_number = int(race["round"])

        meeting_key = round_to_meeting_key.get(
            round_number
        )

        if meeting_key is None:
            raise ValueError(
                f"Nie znaleziono meeting_key dla rundy "
                f"{round_number}: {race['raceName']}."
            )

        session_key = meeting_to_session_key.get(
            meeting_key
        )

        if session_key is None:
            raise ValueError(
                f"Nie znaleziono głównej sesji Race dla "
                f"meeting_key {meeting_key}."
            )

        for result in race["Results"]:
            driver = result["Driver"]
            constructor = result.get("Constructor", {})

            clean_grid_record = {
                "meeting_key": meeting_key,
                "session_key": session_key,
                "round": round_number,
                "race_name": race["raceName"],
                "driver_number": result["number"],
                "driver_code": driver.get("code"),
                "driver_name": (
                    f"{driver['givenName']} "
                    f"{driver['familyName']}"
                ),
                "team_name": constructor.get("name"),
                "grid_position": result.get("grid"),
            }

            starting_grid_clean.append(
                clean_grid_record
            )

    offset += PAGE_LIMIT


# Utworzenie DataFrame
starting_grid_df = pd.DataFrame(
    starting_grid_clean
)

if starting_grid_df.empty:
    raise RuntimeError(
        "Nie pobrano żadnych danych pól startowych."
    )


# Konwersja typów danych
starting_grid_df["driver_number"] = pd.to_numeric(
    starting_grid_df["driver_number"],
    errors="coerce",
).astype("Int64")

starting_grid_df["grid_position"] = pd.to_numeric(
    starting_grid_df["grid_position"],
    errors="coerce",
).astype("Int64")


# Kontrola jakości danych
duplicate_count = starting_grid_df.duplicated(
    subset=["session_key", "driver_number"]
).sum()

if duplicate_count > 0:
    raise ValueError(
        f"Wykryto {duplicate_count} duplikatów "
        "pól startowych."
    )

missing_grid_count = (
    starting_grid_df["grid_position"]
    .isna()
    .sum()
)

if missing_grid_count > 0:
    print(
        f"Ostrzeżenie: {missing_grid_count} rekordów "
        "nie ma grid_position."
    )

race_count = starting_grid_df["meeting_key"].nunique()
expected_race_count = len(meetings_df)

if race_count != expected_race_count:
    print(
        f"Ostrzeżenie: starting_grid zawiera "
        f"{race_count} wyścigów, a meetings zawiera "
        f"{expected_race_count}."
    )


# Zapis danych
starting_grid_df.to_csv(
    PROCESSED_DATA_PATH,
    index=False,
)

print(
    f"Zapisano {len(starting_grid_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)

print(
    f"Liczba wyścigów: "
    f"{starting_grid_df['meeting_key'].nunique()}"
)