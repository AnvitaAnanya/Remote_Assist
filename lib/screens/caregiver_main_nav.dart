import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'caregiver_screen.dart';
import 'session_history_screen.dart';
import 'settings_screen.dart';

class CaregiverMainNav extends StatefulWidget {
  const CaregiverMainNav({super.key});

  @override
  State<CaregiverMainNav> createState() => _CaregiverMainNavState();
}

class _CaregiverMainNavState extends State<CaregiverMainNav> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const CaregiverHomeScreen(),
    // SessionHistoryScreen hidden for now — functionality kept in code
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            )
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          backgroundColor: Colors.white,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: "Home",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: "Settings",
            ),
          ],
        ),
      ),
    );
  }
}
