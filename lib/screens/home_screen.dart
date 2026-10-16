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

const _landingBackground = Color(0xFF110B20);
const _landingPink = Color(0xFFFF79C8);
const _landingBlue = Color(0xFF213D68);

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
      backgroundColor: _landingBackground,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _landingBackground,
                    Color(0xFF171027),
                    _landingBackground,
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: 300,
            right: -150,
            child: _BackgroundGlow(size: 360, color: Color(0xFF354DD1)),
          ),
          const Positioned(
            bottom: -110,
            left: -95,
            child: _BackgroundGlow(size: 320, color: Color(0xFFB02A8E)),
          ),
          const Positioned(
            bottom: -100,
            right: -90,
            child: _BackgroundGlow(size: 320, color: Color(0xFF7139D2)),
          ),
          const Positioned(
            top: 370,
            right: 18,
            child: _Sparkle(
              icon: Icons.auto_awesome,
              color: Color(0xFFA854D2),
              size: 18,
              rotation: -0.35,
            ),
          ),
          const Positioned(
            top: 610,
            left: 24,
            child: _Sparkle(
              icon: Icons.circle,
              color: Color(0xFF9851C4),
              size: 9,
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  _buildWelcomePanel(),
                  const SizedBox(height: 20),
                  _buildModuleCard(
                    title: 'Alumnos',
                    description: 'Cursos, asistencia, encuestas y pagos.',
                    icon: Icons.face_3_rounded,
                    onTap: _showLoginRegister,
                  ),
                  const SizedBox(height: 15),
                  _buildModuleCard(
                    title: 'Profesores',
                    description:
                        'Listado de alumnos, asistencia y evaluaciones.',
                    icon: Icons.auto_stories_rounded,
                    onTap: () => _openProtectedModule(
                      module: 'profesor',
                      title: 'Acceso de profesor',
                    ),
                  ),
                  const SizedBox(height: 15),
                  _buildModuleCard(
                    title: 'Administrador',
                    description: 'Cursos, alumnos, pagos y auditoría.',
                    icon: Icons.admin_panel_settings_rounded,
                    onTap: () => _openProtectedModule(
                      module: 'administrador',
                      title: 'Acceso de administrador',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: TextButton(
                      onPressed: _showLoginRegister,
                      style: TextButton.styleFrom(
                        foregroundColor: _landingPink,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                      ),
                      child: const Text(
                        '¿Aún no tienes una cuenta? Regístrate o inicia sesión',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF281D38), Color(0xFF1D172B)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _landingPink.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(color: _landingPink.withValues(alpha: 0.2), blurRadius: 14),
        ],
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo_umbral.png',
            width: 116,
            height: 42,
            fit: BoxFit.contain,
            semanticLabel: 'UMBRAL',
          ),
          const Spacer(),
          TextButton(
            onPressed: _showLoginRegister,
            style: TextButton.styleFrom(foregroundColor: _landingPink),
            child: const Text(
              'Entrar',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF34102F), Color(0xFF202342), _landingBlue],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _landingPink.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: _landingPink.withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              children: [
                const TextSpan(
                  text: '¡Hola ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: '$_welcomeName!',
                  style: const TextStyle(color: _landingPink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Bienvenida a UMBRAL. Selecciona un módulo para comenzar:',
            style: TextStyle(
              color: Color(0xFFE2D9EA),
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ],
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A2038), Color(0xFF211B30)],
            ),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A0710).withValues(alpha: 0.42),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: _landingPink.withValues(alpha: 0.07),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 62,
                child: Center(
                  child: Icon(
                    icon,
                    color: _landingPink,
                    size: 48,
                    shadows: [
                      Shadow(
                        color: AppColors.neonAccent.withValues(alpha: 0.8),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFFC8BCD4),
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white,
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({
    required this.icon,
    required this.color,
    required this.size,
    this.rotation = 0,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.rotate(
        angle: rotation,
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}
