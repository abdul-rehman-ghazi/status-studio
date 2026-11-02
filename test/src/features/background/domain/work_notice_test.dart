import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/background/domain/work_notice.dart';

void main() {
  test('progress_body_puts_the_percent_first', () {
    const notice = ProgressNotice(
      title: 'Writing the script',
      text: 'Never Gonna Give You Up',
      percent: 45,
    );

    expect(notice.body, '45 % · Never Gonna Give You Up');
  });

  test('notices_with_the_same_words_and_percent_are_equal', () {
    const first = ProgressNotice(title: 'Step', text: 'Video', percent: 3);
    const second = ProgressNotice(title: 'Step', text: 'Video', percent: 3);

    expect(first, second);
  });
}
