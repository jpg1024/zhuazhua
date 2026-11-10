import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoo_desktop_pet/core/animals.dart';
import 'package:zoo_desktop_pet/growth/growth_service.dart';
import 'package:zoo_desktop_pet/pet/pet_page.dart';

import 'test_paths.dart';

void main() {
  late Directory tmp;
  late GrowthService growth;

  setUp(() {
    tmp = setupPaths();
    growth = GrowthService('cat');
  });

  tearDown(() {
    growth.dispose();
    teardownPaths(tmp);
  });

  testWidgets('成长记录较多时卡片限高且内容可滚动', (tester) async {
    for (var i = 0; i < 20; i++) {
      growth.addEvent('aiChat', '成长记录 $i');
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GrowthCard(
            growth: growth,
            animal: animalById('cat'),
            maxHeight: 220,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(GrowthCard)).height, 220);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pump();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
