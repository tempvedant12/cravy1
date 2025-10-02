import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateRestaurantScreen extends StatefulWidget {
  const CreateRestaurantScreen({super.key});

  @override
  State<CreateRestaurantScreen> createState() => _CreateRestaurantScreenState();
}

class _CreateRestaurantScreenState extends State<CreateRestaurantScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _restaurantName = '';
  String _address = '';
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _createRestaurant() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      _formKey.currentState!.save();

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          // Handle case where user is not logged in
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You must be logged in to create a restaurant.')),
            );
          }
          setState(() => _isLoading = false);
          return;
        }

        // 1. Create the restaurant document
        DocumentReference restaurantRef = await FirebaseFirestore.instance.collection('restaurants').add({
          'name': _restaurantName,
          'address': _address,
          'ownerId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 2. Add the creator as the first staff member with an 'Admin' role
        await restaurantRef.collection('staff').doc(user.uid).set({
          'role': 'Admin',
          'addedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          // Show success message and then pop
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Restaurant "$_restaurantName" created successfully!'),
              backgroundColor: Colors.green[700],
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating restaurant: ${e.toString()}')),
          );
        }
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
                    _buildForm(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent, // Makes AppBar transparent
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Icons.storefront_outlined,
          size: 50,
          color: theme.primaryColor,
        ),
        const SizedBox(height: 16),
        Text(
          'Set Up Your Restaurant',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Fill in the details below to get your new restaurant on DineFlow.',
          style: theme.textTheme.bodyLarge,
          textAlign: TextAlign.center,
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
          _buildTextField(
            label: 'Restaurant Name',
            icon: Icons.restaurant_menu_outlined,
            validator: (value) => value!.trim().isEmpty ? 'Please enter a name' : null,
            onSaved: (value) => _restaurantName = value!.trim(),
          ),
          const SizedBox(height: 20),
          _buildTextField(
            label: 'Address or Location',
            icon: Icons.location_on_outlined,
            validator: (value) => value!.trim().isEmpty ? 'Please enter an address' : null,
            onSaved: (value) => _address = value!.trim(),
          ),
          const SizedBox(height: 40),
          _buildSubmitButton(),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required FormFieldValidator<String> validator,
    required FormFieldSetter<String> onSaved,
  }) {
    return TextFormField(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 22),
      ),
      validator: validator,
      onSaved: onSaved,
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }

  Widget _buildSubmitButton() {
    return _isLoading
        ? Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
      ),
    )
        : ElevatedButton.icon(
      icon: const Icon(Icons.add_business_outlined),
      onPressed: _createRestaurant,
      label: const Text('Create Restaurant'),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 20),
      ),
    );
  }
}