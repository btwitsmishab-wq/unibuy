const fs = require('fs');
const path = require('path');
const db = require('./db');
require('dotenv').config();

async function migrate() {
    try {
        const sql = fs.readFileSync(path.join(__dirname, 'migrate_caching.sql'), 'utf8');
        console.log('Adding caching columns to global_products...');
        await db.query(sql);
        console.log('Cache Migration successful.');
        process.exit(0);
    } catch (e) {
        console.error('Migration failed:', e);
        process.exit(1);
    }
}

migrate();
