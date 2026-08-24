import 'package:flutter/material.dart';
import 'package:mobile/constants/colors.dart';
import 'package:provider/provider.dart';
import 'package:rolling_bottom_bar/rolling_bottom_bar.dart';
import 'package:rolling_bottom_bar/rolling_bottom_bar_item.dart';

import '../provider/auth_provider.dart';
import 'home_screen.dart';
import 'community_screen.dart';
import 'event_screen.dart';
import 'donation_screen.dart';
import 'profile_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final PageController _controller = PageController();

  static const List<Widget> _screens = [
    HomeScreen(),
    CommunityScreen(),
    EventScreen(),
    DonationScreen(),
    ProfileScreen(),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap(int index) {
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Diambil untuk menampilkan foto profil di icon paling kanan.
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _controller,
        // Ganti tab cuma lewat navbar, bukan swipe, biar animasi "rolling"-nya konsisten.
        physics: const NeverScrollableScrollPhysics(),
        children: _screens,
      ),
      bottomNavigationBar: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          RollingBottomBar(
            controller: _controller,
            items: const [
              RollingBottomBarItem(Icons.home_rounded, label: 'Beranda'),
              RollingBottomBarItem(Icons.groups_rounded, label: 'Komunitas'),
              RollingBottomBarItem(Icons.event_rounded, label: 'Event'),
              RollingBottomBarItem(
                Icons.volunteer_activism_rounded,
                label: 'Donasi',
              ),
              RollingBottomBarItem(Icons.person_rounded, label: 'Profil'),
            ],
            activeItemColor: AppColors.primary,
            enableIconRotation: true,
            onTap: _onTap,
          ),
        ],
      ),
    );
  }
}
