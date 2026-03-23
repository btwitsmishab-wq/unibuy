import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';
import 'room_details_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  int _currentIndex = 1; // Default to Rooms tab

  // Rooms Tab Data
  List<dynamic> _rooms = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
    _fetchUnreadCount(); // Initial load
    _setupSocket();
  }

  void _setupSocket() {
    _socketService.connect();
    _socketService.onRoomStatusUpdated('home', (data) {
      if (!mounted) return;
      final roomId = data['roomId'];
      final newStatus = data['status'];
      // Instant in-state patch — no full API refetch needed
      final idx = _rooms.indexWhere((r) => r['id'] == roomId || r['id'].toString() == roomId.toString());
      if (idx != -1) {
        setState(() => _rooms[idx] = Map<String, dynamic>.from(_rooms[idx])..[  'status'] = newStatus);
      } else {
        // Room not in list yet (e.g. just joined), do a full refresh
        _fetchRooms();
      }
    });
    // Real-time badge: listen for this user's notifications
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _socketService.onNewNotification('home', uid, (notif) {
        if (mounted) setState(() => _unreadCount++);
      });
    }
  }

  @override
  void dispose() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _socketService.offNewNotification('home', uid);
    _socketService.offRoomStatusUpdated('home');
    super.dispose();
  }

  Future<void> _fetchUnreadCount() async {
    try {
      final notifs = await _apiService.getNotifications();
      if (mounted) {
        setState(() {
          _unreadCount = notifs.where((n) => n['read_status'] == false).length;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notification count: $e');
    }
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rooms = await _apiService.getUserRooms();
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _buildRoomsTab(),
          const NotificationsScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) _fetchRooms();
          // When tapping the Notifications tab, reset badge
          if (index == 2) {
            setState(() => _unreadCount = 0);
            _fetchUnreadCount();
          }
        },
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home_rounded), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.meeting_room_outlined), activeIcon: Icon(Icons.meeting_room_rounded), label: 'Rooms'),
          BottomNavigationBarItem(
            icon: Badge(
              label: Text('$_unreadCount'),
              isLabelVisible: _unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            activeIcon: Badge(
              label: Text('$_unreadCount'),
              isLabelVisible: _unreadCount > 0,
              child: const Icon(Icons.notifications_rounded),
            ),
            label: 'Activity',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), activeIcon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    final user = FirebaseAuth.instance.currentUser;
    final firstName = (user?.displayName ?? user?.email?.split('@')[0] ?? 'User').split(' ')[0];
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F264D), Color(0xFF1D5DE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting,', style: const TextStyle(color: Colors.white60, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(firstName, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _buildHeroStat('${_rooms.length}', 'Rooms', Icons.meeting_room_rounded),
                      const SizedBox(width: 12),
                      _buildHeroStat('$_unreadCount', 'Alerts', Icons.notifications_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Content
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text('Recent Rooms', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F264D))),
                const SizedBox(height: 12),
                if (_rooms.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.add_home_work_rounded, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No rooms yet', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('Go to the Rooms tab to create or join one.', style: TextStyle(color: Colors.grey.shade400, fontSize: 13), textAlign: TextAlign.center),
                      ],
                    ),
                  )
                else
                  ...(_rooms.take(3).map((room) => _buildHomeRoomCard(room))),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat(String value, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, height: 1)),
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeRoomCard(Map<String, dynamic> room) {
    final status = room['status'] ?? 'active';
    final Color statusColor = status == 'shopping' ? Colors.orange : (status == 'completed' ? Colors.green : const Color(0xFF1D5DE4));
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RoomDetailsScreen(
            roomId: room['id'],
            roomName: room['name'] ?? 'Room',
            roomCode: room['room_code'] ?? '',
          ),
        )).then((_) => _fetchRooms());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  (room['name'] ?? 'R')[0].toUpperCase(),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: statusColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(room['name'] ?? 'Room', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F264D))),
                  Text('${room['participant_count'] ?? 0} members', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomsTab() {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rooms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_rounded),
            tooltip: 'Join Room',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JoinRoomScreen()));
              _fetchRooms();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateRoomScreen()));
          _fetchRooms();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create Room', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: user == null
          ? const Center(child: Text('Please log in again.'))
          : RefreshIndicator(
              onRefresh: _fetchRooms,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(child: Text('Error: $_errorMessage'))
                      : _rooms.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                              itemCount: _rooms.length,
                              itemBuilder: (context, index) {
                                final room = _rooms[index];
                                final roomName = room['name'] ?? 'No Name';
                                final isOwner = room['created_by'] == user.uid;
                                final status = room['status'] ?? 'active';
                                final Color statusColor = status == 'shopping'
                                    ? Colors.orange
                                    : (status == 'completed' ? Colors.green : const Color(0xFF1D5DE4));

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade200, width: 1.5),
                                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => RoomDetailsScreen(
                                              roomId: room['id'],
                                              roomName: roomName,
                                              roomCode: room['room_code'] ?? '',
                                            ),
                                          ),
                                        ).then((_) => _fetchRooms());
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 48, height: 48,
                                              decoration: BoxDecoration(
                                                color: statusColor.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  roomName.isNotEmpty ? roomName[0].toUpperCase() : '?',
                                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: statusColor),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF0F264D))),
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    '${room['category_name'] ?? 'General'}  ·  ${room['participant_count'] ?? 0} members',
                                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: statusColor.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                                                ),
                                                const SizedBox(height: 6),
                                                if (isOwner)
                                                  InkWell(
                                                    onTap: () => _showDeleteDialog(context, room['id'], roomName),
                                                    borderRadius: BorderRadius.circular(6),
                                                    child: Padding(
                                                      padding: const EdgeInsets.all(2),
                                                      child: Icon(Icons.delete_outline_rounded, color: Colors.red.shade300, size: 16),
                                                    ),
                                                  )
                                                else
                                                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 18),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
    );
  }


  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90, height: 90,
            decoration: BoxDecoration(
              color: const Color(0xFF1D5DE4).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.meeting_room_outlined, size: 46, color: Color(0xFF1D5DE4)),
          ),
          const SizedBox(height: 20),
          const Text('No rooms yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F264D))),
          const SizedBox(height: 8),
          Text('Create a room or join one using a code!', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ],
      ),
    );
  }

  // ... (keeping _showDeleteDialog and _deleteRoom as they were but slightly cleaned for the new context)
  Future<void> _showDeleteDialog(BuildContext context, int roomId, String roomName) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Are you sure you want to delete "$roomName"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteRoom(context, roomId);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRoom(BuildContext context, int roomId) async {
    try {
      await _apiService.deleteRoom(roomId);
      _fetchRooms();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
