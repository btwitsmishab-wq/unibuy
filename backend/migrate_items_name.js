const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        console.log('Migrating ITEMS table...');

        // 1. Add added_by_name column to items
        console.log('Adding "added_by_name" column to items table...');
        await pool.query("ALTER TABLE items ADD COLUMN IF NOT EXISTS added_by_name VARCHAR(255) DEFAULT 'A user';");

        console.log('Successfully updated schema.');
        process.exit(0);
    } catch (err) {
        console.error('Migration failed:', err);
        process.exit(1);
    }
}

run();
