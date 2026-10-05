import time

import requests


REQUEST_DELAY = 2.1
MAX_ATTEMPTS = 3
REQUEST_TIMEOUT = 30


def fetch_openf1_json(url, key_name, key_value):
    """
    Pobiera dane JSON z OpenF1 z obsługą limitu API,
    timeoutów i ponawiania zapytań.
    """
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            response = requests.get(url, timeout=REQUEST_TIMEOUT)

            if response.status_code == 200:
                data = response.json()
                time.sleep(REQUEST_DELAY)
                return data

            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After")
                wait_seconds = float(retry_after) if retry_after else 15 * attempt

                print(
                    f"Limit API dla {key_name} {key_value}. "
                    f"Próba {attempt}/{MAX_ATTEMPTS}. "
                    f"Ponowienie za {wait_seconds:.0f} s."
                )

                time.sleep(wait_seconds)
                continue

            print(
                f"Błąd dla {key_name} {key_value}: "
                f"{response.status_code}"
            )
            time.sleep(REQUEST_DELAY)
            return []

        except requests.exceptions.RequestException as error:
            print(
                f"Problem z połączeniem dla {key_name} {key_value}. "
                f"Próba {attempt}/{MAX_ATTEMPTS}: {error}"
            )

            if attempt < MAX_ATTEMPTS:
                time.sleep(5 * attempt)

    print(
        f"Nie udało się pobrać danych dla "
        f"{key_name} {key_value}."
    )
    time.sleep(REQUEST_DELAY)
    return []
