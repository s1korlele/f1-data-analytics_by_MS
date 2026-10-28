from pathlib import Path
import json

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/session_result"


def get_phase_value(values, index):
    """Zwraca element Q1/Q2/Q3; skalar jest traktowany jako faza 1."""
    if isinstance(values, list):
        return values[index] if len(values) > index else None
    return values if index == 0 else None


def split_numeric_text(value):
    """Rozdziela gap na wartość liczbową i tekstową."""
    if value is None:
        return None, None
    if isinstance(value, bool):
        return None, str(value)
    if isinstance(value, (int, float)):
        return float(value), None

    text = str(value).strip()
    if not text:
        return None, None

    normalized = text.replace(",", ".")
    if normalized.startswith("+"):
        normalized = normalized[1:]

    try:
        return float(normalized), None
    except ValueError:
        return None, text


def serialize_raw(value):
    """Zachowuje oryginalną reprezentację pola do audytu."""
    if value is None:
        return None
    if isinstance(value, list):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def extract_year(year):
    sessions_path = PROCESSED_DIR / f"sessions_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"session_results_{year}.csv"

    sessions_df = pd.read_csv(sessions_path)

    required_session_columns = {
        "meeting_key",
        "session_key",
        "session_type",
        "session_name",
        "is_cancelled",
    }
    missing_columns = required_session_columns - set(sessions_df.columns)
    if missing_columns:
        raise ValueError(
            f"{year}: brak wymaganych kolumn w sessions CSV: "
            + ", ".join(sorted(missing_columns))
        )

    session_lookup = (
        sessions_df[
            [
                "meeting_key",
                "session_key",
                "session_type",
                "session_name",
                "is_cancelled",
            ]
        ]
        .drop_duplicates(subset=["session_key"])
        .set_index("session_key")
    )

    results_clean = []
    missing_result_sessions = []

    for session_key in sessions_df["session_key"].tolist():
        session_meta = session_lookup.loc[session_key]

        results = fetch_openf1_json(
            url=f"{OPENF1_URL}?session_key={session_key}",
            key_name="session_key",
            key_value=session_key,
        )

        if not results:
            missing_result_sessions.append(
                {
                    "session_key": session_key,
                    "session_type": session_meta["session_type"],
                    "session_name": session_meta["session_name"],
                    "is_cancelled": session_meta["is_cancelled"],
                }
            )
            continue

        for result in results:
            duration = result.get("duration")
            gap = result.get("gap_to_leader")
            duration_is_array = isinstance(duration, list)
            gap_is_array = isinstance(gap, list)

            duration_seconds = None if duration_is_array else duration
            gap_seconds, gap_text = (None, None)
            if not gap_is_array:
                gap_seconds, gap_text = split_numeric_text(gap)

            phase_duration_values = [
                get_phase_value(duration, index)
                if duration_is_array
                else None
                for index in range(3)
            ]
            phase_gap_values = [
                get_phase_value(gap, index)
                if gap_is_array
                else None
                for index in range(3)
            ]
            phase_gap_split = [
                split_numeric_text(value)
                for value in phase_gap_values
            ]

            results_clean.append(
                {
                    "meeting_key": result.get("meeting_key"),
                    "session_key": result.get("session_key"),
                    "session_type": session_meta["session_type"],
                    "session_name": session_meta["session_name"],
                    "driver_number": result.get("driver_number"),
                    "position": result.get("position"),
                    "number_of_laps": result.get("number_of_laps"),
                    # Pole points nie jest gwarantowane przez OpenF1,
                    # ale zachowujemy je, jeżeli pojawi się w payloadzie.
                    "points": result.get("points"),
                    "dnf": result.get("dnf"),
                    "dns": result.get("dns"),
                    "dsq": result.get("dsq"),
                    "duration_seconds": duration_seconds,
                    "gap_to_leader_seconds": gap_seconds,
                    "gap_to_leader_text": gap_text,
                    "phase_1_duration_seconds": phase_duration_values[0],
                    "phase_2_duration_seconds": phase_duration_values[1],
                    "phase_3_duration_seconds": phase_duration_values[2],
                    "phase_1_gap_to_leader_seconds": phase_gap_split[0][0],
                    "phase_1_gap_to_leader_text": phase_gap_split[0][1],
                    "phase_2_gap_to_leader_seconds": phase_gap_split[1][0],
                    "phase_2_gap_to_leader_text": phase_gap_split[1][1],
                    "phase_3_gap_to_leader_seconds": phase_gap_split[2][0],
                    "phase_3_gap_to_leader_text": phase_gap_split[2][1],
                    "duration_raw": serialize_raw(duration),
                    "gap_to_leader_raw": serialize_raw(gap),
                }
            )

    session_results_df = pd.DataFrame(results_clean)

    if session_results_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych session_result dla {year}."
        )

    for column in [
        "meeting_key",
        "session_key",
        "driver_number",
        "position",
        "number_of_laps",
    ]:
        session_results_df[column] = pd.to_numeric(
            session_results_df[column],
            errors="coerce",
        ).astype("Int64")

    duplicate_count = session_results_df.duplicated(
        subset=["session_key", "driver_number"]
    ).sum()
    if duplicate_count > 0:
        raise ValueError(
            f"{year}: wykryto {duplicate_count} duplikatów "
            "session_key + driver_number w session_result."
        )

    result_session_meetings = (
        session_results_df[["session_key", "meeting_key"]]
        .drop_duplicates()
        .set_index("session_key")["meeting_key"]
    )

    for session_key, meeting_key in result_session_meetings.items():
        expected_meeting_key = int(
            session_lookup.loc[session_key, "meeting_key"]
        )
        if int(meeting_key) != expected_meeting_key:
            raise ValueError(
                f"{year}: niezgodny meeting_key dla session_key {session_key}: "
                f"OpenF1={meeting_key}, sessions CSV={expected_meeting_key}."
            )

    session_results_df = session_results_df.sort_values(
        by=["session_key", "position", "driver_number"],
        na_position="last",
    ).reset_index(drop=True)

    session_results_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(session_results_df)} rekordów do "
        f"{processed_data_path.name}."
    )

    result_summary = (
        session_results_df.groupby(
            ["session_type", "session_name"],
            dropna=False,
        )
        .size()
        .reset_index(name="rows")
        .sort_values(["session_type", "session_name"])
    )
    print(f"{year}: liczba rekordów session_result według typu sesji:")
    for row in result_summary.itertuples(index=False):
        print(
            f"- {row.session_type} / {row.session_name}: "
            f"{row.rows} rekordów"
        )

    if missing_result_sessions:
        print(
            f"{year}: ostrzeżenie - OpenF1 nie zwrócił session_result "
            "dla następujących sesji:"
        )
        for item in missing_result_sessions:
            print(
                f"- session_key={item['session_key']}, "
                f"type='{item['session_type']}', "
                f"name='{item['session_name']}', "
                f"cancelled={item['is_cancelled']}"
            )


def main():
    for year in parse_years(
        "Pobiera oficjalne wyniki wszystkich sesji z OpenF1."
    ):
        print(f"\n=== Session Results {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
