import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_conversacion.dart';
import '../models/chat_mensaje.dart';
import '../services/auth_service.dart';
import '../services/comunicaciones_service.dart';
import '../theme/module_app_bar.dart';

class ChatPage extends StatefulWidget {
  final ChatConversacion conversacion;

  const ChatPage({super.key, required this.conversacion});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _svc = ComunicacionesService.instance;
  final _textoCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription? _sub;
  List<ChatMensaje> _mensajes = [];
  bool _enviando = false;
  String? _estadoEnvio;

  String get _yo => AuthService.instance.currentUser?.usuario ?? '';

  @override
  void initState() {
    super.initState();
    _svc.marcarLeidos(widget.conversacion.id);
    _sub = _svc.watchMensajes(widget.conversacion.id).listen((msgs) {
      if (!mounted) return;
      setState(() => _mensajes = msgs);
      _svc.marcarLeidos(widget.conversacion.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _textoCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _enviarTexto() async {
    final texto = _textoCtrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    _textoCtrl.clear();
    try {
      await _svc.enviarTexto(widget.conversacion.id, texto);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _adjuntar({required bool camara}) async {
    setState(() {
      _enviando = true;
      _estadoEnvio = camara ? 'Enviando imagen...' : 'Subiendo archivo...';
    });
    try {
      if (camara) {
        final picker = ImagePicker();
        final img = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 75,
        );
        if (img == null) return;
        await _svc.enviarArchivo(
          conversacionId: widget.conversacion.id,
          archivo: File(img.path),
          mime: 'image/jpeg',
        );
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'jpg',
            'jpeg',
            'png',
            'pdf',
            'xlsx',
            'csv',
            'docx',
          ],
        );
        if (result == null || result.files.isEmpty) return;
        final f = result.files.first;
        if (f.path == null) return;
        final ext = (f.extension ?? '').toLowerCase();
        final mime = switch (ext) {
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          'pdf' => 'application/pdf',
          'xlsx' =>
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          'csv' => 'text/csv',
          'docx' =>
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          _ => 'application/octet-stream',
        };
        await _svc.enviarArchivo(
          conversacionId: widget.conversacion.id,
          archivo: File(f.path!),
          mime: mime,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo adjuntar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _enviando = false;
          _estadoEnvio = null;
        });
      }
    }
  }

  String _fmtHora(DateTime f) =>
      '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

  String _fmtFecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final titulo = widget.conversacion.tituloPara(_yo);

    return Scaffold(
      appBar: buildModuleAppBar(context, title: titulo),
      body: Column(
        children: [
          if (_estadoEnvio != null)
            MaterialBanner(
              content: Text(_estadoEnvio!),
              actions: const [SizedBox.shrink()],
            ),
          Expanded(
            child: _mensajes.isEmpty
                ? Center(
                    child: Text(
                      'Sin mensajes aún.\nEscribí el primero.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _mensajes.length,
                    itemBuilder: (context, i) {
                      final m = _mensajes[i];
                      final mio = m.autorUsuario == _yo;
                      final showDate = i == 0 ||
                          _fmtFecha(_mensajes[i - 1].fecha) !=
                              _fmtFecha(m.fecha);
                      return Column(
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                _fmtFecha(m.fecha),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          _Burbuja(
                            mensaje: m,
                            mio: mio,
                            hora: _fmtHora(m.fecha),
                            primary: cs.primary,
                            onPrimary: cs.onPrimary,
                            surface: cs.surfaceContainerHighest,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Adjuntar archivo',
                    onPressed: _enviando ? null : () => _adjuntar(camara: false),
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  IconButton(
                    tooltip: 'Cámara',
                    onPressed: _enviando ? null : () => _adjuntar(camara: true),
                    icon: const Icon(Icons.photo_camera_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textoCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _enviarTexto(),
                      decoration: const InputDecoration(
                        hintText: 'Escribí un mensaje...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _enviando ? null : _enviarTexto,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Burbuja extends StatelessWidget {
  final ChatMensaje mensaje;
  final bool mio;
  final String hora;
  final Color primary;
  final Color onPrimary;
  final Color surface;

  const _Burbuja({
    required this.mensaje,
    required this.mio,
    required this.hora,
    required this.primary,
    required this.onPrimary,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    final bg = mio ? primary : surface;
    final fg = mio ? onPrimary : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mio ? 16 : 4),
              bottomRight: Radius.circular(mio ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mio)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    mensaje.autorNombre,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              if (mensaje.tipo == ChatMensajeTipo.imagen &&
                  mensaje.archivoPath != null)
                _ImagenAdjunto(path: mensaje.archivoPath!),
              if (mensaje.tipo == ChatMensajeTipo.archivo)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.insert_drive_file_rounded, color: fg, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        mensaje.archivoNombre ?? 'Archivo',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              if (mensaje.tipo == ChatMensajeTipo.compartido &&
                  mensaje.compartido != null)
                _TarjetaCompartida(item: mensaje.compartido!, fg: fg),
              if (mensaje.texto.isNotEmpty)
                Text(mensaje.texto, style: TextStyle(color: fg)),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  hora,
                  style: TextStyle(
                    fontSize: 10,
                    color: fg.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImagenAdjunto extends StatelessWidget {
  final String path;
  const _ImagenAdjunto({required this.path});

  @override
  Widget build(BuildContext context) {
    final isUrl = path.startsWith('http');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: isUrl
            ? Image.network(path, height: 160, fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => const Icon(Icons.broken_image))
            : Image.file(File(path), height: 160, fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => const Icon(Icons.broken_image)),
      ),
    );
  }
}

class _TarjetaCompartida extends StatelessWidget {
  final ChatCompartido item;
  final Color fg;

  const _TarjetaCompartida({required this.item, required this.fg});

  IconData get _icon => switch (item.tipo) {
        'producto' => Icons.inventory_2_rounded,
        'venta' || 'presupuesto' => Icons.receipt_long_rounded,
        'remito' => Icons.local_shipping_rounded,
        'compra' => Icons.shopping_cart_rounded,
        'cliente' => Icons.person_rounded,
        _ => Icons.link_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(_icon, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.titulo,
                  style: TextStyle(color: fg, fontWeight: FontWeight.bold),
                ),
                if (item.subtitulo.isNotEmpty)
                  Text(
                    item.subtitulo,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
