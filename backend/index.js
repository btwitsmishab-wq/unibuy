const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');
require('dotenv').config();
const db = require('./db');
const { calculateConfidence: calculateProductConfidence } = require('./confidence');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const logFile = path.join(__dirname, 'unibuy_backend_debug.log');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
    cors: {
        origin: '*',
        methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    }
});
const PORT = process.env.PORT || 5000;

// Shared Real-Time Notification Helper
const pushNotification = async (userId, roomId, title, message, type) => {
    try {
        const result = await db.query(
            'INSERT INTO notifications (user_id, room_id, title, message, type) VALUES ($1, $2, $3, $4, $5) RETURNING *',
            [userId, roomId, title, message, type]
        );
        const notif = result.rows[0];
        // Real-time push — only the specific user will receive this
        io.emit(`notification_${userId}`, {
            id: notif.id,
            title: notif.title,
            message: notif.message,
            type: notif.type,
            room_id: notif.room_id,
            created_at: notif.created_at,
            read_status: false,
        });
    } catch (e) {
        console.error('pushNotification error:', e);
    }
};

// Flag to check if Firebase is initialized
let isFirebaseEnabled = false;

// Middleware
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-user-uid'],
}));
app.use(express.json());

// Initialize Firebase Admin (Conditional logic if service account exists)
try {
    const serviceAccount = require(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
    console.log('Firebase Admin initialized');
    fs.appendFileSync(logFile, `[${new Date().toISOString()}] Firebase Admin initialized successfully\n`);
    isFirebaseEnabled = true;
} catch (error) {
    const warnMsg = `Firebase Admin could not be initialized. Check FIREBASE_SERVICE_ACCOUNT path in .env. Error: ${error.message}`;
    console.warn(warnMsg);
    fs.appendFileSync(logFile, `[${new Date().toISOString()}] ${warnMsg}\n`);
}

// --- SOCKET.IO CONNECTION ---
io.on('connection', (socket) => {
    socket.on('join_room', (roomId) => {
        socket.join(`room_${roomId}`);
    });

    socket.on('leave_room', (roomId) => {
        socket.leave(`room_${roomId}`);
    });
});

// --- NOTIFICATION SYSTEM ---

const emitEvent = async (type, roomId, triggerUser, metadata = {}) => {
    try {
        const eventRes = await db.query(
            'INSERT INTO events (event_type, room_id, trigger_user, metadata) VALUES ($1, $2, $3, $4) RETURNING *',
            [type, roomId, triggerUser, metadata]
        );

        // Background process to create notifications
        processNotifications(eventRes.rows[0]);
    } catch (err) {
        console.error('Event Error:', err);
    }
};

const processNotifications = async (event) => {
    const { event_type, room_id, trigger_user, metadata } = event;

    // Get all room members except the trigger user
    const members = await db.query(
        'SELECT fire_base_uid FROM room_members WHERE room_id = $1 AND fire_base_uid != $2',
        [room_id, trigger_user]
    );

    const roomRes = await db.query('SELECT name FROM rooms WHERE id = $1', [room_id]);
    const roomName = roomRes.rows[0]?.name || 'a room';

    let title = '';
    let message = '';

    switch (event_type) {
        case 'ITEM_ADDED':
            title = 'New Item Added';
            message = `${metadata.user_name || 'Someone'} added "${metadata.item_name}" to ${roomName}`;
            break;
        case 'ITEM_PURCHASED':
            title = 'Item Purchased';
            message = `"${metadata.item_name}" has been purchased in ${roomName}`;
            break;
        case 'ITEM_UNAVAILABLE':
            title = 'Item Unavailable';
            message = `"${metadata.item_name}" is marked as unavailable in ${roomName}`;
            break;
        case 'ITEM_OUT_OF_BUDGET':
            title = 'Item Out of Budget';
            message = `"${metadata.item_name}" was marked as out of budget in ${roomName}`;
            break;
        case 'ITEM_REPLACED':
            title = 'Item Replaced';
            message = `"${metadata.item_name}" has been replaced with "${metadata.alternative_name}" in ${roomName}`;
            break;
        case 'BUDGET_EXCEEDED':
            title = 'Budget Alert!';
            message = `The budget for ${roomName} has been exceeded! Total: $${metadata.current_total}`;
            break;
        case 'SHOPPING_STARTED':
            title = 'Shopping Started!';
            message = `Purchasing has started for "${roomName}". Get ready!`;
            break;
        case 'SHOPPING_FINISHED':
            title = 'Shopping Finished';
            message = `Shopping for "${roomName}" is complete. View the summary now!`;
            break;
        case 'ROOM_DEACTIVATED':
            title = 'Room Closed';
            message = `The room "${roomName}" has been closed by the owner.`;
            break;
        default:
            return;
    }

    for (const member of members.rows) {
        await pushNotification(member.fire_base_uid, room_id, title, message, event_type);
    }
};

// Auth Middleware
const authenticateUser = async (req, res, next) => {
    const authHeader = req.headers.authorization;
    const fallbackUid = req.headers['x-user-uid'];

    if (!isFirebaseEnabled && fallbackUid) {
        // Local dev fallback: Trust the UID from header (only for local testing)
        req.user = { uid: fallbackUid };
        return next();
    }

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    const idToken = authHeader.split('Bearer ')[1];
    try {
        const decodedToken = await admin.auth().verifyIdToken(idToken);
        req.user = decodedToken;
        next();
    } catch (error) {
        res.status(403).json({ error: 'Invalid token' });
    }
};

// Routes
app.get('/health', (req, res) => {
    res.json({ status: 'Backend is running', timestamp: new Date() });
});

// Auto-Migration Route (Temporary for Cloud Setup)
app.get('/api/admin/migrate', async (req, res) => {
    try {
        const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf-8');
        await db.query(schema);
        
        const migrate = fs.readFileSync(path.join(__dirname, 'migrate.sql'), 'utf-8');
        await db.query(migrate);

        // Inject the missing status column that was absent from both schema.sql and migrate.sql
        await db.query(`ALTER TABLE rooms ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'active'`);
        
        // Inject missing item columns
        await db.query(`ALTER TABLE items ADD COLUMN IF NOT EXISTS added_by_name VARCHAR(255)`);
        await db.query(`ALTER TABLE items ADD COLUMN IF NOT EXISTS purchased_price DECIMAL(10, 2)`);
        await db.query(`ALTER TABLE items ADD COLUMN IF NOT EXISTS purchased_quantity INTEGER`);

        res.json({ message: 'Database schema and migrations applied successfully!' });
    } catch (err) {
        console.error('Migration Error:', err);
        res.status(500).json({ error: 'Migration failed', details: err.message });
    }
});

// Get all categories
app.get('/api/categories', async (req, res) => {
    try {
        const result = await db.query('SELECT * FROM categories ORDER BY id ASC');
        res.json(result.rows);
    } catch (err) {
        console.error('Fetch Categories Error:', err);
        res.status(500).json({ error: 'Failed to fetch categories' });
    }
});

// Utility to generate room code
const generateRoomCode = () => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for (let i = 0; i < 6; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
};

// --- ROOMS ROUTES ---

// Start Shopping Mode
app.post('/api/rooms/:id/start-shopping', authenticateUser, async (req, res) => {
    const roomId = req.params.id;
    const requesterUid = req.user.uid;

    try {
        await db.query('BEGIN');

        // Check if requester is admin
        const roomRes = await db.query('SELECT name, created_by FROM rooms WHERE id = $1', [roomId]);
        if (roomRes.rows.length === 0) return res.status(404).json({ error: 'Room not found' });
        if (roomRes.rows[0].created_by !== requesterUid) {
            return res.status(403).json({ error: 'Only admin can start shopping' });
        }

        const roomName = roomRes.rows[0].name;

        // Set status = 'shopping' and is_shopping = true
        await db.query('UPDATE rooms SET status = $1, is_shopping = TRUE WHERE id = $2', ['shopping', roomId]);

        // Emit EVENT
        await emitEvent('SHOPPING_STARTED', roomId, requesterUid);

        await db.query('COMMIT');
        io.to(`room_${roomId}`).emit('items_updated');
        io.emit('room_status_updated', { roomId, status: 'shopping' });
        res.json({ message: 'Shopping mode started' });
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed to start shopping' });
    }
});

// Finalize Shopping Mode
app.post('/api/rooms/:id/finalize-shopping', authenticateUser, async (req, res) => {
    const roomId = req.params.id;
    const requesterUid = req.user.uid;

    try {
        // Check if requester is admin
        const roomRes = await db.query('SELECT created_by FROM rooms WHERE id = $1', [roomId]);
        if (roomRes.rows.length === 0) return res.status(404).json({ error: 'Room not found' });
        if (roomRes.rows[0].created_by !== requesterUid) {
            return res.status(403).json({ error: 'Only admin can finalize shopping' });
        }

        // Set status = 'completed' and is_shopping = false
        await db.query('UPDATE rooms SET status = $1, is_shopping = FALSE WHERE id = $2', ['completed', roomId]);

        // Emit EVENT
        await emitEvent('SHOPPING_FINISHED', roomId, requesterUid);

        io.to(`room_${roomId}`).emit('items_updated');
        io.emit('room_status_updated', { roomId, status: 'completed' });
        res.json({ message: 'Shopping mode finalized' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to finalize shopping' });
    }
});

// Close Room (Soft delete room, Hard delete items)
app.post('/api/rooms/:id/close', authenticateUser, async (req, res) => {
    const roomId = req.params.id;
    const requesterUid = req.user.uid;

    try {
        await db.query('BEGIN');

        // Check if requester is admin
        const roomRes = await db.query('SELECT created_by FROM rooms WHERE id = $1', [roomId]);
        if (roomRes.rows.length === 0) return res.status(404).json({ error: 'Room not found' });
        if (roomRes.rows[0].created_by !== requesterUid) {
            return res.status(403).json({ error: 'Only admin can close the room' });
        }

        // Deactivate room
        await db.query('UPDATE rooms SET is_active = FALSE WHERE id = $1', [roomId]);

        // Hard delete all items in this room
        await db.query('DELETE FROM items WHERE room_id = $1', [roomId]);

        // Emit EVENT
        await emitEvent('ROOM_DEACTIVATED', roomId, requesterUid);

        await db.query('COMMIT');
        io.to(`room_${roomId}`).emit('items_updated');
        io.emit('room_status_updated', { roomId, status: 'closed' });
        res.json({ message: 'Room closed and all items deleted' });
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed to close room' });
    }
});

// Create a Room
app.post('/api/rooms', async (req, res) => {
    const { name, category_id, fire_base_uid } = req.body;

    try {
        // Generate a unique room code (retry on collision - extremely rare)
        let room_code;
        let attempts = 0;
        while (attempts < 5) {
            const candidate = generateRoomCode();
            const existing = await db.query('SELECT id FROM rooms WHERE room_code = $1', [candidate]);
            if (existing.rows.length === 0) {
                room_code = candidate;
                break;
            }
            attempts++;
        }
        if (!room_code) return res.status(500).json({ error: 'Could not generate unique room code' });

        const result = await db.query(
            'INSERT INTO rooms (name, category_id, created_by, room_code) VALUES ($1, $2, $3, $4) RETURNING *',
            [name, category_id, fire_base_uid, room_code]
        );
        const room = result.rows[0];

        // Add creator as the first member
        await db.query(
            'INSERT INTO room_members (room_id, fire_base_uid) VALUES ($1, $2)',
            [room.id, fire_base_uid]
        );

        res.status(201).json(room);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to create room' });
    }
});

// Get User's Rooms
app.get('/api/rooms', async (req, res) => {
    const { fire_base_uid } = req.query;
    try {
        const roomsList = await db.query(
            `SELECT r.*, c.name AS category_name,
             (SELECT COUNT(*) FROM room_members rm WHERE rm.room_id = r.id) AS participant_count
             FROM rooms r
             JOIN categories c ON r.category_id = c.id
             JOIN room_members rm ON r.id = rm.room_id
             WHERE rm.fire_base_uid = $1 AND r.is_active = TRUE
             ORDER BY r.created_at DESC`,
            [fire_base_uid]
        );
        res.json(roomsList.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch rooms' });
    }
});

// Join a Room
app.post('/api/rooms/join', async (req, res) => {
    const { room_code, fire_base_uid } = req.body;
    try {
        const roomResult = await db.query('SELECT id FROM rooms WHERE room_code = $1 AND is_active = TRUE', [room_code]);
        if (roomResult.rows.length === 0) {
            return res.status(404).json({ error: 'Room not found' });
        }

        const roomId = roomResult.rows[0].id;
        await db.query(
            'INSERT INTO room_members (room_id, fire_base_uid) VALUES ($1, $2) ON CONFLICT DO NOTHING',
            [roomId, fire_base_uid]
        );

        res.json({ message: 'Joined successfully', roomId });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to join room' });
    }
});

// Delete a Room (Hard delete - cascading will handle items, members, etc.)
app.delete('/api/rooms/:id', async (req, res) => {
    const { id } = req.params;
    const { fire_base_uid } = req.query; // Only owner should delete

    try {
        const checkResult = await db.query('SELECT created_by FROM rooms WHERE id = $1', [id]);
        if (checkResult.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

        if (checkResult.rows[0].created_by !== fire_base_uid) {
            return res.status(403).json({ error: 'Only owner can delete the room' });
        }

        // Hard delete the room - this triggers SQL CASCADE delete for items, members, budgets, etc.
        await db.query('DELETE FROM rooms WHERE id = $1', [id]);

        res.json({ message: 'Room and all associated data deleted from database' });
    } catch (err) {
        console.error('Delete Room Error:', err);
        res.status(500).json({ error: 'Failed to delete room' });
    }
});

// --- ITEMS ROUTES ---

// Helper to update room total
const updateRoomTotal = async (roomId) => {
    try {
        console.log(`Updating room total for room: ${roomId}`);
        const result = await db.query(
            'SELECT SUM(quantity * price_estimate) as total FROM items WHERE room_id = $1',
            [roomId]
        );
        const total = parseFloat(result.rows[0].total) || 0;
        console.log(`Calculated total for room ${roomId}: ${total}`);

        await db.query(
            'INSERT INTO room_budget (room_id, current_total) VALUES ($1, $2) ON CONFLICT (room_id) DO UPDATE SET current_total = $2, updated_at = CURRENT_TIMESTAMP',
            [roomId, total]
        );

        const budgetResult = await db.query('SELECT total_budget FROM room_budget WHERE room_id = $1', [roomId]);
        const budget = parseFloat(budgetResult.rows[0]?.total_budget) || 0;

        // Trigger Budget Alert Event
        if (budget > 0 && total > budget) {
            console.log(`Budget exceeded for room ${roomId}: ${total} > ${budget}`);
            emitEvent('BUDGET_EXCEEDED', roomId, null, { current_total: total, total_budget: budget });
        }

        return {
            currentTotal: total,
            totalBudget: budget,
            budgetExceeded: budget > 0 && total > budget
        };
    } catch (err) {
        console.error('updateRoomTotal Error:', err);
        throw err;
    }
};

// Get Items in a Room
app.get('/api/rooms/:id/items', async (req, res) => {
    const roomId = req.params.id;
    try {
        const roomRes = await db.query('SELECT created_by, is_shopping, status, name FROM rooms WHERE id = $1', [roomId]);
        if (roomRes.rows.length === 0) return res.status(404).json({ error: 'Room not found' });

        const isShopping = roomRes.rows[0].is_shopping || false;
        const roomOwner = roomRes.rows[0].created_by || null;
        const roomName = roomRes.rows[0].name || null;

        const participantRes = await db.query('SELECT COUNT(*) FROM room_members WHERE room_id = $1', [roomId]);
        const participantCount = parseInt(participantRes.rows[0].count);

        const itemsRes = await db.query('SELECT * FROM items WHERE room_id = $1 ORDER BY created_at ASC', [roomId]);

        // Sync and fetch budget status
        const budgetStatus = await updateRoomTotal(roomId);

        res.json({
            items: itemsRes.rows,
            roomOwner,
            roomName,
            isShopping,
            status: roomRes.rows[0].status || 'active',
            participantCount,
            budgetStatus
        });
    } catch (err) {
        console.error('GET Items Error:', err);
        res.status(500).json({ error: 'Failed to fetch items', details: err.message });
    }
});

// Add Item (with Smart Consolidation)
app.post('/api/items', async (req, res) => {
    const { room_id, name, quantity, priority, urgency_level, price_estimate, added_by, user_name } = req.body;

    try {
        // Check if room is active
        const roomCheck = await db.query('SELECT is_active FROM rooms WHERE id = $1', [room_id]);
        if (roomCheck.rows.length === 0) return res.status(404).json({ error: 'Room not found' });
        if (!roomCheck.rows[0].is_active) return res.status(403).json({ error: 'Room is closed. Cannot add items.' });

        // Smart Consolidation using UPSERT
        const result = await db.query(
            `INSERT INTO items (room_id, name, quantity, priority, urgency_level, price_estimate, added_by, added_by_name) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
             ON CONFLICT (room_id, LOWER(name)) 
             DO UPDATE SET 
                quantity = items.quantity + EXCLUDED.quantity,
                price_estimate = EXCLUDED.price_estimate,
                urgency_level = EXCLUDED.urgency_level,
                priority = EXCLUDED.priority,
                added_by_name = EXCLUDED.added_by_name
             RETURNING *`,
            [room_id, name, quantity || 1, priority || 1, urgency_level || 1, price_estimate || 0, added_by, user_name || 'A user']
        );

        const budgetStatus = await updateRoomTotal(room_id);

        const itemId = result.rows[0].id;
        const alternatives = req.body.alternatives || []; // e.g. [{name: 'Alt 1', quantity: 2}, ...]

        if (alternatives.length > 0) {
            for (const alt of alternatives) {
                if (alt.name && alt.name.trim() !== "") {
                    await db.query(
                        'INSERT INTO item_alternatives (item_id, alternative_name, quantity, price_estimate) VALUES ($1, $2, $3, $4)',
                        [itemId, alt.name, alt.quantity || 1, alt.price_estimate || 0]
                    );
                }
            }
        }

        // Fetch user name for notification (from Firebase if possible, or just use UID for now if name not stored)
        // For now, let's assume we want to show 'Someone' or get it from req.body if frontend starts sending it.
        // Let's check if 'name' (user name) is passed in req.body
        const userName = req.body.user_name || 'A user';

        // Trigger Item Added Event
        emitEvent('ITEM_ADDED', room_id, added_by, {
            item_name: name,
            user_name: userName
        });

        res.status(201).json({
            item: result.rows[0],
            budgetStatus
        });
        io.to(`room_${room_id}`).emit('items_updated');
    } catch (err) {
        console.error('ADD ITEM ERROR:', err);
        res.status(500).json({ error: 'Failed to add item', details: err.message });
    }
});

// Update Item (PUT - usually for quantity)
app.put('/api/items/:id', async (req, res) => {
    const { quantity, price_estimate } = req.body;
    try {
        const result = await db.query(
            'UPDATE items SET quantity = COALESCE($1, quantity), price_estimate = COALESCE($2, price_estimate) WHERE id = $3 RETURNING *',
            [quantity, price_estimate, req.params.id]
        );

        if (result.rows.length === 0) return res.status(404).json({ error: 'Item not found' });

        const budgetStatus = await updateRoomTotal(result.rows[0].room_id);
        io.to(`room_${result.rows[0].room_id}`).emit('items_updated');
        res.json({ item: result.rows[0], budgetStatus });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to update item' });
    }
});

// Update Item Status (Toggle is_bought or set specific status)
app.patch('/api/items/:id', authenticateUser, async (req, res) => {
    const { is_bought, status, purchased_price, purchased_quantity } = req.body;
    try {
        const result = await db.query(
            `UPDATE items 
             SET is_bought = COALESCE($1, is_bought), 
                 status = COALESCE($2, status), 
                 purchased_price = COALESCE($3, purchased_price),
                 purchased_quantity = COALESCE($4, purchased_quantity),
                 status_updated_at = CURRENT_TIMESTAMP 
             WHERE id = $5 RETURNING *`,
            [is_bought, status, purchased_price, purchased_quantity, req.params.id]
        );

        if (result.rows.length === 0) return res.status(404).json({ error: 'Item not found' });

        const item = result.rows[0];
        const roomRes = await db.query('SELECT name FROM rooms WHERE id = $1', [item.room_id]);
        const roomName = roomRes.rows[0]?.name || 'a room';

        // Notify specialized outcome
        let title = '';
        let message = '';

        if (is_bought === true) {
            title = 'Item Purchased! 🎉';
            message = `Your item "${item.name}" has been purchased in ${roomName}.`;
        } else if (status === 'unavailable') {
            title = 'Item Unavailable';
            message = `Your item "${item.name}" is marked as unavailable in ${roomName}.`;
        } else if (status === 'out_of_budget') {
            title = 'Out of Budget';
            message = `Your item "${item.name}" was marked as out of budget in ${roomName}.`;
        } else if (status === 'replaced') {
            title = 'Item Replaced';
            message = `Your item "${item.name}" was replaced with an alternative in ${roomName}.`;
        }

        if (title) {
            await db.query(
                'INSERT INTO notifications (user_id, room_id, title, message, type) VALUES ($1, $2, $3, $4, $5)',
                [item.added_by, item.room_id, title, message, 'ITEM_STATUS_UPDATE']
            );
        }

        io.to(`room_${item.room_id}`).emit('items_updated');
        res.json(item);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to update item status' });
    }
});

// Delete Item
app.delete('/api/items/:id', authenticateUser, async (req, res) => {
    try {
        const itemId = req.params.id;
        const requesterUid = req.user.uid;

        // Fetch item and room owner info
        const itemResult = await db.query(
            `SELECT i.room_id, i.added_by, r.created_by as room_admin 
             FROM items i 
             JOIN rooms r ON i.room_id = r.id 
             WHERE i.id = $1`,
            [itemId]
        );

        if (itemResult.rows.length === 0) {
            return res.status(404).json({ error: 'Item not found' });
        }

        const { room_id, added_by, room_admin } = itemResult.rows[0];

        const logMsg = `[${new Date().toISOString()}] Deletion Attempt - Item: ${itemId}\n` +
            `Requester UID: ${requesterUid}\n` +
            `Item Creator UID: ${added_by}\n` +
            `Room Admin UID: ${room_admin}\n`;
        fs.appendFileSync(logFile, logMsg);

        // Authorization check: User must be item creator OR room admin
        if (requesterUid !== added_by && requesterUid !== room_admin) {
            fs.appendFileSync(logFile, 'Authorization FAILED\n');
            return res.status(403).json({ error: 'Forbidden: You do not have permission to delete this item' });
        }
        fs.appendFileSync(logFile, 'Authorization SUCCESS\n');

        await db.query('DELETE FROM items WHERE id = $1', [itemId]);

        const budgetStatus = await updateRoomTotal(room_id);
        io.to(`room_${room_id}`).emit('items_updated');
        res.json({ message: 'Item deleted', budgetStatus });
    } catch (err) {
        console.error('DELETE Item Error:', err);
        res.status(500).json({ error: 'Failed to delete item' });
    }
});

// Get Room Budget
app.get('/api/rooms/:id/budget', async (req, res) => {
    try {
        const status = await updateRoomTotal(req.params.id);
        res.json(status);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch budget status' });
    }
});

// Set Room Budget
app.post('/api/rooms/:id/budget', async (req, res) => {
    const { total_budget } = req.body;
    try {
        await db.query(
            'INSERT INTO room_budget (room_id, total_budget) VALUES ($1, $2) ON CONFLICT (room_id) DO UPDATE SET total_budget = $2',
            [req.params.id, total_budget]
        );
        const status = await updateRoomTotal(req.params.id);
        io.to(`room_${req.params.id}`).emit('items_updated');
        res.json(status);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to set budget' });
    }
});

// --- NOTIFICATIONS ROUTES ---

// Get User Notifications
app.get('/api/notifications', async (req, res) => {
    const { fire_base_uid } = req.query;
    try {
        const result = await db.query(
            'SELECT * FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50',
            [fire_base_uid]
        );
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch notifications' });
    }
});

// Mark Notification as Read
app.put('/api/notifications/:id/read', async (req, res) => {
    try {
        await db.query('UPDATE notifications SET read_status = TRUE WHERE id = $1', [req.params.id]);
        res.json({ message: 'Marked as read' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed' });
    }
});

// Clear All Notifications for a User
app.delete('/api/notifications', async (req, res) => {
    const { fire_base_uid } = req.query;
    if (!fire_base_uid) return res.status(400).json({ error: 'Missing fire_base_uid' });

    try {
        await db.query('DELETE FROM notifications WHERE user_id = $1', [fire_base_uid]);
        res.json({ message: 'Notifications cleared' });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to clear notifications' });
    }
});

// --- ITEM ALTERNATIVES & DECISIONS (Module 5) ---

// Get Alternatives for an Item
app.get('/api/items/:id/alternatives', async (req, res) => {
    try {
        const result = await db.query(
            'SELECT * FROM item_alternatives WHERE item_id = $1 ORDER BY priority ASC, created_at ASC',
            [req.params.id]
        );
        res.json(result.rows);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch alternatives' });
    }
});

// Add Alternative to an Item
app.post('/api/items/:id/alternatives', async (req, res) => {
    const { alternative_name, quantity, price_estimate, priority } = req.body;
    try {
        const result = await db.query(
            'INSERT INTO item_alternatives (item_id, alternative_name, quantity, price_estimate, priority) VALUES ($1, $2, $3, $4, $5) RETURNING *',
            [req.params.id, alternative_name, quantity || 1, price_estimate || 0, priority || 1]
        );
        res.status(201).json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to add alternative' });
    }
});

// Update Item Status (Pending, Available, Unavailable, Replaced, Auto_Selected)
app.patch('/api/items/:id/status', async (req, res) => {
    const { status } = req.body;
    try {
        const result = await db.query(
            'UPDATE items SET status = $1, status_updated_at = CURRENT_TIMESTAMP WHERE id = $2 RETURNING *',
            [status, req.params.id]
        );
        if (result.rows.length === 0) return res.status(404).json({ error: 'Item not found' });

        // If status is 'unavailable', we might want to trigger a notification eventually
        if (status === 'unavailable') {
            const item = result.rows[0];
            emitEvent('ITEM_UNAVAILABLE', item.room_id, null, { item_name: item.name });
        }

        res.json(result.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to update status' });
    }
});

// Record Decision
app.post('/api/items/:id/decision', async (req, res) => {
    const { selected_option, decision_type, decided_by } = req.body;
    try {
        // Start a transaction
        await db.query('BEGIN');

        const decisionRes = await db.query(
            'INSERT INTO item_decisions (item_id, selected_option, decision_type, decided_by) VALUES ($1, $2, $3, $4) RETURNING *',
            [req.params.id, selected_option, decision_type, decided_by]
        );

        // Update item status based on decision
        let newStatus = 'pending';
        if (decision_type === 'replacement') newStatus = 'replaced';
        else if (decision_type === 'skip') newStatus = 'unavailable';

        await db.query('UPDATE items SET status = $1 WHERE id = $2', [newStatus, req.params.id]);

        await db.query('COMMIT');
        res.status(201).json(decisionRes.rows[0]);
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed to record decision' });
    }
});

// --- INTELLIGENT MISSING ITEM MODULE (Module 5) ---

// Mark Item Unavailable
app.post('/api/items/:id/unavailable', async (req, res) => {
    try {
        await db.query('BEGIN');

        // 1. Update status
        const itemRes = await db.query(
            'UPDATE items SET status = \'unavailable\', status_updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *',
            [req.params.id]
        );

        if (itemRes.rows.length === 0) {
            await db.query('ROLLBACK');
            return res.status(404).json({ error: 'Item not found' });
        }

        const item = itemRes.rows[0];

        // 2. Notify the item owner
        const roomRes = await db.query('SELECT name FROM rooms WHERE id = $1', [item.room_id]);
        const roomName = roomRes.rows[0]?.name || 'a room';

        await db.query(
            'INSERT INTO notifications (user_id, room_id, title, message, type) VALUES ($1, $2, $3, $4, $5)',
            [item.added_by, item.room_id, 'Alert: Product Not Available', `BEEP! 🚨 Your item "${item.name}" is unavailable in ${roomName}. Please check alternatives!`, 'ITEM_UNAVAILABLE']
        );

        // 3. Fetch alternatives
        const alternatives = await db.query(
            'SELECT * FROM item_alternatives WHERE item_id = $1 ORDER BY priority ASC, price_estimate ASC',
            [item.id]
        );

        await db.query('COMMIT');

        res.json({
            message: 'Item marked as unavailable',
            item,
            alternatives: alternatives.rows
        });
        io.to(`room_${item.room_id}`).emit('items_updated');
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed to process unavailability' });
    }
});

// Select Alternative
app.post('/api/items/:id/select-alternative', authenticateUser, async (req, res) => {
    const { alternative_name, price_estimate, purchased_price, purchased_quantity, decided_by } = req.body;
    try {
        await db.query('BEGIN');

        // 1. Log the decision
        await db.query(
            'INSERT INTO item_decisions (item_id, selected_option, decision_type, decided_by) VALUES ($1, $2, $3, $4)',
            [req.params.id, alternative_name, 'replacement', decided_by]
        );

        // Check for name collision
        const existingRes = await db.query(
            'SELECT id, quantity FROM items WHERE room_id = (SELECT room_id FROM items WHERE id = $1) AND LOWER(name) = LOWER($2) AND id != $3',
            [req.params.id, alternative_name, req.params.id]
        );

        let result;
        if (existingRes.rows.length > 0) {
            const existingItem = existingRes.rows[0];
            // Merge into existing item
            result = await db.query(
                `UPDATE items 
                 SET quantity = quantity + $1, 
                     purchased_price = $2, 
                     purchased_quantity = $3,
                     status = 'replaced',
                     is_bought = TRUE
                 WHERE id = $4 RETURNING *`,
                [purchased_quantity, purchased_price, purchased_quantity, existingItem.id]
            );
            await db.query('DELETE FROM items WHERE id = $1', [req.params.id]);
        } else {
            // Update the item
            result = await db.query(
                `UPDATE items 
                 SET name = $1, 
                     price_estimate = $2, 
                     purchased_price = $3, 
                     purchased_quantity = $4,
                     status = 'replaced',
                     is_bought = TRUE
                 WHERE id = $5 RETURNING *`,
                [alternative_name, price_estimate, purchased_price, purchased_quantity, req.params.id]
            );
        }

        // 3. Notify owner
        const item = result.rows[0];
        await emitEvent('ITEM_REPLACED', item.room_id, req.user.uid, {
            item_id: item.id,
            item_name: item.name,
            original_item_id: req.params.id,
            alternative_name: alternative_name
        });

        await db.query('COMMIT');
        io.to(`room_${item.room_id}`).emit('items_updated');
        res.json({ message: 'Item replaced successfully', item: result.rows[0] });
    } catch (err) {
        await db.query('ROLLBACK');
        console.error('Error in select-alternative:', err);
        res.status(500).json({ error: 'Failed to select alternative', details: err.message });
    }
});

// Auto-Select Best Alternative
app.put('/api/items/:id/auto-select', async (req, res) => {
    try {
        await db.query('BEGIN');

        // Find best alternative: highest priority (lowest number), then lowest price
        const altRes = await db.query(
            'SELECT * FROM item_alternatives WHERE item_id = $1 ORDER BY priority ASC, price_estimate ASC LIMIT 1',
            [req.params.id]
        );

        if (altRes.rows.length === 0) {
            await db.query('ROLLBACK');
            return res.status(404).json({ error: 'No alternatives available for auto-selection' });
        }

        const bestAlt = altRes.rows[0];

        // Update item
        const result = await db.query(
            'UPDATE items SET name = $1, price_estimate = $2, status = \'auto_selected\' WHERE id = $3 RETURNING *',
            [bestAlt.alternative_name, bestAlt.price_estimate, req.params.id]
        );

        // Log decision
        await db.query(
            'INSERT INTO item_decisions (item_id, selected_option, decision_type, decided_by) VALUES ($1, $2, $3, $4)',
            [req.params.id, bestAlt.alternative_name, 'auto_selection', 'SYSTEM']
        );

        await db.query('COMMIT');
        io.to(`room_${result.rows[0].room_id}`).emit('items_updated');
        res.json({ message: 'Auto-selection complete', item: result.rows[0] });
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed auto-selection' });
    }
});

// --- BACKGROUND WORKERS ---

const runAutoDecisionWorker = async () => {
    console.log('Running Auto-Decision Worker...');
    try {
        // Find items that have been 'unavailable' for more than 5 minutes
        const pendingItems = await db.query(
            'SELECT * FROM items WHERE status = \'unavailable\' AND status_updated_at < NOW() - INTERVAL \'5 minutes\''
        );

        if (pendingItems.rows.length === 0) return;

        console.log(`Processing auto-decisions for ${pendingItems.rows.length} items...`);

        for (const item of pendingItems.rows) {
            try {
                await db.query('BEGIN');

                // Find best alternative: lowest price then highest priority (highest numerical value)
                // USER RULE: Choose alternative with lowest price, highest priority
                const altRes = await db.query(
                    'SELECT * FROM item_alternatives WHERE item_id = $1 ORDER BY price_estimate ASC, priority DESC LIMIT 1',
                    [item.id]
                );

                if (altRes.rows.length === 0) {
                    // No alternatives? Maybe mark as skipped or just ignore for now
                    console.log(`No alternatives found for item ${item.id} (${item.name})`);
                    await db.query('ROLLBACK');
                    continue;
                }

                const bestAlt = altRes.rows[0];

                // Check for name collision
                const existingRes = await db.query(
                    'SELECT id, quantity FROM items WHERE room_id = $1 AND LOWER(name) = LOWER($2) AND id != $3',
                    [item.room_id, bestAlt.alternative_name, item.id]
                );

                if (existingRes.rows.length > 0) {
                    const existingItem = existingRes.rows[0];
                    // Merge: add our quantity to the existing item and delete this item
                    await db.query(
                        'UPDATE items SET quantity = quantity + $1, status = \'auto_selected\', status_updated_at = NOW() WHERE id = $2',
                        [item.quantity, existingItem.id]
                    );
                    await db.query('DELETE FROM items WHERE id = $1', [item.id]);
                    console.log(`Merged item ${item.id} into existing item ${existingItem.id} due to name collision (${bestAlt.alternative_name})`);
                } else {
                    // Update item
                    await db.query(
                        'UPDATE items SET name = $1, price_estimate = $2, status = \'auto_selected\', status_updated_at = NOW() WHERE id = $3',
                        [bestAlt.alternative_name, bestAlt.price_estimate, item.id]
                    );
                }

                // Log decision
                await db.query(
                    'INSERT INTO item_decisions (item_id, selected_option, decision_type, decided_by) VALUES ($1, $2, $3, $4)',
                    [item.id, bestAlt.alternative_name, 'auto_selection', 'SYSTEM']
                );

                // Notify owner that system made a choice
                await db.query(
                    'INSERT INTO notifications (user_id, room_id, title, message, type) VALUES ($1, $2, $3, $4, $5)',
                    [item.added_by, item.room_id, 'System Auto-Selection', `System automatically selected "${bestAlt.alternative_name}" as a replacement for "${item.name}".`, 'AUTO_SELECTION']
                );

                await db.query('COMMIT');
                console.log(`Successfully auto-selected ${bestAlt.alternative_name} for item ${item.id}`);
            } catch (err) {
                await db.query('ROLLBACK');
                console.error(`Error processing item ${item.id}:`, err);
            }
        }
    } catch (err) {
        console.error('Auto-Decision Worker Error:', err);
    }
};

// --- MODULE 6: PURCHASE FINALIZATION & CONFIDENCE EVALUATION ---

// Helper: Calculate room confidence score
const calculateConfidence = async (roomId) => {
    const result = await db.query(
        `SELECT
            COUNT(*) FILTER (WHERE status IN ('available','auto_selected','replaced')) AS ready,
            COUNT(*) AS total
         FROM items WHERE room_id = $1`,
        [roomId]
    );
    const { ready, total } = result.rows[0];
    if (total === 0) return 0;
    return Math.round((parseInt(ready) / parseInt(total)) * 100);
};

// Initiate a Purchase (creates approval rows for all members)
app.post('/api/rooms/:id/purchase', async (req, res) => {
    const { finalizer_user_id } = req.body;
    const roomId = req.params.id;
    try {
        await db.query('BEGIN');

        // Calculate total cost and confidence
        const itemsRes = await db.query(
            'SELECT SUM(quantity * price_estimate) AS total FROM items WHERE room_id = $1',
            [roomId]
        );
        const totalCost = itemsRes.rows[0].total || 0;
        const confidenceScore = await calculateConfidence(roomId);

        // Create purchase record
        const purchaseRes = await db.query(
            `INSERT INTO purchases (room_id, finalizer_user_id, total_cost, confidence_score)
             VALUES ($1, $2, $3, $4) RETURNING *`,
            [roomId, finalizer_user_id, totalCost, confidenceScore]
        );
        const purchase = purchaseRes.rows[0];

        // Create approval rows for all room members
        const membersRes = await db.query(
            'SELECT fire_base_uid FROM room_members WHERE room_id = $1',
            [roomId]
        );
        for (const member of membersRes.rows) {
            const status = member.fire_base_uid === finalizer_user_id ? 'approved' : 'pending';
            await db.query(
                `INSERT INTO purchase_approvals (purchase_id, user_id, approval_status, approved_at)
                 VALUES ($1, $2, $3, $4)
                 ON CONFLICT (purchase_id, user_id) DO NOTHING`,
                [purchase.id, member.fire_base_uid, status, status === 'approved' ? new Date() : null]
            );

            // Notify each member via real-time push
            if (member.fire_base_uid !== finalizer_user_id) {
                await pushNotification(
                    member.fire_base_uid,
                    roomId,
                    'Purchase Approval Needed',
                    `A purchase has been initiated. Confidence: ${confidenceScore}%. Please approve or reject.`,
                    'PURCHASE_REQUESTED'
                );
            }
        }

        await db.query('COMMIT');
        res.status(201).json({ purchase, confidenceScore });
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed to initiate purchase' });
    }
});

// Approve or Reject a Purchase
app.patch('/api/purchases/:id/approve', async (req, res) => {
    const { user_id, decision } = req.body; // decision: 'approved' | 'rejected'
    try {
        await db.query('BEGIN');

        // Update this user's approval
        await db.query(
            `UPDATE purchase_approvals
             SET approval_status = $1, approved_at = CURRENT_TIMESTAMP
             WHERE purchase_id = $2 AND user_id = $3`,
            [decision, req.params.id, user_id]
        );

        // If anyone rejected => mark purchase rejected
        if (decision === 'rejected') {
            await db.query(
                'UPDATE purchases SET status = $1 WHERE id = $2',
                ['rejected', req.params.id]
            );
        } else {
            // Check if ALL members approved
            const pendingRes = await db.query(
                `SELECT COUNT(*) AS pending FROM purchase_approvals
                 WHERE purchase_id = $1 AND approval_status = 'pending'`,
                [req.params.id]
            );
            if (parseInt(pendingRes.rows[0].pending) === 0) {
                // Finalize the purchase
                await db.query(
                    `UPDATE purchases SET status = 'finalized', finalized_at = CURRENT_TIMESTAMP
                     WHERE id = $1`,
                    [req.params.id]
                );
            }
        }

        // Fetch updated purchase status
        const updatedRes = await db.query('SELECT * FROM purchases WHERE id = $1', [req.params.id]);
        await db.query('COMMIT');
        res.json(updatedRes.rows[0]);
    } catch (err) {
        await db.query('ROLLBACK');
        console.error(err);
        res.status(500).json({ error: 'Failed to process approval' });
    }
});

// Get Purchase Status
app.get('/api/purchases/:id', async (req, res) => {
    try {
        const purchaseRes = await db.query('SELECT * FROM purchases WHERE id = $1', [req.params.id]);
        if (purchaseRes.rows.length === 0) return res.status(404).json({ error: 'Purchase not found' });

        const approvalsRes = await db.query(
            'SELECT * FROM purchase_approvals WHERE purchase_id = $1',
            [req.params.id]
        );

        res.json({ purchase: purchaseRes.rows[0], approvals: approvalsRes.rows });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to fetch purchase' });
    }
});

// Get Room Confidence Score
app.get('/api/rooms/:id/confidence', async (req, res) => {
    try {
        const score = await calculateConfidence(req.params.id); // Note: This uses the old room confidence logic
        res.json({ room_id: req.params.id, confidence_score: score });
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to calculate confidence' });
    }
});

// Get Product Confidence Score (Read-Heavy, Cache-Aside)
app.post('/api/products/confidence', async (req, res) => {
    const { product_name, proposed_price } = req.body;
    if (!product_name) return res.status(400).json({ error: 'product_name is required' });

    try {
        const productRes = await db.query('SELECT * FROM global_products WHERE LOWER(name) = LOWER($1)', [product_name]);
        let product = productRes.rows[0];
        
        if (!product) {
            product = { name: product_name, rating: 0, number_of_votes: 0, average_price: 0, reviews: [] };
        }

        // 1. Check if we have a recent cached_score to prevent OpenAI spam (e.g. within last 24h)
        const isCacheValid = product.cached_score && product.score_last_updated && 
            (new Date() - new Date(product.score_last_updated) < 24 * 60 * 60 * 1000);

        let confidenceData;
        
        if (isCacheValid) {
            confidenceData = product.cached_score;
             // We dynamically adjust ONLY the price_score based on the user's proposed price in the UI
            if (product.average_price > 0 && proposed_price > 0) {
                const ratio = proposed_price / product.average_price;
                let newPriceScore = 100 - ((ratio - 0.5) * 100);
                if (newPriceScore > 100) newPriceScore = 100;
                if (newPriceScore < 0) newPriceScore = 0;
                
                // Recalculate strict final score formula with new dynamic price
                confidenceData.breakdown.price_score = Math.round(newPriceScore);
                confidenceData.score = Math.round(
                    (0.4 * confidenceData.breakdown.rating_score) +
                    (0.3 * confidenceData.breakdown.sentiment_score) +
                    (0.2 * confidenceData.breakdown.popularity_score) +
                    (0.1 * newPriceScore)
                );
            }
        } else {
            // 2. Heavy Recalculation (OpenAI)
            confidenceData = await calculateProductConfidence(product, proposed_price || product.average_price || 0);
            
            // 3. Save Cache background
            if (product.id) {
                db.query('UPDATE global_products SET cached_score = $1, score_last_updated = CURRENT_TIMESTAMP WHERE id = $2', 
                [JSON.stringify(confidenceData), product.id]).catch(console.error);
            }
        }

        res.json({
            product_name: product.name,
            score: confidenceData.score,
            breakdown: confidenceData.breakdown
        });
    } catch (err) {
        console.error('Confidence Score Error:', err);
        res.status(500).json({ error: 'Failed to calculate product confidence score' });
    }
});

// Interact with a Product (Write-Heavy, Real-time Sync)
app.post('/api/products/interact', async (req, res) => {
    const { product_name, new_review, vote_val } = req.body;
    if (!product_name) return res.status(400).json({ error: 'product_name is required' });

    try {
        let productRes = await db.query('SELECT * FROM global_products WHERE LOWER(name) = LOWER($1)', [product_name]);
        let product = productRes.rows[0];

        if (!product) {
            // Auto-create if not exists to allow interaction
            const insertRes = await db.query(
                'INSERT INTO global_products (name, rating, number_of_votes, average_price, reviews) VALUES ($1, $2, $3, $4, $5) RETURNING *',
                [product_name, vote_val || 5.0, vote_val ? 1 : 0, 0, new_review ? JSON.stringify([new_review]) : '[]']
            );
            product = insertRes.rows[0];
        } else {
            // Update logic
            let currentVotes = product.number_of_votes || 0;
            let currentRating = parseFloat(product.rating) || 0;
            let reviews = Array.isArray(product.reviews) ? product.reviews : [];

            if (vote_val) {
                const newTotalRating = (currentRating * currentVotes) + parseFloat(vote_val);
                currentVotes += 1;
                currentRating = newTotalRating / currentVotes;
            }

            if (new_review && new_review.trim() !== '') {
                reviews.push(new_review.trim());
            }

            const updatedRes = await db.query(
                'UPDATE global_products SET rating = $1, number_of_votes = $2, reviews = $3, score_last_updated = NULL WHERE id = $4 RETURNING *',
                [currentRating, currentVotes, JSON.stringify(reviews), product.id]
            );
            product = updatedRes.rows[0];
        }

        res.json({ status: 'Interaction recorded, processing real-time update...' });

        // Run heavy calculation in background and emit
        const backgroundConfidence = await calculateProductConfidence(product, product.average_price || 0);
        
        // Cache it securely
        await db.query('UPDATE global_products SET cached_score = $1, score_last_updated = CURRENT_TIMESTAMP WHERE id = $2', 
            [JSON.stringify(backgroundConfidence), product.id]);

        // Emit real-time WebSocket update to all listeners
        io.emit('product_score_updated', {
            product_name: product.name,
            score: backgroundConfidence.score,
            breakdown: backgroundConfidence.breakdown
        });

    } catch (err) {
        console.error('Interaction Error:', err);
        if (!res.headersSent) res.status(500).json({ error: 'Failed to record interaction' });
    }
});

// Generate Purchase Summary
app.post('/api/purchases/:id/summary', async (req, res) => {
    try {
        const purchaseRes = await db.query('SELECT * FROM purchases WHERE id = $1', [req.params.id]);
        if (purchaseRes.rows.length === 0) return res.status(404).json({ error: 'Not found' });

        const purchase = purchaseRes.rows[0];
        const itemsRes = await db.query(
            'SELECT name, quantity, price_estimate, status FROM items WHERE room_id = $1',
            [purchase.room_id]
        );
        const approvalsRes = await db.query(
            'SELECT user_id, approval_status FROM purchase_approvals WHERE purchase_id = $1',
            [req.params.id]
        );

        const summaryData = {
            purchase_id: purchase.id,
            room_id: purchase.room_id,
            total_cost: purchase.total_cost,
            confidence_score: purchase.confidence_score,
            status: purchase.status,
            items: itemsRes.rows,
            approvals: approvalsRes.rows,
            generated_at: new Date().toISOString()
        };

        const summaryRes = await db.query(
            'INSERT INTO purchase_summary (purchase_id, summary_data) VALUES ($1, $2) RETURNING *',
            [req.params.id, JSON.stringify(summaryData)]
        );

        res.status(201).json(summaryRes.rows[0]);
    } catch (err) {
        console.error(err);
        res.status(500).json({ error: 'Failed to generate summary' });
    }
});

// Run worker every 1 minute
setInterval(runAutoDecisionWorker, 60000);

app.use('/api-docs', express.static('docs')); // Just in case

server.listen(PORT, async () => {
    console.log(`Server is running on port ${PORT}`);

    // Test DB Connection
    try {
        await db.query('SELECT NOW()');
        console.log('✅ Connected to the PostgreSQL database');
    } catch (err) {
        console.error('❌ Database connection failed:', err.message);
    }
});
