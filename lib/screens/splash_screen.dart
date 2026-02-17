import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'email_verification_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    // Wait for 5 seconds as requested
    await Future.delayed(const Duration(seconds: 5));
    
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // Reload user to get latest verification status
      await user.reload();
      if (!mounted) return;
      final updatedUser = FirebaseAuth.instance.currentUser;

      if (updatedUser != null) {
        if (updatedUser.emailVerified) {
          // Logged in AND verified
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
          return;
        } else {
          // Logged in ELECTED but NOT verified
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => EmailVerificationScreen(
                email: updatedUser.email ?? '',
              ),
            ),
          );
          return;
        }
      }
    }

    // Not logged in at all
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/app_logo.jpg',
          fit: BoxFit.contain,
          width: MediaQuery.of(context).size.width * 0.8,
        ),
      ),
    );
  }
}
