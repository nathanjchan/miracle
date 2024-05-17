import requests
import json
from db_utils import connect_to_db, do_query

def fetch_clinical_studies():
    url = "https://clinicaltrials.gov/api/v2/studies?pageSize=100"
    try:
        response = requests.get(url)
        response.raise_for_status()
        return response.json().get('studies', [])
    except requests.exceptions.RequestException as e:
        print(f"An error occurred while fetching data: {e}")
        return []

def parse_data(study):
    return {
        'nct_id': study['protocolSection']['identificationModule']['nctId'],
        'org_study_id': study['protocolSection']['identificationModule']['orgStudyIdInfo']['id'],
        'secondary_ids': json.dumps(study['protocolSection']['identificationModule'].get('secondaryIdInfos', [])),
        'organization': json.dumps(study['protocolSection']['identificationModule']['organization']),
        'brief_title': study['protocolSection']['identificationModule']['briefTitle'],
        'official_title': study['protocolSection']['identificationModule'].get('officialTitle'),
        'status': json.dumps(study['protocolSection']['statusModule']),
        'sponsor_collaborators': json.dumps(study['protocolSection'].get('sponsorCollaboratorsModule', {})),
        'description': json.dumps(study['protocolSection'].get('descriptionModule', {})),
        'conditions': json.dumps(study['protocolSection'].get('conditionsModule', {})),
        'design': json.dumps(study['protocolSection'].get('designModule', {})),
        'arms_interventions': json.dumps(study['protocolSection'].get('armsInterventionsModule', {})),
        'outcomes': json.dumps(study['protocolSection'].get('outcomesModule', {})),
        'eligibility': json.dumps(study['protocolSection'].get('eligibilityModule', {})),
        'contacts_locations': json.dumps(study['protocolSection'].get('contactsLocationsModule', {})),
        'derived': json.dumps(study['derivedSection']),
        'has_results': study['hasResults']
    }

def create_table(conn):
    create_table_query = """
        CREATE TABLE IF NOT EXISTS us (
            nct_id VARCHAR PRIMARY KEY,
            org_study_id VARCHAR,
            secondary_ids JSONB,
            organization JSONB,
            brief_title TEXT,
            official_title TEXT,
            status JSONB,
            sponsor_collaborators JSONB,
            description JSONB,
            conditions JSONB,
            design JSONB,
            arms_interventions JSONB,
            outcomes JSONB,
            eligibility JSONB,
            contacts_locations JSONB,
            derived JSONB,
            has_results BOOLEAN
        )
        """
    do_query(conn, create_table_query)

def insert_study(conn, study):
    with conn.cursor() as cur:
        insert_query = """
        INSERT INTO us (
            nct_id, org_study_id, secondary_ids, organization, brief_title, official_title, status,
            sponsor_collaborators, description, conditions, design, arms_interventions, outcomes,
            eligibility, contacts_locations, derived, has_results
        ) VALUES (
            %(nct_id)s, %(org_study_id)s, %(secondary_ids)s, %(organization)s, %(brief_title)s, %(official_title)s, %(status)s,
            %(sponsor_collaborators)s, %(description)s, %(conditions)s, %(design)s, %(arms_interventions)s, %(outcomes)s,
            %(eligibility)s, %(contacts_locations)s, %(derived)s, %(has_results)s
        )
        ON CONFLICT (nct_id) DO NOTHING
        """
        cur.execute(insert_query, study)
        conn.commit()

def main():
    studies = fetch_clinical_studies()
    conn = connect_to_db()
    create_table(conn)
    for study in studies:
        study_data = parse_data(study)
        insert_study(conn, study_data)
    conn.close()

if __name__ == "__main__":
    main()
