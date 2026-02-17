import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _nameController = TextEditingController();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  
  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String selectedCategory = 'Groceries';
  final List<String> categories = ['Groceries', 'Food', 'Household', 'Other'];

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(Random().nextInt(chars.length))));
  }

  Future<void> _createRoom() async {
    final roomName = _nameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final roomCode = _generateRoomCode();
      final roomRef = _firestore.collection('rooms').doc();

      // We don't await this so it happens "optimistically" in the background
      // Firestore will handle the local write and background sync
      roomRef.set({
        'roomId': roomRef.id,
        'roomName': roomName,
        'category': selectedCategory,
        'roomCode': roomCode,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'memberIds': [user.uid], // Creator is the first member
      });

      if (mounted) {
        // Return to home screen immediately
        Navigator.of(context).pop();
        
        // Clear any existing snackbars to avoid queuing
        ScaffoldMessenger.of(context).clearSnackBars();

        // Show success message (will appear on the Home screen)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Room "$roomName" Created! Code: $roomCode'), 
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2), // Reduced for snappier feel
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Room Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Weekly Shopping',
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Select Category:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    selectedCategory = newValue!;
                  });
                },
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Creating your room...'),
                        ],
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _createRoom,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Create Room',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
