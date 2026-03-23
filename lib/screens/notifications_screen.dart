import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  final SocketService _socketService = SocketService();
  List<dynamic> _notifications = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _fetchNotifications();
    _subscribeToSocket();
  }

  void _subscribeToSocket() {
    if (_currentUserId == null) return;
    _socketService.onNewNotification('notifications_screen', _currentUserId!, (newNotif) {
      if (mounted) {
        setState(() {
          // Prepend the real-time notification to the top of the list
          _notifications.insert(0, newNotif);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(newNotif['title'] ?? 'New notification')),
              ],
            ),
            backgroundColor: const Color(0xFF1D5DE4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    if (_currentUserId != null) {
      _socketService.offNewNotification('notifications_screen', _currentUserId!);
    }
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    try {
      final notifications = await _apiService.getNotifications();
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notifications: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await _apiService.markNotificationAsRead(id);
      setState(() {
        final idx = _notifications.indexWhere((n) => n['id'] == id);
        if (idx != -1) _notifications[idx]['read_status'] = true;
      });
    } catch (e) {
      // Silent fail
    }
  }

  void _showClearConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to delete all notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearAll();
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll() async {
    setState(() => _isLoading = true);
    try {
      await _apiService.clearNotifications();
      setState(() => _notifications = []);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing notifications: $e')),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  int get _unreadCount => _notifications.where((n) => !(n['read_status'] ?? false)).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                color: Color(0xFF0F264D),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D5DE4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_unreadCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _showClearConfirmation,
              child: const Text('Clear All', style: TextStyle(color: Colors.red)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0F264D)),
            onPressed: _fetchNotifications,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 72, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('All caught up!', style: TextStyle(fontSize: 18, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text('New activity will appear here in real-time.', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notif = _notifications[index];
                    final bool isRead = notif['read_status'] ?? false;
                    final DateTime createdAt = DateTime.parse(notif['created_at']);

                    return InkWell(
                      onTap: isRead ? null : () => _markRead(notif['id']),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isRead ? Colors.white : const Color(0xFFEEF4FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isRead ? Colors.grey.shade200 : const Color(0xFF1D5DE4).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: _getIconColor(notif['type']).withValues(alpha: 0.15),
                              child: Icon(_getIcon(notif['type']), color: _getIconColor(notif['type']), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          notif['title'],
                                          style: TextStyle(
                                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                            fontSize: 15,
                                            color: const Color(0xFF0F264D),
                                          ),
                                        ),
                                      ),
                                      if (!isRead)
                                        Container(
                                          width: 8, height: 8,
                                          margin: const EdgeInsets.only(left: 8, top: 4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF1D5DE4),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    notif['message'],
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    DateFormat('MMM d, h:mm a').format(createdAt.toLocal()),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  IconData _getIcon(String? type) {
    switch (type) {
      case 'BUDGET_EXCEEDED': return Icons.warning_amber_rounded;
      case 'ITEM_ADDED': return Icons.add_shopping_cart_rounded;
      case 'PURCHASE_REQUESTED': return Icons.receipt_long_rounded;
      case 'AUTO_SELECTION': return Icons.auto_fix_high_rounded;
      case 'ITEM_PURCHASED': return Icons.check_circle_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _getIconColor(String? type) {
    switch (type) {
      case 'BUDGET_EXCEEDED': return Colors.orange;
      case 'ITEM_ADDED': return Colors.green;
      case 'PURCHASE_REQUESTED': return const Color(0xFF1D5DE4);
      case 'AUTO_SELECTION': return Colors.purple;
      case 'ITEM_PURCHASED': return Colors.teal;
      default: return Colors.blueGrey;
    }
  }
}
