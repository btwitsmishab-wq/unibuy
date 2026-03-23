const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        const res = await pool.query('SELECT * FROM categories ORDER BY id ASC');
        console.log('CATEGORIES_START');
        console.log(JSON.stringify(res.rows));
        console.log('CATEGORIES_END');
        process.exit(0);
    } catch (err) {
        console.error('Fetch failed:', err);
        process.exit(1);
    }
}

run();
