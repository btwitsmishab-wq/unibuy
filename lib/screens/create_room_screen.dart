import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_service.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  final _nameController = TextEditingController();
  final _apiService = ApiService();
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  
  List<dynamic> _availableCategories = [];
  int? _selectedCategoryId;
  bool _isCategoriesLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await _apiService.getCategories();
      if (mounted) {
        setState(() {
          _availableCategories = categories;
          if (_availableCategories.isNotEmpty) {
            _selectedCategoryId = _availableCategories[0]['id'];
          }
          _isCategoriesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCategoriesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading categories: $e')),
        );
      }
    }
  }

  Future<void> _createRoom() async {
    final roomName = _nameController.text.trim();
    if (roomName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room name')),
      );
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final room = await _apiService.createRoom(roomName, _selectedCategoryId!);
      final roomCode = room['room_code'];

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Room Created!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Your room "$roomName" is ready.'),
              const SizedBox(height: 20),
              const Text(
                'Room Code',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: Text(
                  roomCode,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 6,
                    color: Colors.deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Share this code with others to invite them.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).pop();

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
              _isCategoriesLoading
                  ? const Center(child: LinearProgressIndicator())
                  : DropdownButtonFormField<int>(
                      initialValue: _selectedCategoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: _availableCategories.map((dynamic category) {
                        return DropdownMenuItem<int>(
                          value: category['id'],
                          child: Row(
                            children: [
                              Icon(_getCategoryIcon(category['icon'])),
                              const SizedBox(width: 12),
                              Text(category['name']),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (int? newValue) {
                        setState(() {
                          _selectedCategoryId = newValue!;
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

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'shopping_basket':
        return Icons.shopping_basket;
      case 'restaurant':
        return Icons.restaurant;
      case 'home':
        return Icons.home;
      case 'devices':
        return Icons.devices;
      case 'more_horiz':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }
}
