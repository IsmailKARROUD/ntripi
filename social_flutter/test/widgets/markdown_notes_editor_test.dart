// test/widgets/markdown_notes_editor_test.dart
//
// Widget tests for MarkdownNotesEditor's toolbar actions. Each button must
// insert the correct Markdown source into the bound TextEditingController:
//   - Bold / Italic     → wrap selection (or insert placeholder)
//   - H1 / H2           → prefix the current line
//   - Bullet            → prefix the current line with "- "
//   - Numbered          → prefix each line with "1. ", "2. ", ...
//
// We assert against `controller.text` and `controller.selection` directly,
// which is the editor's only public contract. The Preview toggle is also
// tested to confirm it swaps the body widget and disables the toolbar.

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:social_flutter/features/itineraries/presentation/widgets/markdown_notes_editor.dart';

void main() {
  late TextEditingController controller;

  setUp(() {
    controller = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SingleChildScrollView(
            child: MarkdownNotesEditor(
              controller: controller,
              readOnly: false,
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Bold
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Bold button', () {
    testWidgets(
        'Given empty controller, When Bold tapped, Then inserts **bold** with placeholder selected',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();

      expect(controller.text, '**bold**');
      expect(controller.selection.baseOffset, 2);
      expect(controller.selection.extentOffset, 6);
    });

    testWidgets(
        'Given collapsed cursor at end of text, When Bold tapped, Then appends **bold** and selects placeholder',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();

      expect(controller.text, 'hello**bold**');
      expect(controller.selection.baseOffset, 7);
      expect(controller.selection.extentOffset, 11);
    });

    testWidgets(
        'Given an existing selection, When Bold tapped, Then wraps the selection and keeps it selected',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();

      expect(controller.text, 'hello **world**');
      expect(controller.selection.baseOffset, 8);
      expect(controller.selection.extentOffset, 13);
    });
  });

  // -------------------------------------------------------------------------
  // Italic
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Italic button', () {
    testWidgets(
        'Given empty controller, When Italic tapped, Then inserts *italic* with placeholder selected',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Italic'));
      await tester.pump();

      expect(controller.text, '*italic*');
      expect(controller.selection.baseOffset, 1);
      expect(controller.selection.extentOffset, 7);
    });

    testWidgets(
        'Given selection on a word, When Italic tapped, Then wraps with single asterisks',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Italic'));
      await tester.pump();

      expect(controller.text, '*hello* world');
      expect(controller.selection.baseOffset, 1);
      expect(controller.selection.extentOffset, 6);
    });
  });

  // -------------------------------------------------------------------------
  // Heading 1
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Heading 1 button', () {
    testWidgets(
        'Given empty controller, When H1 tapped, Then inserts "# " and places cursor after it',
        (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Heading 1'));
      await tester.pump();

      expect(controller.text, '# ');
      expect(controller.selection.baseOffset, 2);
      expect(controller.selection.isCollapsed, isTrue);
    });

    testWidgets(
        'Given cursor on a single line, When H1 tapped, Then prefixes the whole line with "# "',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 5),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Heading 1'));
      await tester.pump();

      expect(controller.text, '# hello');
      expect(controller.selection.baseOffset, 7);
    });

    testWidgets(
        'Given a two-line selection, When H1 tapped, Then prefixes both lines independently',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'a\nb',
        selection: TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Heading 1'));
      await tester.pump();

      expect(controller.text, '# a\n# b');
    });
  });

  // -------------------------------------------------------------------------
  // Heading 2
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Heading 2 button', () {
    testWidgets(
        'Given cursor on a single line, When H2 tapped, Then prefixes with "## "',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'hello',
        selection: TextSelection.collapsed(offset: 0),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Heading 2'));
      await tester.pump();

      expect(controller.text, '## hello');
    });
  });

  // -------------------------------------------------------------------------
  // Bullet list
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Bullet list button', () {
    testWidgets(
        'Given cursor on a single line, When Bullet tapped, Then prefixes with "- "',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'milk',
        selection: TextSelection.collapsed(offset: 4),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Bullet list'));
      await tester.pump();

      expect(controller.text, '- milk');
    });

    testWidgets(
        'Given a three-line selection, When Bullet tapped, Then prefixes every line',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'a\nb\nc',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Bullet list'));
      await tester.pump();

      expect(controller.text, '- a\n- b\n- c');
    });
  });

  // -------------------------------------------------------------------------
  // Numbered list
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Numbered list button', () {
    testWidgets(
        'Given a single line, When Numbered tapped, Then prefixes with "1. "',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'first',
        selection: TextSelection.collapsed(offset: 5),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Numbered list'));
      await tester.pump();

      expect(controller.text, '1. first');
    });

    testWidgets(
        'Given a three-line selection, When Numbered tapped, Then numbers each line sequentially',
        (tester) async {
      controller.value = const TextEditingValue(
        text: 'a\nb\nc',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );
      await pumpEditor(tester);

      await tester.tap(find.byTooltip('Numbered list'));
      await tester.pump();

      expect(controller.text, '1. a\n2. b\n3. c');
    });
  });

  // -------------------------------------------------------------------------
  // Edit / Preview toggle
  // -------------------------------------------------------------------------
  group('MarkdownNotesEditor – Edit/Preview toggle', () {
    testWidgets(
        'Given the editor mounts, When no toggle is touched, Then it starts in Edit mode (TextField visible, no MarkdownBody)',
        (tester) async {
      controller.text = '# Hello';
      await pumpEditor(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
    });

    testWidgets(
        'Given content in the controller, When Preview tab tapped, Then the TextField is replaced by a MarkdownBody and toolbar buttons are disabled',
        (tester) async {
      controller.text = '# Hello';
      await pumpEditor(tester);

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(MarkdownBody), findsOneWidget);

      final boldButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Bold'),
          matching: find.byType(IconButton),
        ).first,
      );
      expect(boldButton.onPressed, isNull);
    });

    testWidgets(
        'Given Preview mode, When Edit tab tapped, Then the TextField returns and toolbar re-enables',
        (tester) async {
      controller.text = '# Hello';
      await pumpEditor(tester);

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);

      final boldButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Bold'),
          matching: find.byType(IconButton),
        ).first,
      );
      expect(boldButton.onPressed, isNotNull);
    });
  });
}
