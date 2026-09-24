import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'src/engine/dart_engine.dart';
import 'src/engine/models.dart';
import 'src/native/cbr_reader.dart';

void main() {
  runApp(const CbzManagerApp());
}

class CbzManagerApp extends StatelessWidget {
  const CbzManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CBZ Manager',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _engine = DartCbzEngine();

  String _status = 'Phase 0 — engine scaffold.';
  bool _running = false;

  Future<void> _selfTest() async {
    setState(() {
      _running = true;
      _status = 'Running engine self-test...';
    });
    try {
      final archive = Archive();
      archive.add(ArchiveFile.bytes('page_001.png', _solidPng(16, 16)));
      archive.add(ArchiveFile.bytes('page_002.png', _solidPng(16, 16)));
      archive.add(ArchiveFile.bytes('ComicInfo.xml', '<ComicInfo/>'.codeUnits));
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));

      final validation = await _engine.validate(ArchiveData('demo.cbz', bytes));
      final conversion = await _engine.convertWebp(
        ArchiveData('demo.cbz', bytes),
        const ConvertOptions(onlyIfSmaller: false),
      );

      setState(() {
        _status =
            'validate: ${validation.valid ? 'ok' : 'failed'} '
            '(${validation.imageCount} images)\n'
            'convert: ${conversion.success ? 'ok' : 'failed'} '
            '(${conversion.converted} converted)\n'
            'CBR support: ${CbrReader.isSupported ? 'yes' : 'no (libarchive missing)'}';
      });
    } catch (e) {
      setState(() => _status = 'Self-test error: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  static Uint8List _solidPng(int width, int height) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(120, 30, 200));
    return Uint8List.fromList(img.encodePng(image));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CBZ Manager')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Flutter port — Phase 0',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('${defaultTargetPlatform.name} · '
                    '${CbrReader.isSupported ? 'CBR ready' : 'CBR unavailable'}'),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_status),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _running ? null : _selfTest,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run engine self-test'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
