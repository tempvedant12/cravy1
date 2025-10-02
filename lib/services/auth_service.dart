import 'package:firebase_auth/firebase_auth.dart';

// This class encapsulates all Firebase Authentication logic
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream to notify the app about authentication state changes (login/logout)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get the current user
  User? get currentUser => _auth.currentUser;

  Future<String?> sendPasswordResetLink(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; // Success
    } on FirebaseAuthException catch (e) {
      return e.code; // Return the error code
    }
  }

  // Sign in with Email & Password
  // Returns a user-friendly error string on failure, or null on success.
  Future<String?> signInWithEmailAndPassword(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null; // Success
    } on FirebaseAuthException catch (e) {
      // Return a user-friendly message based on the error code
      return e.code;
    }
  }

  // Sign up (create user) with Email & Password
  // Returns a user-friendly error string on failure, or null on success.
  Future<String?> createUserWithEmailAndPassword(String name, String email, String password) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      // After creating the user, update their profile with the name
      await userCredential.user?.updateDisplayName(name);
      // Reload the user to ensure the displayName is updated
      await userCredential.user?.reload();
      return null; // Success
    } on FirebaseAuthException catch (e) {
      print(e.code);

      // Return a user-friendly message based on the error code
      return e.code;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}