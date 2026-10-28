from pathlib import Path
import time

import pandas as pd
import requests

from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"

USER_AGENT = "f1-data-analytics-by-MS/1.0"
PAGE_LIMIT = 100
REQUEST_DELAY = 0.5
MAX_ATTEMPTS = 3
REQUEST_TIMEOUT = 30

def fetch_jolpica_page(base_url, resource, offset):
    url = f"{base_url}/{resource}/"
    params = {"limit": PAGE_LIMIT, "offset": offset}
    headers = {"User-Agent": USER_AGENT}

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

def build_meeting_date_lookup(meetings_df):
    lookup_df = meetings_df.copy()
    lookup_df["date_start"] = pd.to_datetime(
        lookup_df["date_start"], format="ISO8601", utc=True
    )
    lookup_df["date_end"] = pd.to_datetime(
        lookup_df["date_end"], format="ISO8601", utc=True
    )
    lookup_df["start_date"] = lookup_df["date_start"].dt.date
    lookup_df["end_date"] = lookup_df["date_end"].dt.date
    return lookup_df

def resolve_meeting_key(race, meeting_date_lookup):
    race_date_raw = race.get("date")
    if not race_date_raw:
        raise ValueError(
            f"Jolpica nie zwróciła daty wyścigu dla {race.get('raceName')}."
        )

    race_date = pd.Timestamp(race_date_raw).date()

    candidates = meeting_date_lookup[
        (meeting_date_lookup["start_date"] <= race_date)
        & (meeting_date_lookup["end_date"] >= race_date)
    ]

    if len(candidates) == 1:
        return int(candidates.iloc[0]["meeting_key"])

    if len(candidates) > 1:
        raise ValueError(
            "Niejednoznaczne mapowanie Jolpica -> OpenF1 dla "
            f"{race.get('raceName')} ({race_date})."
        )

    temp = meeting_date_lookup.copy()
    temp["date_distance"] = temp["end_date"].apply(
        lambda date_value: abs((date_value - race_date).days)
    )
    nearest = temp.sort_values(["date_distance", "meeting_key"]).iloc[0]

    if int(nearest["date_distance"]) <= 1:
        print(
            "Ostrzeżenie: starting grid - użyto mapowania po najbliższej "
            f"dacie dla {race.get('raceName')} ({race_date}) -> "
            f"meeting_key={int(nearest['meeting_key'])}."
        )
        return int(nearest["meeting_key"])

    raise ValueError(
        f"Nie znaleziono meeting_key dla {race.get('raceName')} "
        f"z datą {race_date}."
    )

def collect_results(
    base_url,
    resource,
    results_key,
    session_name,
    meeting_date_lookup,
    session_lookup,
):
    records = []
    offset = 0
    total_results = None

    while total_results is None or offset < total_results:
        data = fetch_jolpica_page(
            base_url=base_url,
            resource=resource,
            offset=offset,
        )

        if data is None:
            raise RuntimeError(
                f"Nie udało się pobrać danych Jolpica: "
                f"{resource}, offset={offset}."
            )

        mr_data = data["MRData"]
        race_table = mr_data["RaceTable"]
        races = race_table.get("Races", [])
        total_results = int(mr_data.get("total", 0))

        for race in races:
            round_number = int(race["round"])
            meeting_key = resolve_meeting_key(
                race=race,
                meeting_date_lookup=meeting_date_lookup,
            )

            session_key = session_lookup.get((meeting_key, session_name))

            if session_key is None:
                if session_name == "Sprint":
                    continue
                raise ValueError(
                    f"Nie znaleziono sesji '{session_name}' dla "
                    f"meeting_key={meeting_key}, round={round_number}."
                )

            for result in race.get(results_key, []):
                driver = result.get("Driver", {})
                constructor = result.get("Constructor", {})

                records.append({
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
                    "grid_position": result.get("grid"),
                })

        offset += PAGE_LIMIT

    return records

def extract_year(year):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    sessions_path = PROCESSED_DIR / f"sessions_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"starting_grid_{year}.csv"
    jolpica_base_url = f"https://api.jolpi.ca/ergast/f1/{year}"

    meetings_df = pd.read_csv(meetings_path)
    sessions_df = pd.read_csv(sessions_path)
    meeting_date_lookup = build_meeting_date_lookup(meetings_df)

    race_sessions_df = sessions_df[
        sessions_df["session_name"].isin(["Race", "Sprint"])
    ].copy()

    session_lookup = {
        (int(row.meeting_key), str(row.session_name)): int(row.session_key)
        for row in race_sessions_df.itertuples(index=False)
    }

    print(f"{year}: pobieranie starting grid dla Race z Jolpica...")
    race_grid_records = collect_results(
        base_url=jolpica_base_url,
        resource="results",
        results_key="Results",
        session_name="Race",
        meeting_date_lookup=meeting_date_lookup,
        session_lookup=session_lookup,
    )
    print(f"{year}: Race grid - {len(race_grid_records)} rekordów.")

    print(f"{year}: pobieranie starting grid dla Sprint z Jolpica...")
    sprint_grid_records = collect_results(
        base_url=jolpica_base_url,
        resource="sprint",
        results_key="SprintResults",
        session_name="Sprint",
        meeting_date_lookup=meeting_date_lookup,
        session_lookup=session_lookup,
    )
    print(f"{year}: Sprint grid - {len(sprint_grid_records)} rekordów.")

    starting_grid_df = pd.DataFrame(race_grid_records + sprint_grid_records)
    if starting_grid_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych pól startowych z Jolpica dla {year}."
        )

    for column in [
        "meeting_key",
        "session_key",
        "round",
        "driver_number",
        "grid_position",
    ]:
        starting_grid_df[column] = pd.to_numeric(
            starting_grid_df[column], errors="coerce"
        ).astype("Int64")

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
            f"{year}: wykryto {duplicate_count} duplikatów "
            "session_key + driver_number w starting_grid.\n"
            f"Przykłady:\n{duplicate_sample.to_string(index=False)}"
        )

    missing_grid_count = starting_grid_df["grid_position"].isna().sum()
    if missing_grid_count > 0:
        print(
            f"{year}: ostrzeżenie - {missing_grid_count} rekordów "
            "nie ma grid_position."
        )

    starting_grid_df = starting_grid_df.sort_values(
        by=["round", "session_key", "grid_position"],
        na_position="last",
    ).reset_index(drop=True)

    starting_grid_df.to_csv(processed_data_path, index=False)

    race_keys = set(
        race_sessions_df.loc[
            race_sessions_df["session_name"] == "Race",
            "session_key",
        ]
    )
    sprint_keys = set(
        race_sessions_df.loc[
            race_sessions_df["session_name"] == "Sprint",
            "session_key",
        ]
    )

    race_session_count = starting_grid_df[
        starting_grid_df["session_key"].isin(race_keys)
    ]["session_key"].nunique()
    sprint_session_count = starting_grid_df[
        starting_grid_df["session_key"].isin(sprint_keys)
    ]["session_key"].nunique()

    print(
        f"{year}: zapisano {len(starting_grid_df)} rekordów do "
        f"{processed_data_path.name}."
    )
    print(
        f"{year}: sesje z gridem: Race={race_session_count}, "
        f"Sprint={sprint_session_count}."
    )

def main():
    for year in parse_years("Pobiera starting grid Race i Sprint z Jolpica."):
        print(f"\n=== Starting Grid {year} ===")
        extract_year(year)

if __name__ == "__main__":
    main()
