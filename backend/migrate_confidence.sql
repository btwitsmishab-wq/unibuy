CREATE TABLE IF NOT EXISTS global_products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) UNIQUE NOT NULL,
    rating DECIMAL(3, 2) DEFAULT 0.0,
    number_of_votes INTEGER DEFAULT 0,
    average_price DECIMAL(10, 2) DEFAULT 0.0,
    reviews JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert some dummy data for testing the confidence score
INSERT INTO global_products (name, rating, number_of_votes, average_price, reviews)
VALUES 
('Premium Wireless Headphones', 4.5, 120, 199.99, '["Great sound quality!", "Battery life is amazing, but a bit heavy.", "Absolutely love these headphones.", "Not worth the price, cheap build."]'::jsonb),
('Smartwatch Series 7', 3.8, 45, 249.00, '["Good features but battery dies fast.", "Nice display.", "Overpriced.", "Heart rate monitor is inaccurate."]'::jsonb),
('Ergonomic Office Chair', 4.8, 300, 349.50, '["Very comfortable for long hours.", "Best chair I have ever bought.", "Sturdy and well-built.", "Saved my back!"]'::jsonb)
ON CONFLICT (name) DO NOTHING;
