import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cravy/screen/restaurant/restaurant_screen.dart';

class EditRestaurantScreen extends StatefulWidget {
  final Restaurant restaurant;

  const EditRestaurantScreen({super.key, required this.restaurant});

  @override
  _EditRestaurantScreenState createState() => _EditRestaurantScreenState();
}

class _EditRestaurantScreenState extends State<EditRestaurantScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.restaurant.name);
    _addressController = TextEditingController(text: widget.restaurant.address);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        await FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurant.id)
            .update({
          'name': _nameController.text.trim(),
          'address': _addressController.text.trim(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Restaurant details updated!')),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating details: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteRestaurant() async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Restaurant?'),
        content: Text(
            'Are you sure you want to delete "${widget.restaurant.name}"? This will delete all associated data including menus, orders, and settings. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        // You should ideally use a Cloud Function to delete all subcollections recursively.
        // The following is a client-side approximation and might not be complete.
        final restaurantRef = FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurant.id);

        // Delete some known subcollections (add others as needed)
        await _deleteSubcollection(restaurantRef.collection('orders'));
        await _deleteSubcollection(restaurantRef.collection('menus'));
        await _deleteSubcollection(restaurantRef.collection('inventory'));
        await _deleteSubcollection(restaurantRef.collection('tables'));
        await _deleteSubcollection(restaurantRef.collection('floors'));
        await _deleteSubcollection(restaurantRef.collection('staff'));
        await _deleteSubcollection(restaurantRef.collection('reservations'));
        await _deleteSubcollection(restaurantRef.collection('billConfigurations'));
        await _deleteSubcollection(restaurantRef.collection('coupons'));
        await _deleteSubcollection(restaurantRef.collection('purchaseOrders'));
        await _deleteSubcollection(restaurantRef.collection('suppliers'));


        // Finally, delete the restaurant document itself
        await restaurantRef.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('"${widget.restaurant.name}" has been deleted.')),
          );
          // Pop until back to the home screen
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting restaurant: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _deleteSubcollection(CollectionReference subcollection) async {
    final snapshot = await subcollection.limit(500).get();
    if (snapshot.docs.isEmpty) {
      return;
    }
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    // Recurse to delete remaining documents
    await _deleteSubcollection(subcollection);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurant Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Restaurant Name'),
                validator: (value) =>
                value!.trim().isEmpty ? 'Please enter a name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: (value) =>
                value!.trim().isEmpty ? 'Please enter an address' : null,
              ),
              const Spacer(),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _saveChanges,
                  child: const Text('Save Changes'),
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _deleteRestaurant,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
                child: const Text('Delete Restaurant'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}