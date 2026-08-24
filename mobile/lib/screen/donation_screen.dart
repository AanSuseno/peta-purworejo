import 'package:flutter/material.dart';

class DonationScreen extends StatelessWidget {
  const DonationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Donasi'),
      //   backgroundColor: Colors.blue.shade700,
      //   foregroundColor: Colors.white,
      // ),
      body: const Center(
        child: Text(
          'Ini halaman Donasi',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
