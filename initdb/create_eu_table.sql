CREATE TABLE IF NOT EXISTS eu (
    eudract_number VARCHAR PRIMARY KEY,
    sponsor_protocol_number VARCHAR,
r    sponsor_name TEXT,
    full_title TEXT,
    medical_condition TEXT,
    trial_protocol TEXT,
    trial_status TEXT,
    trial_results TEXT
);
