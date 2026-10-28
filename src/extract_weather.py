from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"
OPENF1_URL = "https://api.openf1.org/v1/weather"


def extract_year(year):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"weather_{year}.csv"

    meetings_df = pd.read_csv(meetings_path)
    weather_clean = []

    for meeting_key in meetings_df["meeting_key"].tolist():
        weather_records = fetch_openf1_json(
            url=f"{OPENF1_URL}?meeting_key={meeting_key}",
            key_name="meeting_key",
            key_value=meeting_key,
        )

        for weather in weather_records:
            weather_clean.append(
                {
                    "meeting_key": weather.get("meeting_key"),
                    "session_key": weather.get("session_key"),
                    "date": weather.get("date"),
                    "air_temperature": weather.get("air_temperature"),
                    "track_temperature": weather.get("track_temperature"),
                    "humidity": weather.get("humidity"),
                    "pressure": weather.get("pressure"),
                    "rainfall": weather.get("rainfall"),
                    "wind_direction": weather.get("wind_direction"),
                    "wind_speed": weather.get("wind_speed"),
                }
            )

    weather_df = pd.DataFrame(weather_clean)

    if weather_df.empty:
        raise RuntimeError(
            f"Nie pobrano żadnych danych pogodowych dla {year}."
        )

    weather_df["date"] = pd.to_datetime(
        weather_df["date"],
        format="ISO8601",
        utc=True,
    )

    for column in ["wind_direction", "rainfall"]:
        weather_df[column] = pd.to_numeric(
            weather_df[column],
            errors="coerce",
        ).astype("Int64")

    duplicate_count = weather_df.duplicated().sum()
    if duplicate_count > 0:
        print(
            f"{year}: usunięto {duplicate_count} dokładnych "
            "duplikatów danych pogodowych."
        )
        weather_df = weather_df.drop_duplicates().copy()

    weather_df = weather_df.sort_values(
        ["session_key", "date"]
    ).reset_index(drop=True)

    weather_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: zapisano {len(weather_df)} rekordów do "
        f"{processed_data_path.name}."
    )


def main():
    for year in parse_years("Pobiera dane pogodowe z OpenF1."):
        print(f"\n=== Weather {year} ===")
        extract_year(year)


if __name__ == "__main__":
    main()
