import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _joinRoom() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room code')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      // 1. Find the room with this code
      final querySnapshot = await FirebaseFirestore.instance
          .collection('rooms')
          .where('roomCode', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid Room Code'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final roomDoc = querySnapshot.docs.first;
      final roomData = roomDoc.data() as Map<String, dynamic>;
      final List<dynamic> memberIds = List.from(roomData['memberIds'] ?? []);

      // 2. Check if user is already a member
      if (memberIds.contains(user.uid)) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are already in this room!'), backgroundColor: Colors.orange),
          );
          Navigator.pop(context);
        }
        return;
      }

      // 3. Add user to memberIds array
      await roomDoc.reference.update({
        'memberIds': FieldValue.arrayUnion([user.uid]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined the room!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                'Enter the Room Code shared by your friend to join the purchase list.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _codeController,
                decoration: const InputDecoration(
                  labelText: 'Room Code',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., AB12X9',
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Joining room...'),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _joinRoom,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Join Room'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
