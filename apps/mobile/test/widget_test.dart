import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatly/core/widgets/glassmorphic_container.dart';

void main() {
  testWidgets('GlassmorphicContainer renders child and padding correctly', (WidgetTester tester) async {
    const textKey = Key('test-child-text');
    const childText = 'Hello E2EE';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassmorphicContainer(
            padding: EdgeInsets.all(16.0),
            child: Text(childText, key: textKey),
          ),
        ),
      ),
    );

    // Verify child is rendered
    expect(find.text(childText), findsOneWidget);
    expect(find.byKey(textKey), findsOneWidget);

    // Verify container padding is applied
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(GlassmorphicContainer),
        matching: find.byType(Container),
      ).last,
    );
    expect(container.padding, const EdgeInsets.all(16.0));
  });
}
