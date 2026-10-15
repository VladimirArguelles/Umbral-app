import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_dashboard_screen.dart';
import 'login_modal.dart';
import 'module_pin_modal.dart';
import 'module_pin_setup_modal.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'teacher_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final StreamSubscription<AuthState> _authSubscription;
  String _welcomeName = 'alumna';

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _updateWelcomeName(auth.currentUser?.userMetadata, auth.currentUser?.email);
    _authSubscription = auth.onAuthStateChange.listen((state) {
      final user = state.session?.user;
      _updateWelcomeName(user?.userMetadata, user?.email);
    });
  }

  void _updateWelcomeName(Map<String, dynamic>? metadata, String? email) {
    final candidates = [
      metadata?['full_name']?.toString().trim(),
      email?.split('@').first.trim(),
    ];
    final name = candidates.firstWhere(
      (candidate) => candidate != null && candidate.isNotEmpty,
      orElse: () => 'alumna',
    );

    if (mounted && _welcomeName != name) {
      setState(() => _welcomeName = name!);
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _showLoginRegister() {
    showDialog<void>(
      context: context,
      builder: (context) => const LoginModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/logo_umbral.png',
              height: 40,
              fit: BoxFit.contain,
              semanticLabel: 'UMBRAL',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _showLoginRegister,
            child: const Text(
              'Entrar',
              style: TextStyle(
                color: AppColors.neonAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.neonAccent.withValues(alpha: 0.65),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Hola $_welcomeName!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bienvenida a UMBRAL. Selecciona un módulo para comenzar:',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildModuleCard(
              title: 'Módulo Alumnos',
              description: 'Cursos, asistencia, encuestas y pagos.',
              icon: Icons.person_outline,
              onTap: _showLoginRegister,
            ),
            const SizedBox(height: 15),
            _buildModuleCard(
              title: 'Módulo Profesores',
              description: 'Listado de alumnos, asistencia y evaluaciones.',
              icon: Icons.menu_book_outlined,
              onTap: () => _openProtectedModule(
                module: 'profesor',
                title: 'Acceso de profesor',
              ),
            ),
            const SizedBox(height: 15),
            _buildModuleCard(
              title: 'Módulo Administrador',
              description: 'Cursos, alumnos, pagos y auditoría.',
              icon: Icons.admin_panel_settings_outlined,
              onTap: () => _openProtectedModule(
                module: 'administrador',
                title: 'Acceso de administrador',
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: _showLoginRegister,
                child: const Text(
                  '¿Aún no tienes una cuenta? Regístrate o inicia sesión',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.softAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProtectedModule({
    required String module,
    required String title,
  }) async {
    final setupComplete = await showDialog<bool>(
      context: context,
      builder: (_) => ModulePinSetupModal(module: module),
    );

    if (!mounted || setupComplete != true) return;

    final access = await showDialog<ModuleAccess>(
      context: context,
      builder: (_) => ModulePinModal(module: module, title: title),
    );

    if (!mounted || access == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => module == 'profesor'
            ? TeacherDashboardScreen(access: access)
            : AdminDashboardScreen(access: access),
      ),
    );
  }

  Widget _buildModuleCard({
    required String title,
    required String description,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.softAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.softAccent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white38,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
