-- Safe migration: add missing columns to existing items table
ALTER TABLE items ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'pending';
ALTER TABLE items ADD COLUMN IF NOT EXISTS status_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE items ADD COLUMN IF NOT EXISTS is_bought BOOLEAN DEFAULT FALSE;

-- Add is_shopping to rooms
ALTER TABLE rooms ADD COLUMN IF NOT EXISTS is_shopping BOOLEAN DEFAULT FALSE;

-- Add quantity to item_alternatives
ALTER TABLE item_alternatives ADD COLUMN IF NOT EXISTS quantity INTEGER DEFAULT 1;

-- Update any existing rows to have 'pending' status if null
UPDATE items SET status = 'pending' WHERE status IS NULL;
UPDATE items SET status_updated_at = created_at WHERE status_updated_at IS NULL;

-- Verify
SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'items' ORDER BY ordinal_position;
