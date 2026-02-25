import 'package:flutter_test/flutter_test.dart';

import 'package:workflow_tool/main.dart';

void main() {
  testWidgets('workflow home renders', (tester) async {
    await tester.pumpWidget(const WorkflowApp());

    expect(find.text('Android Workflow Tool'), findsOneWidget);
    expect(find.text('新建工作流'), findsOneWidget);
  });
}
