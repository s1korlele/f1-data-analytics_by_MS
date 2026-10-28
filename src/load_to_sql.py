from decimal import Decimal, InvalidOperation
from pathlib import Path
import math

import pandas as pd
import pyodbc

from season_config import parse_years

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = PROJECT_ROOT / "data" / "processed"

SERVER = r"localhost\F1DEV"
DATABASE = "F1Analytics"
DRIVER = "ODBC Driver 18 for SQL Server"
BATCH_SIZE = 5000

# Pomocniczy loader Python. Głównym loaderem projektu pozostaje SSIS.
# Każda tabela jest czyszczona tylko raz, a następnie ładowane są wszystkie
# wybrane sezony, dzięki czemu uruchomienie wielosezonowe nie zostawia
# w stagingu wyłącznie ostatniego pliku.
DATASETS = [
    ("meetings", "stg.Meetings"),
    ("sessions", "stg.Sessions"),
    ("session_results", "stg.SessionResults"),
    ("drivers", "stg.Drivers"),
    ("race_control", "stg.RaceControl"),
    ("laps", "stg.Laps"),
    ("stints", "stg.Stints"),
    ("pit_stops", "stg.PitStops"),
    ("weather", "stg.Weather"),
    ("starting_grid", "stg.StartingGrid"),
    ("attendance", "stg.Attendance"),
]

NULL_TOKENS = {
    "",
    "nan",
    "none",
    "null",
    "<na>",
    "nat",
}


def get_connection():
    connection_string = (
        f"DRIVER={{{DRIVER}}};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        "Trusted_Connection=yes;"
        "Encrypt=yes;"
        "TrustServerCertificate=yes;"
    )
    return pyodbc.connect(connection_string)


def get_sql_columns(connection, table_name):
    schema_name, object_name = table_name.split(".", 1)
    cursor = connection.cursor()
    cursor.execute(
        """
        SELECT COLUMN_NAME, DATA_TYPE
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ?
          AND TABLE_NAME = ?
        ORDER BY ORDINAL_POSITION;
        """,
        schema_name,
        object_name,
    )
    columns = cursor.fetchall()
    cursor.close()

    if not columns:
        raise ValueError(f"Nie znaleziono tabeli {table_name} w SQL Server.")

    return [
        (row.COLUMN_NAME, row.DATA_TYPE.lower())
        for row in columns
    ]


def is_null_value(value):
    if value is None:
        return True
    if isinstance(value, float):
        return math.isnan(value) or math.isinf(value)
    return str(value).strip().lower() in NULL_TOKENS


def convert_value(value, sql_type, column_name, csv_name, row_number):
    if is_null_value(value):
        return None

    text = str(value).strip()

    try:
        if sql_type in {"tinyint", "smallint", "int", "bigint"}:
            return int(Decimal(text))

        if sql_type in {"decimal", "numeric", "money", "smallmoney"}:
            return Decimal(text)

        if sql_type in {"float", "real"}:
            number = float(text)
            return number if math.isfinite(number) else None

        if sql_type == "bit":
            normalized = text.lower()
            if normalized in {"true", "1"}:
                return True
            if normalized in {"false", "0"}:
                return False
            raise ValueError(f"Nieprawidłowa wartość BIT: {text}")

        # DATE / DATETIMEOFFSET oraz tekst przekazujemy jako string.
        return text

    except (ValueError, InvalidOperation) as error:
        raise ValueError(
            f"Błąd konwersji w {csv_name}, wiersz {row_number}, "
            f"kolumna '{column_name}', wartość '{value}', "
            f"typ SQL '{sql_type}'."
        ) from error


def prepare_rows(connection, csv_path, table_name):
    df = pd.read_csv(
        csv_path,
        dtype=str,
        keep_default_na=False,
    )

    if df.empty:
        raise ValueError(f"Plik {csv_path.name} nie zawiera danych.")

    sql_columns = get_sql_columns(connection, table_name)
    sql_column_names = [column_name for column_name, _ in sql_columns]
    csv_columns = list(df.columns)

    if csv_columns != sql_column_names:
        raise ValueError(
            f"Niezgodne kolumny dla {csv_path.name} -> {table_name}.\n"
            f"CSV: {csv_columns}\n"
            f"SQL: {sql_column_names}"
        )

    rows = []
    for index, row in df.iterrows():
        converted_row = []
        for column_name, sql_type in sql_columns:
            converted_row.append(
                convert_value(
                    value=row[column_name],
                    sql_type=sql_type,
                    column_name=column_name,
                    csv_name=csv_path.name,
                    row_number=index + 2,
                )
            )
        rows.append(tuple(converted_row))

    return df, rows


def load_dataset(connection, dataset_name, table_name, years):
    csv_paths = [
        DATA_PATH / f"{dataset_name}_{year}.csv"
        for year in years
    ]

    missing_files = [path.name for path in csv_paths if not path.exists()]
    if missing_files:
        raise FileNotFoundError(
            f"Brakuje plików dla {table_name}: "
            + ", ".join(missing_files)
        )

    prepared = []
    expected_rows = 0
    columns = None

    for csv_path in csv_paths:
        df, rows = prepare_rows(connection, csv_path, table_name)
        if columns is None:
            columns = list(df.columns)
        prepared.append((csv_path, rows))
        expected_rows += len(df)

    column_sql = ", ".join(f"[{column}]" for column in columns)
    placeholders = ", ".join("?" for _ in columns)
    insert_sql = (
        f"INSERT INTO {table_name} ({column_sql}) "
        f"VALUES ({placeholders})"
    )

    cursor = connection.cursor()
    cursor.fast_executemany = False

    try:
        print(
            f"Ładowanie {table_name}: "
            + ", ".join(path.name for path in csv_paths)
        )

        cursor.execute(f"TRUNCATE TABLE {table_name}")

        fallback_completed = False

        for csv_path, rows in prepared:
            for start in range(0, len(rows), BATCH_SIZE):
                batch = rows[start:start + BATCH_SIZE]
                try:
                    cursor.executemany(insert_sql, batch)
                except pyodbc.Error as batch_error:
                    connection.rollback()
                    cursor.execute(f"TRUNCATE TABLE {table_name}")

                    # Fallback odtwarza cały dataset wiersz po wierszu,
                    # aby wskazać dokładny rekord powodujący błąd.
                    for fallback_path, fallback_rows in prepared:
                        for row_index, row in enumerate(fallback_rows, start=2):
                            try:
                                cursor.execute(insert_sql, row)
                            except pyodbc.Error as row_error:
                                connection.rollback()
                                row_values = dict(zip(columns, row))
                                raise RuntimeError(
                                    f"Błąd SQL w {fallback_path.name}, "
                                    f"wiersz {row_index}.\n"
                                    f"Dane: {row_values}"
                                ) from row_error

                    fallback_completed = True
                    break

            if fallback_completed:
                break

        cursor.execute(f"SELECT COUNT(*) FROM {table_name}")
        sql_row_count = cursor.fetchone()[0]

        if sql_row_count != expected_rows:
            raise ValueError(
                f"Niezgodna liczba rekordów dla {table_name}. "
                f"CSV: {expected_rows}, SQL: {sql_row_count}."
            )

        connection.commit()
        print(f"OK: {table_name} ({sql_row_count} rekordów)")

    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()


def main():
    years = parse_years(
        "Pomocniczo ładuje wybrane sezony CSV do stagingu SQL Server."
    )

    connection = get_connection()
    try:
        print(f"Połączono z {SERVER} / {DATABASE}.")
        for dataset_name, table_name in DATASETS:
            load_dataset(
                connection=connection,
                dataset_name=dataset_name,
                table_name=table_name,
                years=years,
            )

        print(
            "Wszystkie wybrane sezony zostały załadowane "
            "do schematu stg."
        )
    finally:
        connection.close()


if __name__ == "__main__":
    main()
