import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentAttendanceScreen extends StatefulWidget {
  const StudentAttendanceScreen({super.key});

  @override
  State<StudentAttendanceScreen> createState() =>
      _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  Timer? _clock;
  Map<String, dynamic>? _course;
  Map<String, String> _attendanceByDate = {};
  int _absenceCount = 0;
  bool _loading = true;
  bool _marking = false;
  String? _error;
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _loadAttendance();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadAttendance() async {
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
          .select(
            'curso_id,cursos(id,nombre_curso,estado,horario_inicio,horario_fin,dias_clase)',
          )
          .eq('user_id', userId)
          .maybeSingle();
      final linkedCourse = alumno?['cursos'];
      final course = linkedCourse is Map<String, dynamic> ? linkedCourse : null;

      final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
      final lastDay = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
      final monthRows = await client
          .from('asistencia')
          .select('clase_fecha,asistio')
          .eq('user_id', userId)
          .gte('clase_fecha', _dateKey(firstDay))
          .lte('clase_fecha', _dateKey(lastDay));
      final absenceRows = await client
          .from('asistencia')
          .select('id')
          .eq('user_id', userId)
          .eq('asistio', false);

      if (!mounted) return;
      setState(() {
        _course = course;
        _attendanceByDate = {
          for (final row in (monthRows as List).cast<Map<String, dynamic>>())
            row['clase_fecha'].toString(): row['asistio'] == true
                ? 'presente'
                : 'ausente',
        };
        _absenceCount = (absenceRows as List).length;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la asistencia: $error';
        _loading = false;
      });
    }
  }

  bool get _canMark {
    final course = _course;
    if (course == null || course['estado'] != 'activo') return false;
    final today = DateTime.now();
    final dayNames = (course['dias_clase'] as List? ?? const [])
        .map((day) => day.toString().toLowerCase())
        .toSet();
    if (!dayNames.contains(_weekdayName(today.weekday))) return false;

    final todayKey = _dateKey(today);
    if (_attendanceByDate.containsKey(todayKey)) return false;

    final start = _parseTime(course['horario_inicio']);
    final end = _parseTime(course['horario_fin']);
    if (start == null || end == null) return false;
    final nowMinutes = today.hour * 60 + today.minute;
    return nowMinutes >= start && nowMinutes <= end;
  }

  Future<void> _markPresent() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final courseId = _course?['id']?.toString();
    if (userId == null || courseId == null || !_canMark) return;

    setState(() => _marking = true);
    try {
      await Supabase.instance.client.from('asistencia').insert({
        'user_id': userId,
        'curso_id': courseId,
        'clase_fecha': _dateKey(DateTime.now()),
        'asistio': true,
      });
      await _loadAttendance();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo registrar la asistencia: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistencia'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loadAttendance,
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
              onRefresh: _loadAttendance,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_absenceCount >= 2)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE2E2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Alerta: Posees 2 o más ausencias registradas. Por favor comunícate con tu instructora para evitar la suspensión.',
                        style: TextStyle(color: Color(0xFF991B1B)),
                      ),
                    ),
                  if (_absenceCount >= 2) const SizedBox(height: 14),
                  Text(
                    _course?['nombre_curso']?.toString() ?? 'Sin curso activo',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCalendar(),
                  const SizedBox(height: 16),
                  if (_course == null)
                    const Text('No tienes un curso activo asignado.')
                  else ...[
                    Text(
                      _canMark ? 'La franja de asistencia está abierta.' : 'La asistencia solo se puede marcar durante los días y el horario de tu curso.',
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _canMark && !_marking ? _markPresent : null,
                      icon: _marking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Marcar presente'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text('Ausencias registradas: $_absenceCount'),
                ],
              ),
            ),
    );
  }

  Widget _buildCalendar() {
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final leadingDays = firstDay.weekday - 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text(
                  '${_monthName(_visibleMonth.month)} ${_visibleMonth.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const Row(
              children: [
                Expanded(child: Center(child: Text('L'))),
                Expanded(child: Center(child: Text('M'))),
                Expanded(child: Center(child: Text('X'))),
                Expanded(child: Center(child: Text('J'))),
                Expanded(child: Center(child: Text('V'))),
                Expanded(child: Center(child: Text('S'))),
                Expanded(child: Center(child: Text('D'))),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: leadingDays + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, index) {
                if (index < leadingDays) return const SizedBox.shrink();
                final day = index - leadingDays + 1;
                final key = _dateKey(
                  DateTime(_visibleMonth.year, _visibleMonth.month, day),
                );
                final status = _attendanceByDate[key];
                final isToday = key == _dateKey(DateTime.now());
                return Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isToday
                        ? const Color(0xFFE8F5E9)
                        : Colors.transparent,
                    border: isToday
                        ? Border.all(color: const Color(0xFF22C55E))
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day'),
                      if (status != null)
                        Icon(
                          status == 'presente' ? Icons.check : Icons.close,
                          size: 14,
                          color: status == 'presente'
                              ? Colors.green
                              : Colors.red,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _changeMonth(int offset) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + offset,
      );
    });
    _loadAttendance();
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  int? _parseTime(Object? value) {
    final parts = value?.toString().split(':');
    if (parts == null || parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  String _weekdayName(int weekday) => const [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ][weekday - 1];

  String _monthName(int month) => const [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ][month - 1];
}
