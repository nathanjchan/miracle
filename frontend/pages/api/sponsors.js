import pool from './db';

export default async function handler(req, res) {
  try {
    const { rows } = await pool.query(
      `SELECT sponsor, COUNT(DISTINCT study_identifier) as trial_count
       FROM combined_view
       GROUP BY sponsor`
    );
    res.status(200).json(rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}
