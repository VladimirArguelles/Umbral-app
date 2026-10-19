import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({required this.access, super.key});

  final ModuleAccess access;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _payments = [];

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
        _payments = _records(data['payments']);
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el panel administrativo: $error';
        _loading = false;
      });
    }
  }

  Future<void> _updatePayment(
    Map<String, dynamic> payment,
    String status,
  ) async {
    try {
      await AuthService().runModuleAction(
        access: widget.access,
        action: 'update_payment',
        payload: {'payment_id': payment['id'].toString(), 'estado': status},
      );
      await _loadDashboard();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'verificado' ? 'Pago aprobado.' : 'Pago rechazado.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el pago: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateCourseStatus(
    Map<String, dynamic> course,
    String status,
  ) async {
    try {
      await AuthService().runModuleAction(
        access: widget.access,
        action: 'update_course_status',
        payload: {'course_id': course['id'].toString(), 'estado': status},
      );
      await _loadDashboard();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el curso: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _assignStudent(
    Map<String, dynamic> student,
    String courseId,
  ) async {
    try {
      await AuthService().runModuleAction(
        access: widget.access,
        action: 'assign_student_course',
        payload: {
          'user_id': student['user_id'].toString(),
          'course_id': courseId,
        },
      );
      await _loadDashboard();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo asignar el curso: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de administrador'),
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
          : RefreshIndicator(
              onRefresh: _loadDashboard,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummary(context),
                  const SizedBox(height: 20),
                  Text('Cursos', style: Theme.of(context).textTheme.titleLarge),
                  if (_courses.isEmpty)
                    const ListTile(title: Text('No hay cursos registrados.')),
                  for (final course in _courses)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(
                          course['nombre_curso']?.toString() ?? 'Curso',
                        ),
                        subtitle: DropdownButtonFormField<String>(
                          initialValue:
                              [
                                'activo',
                                'finalizado',
                              ].contains(course['estado'])
                              ? course['estado'].toString()
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Estado del curso',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'activo',
                              child: Text('Activo'),
                            ),
                            DropdownMenuItem(
                              value: 'finalizado',
                              child: Text('Finalizado'),
                            ),
                          ],
                          onChanged: _loading
                              ? null
                              : (value) {
                                  if (value != null &&
                                      value != course['estado']) {
                                    _updateCourseStatus(course, value);
                                  }
                                },
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Alumnos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_students.isEmpty)
                    const ListTile(title: Text('No hay alumnos registrados.')),
                  for (final student in _students)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                          student['nombre_completo']?.toString() ?? 'Alumno',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${student['correo'] ?? ''} · Cédula ${student['cedula'] ?? ''}',
                            ),
                            Text(
                              student['registrado_en_app'] == true
                                  ? 'Cuenta vinculada'
                                  : 'Preinscrito · Sin cuenta vinculada',
                            ),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _courses.any(
                                    (course) =>
                                        course['id'].toString() ==
                                        student['curso_id']?.toString(),
                                  )
                                  ? student['curso_id'].toString()
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Curso asignado',
                              ),
                              hint: const Text('Sin curso'),
                              items: [
                                for (final course in _courses)
                                  DropdownMenuItem(
                                    value: course['id'].toString(),
                                    child: Text(
                                      course['nombre_curso']?.toString() ??
                                          'Curso',
                                    ),
                                  ),
                              ],
                              onChanged: _loading
                                  ? null
                                  : (value) {
                                      if (value != null &&
                                          value !=
                                              student['curso_id']?.toString()) {
                                        _assignStudent(student, value);
                                      }
                                    },
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Auditoría de pagos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_payments.isEmpty)
                    const ListTile(title: Text('No hay pagos registrados.')),
                  for (final payment in _payments) _buildPaymentCard(payment),
                ],
              ),
            ),
    );
  }

  Widget _buildSummary(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _SummaryValue(label: 'Cursos', value: _courses.length),
          _SummaryValue(label: 'Alumnos', value: _students.length),
          _SummaryValue(
            label: 'Pendientes',
            value: _payments
                .where((payment) => payment['estado'] == 'pendiente')
                .length,
          ),
        ],
      ),
    ),
  );

  Widget _buildPaymentCard(Map<String, dynamic> payment) {
    final student = _asRecord(payment['alumnos']);
    final participationSurvey = _asRecord(payment['encuestas_participacion']);
    final course = _asRecord(participationSurvey?['cursos']);
    final status = payment['estado']?.toString() ?? 'pendiente';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(student?['nombre_completo']?.toString() ?? 'Alumno'),
            Text(
              '${course?['nombre_curso'] ?? 'Curso'} · '
              'Fecha ${participationSurvey?['clase_futura_fecha'] ?? 'sin fecha'}',
            ),
            Text('Aporte: ${payment['monto_aporte'] ?? '—'} · Estado: $status'),
            if (payment['signed_image_url'] is String)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Image.network(
                  payment['signed_image_url'] as String,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Text('No se pudo visualizar el comprobante.'),
                ),
              ),
            if (status == 'pendiente')
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _updatePayment(payment, 'verificado'),
                    icon: const Icon(Icons.check),
                    label: const Text('Aprobar'),
                  ),
                  TextButton.icon(
                    onPressed: () => _updatePayment(payment, 'rechazado'),
                    icon: const Icon(Icons.close),
                    label: const Text('Rechazar'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _records(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : [];

Map<String, dynamic>? _asRecord(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$value', style: Theme.of(context).textTheme.headlineSmall),
      Text(label),
    ],
  );
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
