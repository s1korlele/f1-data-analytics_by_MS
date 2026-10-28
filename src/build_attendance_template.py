from pathlib import Path
import pandas as pd
from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"

def build_year(year):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    processed_data_path = PROCESSED_DIR / f"attendance_{year}.csv"

    if processed_data_path.exists():
        print(
            f"{year}: {processed_data_path.name} już istnieje - pomijam, "
            "żeby nie nadpisać ręcznie uzupełnionych danych."
        )
        return

    meetings_df = pd.read_csv(meetings_path)

    attendance_df = meetings_df[
        ["meeting_key", "meeting_name", "country_name", "circuit_short_name"]
    ].copy()

    attendance_df["weekend_attendance"] = pd.NA
    attendance_df["race_day_attendance"] = pd.NA
    attendance_df["source_url"] = pd.NA
    attendance_df["source_date"] = pd.NA
    attendance_df["notes"] = pd.NA

    attendance_df.to_csv(processed_data_path, index=False)
    print(
        f"{year}: utworzono szablon {processed_data_path.name}. "
        "Dane frekwencji należy uzupełnić ręcznie z wiarygodnych źródeł."
    )

def main():
    for year in parse_years(
        "Tworzy bezpieczny szablon attendance dla wskazanych sezonów."
    ):
        print(f"\n=== Attendance Template {year} ===")
        build_year(year)

if __name__ == "__main__":
    main()
