from pathlib import Path

import pandas as pd

from openf1_client import fetch_openf1_json


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = PROJECT_ROOT / "data" / "processed" / "meetings_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "weather_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/weather"


# Wczytanie weekendów Grand Prix
meetings_df = pd.read_csv(MEETINGS_PATH)
meeting_keys = meetings_df["meeting_key"].tolist()


# Pobranie danych pogodowych
weather_clean = []

for meeting_key in meeting_keys:
    url = f"{OPENF1_URL}?meeting_key={meeting_key}"

    weather_records = fetch_openf1_json(
        url=url,
        key_name="meeting_key",
        key_value=meeting_key,
    )

    for weather in weather_records:
        clean_weather = {
            "meeting_key": weather["meeting_key"],
            "session_key": weather["session_key"],
            "date": weather["date"],
            "air_temperature": weather["air_temperature"],
            "track_temperature": weather["track_temperature"],
            "humidity": weather["humidity"],
            "pressure": weather["pressure"],
            "rainfall": weather["rainfall"],
            "wind_direction": weather["wind_direction"],
            "wind_speed": weather["wind_speed"],
        }

        weather_clean.append(clean_weather)


# Utworzenie DataFrame
weather_df = pd.DataFrame(weather_clean)

if weather_df.empty:
    raise RuntimeError("Nie pobrano żadnych danych pogodowych.")


# Konwersja typów danych
weather_df["date"] = pd.to_datetime(
    weather_df["date"],
    format="ISO8601",
    utc=True,
)

weather_df["wind_direction"] = (
    weather_df["wind_direction"].astype("Int64")
)

weather_df["rainfall"] = (
    weather_df["rainfall"].astype("Int64")
)


# Kontrola jakości danych
duplicate_count = weather_df.duplicated().sum()

if duplicate_count > 0:
    print(
        f"Usunięto {duplicate_count} dokładnych duplikatów "
        "danych pogodowych."
    )

    weather_df = weather_df.drop_duplicates().copy()


# Zapis danych
weather_df.to_csv(PROCESSED_DATA_PATH, index=False)

print(
    f"Zapisano {len(weather_df)} rekordów do "
    f"{PROCESSED_DATA_PATH.name}."
)
