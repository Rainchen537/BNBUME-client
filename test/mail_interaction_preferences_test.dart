import 'dart:convert';

import 'package:bnbu_me/services/mail_interaction_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'defaults, normalized sender rules and both gestures survive reload',
    () async {
      final preferences = MailInteractionPreferences();
      await preferences.load('fixture-a');
      expect(preferences.read('fixture-a').left, MailSwipeChoice.star);
      expect(preferences.read('fixture-a').right, MailSwipeChoice.readDelete);
      await preferences.update(
        'fixture-a',
        left: MailSwipeChoice.mute,
        right: MailSwipeChoice.none,
        sender: 'Fixture <Sender@Example.test>',
        muted: true,
      );
      final reloaded = MailInteractionPreferences();
      await reloaded.load('fixture-a');
      expect(reloaded.read('fixture-a').left, MailSwipeChoice.mute);
      expect(reloaded.read('fixture-a').right, MailSwipeChoice.none);
      expect(
        reloaded.read('fixture-a').isMuted('Other name <sender@example.test>'),
        isTrue,
      );
      expect(reloaded.read('fixture-b').mutedSenders, isEmpty);
      expect(reloaded.read('fixture-b').left, MailSwipeChoice.star);
      await reloaded.update(
        'fixture-a',
        sender: 'sender@example.test',
        muted: false,
      );
      expect(reloaded.read('fixture-a').mutedSenders, isEmpty);
    },
  );

  test('concurrent updates preserve both gestures and sender rules', () async {
    final preferences = MailInteractionPreferences();
    await Future.wait([
      preferences.update('fixture-a', left: MailSwipeChoice.read),
      preferences.update('fixture-a', right: MailSwipeChoice.delete),
      preferences.update('fixture-a', sender: 'one@example.test', muted: true),
      preferences.update('fixture-a', sender: 'two@example.test', muted: true),
    ]);
    final settings = preferences.read('fixture-a');
    expect(settings.left, MailSwipeChoice.read);
    expect(settings.right, MailSwipeChoice.delete);
    expect(settings.mutedSenders, {'one@example.test', 'two@example.test'});
  });

  test(
    'invalid addresses cannot create broad rules or poison the write queue',
    () async {
      final preferences = MailInteractionPreferences();
      await expectLater(
        preferences.update('fixture-a', sender: 'not an address', muted: true),
        throwsFormatException,
      );
      expect(mailSenderAddress('a@example.test, b@example.test'), isNull);
      await preferences.update(
        'fixture-a',
        sender: 'safe@example.test',
        muted: true,
      );
      expect(preferences.read('fixture-a').mutedSenders, {'safe@example.test'});
    },
  );

  test(
    'corrupt or unknown local settings fall back without blocking mail',
    () async {
      String key(String owner) =>
          'mail.interactions.v1.${sha256.convert(utf8.encode(owner))}';
      SharedPreferences.setMockInitialValues({
        key('broken'): '{',
        key('newer'): jsonEncode({
          'left': 'future-choice',
          'muted': ['not-address', 'ok@example.test'],
        }),
      });
      final preferences = MailInteractionPreferences();
      await preferences.load('broken');
      await preferences.load('newer');
      expect(preferences.read('broken').mutedSenders, isEmpty);
      expect(preferences.read('newer').left, MailSwipeChoice.star);
      expect(preferences.read('newer').mutedSenders, {'ok@example.test'});
    },
  );
}
