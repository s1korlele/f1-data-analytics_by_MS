from pathlib import Path
import argparse
import unicodedata
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PROCESSED_DIR = PROJECT_ROOT / "data" / "processed"

SOURCE_2023 = "https://gpdestinations.com/ranked-the-top-attended-formula-1-races-in-2023/"
SOURCE_2024 = "https://gpdestinations.com/ranked-the-top-attended-formula-1-races-in-2024/"
SOURCE_RESOURCE = "https://gpdestinations.com/resources/f1-attendance-figures/"
SOURCE_AUSTRALIA_2023 = "https://gpdestinations.com/record-breaking-444000-weekend-attendance-at-2023-australian-grand-prix/"
SOURCE_JAPAN_2023 = "https://gpdestinations.com/2023-japanese-grand-prix-suzuka-attendance/"
SOURCE_MEXICO_2023 = "https://www.mexicogp.mx/mediacenter/el-mexico-gp-2023-dejo-una-derrama-economica-superior-a-los-15-mil-millones-de-pesos-en-el-pais/?IDM=LANG_EN"
SOURCE_MEXICO_2024 = "https://www.mexicogp.mx/mediacenter/carlos-sainz-domino-para-el-tercertriunfo-de-ferrari-en-el-mexico-gp/"


def record(weekend, race_day=None, source_url=None, source_date=None, notes=""):
    return {
        "weekend_attendance": weekend,
        "race_day_attendance": race_day,
        "source_url": source_url,
        "source_date": source_date,
        "notes": notes,
    }


ATTENDANCE = {
    2023: {
        "bahrain grand prix": record(99500, 36000, SOURCE_2023, "2023-12-01", "Weekend and race-day attendance reported."),
        "saudi arabian grand prix": record(150000, None, SOURCE_2023, "2023-12-01", "Approximate value. Source reports weekend attendance in excess of 150,000; stored as 150,000 baseline."),
        "australian grand prix": record(444631, 131124, SOURCE_AUSTRALIA_2023, "2023-04-03", "Official/event-reported 4-day total and Sunday attendance."),
        "azerbaijan grand prix": record(95000, None, "https://www.cityam.com/f1-attendances-miami-behind-las-vegas-and-austin-in-us/", None, "Estimated/unofficial. No official 2023 weekend figure was announced; published estimate used for completeness."),
        "miami grand prix": record(270491, 90766, SOURCE_2023, "2023-12-01", "Weekend attendance and race-day attendance reported."),
        "monaco grand prix": record(200000, None, SOURCE_2023, "2023-12-01", "Estimated/unofficial. Monaco did not publish a 2023 attendance figure; value reflects the traditional recent weekend level cited by the source."),
        "spanish grand prix": record(284066, 125565, SOURCE_2023, "2023-12-01", "Weekend and race-day attendance reported."),
        "canadian grand prix": record(345000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "austrian grand prix": record(304000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "british grand prix": record(480000, 160000, SOURCE_2023, "2023-12-01", "4-day weekend attendance and race-day attendance reported."),
        "hungarian grand prix": record(303000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "belgian grand prix": record(380000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "dutch grand prix": record(305000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "italian grand prix": record(304135, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported. Some contemporary reports show 304,134; source table uses 304,135."),
        "singapore grand prix": record(264108, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "japanese grand prix": record(222000, 101000, SOURCE_JAPAN_2023, "2023-09-24", "Weekend total and Sunday attendance reported by Formula 1/Suzuka."),
        "qatar grand prix": record(120000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "united states grand prix": record(432000, None, SOURCE_2023, "2023-12-01", "4-day weekend attendance reported."),
        "mexico city grand prix": record(400639, 149721, SOURCE_MEXICO_2023, None, "Official promoter figures for 3-day total and Sunday."),
        "sao paulo grand prix": record(267000, None, SOURCE_2023, "2023-12-01", "Weekend attendance reported."),
        "las vegas grand prix": record(315000, None, SOURCE_2023, "2023-12-01", "4-day weekend attendance reported."),
        "abu dhabi grand prix": record(170000, None, SOURCE_2024, "2024-12-16", "2023 figure reported retrospectively in the 2024 attendance review."),
    },
    2024: {
        "bahrain grand prix": record(100000, 37000, SOURCE_2024, "2024-12-16", "Weekend total and race-day attendance reported."),
        "saudi arabian grand prix": record(150000, None, SOURCE_2024, "2024-12-16", "Estimated/unofficial. No official 2024 figure published; source estimates the weekend at around 150,000 based on recent years."),
        "australian grand prix": record(452055, 132106, SOURCE_2024, "2024-12-16", "Official/event-reported 4-day total and Sunday attendance."),
        "japanese grand prix": record(229000, 102000, SOURCE_2024, "2024-12-16", "Weekend attendance reported; Sunday figure reported separately in attendance breakdowns."),
        "chinese grand prix": record(200000, None, SOURCE_2024, "2024-12-16", "Approximate/unofficial. Local government reported nearly 200,000; stored as rounded 200,000."),
        "miami grand prix": record(275000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "emilia romagna grand prix": record(200000, None, SOURCE_2024, "2024-12-16", "Approximate/lower-bound. Source reports more than 200,000; stored as 200,000 baseline."),
        "monaco grand prix": record(200000, None, SOURCE_2024, "2024-12-16", "Estimated/unofficial. Monaco did not publish a 2024 figure; value reflects the recent historical level cited by the source."),
        "canadian grand prix": record(350000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "spanish grand prix": record(297368, 125210, SOURCE_2024, "2024-12-16", "Circuit-reported weekend figure used. Formula 1 broadcast reported 288,218; source documents the discrepancy. Sunday attendance reported as 125,210."),
        "austrian grand prix": record(302000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "british grand prix": record(480000, 164000, SOURCE_2024, "2024-12-16", "4-day weekend attendance and race-day attendance reported."),
        "hungarian grand prix": record(310000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "belgian grand prix": record(380000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "dutch grand prix": record(305000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "italian grand prix": record(335000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "azerbaijan grand prix": record(76000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported by Baku City Circuit."),
        "singapore grand prix": record(269072, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "united states grand prix": record(430000, None, SOURCE_RESOURCE, None, "Estimated/unofficial weekend attendance. Official 2024 COTA weekend figure was not announced; current attendance resource marks 430,000 as estimated."),
        "mexico city grand prix": record(404958, 154142, SOURCE_MEXICO_2024, "2024-10-27", "Official promoter figures for 3-day total and Sunday."),
        "sao paulo grand prix": record(291717, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "las vegas grand prix": record(306000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported."),
        "qatar grand prix": record(154973, None, SOURCE_2024, "2024-12-16", "3-day weekend attendance reported."),
        "abu dhabi grand prix": record(190000, None, SOURCE_2024, "2024-12-16", "Weekend attendance reported in the 2024 review."),
    },
}


def normalize_name(value):
    text = unicodedata.normalize("NFKD", str(value))
    text = "".join(char for char in text if not unicodedata.combining(char))
    return " ".join(text.lower().strip().split())


def parse_args():
    parser = argparse.ArgumentParser(description="Build attendance_2023.csv and attendance_2024.csv from meetings_<year>.csv.")
    parser.add_argument("--years", nargs="+", type=int, default=[2023, 2024], choices=[2023, 2024])
    parser.add_argument("--force", action="store_true", help="Overwrite existing attendance_<year>.csv.")
    return parser.parse_args()


def build_year(year, force=False):
    meetings_path = PROCESSED_DIR / f"meetings_{year}.csv"
    output_path = PROCESSED_DIR / f"attendance_{year}.csv"

    if not meetings_path.exists():
        raise FileNotFoundError(f"Brak pliku {meetings_path}.")

    if output_path.exists() and not force:
        raise FileExistsError(f"{output_path.name} już istnieje. Użyj --force tylko jeśli chcesz go świadomie nadpisać.")

    meetings_df = pd.read_csv(meetings_path)
    required_columns = {"meeting_key", "meeting_name", "country_name", "circuit_short_name"}
    missing_columns = required_columns - set(meetings_df.columns)
    if missing_columns:
        raise ValueError(f"{meetings_path.name}: brak kolumn: " + ", ".join(sorted(missing_columns)))

    lookup = ATTENDANCE[year]
    rows = []
    unmatched = []

    for meeting in meetings_df.itertuples(index=False):
        normalized = normalize_name(meeting.meeting_name)
        values = lookup.get(normalized)
        if values is None:
            unmatched.append(meeting.meeting_name)
            continue

        rows.append({
            "meeting_key": meeting.meeting_key,
            "meeting_name": meeting.meeting_name,
            "country_name": meeting.country_name,
            "circuit_short_name": meeting.circuit_short_name,
            **values,
        })

    if unmatched:
        raise ValueError(f"{year}: brak attendance mapping dla: " + ", ".join(sorted(unmatched)))

    attendance_df = pd.DataFrame(rows)
    if len(attendance_df) != len(meetings_df):
        raise ValueError(f"{year}: attendance rows={len(attendance_df)}, meetings rows={len(meetings_df)}.")

    if attendance_df["meeting_key"].duplicated().any():
        raise ValueError(f"{year}: duplikaty meeting_key w attendance.")

    attendance_df["weekend_attendance"] = pd.to_numeric(attendance_df["weekend_attendance"], errors="coerce").astype("Int64")
    attendance_df["race_day_attendance"] = pd.to_numeric(attendance_df["race_day_attendance"], errors="coerce").astype("Int64")
    attendance_df.to_csv(output_path, index=False)

    estimated_count = attendance_df["notes"].str.contains("Estimated|Approximate", case=False, na=False).sum()
    race_day_count = attendance_df["race_day_attendance"].notna().sum()

    print(f"{year}: zapisano {len(attendance_df)} rekordów do {output_path.name}.")
    print(f"{year}: weekend_attendance {attendance_df['weekend_attendance'].notna().sum()}/{len(attendance_df)}, race_day_attendance {race_day_count}/{len(attendance_df)}, estimated/approximate={estimated_count}.")


def main():
    args = parse_args()
    for year in sorted(set(args.years)):
        print(f"\n=== Attendance {year} ===")
        build_year(year=year, force=args.force)


if __name__ == "__main__":
    main()
