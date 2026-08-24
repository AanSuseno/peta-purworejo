import 'package:flutter/material.dart';

class EventScreen extends StatelessWidget {
  const EventScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Event'),
      //   backgroundColor: Colors.blue.shade700,
      //   foregroundColor: Colors.white,
      // ),
      body: const Center(
        child: Text(
          'Ini halaman Event',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
