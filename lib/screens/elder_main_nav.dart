import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'elder_home_screen.dart';
import 'session_history_screen.dart';
import 'settings_screen.dart';

class ElderMainNav extends StatefulWidget {
  const ElderMainNav({super.key});

  @override
  State<ElderMainNav> createState() => _ElderMainNavState();
}

class _ElderMainNavState extends State<ElderMainNav> {
  int _currentIndex = 0;
  
  final List<Widget> _pages = [
    const ElderHomeScreen(),
    const SessionHistoryScreen(), // Will crash if not implemented, I'll mock it soon
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
              icon: Icon(Icons.history_outlined),
              activeIcon: Icon(Icons.history),
              label: "History",
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
