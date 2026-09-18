import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('probe golden', (tester) async {
    print('PROBE: start');
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('你好 hi'))),
    ));
    print('PROBE: pumped');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('tmpgold/probe.png'),
    );
    print('PROBE: golden done');
  });
}
