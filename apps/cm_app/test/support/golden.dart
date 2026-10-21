import 'dart:io';

import 'package:flutter/services.dart';

/// Loads Roboto and the Material icons from the Flutter SDK, so goldens show
/// real text and icons instead of Ahem boxes. `rootBundle` has no fonts in
/// tests, so the files are read from `bin/cache/artifacts/material_fonts`
/// of the SDK running the test.
Future<void> loadTestFonts() async {
  final fonts = _materialFontsDir();
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('${fonts.path}/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

/// Walks up from the test executable (`flutter_tester` or `dart`, both under
/// `<sdk>/bin/cache/`) to the SDK's material fonts directory.
Directory _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (true) {
    final fonts = Directory('${dir.path}/bin/cache/artifacts/material_fonts');
    if (File('${fonts.path}/Roboto-Regular.ttf').existsSync()) return fonts;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Roboto-Regular.ttf not found under any bin/cache/artifacts/'
        'material_fonts above ${Platform.resolvedExecutable}; run '
        '`flutter precache` or check the Flutter SDK install.',
      );
    }
    dir = parent;
  }
}
