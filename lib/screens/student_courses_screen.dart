import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentCoursesScreen extends StatefulWidget {
  const StudentCoursesScreen({super.key});

  @override
  State<StudentCoursesScreen> createState() => _StudentCoursesScreenState();
}

class _StudentCoursesScreenState extends State<StudentCoursesScreen> {
  Map<String, dynamic>? _activeCourse;
  List<Map<String, dynamic>> _history = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'No hay una sesión activa.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final alumno = await client
          .from('alumnos')
          .select('curso_id, cursos(id,nombre_curso,descripcion,estado)')
          .eq('user_id', userId)
          .maybeSingle();

      final courseValue = alumno?['cursos'];
      final activeCourse = courseValue is Map<String, dynamic>
          ? courseValue
          : null;
      final historyRows = await client
          .from('historial_cursos')
          .select('curso_id,fecha_inscripcion,fecha_finalizacion,cursos(nombre_curso,descripcion)')
          .eq('user_id', userId)
          .order('fecha_finalizacion', ascending: false);

      if (!mounted) return;
      setState(() {
        _activeCourse = activeCourse?['estado'] == 'activo'
            ? activeCourse
            : null;
        _history = (historyRows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus cursos: $error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Cursos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadCourses,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadCourses,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Curso activo',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  if (_activeCourse == null)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('No tienes un curso activo asignado.'),
                      ),
                    )
                  else
                    _CourseCard(course: _activeCourse!),
                  const SizedBox(height: 18),
                  ExpansionTile(
                    initiallyExpanded: true,
                    title: Text('Cursos finalizados (${_history.length})'),
                    children: _history.isEmpty
                        ? const [
                            ListTile(
                              title: Text(
                                'Aún no tienes cursos finalizados en tu historial.',
                              ),
                            ),
                          ]
                        : _history
                              .map(
                                (item) => _CourseCard(
                                  course:
                                      item['cursos'] as Map<String, dynamic>? ??
                                      const {},
                                  subtitle:
                                      'Finalizado: ${_formatDate(item['fecha_finalizacion'])}',
                                ),
                              )
                              .toList(),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatDate(Object? value) {
    if (value == null) return 'fecha no disponible';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return 'fecha no disponible';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _CourseCard extends StatelessWidget {
  final Map<String, dynamic> course;
  final String? subtitle;

  const _CourseCard({required this.course, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.menu_book, color: Color(0xFF22C55E)),
        title: Text(course['nombre_curso']?.toString() ?? 'Curso'),
        subtitle: Text(
          subtitle ??
              course['descripcion']?.toString() ??
              'Sin descripción disponible.',
        ),
      ),
    );
  }
}
