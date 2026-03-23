require('dotenv').config();
const { calculateConfidence } = require('./confidence');
const db = require('./db');

async function test() {
    try {
        console.log('Fetching test product...');
        const productRes = await db.query("SELECT * FROM global_products WHERE name = 'Premium Wireless Headphones'");
        const product = productRes.rows[0];
        
        if (!product) {
            console.error('Test product not found in DB!');
            process.exit(1);
        }

        console.log('Product Data:', product);
        const result = calculateConfidence(product, 150.00); // 150 is cheaper than 199.99 average
        
        console.log('\n--- CONFIDENCE SCORE TEST ---');
        console.log(JSON.stringify(result, null, 2));
        
        process.exit(0);
    } catch (e) {
        console.error('Test failed:', e);
        process.exit(1);
    }
}

test();
