const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        console.log('--- DATABASE STATUS ---');

        // Check categories
        const catRes = await pool.query('SELECT * FROM categories ORDER BY id ASC');
        console.log('CATEGORIES:', JSON.stringify(catRes.rows));

        // Check counts
        const roomCount = await pool.query('SELECT COUNT(*) FROM rooms');
        console.log('ROOM_COUNT:', roomCount.rows[0].count);

        const itemCount = await pool.query('SELECT COUNT(*) FROM items');
        console.log('ITEM_COUNT:', itemCount.rows[0].count);

        process.exit(0);
    } catch (err) {
        console.error('DB Status Check Failed:', err);
        process.exit(1);
    }
}

run();
