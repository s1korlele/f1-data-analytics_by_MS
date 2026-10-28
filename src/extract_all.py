from pathlib import Path
import argparse
import subprocess
import sys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = PROJECT_ROOT / "src"

DEFAULT_YEARS = [2023, 2024, 2025]

EXTRACTORS = [
    "extract_meetings.py",
    "extract_sessions.py",
    "extract_drivers.py",
    "extract_session_results.py",
    "extract_laps.py",
    "extract_stints.py",
    "extract_pit_stops.py",
    "extract_race_control.py",
    "extract_weather.py",
    "extract_starting_grid.py",
]


def parse_args():
    parser = argparse.ArgumentParser(
        description=(
            "Uruchamia cały aktywny pipeline ekstrakcji "
            "dla wskazanych sezonów."
        )
    )
    parser.add_argument(
        "--years",
        nargs="+",
        type=int,
        default=DEFAULT_YEARS,
        help=(
            "Sezony do pobrania, np. --years 2023 2024. "
            "Domyślnie: 2023 2024 2025."
        ),
    )
    return parser.parse_args()


def main():
    args = parse_args()
    years = [str(year) for year in sorted(set(args.years))]

    for extractor in EXTRACTORS:
        script_path = SRC_DIR / extractor
        if not script_path.exists():
            raise FileNotFoundError(f"Brak extractora: {script_path}")

        command = [
            sys.executable,
            str(script_path),
            "--years",
            *years,
        ]

        print("\n" + "=" * 70)
        print(f"URUCHAMIAM: {extractor} dla sezonów {', '.join(years)}")
        print("=" * 70)

        subprocess.run(
            command,
            cwd=PROJECT_ROOT,
            check=True,
        )

    print("\nWszystkie extractory zakończone poprawnie.")
    print("Attendance nie jest pobierane automatycznie.")
    print(
        "Szablony można utworzyć osobno: "
        "python src\\build_attendance_template.py --years "
        + " ".join(years)
    )


if __name__ == "__main__":
    main()
