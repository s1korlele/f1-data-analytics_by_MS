from pathlib import Path

import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MEETINGS_PATH = PROJECT_ROOT / "data" / "processed" / "meetings_2025.csv"
PROCESSED_DATA_PATH = (
    PROJECT_ROOT
    / "data"
    / "processed"
    / "attendance_2025.csv"
)


# Wczytanie weekendów Grand Prix
meetings_df = pd.read_csv(MEETINGS_PATH)


# Utworzenie szablonu frekwencji
attendance_df = meetings_df[
    [
        "meeting_key",
        "meeting_name",
        "country_name",
        "circuit_short_name",
    ]
].copy()

attendance_df["weekend_attendance"] = pd.NA
attendance_df["race_day_attendance"] = pd.NA
attendance_df["source_url"] = pd.NA
attendance_df["source_date"] = pd.NA
attendance_df["notes"] = pd.NA


# Zapis szablonu
attendance_df.to_csv(
    PROCESSED_DATA_PATH,
    index=False,
)

print(
    f"Utworzono szablon {PROCESSED_DATA_PATH.name}. "
    "Dane frekwencji należy uzupełnić z wiarygodnych źródeł."
)
