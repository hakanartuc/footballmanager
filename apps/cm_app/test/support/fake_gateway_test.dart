import 'package:cm_app/engine/engine_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_gateway.dart';

void main() {
  test('unscripted player and lineup fail with a GatewayError', () async {
    final g = FakeGateway.ready();
    expect(g.player(1), throwsA(isA<GatewayError>()));
    expect(g.lineup(1), throwsA(isA<GatewayError>()));
    expect(g.lineup(1, auto: true), throwsA(isA<GatewayError>()));
  });
}
