import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({required this.access, super.key});

  final ModuleAccess access;

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _attendance = [];
  List<Map<String, dynamic>> _surveys = [];
  List<Map<String, dynamic>> _responses = [];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AuthService().runModuleAction(
        access: widget.access,
        action: 'dashboard',
      );
      if (!mounted) return;
      setState(() {
        _courses = _records(data['courses']);
        _students = _records(data['students']);
        _attendance = _records(data['attendance']);
        _surveys = _records(data['surveys']);
        _responses = _records(data['responses']);
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el panel docente: $error';
        _loading = false;
      });
    }
  }

  Future<void> _saveAttendance(
    Map<String, dynamic> course,
    Map<String, dynamic> student,
    bool present,
  ) async {
    final date = _todayKey();
    setState(() => _saving = true);
    try {
      await AuthService().runModuleAction(
        access: widget.access,
        action: 'save_attendance',
        payload: {
          'course_id': course['id'].toString(),
          'user_id': student['user_id'].toString(),
          'clase_fecha': date,
          'asistio': present,
        },
      );
      await _loadDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Asistencia guardada.')));
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la asistencia: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createSurvey(Map<String, dynamic> course) async {
    final formKey = GlobalKey<FormState>();
    final dateController = TextEditingController();
    final costController = TextEditingController();
    final contributionController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Crear evaluación de participación'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: dateController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Fecha de la clase (AAAA-MM-DD)',
                  filled: true,
                  fillColor: AppColors.panel,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.softAccent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.neonAccent,
                      width: 2,
                    ),
                  ),
                ),
                validator: (value) => DateTime.tryParse(value ?? '') == null
                    ? 'Fecha inválida'
                    : null,
              ),
              TextFormField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Costo total de insumos',
                  filled: true,
                  fillColor: AppColors.panel,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.softAccent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.neonAccent,
                      width: 2,
                    ),
                  ),
                ),
                validator: _validateAmount,
              ),
              TextFormField(
                controller: contributionController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Aporte individual',
                  filled: true,
                  fillColor: AppColors.panel,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.softAccent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: AppColors.neonAccent,
                      width: 2,
                    ),
                  ),
                ),
                validator: _validateAmount,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.softAccent),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(dialogContext, true);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.neonAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (accepted != true || !mounted) {
      dateController.dispose();
      costController.dispose();
      contributionController.dispose();
      return;
    }

    try {
      await AuthService().runModuleAction(
        access: widget.access,
        action: 'create_survey',
        payload: {
          'course_id': course['id'].toString(),
          'clase_futura_fecha': dateController.text,
          'costo_total_insumos': double.parse(costController.text),
          'monto_aporte_individual': double.parse(contributionController.text),
        },
      );
      await _loadDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Evaluación creada.')));
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo crear la evaluación: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      dateController.dispose();
      costController.dispose();
      contributionController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de profesor'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorMessage(message: _error!, onRetry: _loadDashboard)
          : _courses.isEmpty
          ? const Center(
              child: Text('No hay cursos asignados a este profesor.'),
            )
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Cursos, alumnos y asistencia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  for (final course in _courses) _buildCourseCard(course),
                ],
              ),
            ),
    );
  }

  Widget _buildCourseCard(Map<String, dynamic> course) {
    final courseId = course['id'].toString();
    final students = _students
        .where((student) => student['curso_id'].toString() == courseId)
        .toList();
    final surveys = _surveys
        .where((survey) => survey['curso_id'].toString() == courseId)
        .toList();
    final surveyIds = surveys.map((survey) => survey['id'].toString()).toSet();
    final responseCount = _responses
        .where(
          (response) => surveyIds.contains(response['encuesta_id'].toString()),
        )
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        title: Text(course['nombre_curso']?.toString() ?? 'Curso'),
        subtitle: Text(
          '${course['estado'] ?? 'Sin estado'} · ${students.length} alumnos · '
          '${surveys.length} evaluaciones · $responseCount respuestas',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving ? null : () => _createSurvey(course),
              icon: const Icon(Icons.assignment_add),
              label: const Text('Crear evaluación'),
            ),
          ),
          if (students.isEmpty)
            const ListTile(
              title: Text('Este curso no tiene alumnos inscritos.'),
            ),
          if (surveys.isNotEmpty) ...[
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Evaluaciones y participación',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final survey in surveys) _buildSurveySummary(survey),
          ],
          for (final student in students) _buildStudentRow(course, student),
        ],
      ),
    );
  }

  Widget _buildSurveySummary(Map<String, dynamic> survey) {
    final responses = _responses
        .where(
          (response) =>
              response['encuesta_id'].toString() == survey['id'].toString(),
        )
        .toList();
    final yesCount = responses
        .where((response) => response['participara'] == true)
        .length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('Clase futura: ${survey['clase_futura_fecha']}'),
      subtitle: Text(
        'Costo de insumos: ${survey['costo_total_insumos']} · '
        'Aporte individual: ${survey['monto_aporte_individual']}\n'
        '$yesCount participarán · ${responses.length - yesCount} no participarán',
      ),
    );
  }

  Widget _buildStudentRow(
    Map<String, dynamic> course,
    Map<String, dynamic> student,
  ) {
    final today = _todayKey();
    final attendanceRecord = _attendance.where(
      (row) =>
          row['user_id'].toString() == student['user_id'].toString() &&
          row['curso_id'].toString() == course['id'].toString() &&
          row['clase_fecha'].toString().startsWith(today),
    );
    final currentStatus = attendanceRecord.isEmpty
        ? null
        : attendanceRecord.first['asistio'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(student['nombre_completo']?.toString() ?? 'Alumno'),
      subtitle: Text(student['correo']?.toString() ?? ''),
      trailing: _saving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Marcar presente',
                  color: currentStatus == true ? Colors.green : null,
                  onPressed: () => _saveAttendance(course, student, true),
                  icon: const Icon(Icons.check_circle_outline),
                ),
                IconButton(
                  tooltip: 'Marcar ausente',
                  color: currentStatus == false ? Colors.red : null,
                  onPressed: () => _saveAttendance(course, student, false),
                  icon: const Icon(Icons.cancel_outlined),
                ),
              ],
            ),
    );
  }
}

List<Map<String, dynamic>> _records(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : [];

String _todayKey() {
  final today = DateTime.now();
  return '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
}

String? _validateAmount(String? value) {
  final amount = double.tryParse(value ?? '');
  if (amount == null || amount < 0) return 'Ingresa un monto válido';
  return null;
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
