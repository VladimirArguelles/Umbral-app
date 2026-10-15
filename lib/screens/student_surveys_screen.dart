import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_tools;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudentSurveysScreen extends StatefulWidget {
  const StudentSurveysScreen({super.key});

  @override
  State<StudentSurveysScreen> createState() => _StudentSurveysScreenState();
}

class _StudentSurveysScreenState extends State<StudentSurveysScreen> {
  final _imagePicker = ImagePicker();
  List<Map<String, dynamic>> _surveys = [];
  Map<String, Map<String, dynamic>> _answers = {};
  Map<String, Map<String, dynamic>> _payments = {};
  Map<String, String> _signedImageUrls = {};
  final Map<String, Uint8List> _selectedImages = {};
  bool _loading = true;
  String? _error;
  String? _savingSurveyId;

  @override
  void initState() {
    super.initState();
    _loadScreen();
  }

  Future<void> _loadScreen() async {
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
      final student = await client
          .from('alumnos')
          .select('curso_id')
          .eq('user_id', userId)
          .maybeSingle();
      final courseId = student?['curso_id']?.toString();
      final surveyRows = courseId == null
          ? <Map<String, dynamic>>[]
          : (await client
                    .from('encuestas_participacion')
                    .select(
                      'id,curso_id,clase_futura_fecha,costo_total_insumos,monto_aporte_individual,created_at',
                    )
                    .eq('curso_id', courseId)
                    .order('clase_futura_fecha'))
                .cast<Map<String, dynamic>>();
      final answerRows = await client
          .from('respuestas_encuesta')
          .select('id,encuesta_id,participara')
          .eq('user_id', userId);
      final paymentRows = await client
          .from('pagos')
          .select('id,encuesta_id,monto_aporte,imagen_url,estado,created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final payments = {
        for (final row in (paymentRows as List).cast<Map<String, dynamic>>())
          row['encuesta_id'].toString(): row,
      };
      final imageUrls = <String, String>{};
      for (final entry in payments.entries) {
        final path = entry.value['imagen_url']?.toString();
        if (path == null || path.isEmpty) continue;
        imageUrls[entry.key] = path.startsWith('http')
            ? path
            : await client.storage
                  .from('comprobantes-pago')
                  .createSignedUrl(path, 3600);
      }

      if (!mounted) return;
      setState(() {
        _surveys = surveyRows;
        _answers = {
          for (final row in (answerRows as List).cast<Map<String, dynamic>>())
            row['encuesta_id'].toString(): row,
        };
        _payments = payments;
        _signedImageUrls = imageUrls;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar encuestas y aportes: $error';
        _loading = false;
      });
    }
  }

  Future<void> _answerSurvey(
    Map<String, dynamic> survey,
    bool willParticipate,
  ) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    final surveyId = survey['id'].toString();
    final existing = _answers[surveyId];
    setState(() => _savingSurveyId = surveyId);
    try {
      if (existing == null) {
        await client.from('respuestas_encuesta').insert({
          'encuesta_id': surveyId,
          'user_id': userId,
          'participara': willParticipate,
        });
      } else {
        await client
            .from('respuestas_encuesta')
            .update({'participara': willParticipate})
            .eq('id', existing['id'])
            .eq('user_id', userId);
      }
      await _loadScreen();
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar tu respuesta: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingSurveyId = null);
    }
  }

  Future<void> _pickImage(String surveyId) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _selectedImages[surveyId] = bytes);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo seleccionar el comprobante: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitPayment(Map<String, dynamic> survey) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    final surveyId = survey['id'].toString();
    final selectedImage = _selectedImages[surveyId];
    final amount = (survey['monto_aporte_individual'] as num?)?.toDouble();
    if (userId == null ||
        selectedImage == null ||
        amount == null ||
        amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un comprobante de pago válido.'),
        ),
      );
      return;
    }

    setState(() => _savingSurveyId = surveyId);
    final filePath =
        '$userId/${surveyId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final decoded = image_tools.decodeImage(selectedImage);
      if (decoded == null) {
        throw const FormatException('El comprobante no es una imagen válida.');
      }
      await client.storage
          .from('comprobantes-pago')
          .uploadBinary(
            filePath,
            Uint8List.fromList(image_tools.encodeJpg(decoded)),
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      final existingPayment = _payments[surveyId];
      if (existingPayment == null) {
        await client.from('pagos').insert({
          'user_id': userId,
          'encuesta_id': surveyId,
          'monto_aporte': amount,
          'imagen_url': filePath,
          'estado': 'pendiente',
        });
      } else if (['pendiente', 'rechazado'].contains(
        existingPayment['estado'],
      )) {
        await client
            .from('pagos')
            .update({
              'imagen_url': filePath,
              'monto_aporte': amount,
              'estado': 'pendiente',
            })
            .eq('id', existingPayment['id'])
            .eq('user_id', userId);
        final oldPath = existingPayment['imagen_url']?.toString();
        if (oldPath != null && !oldPath.startsWith('http')) {
          await client.storage.from('comprobantes-pago').remove([oldPath]);
        }
      } else {
        throw StateError('Este aporte ya fue revisado y no puede modificarse.');
      }
      if (!mounted) return;
      setState(() => _selectedImages.remove(surveyId));
      await _loadScreen();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comprobante enviado para revisión.')),
      );
    } on Exception catch (error) {
      try {
        await client.storage.from('comprobantes-pago').remove([filePath]);
      } on Exception catch (cleanupError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo limpiar la carga: $cleanupError'),
            ),
          );
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar el aporte: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingSurveyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encuestas y aportes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _loadScreen,
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
              onRefresh: _loadScreen,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Encuestas de participación',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_surveys.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No hay encuestas para tu curso.'),
                      ),
                    ),
                  for (final survey in _surveys) _buildSurveyCard(survey),
                ],
              ),
            ),
    );
  }

  Widget _buildSurveyCard(Map<String, dynamic> survey) {
    final surveyId = survey['id'].toString();
    final answer = _answers[surveyId];
    final payment = _payments[surveyId];
    final imageBytes = _selectedImages[surveyId];
    final status = payment?['estado']?.toString();
    final canUpdatePayment = payment == null || status != 'verificado';

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Clase: ${_formatDate(survey['clase_futura_fecha'])}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('Costo de insumos: ${survey['costo_total_insumos'] ?? 0}'),
            Text(
              'Aporte individual: ${survey['monto_aporte_individual'] ?? 0}',
            ),
            const SizedBox(height: 10),
            Text(
              answer == null
                  ? '¿Participarás en esta clase?'
                  : answer['participara'] == true
                  ? 'Tu respuesta: Sí participaré'
                  : 'Tu respuesta: No participaré',
            ),
            if (answer == null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _savingSurveyId == surveyId
                        ? null
                        : () => _answerSurvey(survey, true),
                    child: const Text('Sí'),
                  ),
                  OutlinedButton(
                    onPressed: _savingSurveyId == surveyId
                        ? null
                        : () => _answerSurvey(survey, false),
                    child: const Text('No'),
                  ),
                ],
              ),
            const Divider(height: 24),
            Text(
              payment == null
                  ? 'Aporte pendiente de envío'
                  : 'Estado del aporte: $status',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_signedImageUrls[surveyId] case final imageUrl?)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Image.network(
                  imageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Text('No se pudo visualizar el comprobante.'),
                ),
              ),
            if (imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Image.memory(
                  imageBytes,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (canUpdatePayment)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _savingSurveyId == surveyId
                        ? null
                        : () => _pickImage(surveyId),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      imageBytes == null
                          ? 'Seleccionar comprobante'
                          : 'Cambiar comprobante',
                    ),
                  ),
                  if (imageBytes != null)
                    FilledButton(
                      onPressed: _savingSurveyId == surveyId
                          ? null
                          : () => _submitPayment(survey),
                      child: _savingSurveyId == surveyId
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Enviar aporte'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'fecha por confirmar';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
