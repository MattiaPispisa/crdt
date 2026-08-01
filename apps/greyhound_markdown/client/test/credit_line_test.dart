import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/credit_line.dart';
import 'package:greyhound_markdown_client/src/widgets/footer_link.dart';

void main() {
  testWidgets('CreditLine links the author to their site', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CreditLine())),
    );

    expect(find.text(kCreditPrefix), findsOneWidget);
    final link = tester.widget<FooterLink>(find.byType(FooterLink));
    expect(link.label, kAuthor);
    expect(link.url, kAuthorUrl);
  });
}
