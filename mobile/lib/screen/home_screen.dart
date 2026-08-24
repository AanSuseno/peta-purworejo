import 'package:flutter/material.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';

import '../provider/auth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('Home'),
      //   backgroundColor: AppColors.primary,
      //   foregroundColor: Colors.white,
      //   actions: [
      //     IconButton(
      //       icon: const Icon(Icons.logout),
      //       onPressed: () async {
      //         await auth.logout();
      //       },
      //     ),
      //   ],
      // ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Foto Profile
              CircleAvatar(
                radius: 70,
                backgroundImage: auth.photoUrl != null
                    ? NetworkImage(auth.photoUrl!)
                    : null,
                backgroundColor: AppColors.primary.withOpacity(0.2),
                child: auth.photoUrl == null
                    ? Icon(Icons.person, size: 70, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(height: 30),

              // Nama
              Text(
                auth.displayName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              // Email
              Text(
                auth.email,
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),

              const SizedBox(height: 30),

              // Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.secondary),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: AppColors.secondary),
                    const SizedBox(width: 10),
                    Text(
                      'Signed in with Google',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
