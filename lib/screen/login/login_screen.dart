import 'dart:ui';
import 'package:cravy/services/auth_service.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _formSwitchController;

  String email = '', password = '', name = '', error = '';
  bool isLogin = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _formSwitchController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _formSwitchController.dispose();
    super.dispose();
  }

  void toggleView() {
    setState(() {
      _formKey.currentState?.reset();
      error = '';
      isLogin = !isLogin;
      isLogin ? _formSwitchController.reverse() : _formSwitchController.forward();
    });
  }

  Future<void> submitForm() async {
    // Hide keyboard for a cleaner experience
    FocusScope.of(context).unfocus();
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
        error = '';
      });
      String? result = isLogin
          ? await _auth.signInWithEmailAndPassword(email, password)
          : await _auth.createUserWithEmailAndPassword(name, email, password);

      // Check if the widget is still in the tree before updating the state
      if (mounted && result != null) {
        setState(() {
          error = result;
          isLoading = false;
        });
      } else if (mounted) {
        // If successful, the AuthWrapper will navigate away.
        // This is a fallback to stop the loading indicator.
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          // Center the content and constrain its width on larger screens
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 50),
                          _buildHeader(),
                          const SizedBox(height: 50),
                          _buildForm(),
                          const SizedBox(height: 30),
                          _buildToggleViewButton(),
                          const SizedBox(height: 50),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.scaffoldBackgroundColor,
            theme.scaffoldBackgroundColor.withOpacity(0.9)
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(Icons.ramen_dining_outlined, color: theme.textTheme.displayLarge?.color, size: 40),
        const SizedBox(height: 16),
        Text('DineFlow', style: theme.textTheme.displayLarge),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
          child: Text(
            isLogin ? 'Welcome back' : 'Create your account',
            key: ValueKey<bool>(isLogin),
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizeTransition(
            sizeFactor: CurvedAnimation(parent: _formSwitchController, curve: Curves.easeInOut),
            axisAlignment: -1.0,
            child: Column(
              children: [
                _buildTextField(
                  label: 'Name',
                  icon: Icons.person_outline,
                  onChanged: (val) => setState(() => name = val),
                  validator: (val) => !isLogin && val!.isEmpty ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          _buildTextField(
            label: 'Email',
            icon: Icons.alternate_email_rounded,
            keyboardType: TextInputType.emailAddress,
            onChanged: (val) => setState(() => email = val.trim()),
            validator: (val) => val!.isEmpty || !val.contains('@') ? 'Enter a valid email' : null,
          ),
          const SizedBox(height: 20),
          _buildTextField(
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            isPassword: true,
            onChanged: (val) => setState(() => password = val),
            validator: (val) => val!.length < 6 ? 'Password must be 6+ characters' : null,
          ),
          const SizedBox(height: 12),
          if (isLogin)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _showForgotPasswordDialog(context),
                child: const Text('Forgot Password?'),
              ),
            ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: error.isNotEmpty ? _buildErrorMessage() : const SizedBox(height: 20),
          ),
          const SizedBox(height: 10),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    required ValueChanged<String> onChanged,
    required FormFieldValidator<String> validator,
  }) {
    return TextFormField(
      obscureText: isPassword,
      keyboardType: keyboardType,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.9),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
      ),
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _buildErrorMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          error,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.error),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : ElevatedButton(
      onPressed: submitForm,
      child: Text(isLogin ? 'Sign In' : 'Create Account'),
    );
  }

  Widget _buildToggleViewButton() {
    final theme = Theme.of(context);
    return Center(
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: theme.textTheme.bodyLarge?.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: toggleView,
        child: Text.rich(
          TextSpan(
            text: isLogin ? "Don't have an account? " : "Already have an account? ",
            style: theme.textTheme.bodyLarge,
            children: [
              TextSpan(
                text: isLogin ? 'Sign Up' : 'Sign In',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Reset Password'),
          content: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Enter your email',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email.')),
                  );
                  return;
                }

                Navigator.of(dialogContext).pop(); // Close the dialog

                final result = await _auth.sendPasswordResetLink(email);

                if (mounted) {
                  final message = result == null
                      ? 'Password reset link sent to $email.'
                      : 'Error: Could not send link.'; // Improve error handling as needed

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              },
              child: const Text('Send Link'),
            ),
          ],
        );
      },
    );
  }


}