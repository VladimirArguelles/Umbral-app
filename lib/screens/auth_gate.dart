import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'home_screen.dart';
import 'student_main_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _session;
  Future<String>? _roleFuture;

  @override
  void initState() {
    super.initState();
    _session = _auth.currentSession;
    _loadRole();
    _authSubscription = _auth.onAuthStateChange.listen((authState) {
      setState(() {
        _session = authState.session;
        _loadRole();
      });
    });
  }

  void _loadRole() {
    _roleFuture = _session == null ? null : AuthService().getUserRole();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) {
      return const HomeScreen();
    }

    return FutureBuilder<String>(
      future: _roleFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF22C55E)),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No se pudo determinar el acceso de esta cuenta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => setState(_loadRole),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        switch (snapshot.data ?? 'desconocido') {
          case 'alumno':
            final user = _session?.user;
            final metadata = user?.userMetadata;
            final displayName =
                metadata?['full_name']?.toString().trim().isNotEmpty == true
                ? metadata!['full_name'].toString().trim()
                : user?.email?.split('@').first ?? 'alumno';
            return StudentMainScreen(username: displayName);
          default:
            return const HomeScreen();
        }
      },
    );
  }
}
