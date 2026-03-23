import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameController = TextEditingController();
  bool _isUpdating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _nameController.text = user.displayName ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Display Name'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'New Name',
            hintText: 'Enter your name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = _nameController.text.trim();
              if (newName.isEmpty) return;

              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              setState(() => _isUpdating = true);

              try {
                await user.updateDisplayName(newName);
                await user.reload();
                if (mounted) {
                  setState(() {}); // Refresh UI
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Profile updated successfully')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Error updating profile: $e')),
                  );
                }
              } finally {
                if (mounted) setState(() => _isUpdating = false);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        centerTitle: true,
      ),
      body: _isUpdating
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: const Color(0xFF1D5DE4).withValues(alpha: 0.12),
                          child: Text(
                            (user?.displayName != null && user!.displayName!.isNotEmpty)
                                ? user.displayName![0].toUpperCase()
                                : (user?.email != null ? user!.email![0].toUpperCase() : '?'),
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D5DE4),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _updateDisplayName,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1D5DE4),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildEditableInfoCard(
                    context,
                    label: 'Display Name',
                    value: user?.displayName ?? 'Not set',
                    icon: Icons.person_outline,
                    onEdit: _updateDisplayName,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoCard(
                    context,
                    label: 'Email',
                    value: user?.email ?? 'No email',
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'UniBuy v1.0.0',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEditableInfoCard(BuildContext context,
      {required String label, required String value, required IconData icon, required VoidCallback onEdit}) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(16),
      child: _buildInfoCard(context, label: label, value: value, icon: icon, isEditable: true),
    );
  }

  Widget _buildInfoCard(BuildContext context,
      {required String label, required String value, required IconData icon, bool isEditable = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1D5DE4).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF1D5DE4)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (isEditable)
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
            ),
        ],
      ),
    );
  }
}
