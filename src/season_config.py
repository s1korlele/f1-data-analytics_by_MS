import argparse

DEFAULT_YEARS = (2023, 2024, 2025)
MIN_OPENF1_YEAR = 2023


def parse_years(description):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        "--years",
        nargs="+",
        type=int,
        default=list(DEFAULT_YEARS),
        help=(
            "Sezony do przetworzenia, np. --years 2023 2024. "
            f"Domyślnie: {' '.join(map(str, DEFAULT_YEARS))}."
        ),
    )

    args = parser.parse_args()
    years = sorted(set(args.years))

    invalid_years = [year for year in years if year < MIN_OPENF1_YEAR]
    if invalid_years:
        raise ValueError(
            "OpenF1 udostępnia dane historyczne od sezonu "
            f"{MIN_OPENF1_YEAR}. Nieobsługiwane sezony: "
            + ", ".join(map(str, invalid_years))
        )

    return years
