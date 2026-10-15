import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de alumno'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => Supabase.instance.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAbsences,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¡Hola ${widget.username}!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Continúa tu aprendizaje y revisa tus actividades.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_loadError case final error?)
              _MessageCard(message: error, color: Colors.red.shade100)
            else if (_absenceCount == null)
              const Center(child: CircularProgressIndicator())
            else if (_absenceCount! >= 2)
              const _MessageCard(
                message:
                    'Alerta: Posees 2 o más ausencias registradas. Por favor comunícate con tu instructora para evitar la suspensión.',
                color: Color(0xFFFFE2E2),
              )
            else
              _MessageCard(
                message: 'Ausencias registradas: $_absenceCount',
                color: const Color(0xFFE8F5E9),
              ),
            const SizedBox(height: 22),
            const Text(
              'Accesos rápidos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _ShortcutTile(
              icon: Icons.menu_book_outlined,
              title: 'Mis Cursos',
              onTap: () => widget.onNavigate?.call(1),
            ),
            _ShortcutTile(
              icon: Icons.edit_calendar_outlined,
              title: 'Marcar asistencia',
              onTap: () => widget.onNavigate?.call(2),
            ),
            _ShortcutTile(
              icon: Icons.rate_review_outlined,
              title: 'Encuestas y aportes',
              onTap: () => widget.onNavigate?.call(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;
  final Color color;

  const _MessageCard({required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF7F1D1D))),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F172A)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
