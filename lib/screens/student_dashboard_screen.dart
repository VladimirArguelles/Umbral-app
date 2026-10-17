import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

class StudentDashboardScreen extends StatefulWidget {
  final String username;
  final ValueChanged<int>? onNavigate;

  const StudentDashboardScreen({
    super.key,
    required this.username,
    this.onNavigate,
  });

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  int? _absenceCount;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAbsences();
  }

  Future<void> _loadAbsences() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('asistencia')
          .select('clase_fecha')
          .eq('user_id', userId)
          .eq('asistio', false);
      if (!mounted) return;
      setState(() {
        _absenceCount = (rows as List).length;
        _loadError = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _loadError = 'No se pudo consultar tu asistencia: $error');
    }
  }

  void _openSearch() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF24152F),
        title: const Text(
          '¿Qué deseas consultar?',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SearchOption(
              icon: Icons.menu_book_rounded,
              label: 'Mis cursos',
              onTap: () => _navigateFromDialog(dialogContext, 1),
            ),
            _SearchOption(
              icon: Icons.event_available_rounded,
              label: 'Mi asistencia',
              onTap: () => _navigateFromDialog(dialogContext, 2),
            ),
            _SearchOption(
              icon: Icons.thumb_up_rounded,
              label: 'Encuestas',
              onTap: () => _navigateFromDialog(dialogContext, 3),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateFromDialog(BuildContext dialogContext, int index) {
    Navigator.of(dialogContext).pop();
    widget.onNavigate?.call(index);
  }

  void _openDrawerPage(BuildContext drawerContext, int index) {
    Navigator.of(drawerContext).pop();
    widget.onNavigate?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF170D25),
      drawer: _buildDrawer(),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.softAccent,
          backgroundColor: const Color(0xFF24152F),
          onRefresh: _loadAbsences,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _buildHeader(),
                const SizedBox(height: 18),
                _buildHero(constraints.maxWidth),
                if (_loadError != null) ...[
                  const SizedBox(height: 14),
                  _buildAttendanceError(),
                ],
                const SizedBox(height: 22),
                _DashboardModuleCard(
                  icon: Icons.menu_book_rounded,
                  title: 'MIS CURSOS',
                  description: 'Visualiza tus cursos',
                  buttonLabel: 'IR A MIS CURSOS',
                  accent: const Color(0xFFFF84C9),
                  onTap: () => widget.onNavigate?.call(1),
                ),
                const SizedBox(height: 18),
                _DashboardModuleCard(
                  icon: Icons.event_available_rounded,
                  title: 'MI ASISTENCIA',
                  description: _absenceCount == null
                      ? 'Consulta tu historial de participación'
                      : '$_absenceCount ${_absenceCount == 1 ? 'ausencia registrada' : 'ausencias registradas'}',
                  buttonLabel: 'IR A MI ASISTENCIA',
                  accent: const Color(0xFF9CDDAF),
                  onTap: () => widget.onNavigate?.call(2),
                ),
                const SizedBox(height: 18),
                _DashboardModuleCard(
                  icon: Icons.thumb_up_rounded,
                  title: 'ENCUESTAS',
                  description: 'Participa en las encuestas',
                  buttonLabel: 'IR A ENCUESTAS',
                  accent: const Color(0xFFFFCC8A),
                  onTap: () => widget.onNavigate?.call(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final logoWidth = MediaQuery.sizeOf(context).width < 420 ? 116.0 : 160.0;

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'UMBRAL',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Abrir menú',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Buscar secciones',
                      onPressed: _openSearch,
                      icon: const Icon(Icons.search_rounded),
                    ),
                  ],
                ),
              ),
              IgnorePointer(
                child: Image.asset(
                  'assets/logo_umbral.png',
                  width: logoWidth,
                  height: 52,
                  fit: BoxFit.contain,
                  semanticLabel: 'UMBRAL',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Supabase.instance.client.auth.signOut(),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFE681B5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 9,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Salir',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
      ],
    );
  }

  Widget _buildHero(double availableWidth) {
    final compact = availableWidth < 480;
    final titleSize = compact ? 32.0 : 43.0;
    final illustrationWidth = compact ? 138.0 : 230.0;
    final name = widget.username.trim();

    return Container(
      height: compact ? 258 : 294,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF27112F), Color(0xFF1D102B), Color(0xFF19152D)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(right: -35, bottom: -85, child: _HeroGlow()),
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 20, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (name.isNotEmpty) ...[
                        Text(
                          'BIENVENIDA, ${name.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFFFA2D5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'FORMACIONES\nINMUJER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            height: 1.06,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.9,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Empoderando mujeres a través de la educación y la formación profesional.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: compact ? 13 : 16,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: illustrationWidth,
                  child: Image.asset(
                    'assets/images/formaciones_inmujer.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    semanticLabel: 'Mujeres formándose en educación, cocina y formación profesional',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceError() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF421B35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.softAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.softAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadError!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Reintentar',
            onPressed: _loadAbsences,
            icon: const Icon(Icons.refresh, color: AppColors.softAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF20122E),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Image.asset(
                'assets/logo_umbral.png',
                height: 54,
                fit: BoxFit.contain,
              ),
            ),
            const Divider(color: Colors.white12),
            _DrawerLink(
              icon: Icons.home_outlined,
              label: 'Inicio',
              onTap: () => _openDrawerPage(context, 0),
            ),
            _DrawerLink(
              icon: Icons.menu_book_outlined,
              label: 'Mis cursos',
              onTap: () => _openDrawerPage(context, 1),
            ),
            _DrawerLink(
              icon: Icons.event_available_outlined,
              label: 'Mi asistencia',
              onTap: () => _openDrawerPage(context, 2),
            ),
            _DrawerLink(
              icon: Icons.thumb_up_alt_outlined,
              label: 'Encuestas',
              onTap: () => _openDrawerPage(context, 3),
            ),
            const Spacer(),
            _DrawerLink(
              icon: Icons.logout,
              label: 'Cerrar sesión',
              onTap: () => Supabase.instance.client.auth.signOut(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardModuleCard extends StatelessWidget {
  const _DashboardModuleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 156),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF351438), Color(0xFF2C1231)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.045)),
          ),
          child: Row(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFF180F24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 52, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 29,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1026),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            buttonLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
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

class _HeroGlow extends StatelessWidget {
  const _HeroGlow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      height: 240,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [Color(0x668F347A), Color(0x008F347A)],
        ),
      ),
    );
  }
}

class _SearchOption extends StatelessWidget {
  const _SearchOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.softAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.softAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}
