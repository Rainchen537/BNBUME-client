import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mail_address_parser.dart';

enum MailSwipeChoice { star, read, readDelete, delete, mute, move, none }

String mailSwipeChoiceLabel(MailSwipeChoice choice) => switch (choice) {
  MailSwipeChoice.star => '星标',
  MailSwipeChoice.read => '已读 / 未读',
  MailSwipeChoice.readDelete => '已读 / 未读和删除',
  MailSwipeChoice.delete => '删除',
  MailSwipeChoice.mute => '发件人免提醒',
  MailSwipeChoice.move => '移动',
  MailSwipeChoice.none => '无操作',
};

String? mailSenderAddress(String sender) {
  try {
    final addresses = parseMailRecipientAddresses(sender);
    if (addresses.length != 1) return null;
    return addresses.single.email.toLowerCase();
  } on FormatException {
    return null;
  }
}

class MailInteractionSettings {
  MailInteractionSettings({
    this.left = MailSwipeChoice.star,
    this.right = MailSwipeChoice.readDelete,
    Set<String> mutedSenders = const {},
  }) : mutedSenders = Set.unmodifiable(mutedSenders);

  final MailSwipeChoice left;
  final MailSwipeChoice right;
  final Set<String> mutedSenders;
  bool isMuted(String sender) =>
      mutedSenders.contains(mailSenderAddress(sender));
}

/// Local, account-isolated preferences. These are not WeCom server rules.
class MailInteractionPreferences extends ChangeNotifier {
  static final shared = MailInteractionPreferences();
  final Map<String, MailInteractionSettings> _values = {};
  final Map<String, Future<void>> _loads = {};
  Future<void>? _writes;

  String _owner(String owner) => owner.trim().toLowerCase().split('@').first;
  String _key(String owner) =>
      'mail.interactions.v1.${sha256.convert(utf8.encode(_owner(owner)))}';

  MailInteractionSettings read(String owner) =>
      _values[_owner(owner)] ?? MailInteractionSettings();

  Future<void> load(String owner) {
    final key = _owner(owner);
    if (_values.containsKey(key)) return Future.value();
    return _loads.putIfAbsent(
      key,
      () => _load(owner).whenComplete(() {
        _loads.remove(key);
      }),
    );
  }

  Future<void> _load(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(owner));
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        MailSwipeChoice choice(String name, MailSwipeChoice fallback) =>
            MailSwipeChoice.values
                .where((v) => v.name == json[name])
                .firstOrNull ??
            fallback;
        _values[_owner(owner)] = MailInteractionSettings(
          left: choice('left', MailSwipeChoice.star),
          right: choice('right', MailSwipeChoice.readDelete),
          mutedSenders: (json['muted'] as List? ?? const [])
              .whereType<String>()
              .map(mailSenderAddress)
              .whereType<String>()
              .toSet(),
        );
      } on Object {
        // A malformed local preference must not prevent mailbox access.
      }
    }
    _values.putIfAbsent(_owner(owner), MailInteractionSettings.new);
    notifyListeners();
  }

  Future<void> update(
    String owner, {
    MailSwipeChoice? left,
    MailSwipeChoice? right,
    String? sender,
    bool? muted,
  }) {
    final operation = (_writes ?? Future<void>.value()).then((_) async {
      await load(owner);
      final current = read(owner);
      final senders = {...current.mutedSenders};
      if (sender != null) {
        final address = mailSenderAddress(sender);
        if (address == null) throw const FormatException('无法识别发件人地址。');
        if (muted == true) {
          senders.add(address);
        } else {
          senders.remove(address);
        }
      }
      final next = MailInteractionSettings(
        left: left ?? current.left,
        right: right ?? current.right,
        mutedSenders: senders,
      );
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        _key(owner),
        jsonEncode({
          'left': next.left.name,
          'right': next.right.name,
          'muted': senders.toList()..sort(),
        }),
      );
      if (!saved) throw StateError('邮箱设置保存失败，请重试。');
      _values[_owner(owner)] = next;
      notifyListeners();
    });
    final queued = operation.catchError((Object _) {});
    _writes = queued;
    queued.then((_) {
      if (identical(_writes, queued)) _writes = null;
    });
    return operation;
  }
}
