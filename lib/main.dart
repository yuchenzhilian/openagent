// Entry point. The Phase 3 verification UI has been replaced by the full
// multi-page app (chat / model market / settings) defined in app.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: OpenAgentApp()));
}
