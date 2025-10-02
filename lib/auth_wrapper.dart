import 'package:cravy/screen/home/HomeScreen.dart';
import 'package:cravy/screen/login/login_screen.dart';
import 'package:cravy/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// This widget acts as a gatekeeper, showing the correct screen based on auth state.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // While waiting for connection, show a loading indicator
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // If user data exists, they are logged in. Show HomeScreen.
        if (snapshot.hasData && snapshot.data != null) {
          return const HomeScreen();
        }

        // Otherwise, the user is logged out. Show LoginScreen.
        return const LoginScreen();
      },
    );
  }
}
