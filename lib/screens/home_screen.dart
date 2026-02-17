import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_room_screen.dart';
import 'join_room_screen.dart';
import 'login_screen.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Stream<QuerySnapshot>? _roomsStream;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _roomsStream = FirebaseFirestore.instance
          .collection('rooms')
          .where('memberIds', arrayContains: user.uid)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Rooms'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Join Room',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const JoinRoomScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const CreateRoomScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      
      body: user == null || _roomsStream == null
          ? const Center(child: Text('Please log in again.'))
          : StreamBuilder<QuerySnapshot>(
              stream: _roomsStream,
              builder: (context, snapshot) {
                // If we have data (from cache), show it immediately.
                // Only show progress indicator if we have NO data and are still waiting.
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Checking your rooms...'),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final rooms = snapshot.data?.docs ?? [];

                if (rooms.isEmpty) {
                  return Center(
                    child: SingleChildScrollView( // Allow pull to refresh if needed later
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          const Text(
                            'You are not in any rooms yet.',
                            style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          const Text('Create one or join using a code!'),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final roomDoc = rooms[index];
                    final room = roomDoc.data() as Map<String, dynamic>;
                    final roomName = room['roomName'] ?? 'No Name';
                    final isOwner = room['createdBy'] == user.uid;
                    
                    return Card(
                      key: ValueKey(roomDoc.id),
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            roomName.isNotEmpty ? roomName[0].toUpperCase() : '?',
                            style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                        ),
                        title: Text(
                          roomName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('Category: ${room['category']}'),
                        trailing: isOwner 
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _showDeleteDialog(context, roomDoc.id, roomName),
                            )
                          : const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // TODO: Navigate to RoomDetailsScreen
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, String roomId, String roomName) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Room'),
        content: Text('Are you sure you want to delete "$roomName"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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

  Future<void> _deleteRoom(BuildContext context, String roomId) async {
    try {
      await FirebaseFirestore.instance.collection('rooms').doc(roomId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room deleted successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting room: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
