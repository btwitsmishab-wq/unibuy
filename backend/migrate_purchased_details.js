const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        console.log('Adding purchased_price and purchased_quantity to items table...');
        await pool.query('ALTER TABLE items ADD COLUMN IF NOT EXISTS purchased_price DECIMAL(10, 2);');
        await pool.query('ALTER TABLE items ADD COLUMN IF NOT EXISTS purchased_quantity INTEGER;');
        console.log('Successfully updated schema.');
        process.exit(0);
    } catch (err) {
        console.error('Migration failed:', err);
        process.exit(1);
    }
}

run();
