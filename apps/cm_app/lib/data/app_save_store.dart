import 'dart:io';

import 'package:engine/engine.dart';
import 'package:path_provider/path_provider.dart';

/// Opens the app's on-disk [SaveStore].
class AppSaveStore {
  AppSaveStore._();

  /// A [FileSaveStore] at [root], by default `<documents>/saves`. Creates
  /// the directory. [root] is the saves directory itself (slots go directly
  /// in it), not its parent.
  static Future<SaveStore> open({Directory? root}) async {
    final dir =
        root ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}'
          '${Platform.pathSeparator}saves',
        );
    await dir.create(recursive: true);
    return FileSaveStore(dir);
  }
}
