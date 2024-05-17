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
);
