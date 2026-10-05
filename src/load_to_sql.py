from decimal import Decimal, InvalidOperation
from pathlib import Path
import math

import pandas as pd
import pyodbc


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_PATH = PROJECT_ROOT / "data" / "processed"

SERVER = "localhost"
DATABASE = "F1Analytics"
DRIVER = "ODBC Driver 18 for SQL Server"

BATCH_SIZE = 5000

TABLES = {
    "meetings_2025.csv": "stg.Meetings",
    "sessions_2025.csv": "stg.Sessions",
    "drivers_2025.csv": "stg.Drivers",
    "race_control_2025.csv": "stg.RaceControl",
    "race_results_2025.csv": "stg.RaceResults",
    "laps_2025.csv": "stg.Laps",
    "stints_2025.csv": "stg.Stints",
    "pit_stops_2025.csv": "stg.PitStops",
    "weather_2025.csv": "stg.Weather",
    "qualifying_results_2025.csv": "stg.QualifyingResults",
    "starting_grid_2025.csv": "stg.StartingGrid",
    "attendance_2025.csv": "stg.Attendance",
}

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
        SELECT
            COLUMN_NAME,
            DATA_TYPE
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
        raise ValueError(
            f"Nie znaleziono tabeli {table_name} w SQL Server."
        )

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
        if sql_type in {
            "tinyint",
            "smallint",
            "int",
            "bigint",
        }:
            return int(Decimal(text))

        if sql_type in {
            "decimal",
            "numeric",
            "money",
            "smallmoney",
        }:
            return Decimal(text)

        if sql_type in {
            "float",
            "real",
        }:
            number = float(text)

            if not math.isfinite(number):
                return None

            return number

        if sql_type == "bit":
            normalized = text.lower()

            if normalized in {"true", "1"}:
                return True

            if normalized in {"false", "0"}:
                return False

            raise ValueError(
                f"Nieprawidłowa wartość BIT: {text}"
            )

        # DATE / DATETIMEOFFSET oraz tekst przekazujemy jako string.
        # SQL Server poprawnie konwertuje format ISO z naszych CSV.
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
        raise ValueError(
            f"Plik {csv_path.name} nie zawiera danych."
        )

    sql_columns = get_sql_columns(
        connection=connection,
        table_name=table_name,
    )

    sql_column_names = [
        column_name
        for column_name, _ in sql_columns
    ]

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
            converted_value = convert_value(
                value=row[column_name],
                sql_type=sql_type,
                column_name=column_name,
                csv_name=csv_path.name,
                row_number=index + 2,
            )

            converted_row.append(converted_value)

        rows.append(tuple(converted_row))

    return df, rows

def load_table(connection, csv_path, table_name):
    print(
        f"Ładowanie: {csv_path.name} -> {table_name}"
    )

    df, rows = prepare_rows(
        connection=connection,
        csv_path=csv_path,
        table_name=table_name,
    )

    columns = list(df.columns)

    column_sql = ", ".join(
        f"[{column}]"
        for column in columns
    )

    placeholders = ", ".join(
        "?"
        for _ in columns
    )

    insert_sql = (
        f"INSERT INTO {table_name} "
        f"({column_sql}) "
        f"VALUES ({placeholders})"
    )

    cursor = connection.cursor()
    cursor.fast_executemany = False

    try:
        cursor.execute(
            f"TRUNCATE TABLE {table_name}"
        )

        for start in range(0, len(rows), BATCH_SIZE):
            batch = rows[
                start:start + BATCH_SIZE
            ]

            try:
                cursor.executemany(
                    insert_sql,
                    batch,
                )

            except pyodbc.Error as batch_error:
                # Fallback wiersz po wierszu daje dokładny rekord,
                # jeśli sterownik zwróci nieczytelny błąd dla batcha.
                connection.rollback()

                cursor.execute(
                    f"TRUNCATE TABLE {table_name}"
                )

                for row_index, row in enumerate(
                    rows,
                    start=2,
                ):
                    try:
                        cursor.execute(
                            insert_sql,
                            row,
                        )

                    except pyodbc.Error as row_error:
                        connection.rollback()

                        row_values = dict(
                            zip(columns, row)
                        )

                        raise RuntimeError(
                            f"Błąd SQL w {csv_path.name}, "
                            f"wiersz {row_index}.\n"
                            f"Dane: {row_values}"
                        ) from row_error

                # Jeżeli fallback przeszedł poprawnie,
                # kończymy ładowanie tej tabeli.
                break

        cursor.execute(
            f"SELECT COUNT(*) FROM {table_name}"
        )

        sql_row_count = cursor.fetchone()[0]

        if sql_row_count != len(df):
            raise ValueError(
                f"Niezgodna liczba rekordów dla {table_name}. "
                f"CSV: {len(df)}, SQL: {sql_row_count}."
            )

        connection.commit()

        print(
            f"OK: {csv_path.name} -> {table_name} "
            f"({sql_row_count} rekordów)"
        )

    except Exception:
        connection.rollback()
        raise

    finally:
        cursor.close()


def main():
    missing_files = [
        filename
        for filename in TABLES
        if not (DATA_PATH / filename).exists()
    ]

    if missing_files:
        raise FileNotFoundError(
            "Brakuje plików CSV: "
            + ", ".join(missing_files)
        )

    connection = get_connection()

    try:
        print(
            f"Połączono z {SERVER} / {DATABASE}."
        )

        for filename, table_name in TABLES.items():
            csv_path = DATA_PATH / filename

            load_table(
                connection=connection,
                csv_path=csv_path,
                table_name=table_name,
            )

        print(
            "Wszystkie dane zostały załadowane "
            "do schematu stg."
        )

    finally:
        connection.close()


if __name__ == "__main__":
    main()