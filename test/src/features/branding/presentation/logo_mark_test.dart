import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';

void main() {
  testWidgets('logo_mark_is_drawn_at_requested_size', (tester) async {
    await tester.pumpWidget(const Center(child: LogoMark(size: 40)));

    expect(tester.getSize(find.byType(LogoMark)), const Size(40, 40));
  });
}
