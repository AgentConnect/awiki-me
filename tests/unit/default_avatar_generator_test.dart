import 'package:awiki_me/src/presentation/shared/default_avatar_generator.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractDefaultAvatarText', () {
    test('extracts the last two Chinese characters', () {
      expect(extractDefaultAvatarText('张小明'), '小明');
      expect(extractDefaultAvatarText('王强'), '王强');
      expect(extractDefaultAvatarText('欧阳娜娜'), '娜娜');
      expect(extractDefaultAvatarText('林'), '林');
    });

    test('keeps the full agent suffix when the name ends with 智能体', () {
      expect(extractDefaultAvatarText('通知智能体'), '智能体');
      expect(extractDefaultAvatarText('AWiki 智能体'), '智能体');
      expect(extractDefaultAvatarText('智能体通知'), '通知');
    });

    test('extracts English word and camel-case initials', () {
      expect(extractDefaultAvatarText('Howard Chan'), 'HC');
      expect(extractDefaultAvatarText('Howard'), 'H');
      expect(extractDefaultAvatarText('howard'), 'H');
      expect(extractDefaultAvatarText('HowardChan'), 'HC');
      expect(extractDefaultAvatarText('GitHub'), 'GH');
      expect(extractDefaultAvatarText('OpenAI'), 'OA');
    });

    test('normalizes usernames, email local parts, and leading symbols', () {
      expect(extractDefaultAvatarText('howard_chan'), 'HC');
      expect(extractDefaultAvatarText('howard-chan'), 'HC');
      expect(extractDefaultAvatarText('howard.chan'), 'HC');
      expect(extractDefaultAvatarText('howard.chan@gmail.com'), 'HC');
      expect(extractDefaultAvatarText('@howard'), 'H');
    });

    test('keeps mixed-language initials in source order', () {
      expect(extractDefaultAvatarText('张Howard'), '张H');
      expect(extractDefaultAvatarText('Howard张'), 'H张');
    });

    test('returns explicit placeholders for invalid input', () {
      expect(extractDefaultAvatarText(''), '?');
      expect(extractDefaultAvatarText('   '), '?');
      expect(extractDefaultAvatarText('12345'), '#');
      expect(extractDefaultAvatarText('@@@'), '?');
    });
  });

  group('defaultAvatarColor', () {
    test('is deterministic and canonicalizes separators and case', () {
      expect(
        defaultAvatarColor('Howard.Chan'),
        defaultAvatarColor('howard_chan'),
      );
      expect(
        defaultAvatarColor('Howard.Chan'),
        isNot(defaultAvatarColor('Elon Musk')),
      );
    });

    test('uses hash-derived hue with fixed HSL saturation and lightness', () {
      final hsl = HSLColor.fromColor(defaultAvatarColor('Howard Chan'));
      expect(hsl.saturation, closeTo(0.6, 0.01));
      expect(hsl.lightness, closeTo(0.5, 0.01));
      expect(hsl.hue, inInclusiveRange(0, 359));
    });

    test('userId keeps the color stable when the display name changes', () {
      final first = generateDefaultAvatar(name: 'Howard', userId: 'did:test:1');
      final renamed = generateDefaultAvatar(name: '豪哥', userId: 'did:test:1');

      expect(first.text, 'H');
      expect(renamed.text, '豪哥');
      expect(first.backgroundColor, renamed.backgroundColor);
    });
  });
}
