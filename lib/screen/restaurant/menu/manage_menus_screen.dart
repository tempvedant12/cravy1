import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ManageMenusScreen extends StatefulWidget {
  final String restaurantId;

  const ManageMenusScreen({super.key, required this.restaurantId});

  @override
  _ManageMenusScreenState createState() => _ManageMenusScreenState();
}

class _ManageMenusScreenState extends State<ManageMenusScreen> {
  void _addOrEditMenu([DocumentSnapshot? menu]) {
    final controller = TextEditingController(text: menu != null ? menu['name'] : '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(menu == null ? 'Add Menu' : 'Edit Menu'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g., Lunch Menu'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                if (menu == null) {
                  FirebaseFirestore.instance
                      .collection('restaurants')
                      .doc(widget.restaurantId)
                      .collection('menus')
                      .add({'name': controller.text.trim()});
                } else {
                  menu.reference.update({'name': controller.text.trim()});
                }
              }
              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteMenu(DocumentSnapshot menu) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Menu?'),
        content: Text(
            'Are you sure you want to delete the "${menu['name']}" menu? This will also delete all items within this menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              menu.reference.delete();
              Navigator.of(context).pop();
            },
            child: Text('Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Menus'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('restaurants')
            .doc(widget.restaurantId)
            .collection('menus')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final menus = snapshot.data!.docs;
          return ListView.builder(
            itemCount: menus.length,
            itemBuilder: (context, index) {
              final menu = menus[index];
              return ListTile(
                title: Text(menu['name']),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _addOrEditMenu(menu),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteMenu(menu),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditMenu(),
        child: const Icon(Icons.add),
        tooltip: 'Add Menu',
      ),
    );
  }
}