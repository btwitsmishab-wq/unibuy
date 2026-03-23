const fs = require('fs');
const path = require('path');
const db = require('./db');

async function migrate() {
    try {
        const sql = fs.readFileSync(path.join(__dirname, 'migrate_confidence.sql'), 'utf8');
        console.log('Running migration to create global_products...');
        await db.query(sql);
        console.log('Migration successful.');
        process.exit(0);
    } catch (e) {
        console.error('Migration failed:', e);
        process.exit(1);
    }
}

migrate();
