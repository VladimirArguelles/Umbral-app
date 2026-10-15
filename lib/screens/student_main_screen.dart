import 'package:flutter/material.dart';

import 'student_attendance_screen.dart';
import 'student_courses_screen.dart';
import 'student_dashboard_screen.dart';
import 'student_surveys_screen.dart';

class StudentMainScreen extends StatefulWidget {
  final String username;

  const StudentMainScreen({super.key, required this.username});

  @override
  State<StudentMainScreen> createState() => _StudentMainScreenState();
}

class _StudentMainScreenState extends State<StudentMainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      StudentDashboardScreen(
        username: widget.username,
        onNavigate: (index) => setState(() => _currentIndex = index),
      ),
      const StudentCoursesScreen(),
      const StudentAttendanceScreen(),
      const StudentSurveysScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF0F172A),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF22C55E),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          elevation: 10,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Inicio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book),
              label: 'Mis Cursos',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.edit_calendar_outlined),
              activeIcon: Icon(Icons.edit_calendar_rounded),
              label: 'Asistencia',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rate_review_outlined),
              activeIcon: Icon(Icons.rate_review),
              label: 'Encuestas',
            ),
          ],
        ),
      ),
    );
  }
}
