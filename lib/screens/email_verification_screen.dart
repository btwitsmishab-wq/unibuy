import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class EmailVerificationScreen extends StatefulWidget {
  final String email;
  
  const EmailVerificationScreen({super.key, required this.email});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _auth = FirebaseAuth.instance;
  bool _isResending = false;
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    // Periodically check if email is verified
    _checkTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkEmailVerified();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
      final updatedUser = _auth.currentUser;
      
      if (updatedUser?.emailVerified ?? false) {
        _checkTimer?.cancel();
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email verified successfully! You can now log in.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(); // Go back to login
        }
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;

    setState(() {
      _isResending = true;
    });

    try {
      final user = _auth.currentUser;
      
      if (user != null) {
        debugPrint("DEBUG: [Resend] Attempting to send verification email to ${user.email}");
        await user.sendEmailVerification();
        debugPrint("DEBUG: [Resend] Verification email API call completed successfully.");
        
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification email sent! Check your inbox and spam folder.'),
              backgroundColor: Colors.green,
            ),
          );

          // Start cooldown
          setState(() {
            _canResend = false;
            _resendCooldown = 60; // 60 seconds cooldown
          });

          _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            setState(() {
              _resendCooldown--;
              if (_resendCooldown <= 0) {
                _canResend = true;
                timer.cancel();
              }
            });
          });
        }
      } else {
        // User is not signed in, need to sign in first
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session expired. Please sign up again.'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = e.message ?? 'Failed to send verification email';
        if (e.code == 'too-many-requests') {
          message = 'Too many requests. Please wait a few minutes and try again.';
        }
        
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An unexpected error occurred: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.email_outlined,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            
            const Text(
              'Verification Email Sent!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            Text(
              'We sent a verification email to:',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            
            Text(
              widget.email,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'What to do next:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStep('1', 'Check your email inbox'),
                    _buildStep('2', 'Look for an email from Firebase'),
                    _buildStep('3', 'Click the verification link'),
                    _buildStep('4', 'Return here - we\'ll detect it automatically!'),
                    const SizedBox(height: 12),
                    Text(
                      '💡 Tip: Check your spam/junk folder if you don\'t see it',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            
            // Resend Button
            _isResending
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    onPressed: _canResend ? _resendVerificationEmail : null,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      _canResend 
                          ? 'Resend Verification Email' 
                          : 'Resend in ${_resendCooldown}s'
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
            
            const SizedBox(height: 16),
            
            // Back to Login Button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
