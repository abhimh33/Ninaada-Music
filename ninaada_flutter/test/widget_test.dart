// Basic Flutter widget test for Ninaada Music

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: NinaadaApp()));
    await tester.pump();
    // Just verify the app builds without error
    expect(find.byType(NinaadaApp), findsOneWidget);
  });
}
