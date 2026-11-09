// A markdown text's words without the markup (shared/utils/markdown_plain_text
// .dart) — what a folded description, best-time note, stop note or review
// shows, and a one-line summary. Parsed as InertMarkdownBody parses it.
import 'package:flutter_test/flutter_test.dart';
import 'package:ntripi/shared/utils/markdown_plain_text.dart';

void main() {
  test('Given emphasis and headings, Then only their words are left', () {
    expect(markdownPlainText('# Why May\n\nThe **souks** are *quiet*.'),
        'Why May\nThe souks are quiet.');
  });

  test('Given a line break inside a paragraph, Then it stays a line', () {
    expect(markdownPlainText('First line\nsecond line'),
        'First line\nsecond line');
  });

  test('Given lists, Then each item keeps its bullet or number', () {
    expect(markdownPlainText('- one\n- two\n\n3. three\n4. four'),
        '• one\n• two\n3. three\n4. four');
  });

  test('Given a loose list, Then the bullet stays on its item\'s line', () {
    expect(markdownPlainText('- loose one\n\n- loose two'),
        '• loose one\n• loose two');
  });

  test(
      'Given an image and a link, Then the image is its description and the '
      'link its label — no address is shown', () {
    final plain =
        markdownPlainText('See ![a castle](https://x.example/c.png) and '
            '[the map](https://x.example/map).');
    expect(plain, 'See a castle and the map.');
    expect(plain, isNot(contains('x.example')));
  });

  test('Given escaped markup, Then the character itself stays', () {
    expect(markdownPlainText(r'\*not italic\*'), '*not italic*');
  });

  test('Given Arabic and Chinese, Then the words come through untouched', () {
    expect(markdownPlainText('## أفضل وقت\n\n**الربيع** معتدل'),
        'أفضل وقت\nالربيع معتدل');
    expect(markdownPlainText('**春天**最好。'), '春天最好。');
  });

  test('Given singleLine, Then blocks join with spaces — a summary row', () {
    expect(markdownPlainText('# Why\n\n- quiet\n- warm', singleLine: true),
        'Why • quiet • warm');
  });

  test('Given only blanks or markup, Then the result is empty', () {
    expect(markdownPlainText('  \n\n'), '');
    expect(markdownPlainText('![](https://x.example/c.png)'), '');
  });
}
