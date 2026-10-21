import 'package:cm_app/engine/in_process_gateway.dart';

import '../support/gateway_contract.dart';

void main() {
  runGatewayContract(() async => InProcessGateway());
}
