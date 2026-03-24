-- UniBuy Backend Schema
-- Using PostgreSQL for core business logic while keeping Firebase for Auth

-- 1. Categories Table (Metadata for rooms/items)
CREATE TABLE IF NOT EXISTS categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    icon VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Rooms Table (Small group buying spaces)
CREATE TABLE IF NOT EXISTS rooms (
    id SERIAL PRIMARY KEY,
    room_code VARCHAR(10) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    category_id INTEGER REFERENCES categories(id),
    created_by VARCHAR(128) NOT NULL, -- Firebase UID
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    is_shopping BOOLEAN DEFAULT FALSE,
    status VARCHAR(50) DEFAULT 'active'
);

-- 3. Room Members Table (Relationship between users and rooms)
CREATE TABLE IF NOT EXISTS room_members (
    id SERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    fire_base_uid VARCHAR(128) NOT NULL, -- User's Firebase UID
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(room_id, fire_base_uid)
);

-- 4. Items Table (Products/Items within a room)
CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    quantity INTEGER DEFAULT 1,
    priority INTEGER DEFAULT 1,
    urgency_level INTEGER DEFAULT 1,
    price_estimate DECIMAL(10, 2) DEFAULT 0,
    added_by VARCHAR(128) NOT NULL, -- Firebase UID
    added_by_name VARCHAR(255),
    status VARCHAR(50) DEFAULT 'pending', -- pending, available, unavailable, replaced, auto_selected
    is_bought BOOLEAN DEFAULT FALSE,
    purchased_price DECIMAL(10, 2),
    purchased_quantity INTEGER,
    status_updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Unique index to support smart consolidation (case-insensitive name per room)
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_item_room ON items (room_id, LOWER(name));

-- 5. Room Budget Table
CREATE TABLE IF NOT EXISTS room_budget (
    room_id INTEGER PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
    total_budget DECIMAL(10, 2) DEFAULT 0,
    current_total DECIMAL(10, 2) DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. Item Alternatives Table
CREATE TABLE IF NOT EXISTS item_alternatives (
    id SERIAL PRIMARY KEY,
    item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
    alternative_name VARCHAR(255) NOT NULL,
    price_estimate DECIMAL(10, 2) DEFAULT 0,
    priority INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. Item Decisions Table
CREATE TABLE IF NOT EXISTS item_decisions (
    id SERIAL PRIMARY KEY,
    item_id INTEGER REFERENCES items(id) ON DELETE CASCADE,
    selected_option TEXT NOT NULL,
    decision_type VARCHAR(50) NOT NULL,
    decided_by VARCHAR(128) NOT NULL, -- Firebase UID
    decision_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. Events Table (Internal event log)
CREATE TABLE IF NOT EXISTS events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    trigger_user VARCHAR(128), -- Firebase UID
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. Notifications Table (User-facing notifications)
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(128) NOT NULL, -- Firebase UID
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50),
    read_status BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_room ON notifications(room_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);
CREATE INDEX IF NOT EXISTS idx_events_room ON events(room_id);
CREATE INDEX IF NOT EXISTS idx_items_room ON items(room_id);
CREATE INDEX IF NOT EXISTS idx_items_owner ON items(added_by);
CREATE INDEX IF NOT EXISTS idx_alternatives_item ON item_alternatives(item_id);
CREATE INDEX IF NOT EXISTS idx_decisions_item ON item_decisions(item_id);

-- ============================================================
-- MODULE 6: PURCHASE FINALIZATION & CONFIDENCE EVALUATION
-- ============================================================

-- 10. Purchases Table
CREATE TABLE IF NOT EXISTS purchases (
    id SERIAL PRIMARY KEY,
    room_id INTEGER REFERENCES rooms(id) ON DELETE CASCADE,
    finalizer_user_id VARCHAR(128) NOT NULL, -- Firebase UID
    status VARCHAR(50) DEFAULT 'pending',    -- pending, approved, rejected, finalized
    total_cost DECIMAL(10, 2) DEFAULT 0,
    confidence_score INTEGER DEFAULT 0,       -- 0-100 percentage
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    finalized_at TIMESTAMP WITH TIME ZONE
);

-- 11. Purchase Approvals Table
CREATE TABLE IF NOT EXISTS purchase_approvals (
    id SERIAL PRIMARY KEY,
    purchase_id INTEGER REFERENCES purchases(id) ON DELETE CASCADE,
    user_id VARCHAR(128) NOT NULL, -- Firebase UID
    approval_status VARCHAR(50) DEFAULT 'pending', -- pending, approved, rejected
    approved_at TIMESTAMP WITH TIME ZONE,
    UNIQUE(purchase_id, user_id)
);

-- 12. Purchase Summary Table
CREATE TABLE IF NOT EXISTS purchase_summary (
    id SERIAL PRIMARY KEY,
    purchase_id INTEGER REFERENCES purchases(id) ON DELETE CASCADE,
    summary_data JSONB NOT NULL,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Module 6 Indexes
CREATE INDEX IF NOT EXISTS idx_purchases_room ON purchases(room_id);
CREATE INDEX IF NOT EXISTS idx_purchases_finalizer ON purchases(finalizer_user_id);
CREATE INDEX IF NOT EXISTS idx_approvals_purchase ON purchase_approvals(purchase_id);
CREATE INDEX IF NOT EXISTS idx_approvals_user ON purchase_approvals(user_id);
CREATE INDEX IF NOT EXISTS idx_summary_purchase ON purchase_summary(purchase_id);

-- Initial Categories
INSERT INTO categories (name, icon) VALUES 
('Groceries', 'shopping_basket'),
('Food', 'restaurant'),
('Household', 'home'),
('Electronics', 'devices')
ON CONFLICT (name) DO NOTHING;
