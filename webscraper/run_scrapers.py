import subprocess
import time
from db_utils import connect_to_db

def run_scrapers():
    subprocess.run(["python", "scraper_us.py"], check=True)
    subprocess.run(["python", "scraper_eu.py"], check=True)
    create_combined_view()

def create_combined_view():
    conn = connect_to_db()
    with conn.cursor() as cur:
        create_view_query = """
        CREATE OR REPLACE VIEW combined_view AS
        SELECT 
            'US_' || nct_id AS study_identifier,
            LOWER(official_title) AS study_name,
            condition AS conditions,
            sponsor_collaborators->'leadSponsor'->>'name' AS sponsor
        FROM us, jsonb_array_elements_text(conditions->'conditions') AS condition
        UNION ALL
        SELECT 
            'EU_' || eudract_number AS study_identifier,
            LOWER(full_title) AS study_name,
            medical_condition AS conditions,
            sponsor_name AS sponsor
        FROM eu;
        """
        cur.execute(create_view_query)
        conn.commit()
    conn.close()

if __name__ == "__main__":
    while True:
        run_scrapers()
        # Wait for 12 hours (12 hours * 60 minutes * 60 seconds)
        time.sleep(12 * 60 * 60)
