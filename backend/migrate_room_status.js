const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        console.log('Migrating ROOMS table and CATEGORIES...');

        // 1. Add status column to rooms
        console.log('Adding "status" column to rooms table...');
        await pool.query("ALTER TABLE rooms ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'active';");

        // 2. Add 'Other' category
        console.log('Adding "Other" category...');
        await pool.query("INSERT INTO categories (name, icon) VALUES ('Other', 'more_horiz') ON CONFLICT (name) DO NOTHING;");

        console.log('Successfully updated schema.');
        process.exit(0);
    } catch (err) {
        console.error('Migration failed:', err);
        process.exit(1);
    }
}

run();
