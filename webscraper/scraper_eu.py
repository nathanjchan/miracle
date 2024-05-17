import requests
from bs4 import BeautifulSoup
from db_utils import connect_to_db, do_query
import time

def fetch_trials(max_retries=3, retry_delay=2):
    url = "https://www.clinicaltrialsregister.eu/ctr-search/search?query="
    attempts = 0
    while attempts < max_retries:
        try:
            response = requests.get(url)
            response.raise_for_status()
            return response.text
        except requests.exceptions.RequestException as e:
            attempts += 1
            print(f"An error occurred while fetching data: {e}. Attempt {attempts} of {max_retries}.")
            if attempts < max_retries:
                time.sleep(retry_delay)
    print("Max retries reached. Returning an empty result.")
    return ""

def parse_trial(trial):
    eudract_number = trial.find('span', class_='label', string='EudraCT Number:').find_next_sibling(string=True).strip() if trial.find('span', class_='label', string='EudraCT Number:') else None
    sponsor_protocol_number = trial.find('span', class_='label', string='Sponsor Protocol Number:').find_next_sibling(string=True).strip() if trial.find('span', class_='label', string='Sponsor Protocol Number:') else None
    sponsor_name = trial.find('span', class_='label', string='Sponsor Name:').find_next_sibling(string=True).strip() if trial.find('span', class_='label', string='Sponsor Name:') else None
    full_title = trial.find('span', class_='label', string='Full Title:').find_next_sibling(string=True).strip() if trial.find('span', class_='label', string='Full Title:') else None
    medical_condition = trial.find('span', class_='label', string='Medical condition:').find_next_sibling(string=True).strip() if trial.find('span', class_='label', string='Medical condition:') else None

    return {
        'eudract_number': eudract_number,
        'sponsor_protocol_number': sponsor_protocol_number,
        'sponsor_name': sponsor_name,
        'full_title': full_title,
        'medical_condition': medical_condition
    }

def parse_trials(html):
    soup = BeautifulSoup(html, 'html.parser')
    trial_tables = soup.find_all('table', class_='result')
    trials = [parse_trial(trial) for trial in trial_tables]
    return trials

def create_table(conn):
    create_table_query = """
        CREATE TABLE IF NOT EXISTS eu (
            eudract_number VARCHAR PRIMARY KEY,
            sponsor_protocol_number VARCHAR,
            sponsor_name TEXT,
            full_title TEXT,
            medical_condition TEXT
        );
        """
    do_query(conn, create_table_query)

def insert_trial(conn, trial):
    with conn.cursor() as cur:
        insert_query = """
        INSERT INTO eu (
            eudract_number, sponsor_protocol_number, sponsor_name, full_title, medical_condition
        ) VALUES (
            %(eudract_number)s, %(sponsor_protocol_number)s, %(sponsor_name)s, %(full_title)s, %(medical_condition)s
        )
        ON CONFLICT (eudract_number) DO NOTHING;
        """
        cur.execute(insert_query, trial)
        conn.commit()

def main():
    html = fetch_trials()
    trials = parse_trials(html)
    conn = connect_to_db()
    create_table(conn)
    for trial in trials:
        insert_trial(conn, trial)
    conn.close()

if __name__ == "__main__":
    main()
