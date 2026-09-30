import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_interaction_preferences.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/mail_interaction_settings.dart';
import 'package:bnbu_me/widgets/mail_message_row.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/mobile_mail_preview.dart';

const _owner = 'mail-reference-fixture';
final _preferences = MailInteractionPreferences.shared;

Widget _app(Widget child) => RepaintBoundary(
  key: const ValueKey('interaction-capture'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('zh', 'CN'),
    supportedLocales: BnbuLocalizations.supportedLocales,
    localizationsDelegates: const [
      BnbuLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  ),
);

Future<void> _capture(WidgetTester tester, String name) =>
    tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('interaction-capture')),
      );
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/mail-interactions')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in [
        'Roboto',
        'Segoe UI',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
        '.AppleSystemUIFont',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.whereType<Map>()) {
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _preferences.update(
      _owner,
      left: MailSwipeChoice.star,
      right: MailSwipeChoice.readDelete,
    );
    for (final sender in _preferences.read(_owner).mutedSenders) {
      await _preferences.update(_owner, sender: sender, muted: false);
    }
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<MailReferenceFixture> launch(
    WidgetTester tester, {
    bool desktop = false,
    ReferenceMailService? service,
  }) async {
    debugDefaultTargetPlatformOverride = desktop
        ? TargetPlatform.windows
        : TargetPlatform.iOS;
    tester.view.physicalSize = desktop
        ? const Size(1180, 820)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fixture = MailReferenceFixture(mailService: service);
    await fixture.initialize();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(_app(fixture.page()));
    await tester.pumpAndSettle();
    return fixture;
  }

  Future<void> menu(WidgetTester tester, int uid) async {
    await tester.tap(
      find.byKey(ValueKey('mail-desktop-row-$uid')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'iOS left stars, right toggles read, and opening a second row closes the first',
    (tester) async {
      final fixture = await launch(tester);
      final wasSeen = fixture.service.messages
          .firstWhere((m) => m.uid == 2)
          .isSeen;
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加星标'), findsOneWidget);
      await _capture(tester, 'ios-left-star');
      await tester.tap(find.text('添加星标'));
      await tester.pumpAndSettle();
      expect(
        fixture.service.messages.firstWhere((m) => m.uid == 1).isFlagged,
        isTrue,
      );
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('取消星标'), findsOneWidget);
      await tester.drag(
        find.byType(MailMessageRow).at(1),
        const Offset(240, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('取消星标'), findsNothing);
      expect(find.text('删除'), findsOneWidget);
      await tester.tap(find.text(wasSeen ? '标为未读' : '标为已读'));
      await tester.pumpAndSettle();
      expect(
        fixture.service.messages.firstWhere((m) => m.uid == 2).isSeen,
        !wasSeen,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'both directions can be changed in settings and applied on reopening mail',
    (tester) async {
      await _preferences.update(
        _owner,
        sender: 'settings@example.test',
        muted: true,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: SingleChildScrollView(
              child: MailInteractionSettingsPanel(owner: _owner),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('取消免提醒'));
      await tester.pumpAndSettle();
      expect(_preferences.read(_owner).mutedSenders, isEmpty);
      await tester.tap(find.byKey(const ValueKey('mail-swipe-true-star')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('无操作').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mail-swipe-false-readDelete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('已读 / 未读').last);
      await tester.pumpAndSettle();
      expect(_preferences.read(_owner).left, MailSwipeChoice.none);
      expect(_preferences.read(_owner).right, MailSwipeChoice.read);
      await _capture(tester, 'settings');
      await launch(tester);
      final row = tester.widget<MailMessageRow>(
        find.byType(MailMessageRow).first,
      );
      expect(row.swipeActions, isEmpty);
      expect(row.rightSwipeActions.map((a) => a.label), ['标为已读']);
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('添加星标'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Windows right click stars, marks read, selects and confirms deletion',
    (tester) async {
      final fixture = await launch(tester, desktop: true);
      await menu(tester, 1);
      for (final text in ['添加星标', '标为已读', '多选', '删除', '发件人免提醒']) {
        expect(find.text(text), findsOneWidget);
      }
      await _capture(tester, 'windows-context-menu');
      await tester.tap(find.text('添加星标'));
      await tester.pumpAndSettle();
      expect(
        fixture.service.messages.firstWhere((m) => m.uid == 1).isFlagged,
        isTrue,
      );
      await menu(tester, 1);
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(
        fixture.service.messages.firstWhere((m) => m.uid == 1).isSeen,
        isTrue,
      );
      await menu(tester, 1);
      expect(find.text('标为未读'), findsOneWidget);
      await tester.tap(find.text('多选'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .where((c) => c.value == true)
            .length,
        1,
      );
      await tester.tap(find.byKey(const ValueKey('mail-desktop-row-2')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .where((c) => c.value == true)
            .length,
        2,
      );
      await _capture(tester, 'windows-multiselect');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await menu(tester, 1);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        fixture.service.messages.firstWhere((m) => m.uid == 1).folder,
        MailFolder.inbox,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('删除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.service.messages.any(
          (m) => m.uid == 1 && m.folder == MailFolder.inbox,
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final selectAll in [false, true]) {
    testWidgets(
      'desktop top delete uses ${selectAll ? "all" : "only checked"} messages instead of the open message',
      (tester) async {
        final fixture = await launch(tester, desktop: true);
        final originalCount = fixture.service.messages
            .where((m) => m.folder == MailFolder.inbox)
            .length;
        await tester.tap(find.byKey(const ValueKey('mail-desktop-row-1')));
        await tester.pumpAndSettle();
        await menu(tester, 2);
        await tester.tap(find.text('多选'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mail-desktop-row-3')));
        await tester.pumpAndSettle();
        if (selectAll) {
          await tester.tap(find.text('全选'));
          await tester.pumpAndSettle();
        }
        final count = selectAll ? originalCount : 2;
        final topDelete = find.byKey(
          const ValueKey('mail-desktop-delete-or-restore'),
        );
        await tester.tap(topDelete);
        await tester.pumpAndSettle();
        expect(find.text('将选中的 $count 封邮件移到已删除？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(
          fixture.service.messages
              .where((m) => m.folder == MailFolder.inbox)
              .length,
          originalCount,
        );
        await tester.tap(topDelete);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('删除'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          fixture.service.messages
              .where((m) => m.folder == MailFolder.inbox)
              .length,
          originalCount - count,
        );
        if (!selectAll) {
          expect(
            fixture.service.messages.any(
              (m) => m.uid == 1 && m.folder == MailFolder.inbox,
            ),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'muted sender groups mail without marking it read, and unmute restores inbox',
    (tester) async {
      await _preferences.update(_owner, left: MailSwipeChoice.mute);
      final fixture = await launch(tester);
      final first = fixture.service.messages.firstWhere((m) => m.uid == 1);
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('发件人免提醒'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mail-muted-group')), findsOneWidget);
      expect(
        tester
            .widgetList<MailMessageRow>(find.byType(MailMessageRow))
            .any((r) => r.message.uid == 1),
        isFalse,
      );
      expect(
        fixture.service.messages.firstWhere((m) => m.uid == 1).isSeen,
        first.isSeen,
      );
      await tester.tap(find.byKey(const ValueKey('mail-muted-group')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<MailMessageRow>(find.byType(MailMessageRow))
            .every((r) => r.muted),
        isTrue,
      );
      await _capture(tester, 'muted-mail');
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消免提醒'));
      await tester.pumpAndSettle();
      expect(_preferences.read(_owner).mutedSenders, isEmpty);
      expect(find.byType(MailMessageRow), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-folder-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收件箱'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MailMessageRow>(find.byType(MailMessageRow).first)
            .message
            .uid,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'muting an entire first page keeps the load more entry reachable',
    (tester) async {
      final service = ReferenceMailService(DateTime(2026));
      final template = service.messages.first;
      service.messages
        ..clear()
        ..addAll(List.generate(25, (i) => template.copyWith(uid: i + 1)))
        ..add(template.copyWith(uid: 26, sender: 'visible@example.test'));
      await _preferences.update(_owner, sender: template.sender, muted: true);
      await launch(tester, service: service);
      expect(find.byType(MailMessageRow), findsNothing);
      expect(find.text('加载更多'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MailMessageRow>(find.byType(MailMessageRow)).message.uid,
        26,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'custom move gesture restores a single trash message without selecting it',
    (tester) async {
      final service = ReferenceMailService(DateTime(2026));
      service.messages.add(
        service.messages.first.copyWith(uid: 101, folder: MailFolder.trash),
      );
      await _preferences.update(_owner, left: MailSwipeChoice.move);
      await launch(tester, service: service);
      await tester.tap(find.byKey(const ValueKey('mail-folder-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已删除'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-160, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复到原文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();
      expect(
        service.messages.where((m) => m.folder == MailFolder.trash),
        isEmpty,
      );
      expect(service.mutations, contains('move:inbox'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'top mark all read includes unloaded mail and cancellation changes nothing',
    (tester) async {
      final service = ReferenceMailService(DateTime(2026));
      final template = service.messages.first;
      service.messages
        ..clear()
        ..addAll(
          List.generate(
            80,
            (i) => template.copyWith(uid: i + 1, isSeen: false),
          ),
        );
      await launch(tester, service: service);
      expect(find.byType(MailMessageRow).evaluate().length, lessThan(80));
      final button = find.byKey(const ValueKey('mail-mark-all-read'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.messages.every((m) => !m.isSeen), isTrue);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '全部已读'));
      await tester.pumpAndSettle();
      expect(service.messages.every((m) => m.isSeen), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
