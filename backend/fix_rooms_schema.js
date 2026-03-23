const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        console.log('Fixing rooms table schema...');

        // 1. Add status column to rooms
        console.log('Adding "status" column to rooms table...');
        await pool.query("ALTER TABLE rooms ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'active';");

        // 2. Add is_shopping column to rooms
        console.log('Adding "is_shopping" column to rooms table...');
        await pool.query("ALTER TABLE rooms ADD COLUMN IF NOT EXISTS is_shopping BOOLEAN DEFAULT FALSE;");

        console.log('Successfully updated rooms table schema.');
        process.exit(0);
    } catch (err) {
        console.error('Migration failed:', err);
        process.exit(1);
    }
}

run();
