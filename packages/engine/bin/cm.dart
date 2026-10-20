import 'dart:io';

import 'package:engine/src/cli/commands.dart';

void main(List<String> args) async => exit(await runCli(args));
