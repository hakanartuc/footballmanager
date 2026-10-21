import 'dart:typed_data';

import 'package:engine/engine.dart';

/// Throws [SaveError] `io` on the next [write] when [failNextWrite].
class FlakyStore extends MemorySaveStore {
  bool failNextWrite = false;

  @override
  Future<void> write(int slot, Uint8List bytes, SlotInfo meta) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw SaveError(SaveErrorKind.io, 'disk full');
    }
    await super.write(slot, bytes, meta);
  }
}
