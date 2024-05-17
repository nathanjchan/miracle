import pool from './db';

export default async function handler(req, res) {
  try {
    const { rows } = await pool.query(
      `SELECT conditions, COUNT(*) as trial_count
       FROM combined_view
       GROUP BY conditions`
    );
    res.status(200).json(rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}
