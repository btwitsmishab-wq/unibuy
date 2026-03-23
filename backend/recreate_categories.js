const { Pool } = require('pg');
require('dotenv').config({ path: require('path').join(__dirname, '.env') });

const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
});

async function run() {
    try {
        console.log('--- RECREATING CATEGORIES TABLE ---');

        // 1. Create table
        await pool.query(`
            CREATE TABLE IF NOT EXISTS categories (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) UNIQUE NOT NULL,
                icon VARCHAR(50) NOT NULL
            );
        `);
        console.log('Table "categories" ensured.');

        // 2. Insert default categories
        const categories = [
            ['Groceries', 'shopping_basket'],
            ['Food', 'restaurant'],
            ['Household', 'home'],
            ['Electronics', 'devices'],
            ['Other', 'more_horiz']
        ];

        for (const [name, icon] of categories) {
            await pool.query(
                'INSERT INTO categories (name, icon) VALUES ($1, $2) ON CONFLICT (name) DO NOTHING',
                [name, icon]
            );
        }
        console.log('Default categories populated.');

        // 3. Check result
        const res = await pool.query('SELECT * FROM categories ORDER BY id ASC');
        console.log('Table Content:', JSON.stringify(res.rows));

        process.exit(0);
    } catch (err) {
        console.error('Recreation failed:', err);
        process.exit(1);
    }
}

run();
