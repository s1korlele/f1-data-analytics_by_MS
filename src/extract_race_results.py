from pathlib import Path
import time

import pandas as pd
import requests


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SESSIONS_PATH = PROJECT_ROOT / "data" / "processed" / "sessions_2025.csv"
PROCESSED_DATA_PATH = PROJECT_ROOT / "data" / "processed" / "race_results_2025.csv"

OPENF1_URL = "https://api.openf1.org/v1/session_result"


# Wczytanie sesji i wybór głównych wyścigów
sessions_df = pd.read_csv(SESSIONS_PATH)

race_sessions_df = sessions_df[
    sessions_df["session_name"] == "Race"
].copy()

result_session_keys = race_sessions_df["session_key"].tolist()


# Pobranie wyników wyścigów
results_clean = []

for session_key in result_session_keys:
    url = f"{OPENF1_URL}?session_key={session_key}"

    for attempt in range(1, 4):
        try:
            response = requests.get(url, timeout=20)

            if response.status_code == 200:
                race_result = response.json()

                for result in race_result:
                    clean_result = {
                        "meeting_key": result["meeting_key"],
                        "session_key": result["session_key"],
                        "driver_number": result["driver_number"],
                        "position": result["position"],
                        "number_of_laps": result["number_of_laps"],
                        "points": result["points"],
                        "dnf": result["dnf"],
                        "dns": result["dns"],
                        "dsq": result["dsq"],
                        "duration": result["duration"],
                        "gap_to_leader": result["gap_to_leader"],
                    }

                    results_clean.append(clean_result)

                break

            elif response.status_code == 429:
                print(
                    f"Limit API dla session_key {session_key}. "
                    f"Próba {attempt}/3."
                )

                time.sleep(10)

            else:
                print(
                    f"Błąd dla session_key {session_key}: "
                    f"{response.status_code}"
                )

                break

        except requests.exceptions.RequestException as error:
            print(
                f"Problem z połączeniem dla session_key {session_key}. "
                f"Próba {attempt}/3: {error}"
            )

            if attempt < 3:
                time.sleep(5)

    time.sleep(2.1)


# Utworzenie DataFrame
race_results_df = pd.DataFrame(results_clean)


# Konwersja typów danych
race_results_df["position"] = race_results_df["position"].astype("Int64")
race_results_df["number_of_laps"] = race_results_df["number_of_laps"].astype("Int64")

# Zapis danych
race_results_df.to_csv(PROCESSED_DATA_PATH, index=False)