import 'dart:async';

import 'package:flutter/material.dart';

import '../services/mail_interaction_preferences.dart';
import '../theme/app_theme.dart';

class MailInteractionSettingsPanel extends StatefulWidget {
  const MailInteractionSettingsPanel({super.key, required this.owner});
  final String owner;

  @override
  State<MailInteractionSettingsPanel> createState() =>
      _MailInteractionSettingsPanelState();
}

class _MailInteractionSettingsPanelState
    extends State<MailInteractionSettingsPanel> {
  final _preferences = MailInteractionPreferences.shared;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_save(() => _preferences.load(widget.owner)));
  }

  @override
  void didUpdateWidget(MailInteractionSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner != widget.owner) {
      unawaited(_save(() => _preferences.load(widget.owner)));
    }
  }

  Future<void> _save(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _error = '邮箱设置保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _preferences,
    builder: (context, _) {
      final settings = _preferences.read(widget.owner);
      Widget choice(String label, MailSwipeChoice value, bool left) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: DropdownButtonFormField<MailSwipeChoice>(
          key: ValueKey('mail-swipe-$left-${value.name}'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.l10n.text(label)),
          items: [
            for (final item in MailSwipeChoice.values)
              DropdownMenuItem(
                value: item,
                child: Text(context.l10n.text(mailSwipeChoiceLabel(item))),
              ),
          ],
          onChanged: _busy
              ? null
              : (next) {
                  if (next != null) {
                    unawaited(
                      _save(
                        () => _preferences.update(
                          widget.owner,
                          left: left ? next : null,
                          right: left ? null : next,
                        ),
                      ),
                    );
                  }
                },
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(title: Text(context.l10n.text('邮件操作'))),
          choice('向左滑动', settings.left, true),
          choice('向右滑动', settings.right, false),
          ListTile(
            title: Text(context.l10n.text('免提醒发件人')),
            subtitle: Text(
              context.l10n.text('免提醒邮件单独归类，不显示未读圆点。仅保存在本机，不与企业微信同步。'),
            ),
          ),
          if (settings.mutedSenders.isEmpty)
            ListTile(
              subtitle: Text(context.l10n.text('长按邮件后选择“标记”，或右键邮件，设置发件人免提醒。')),
            ),
          for (final address in settings.mutedSenders.toList()..sort())
            ListTile(
              title: Text(address),
              trailing: IconButton(
                tooltip: context.l10n.text('取消免提醒'),
                icon: const Icon(Icons.notifications_active_outlined),
                onPressed: _busy
                    ? null
                    : () => _save(
                        () => _preferences.update(
                          widget.owner,
                          sender: address,
                          muted: false,
                        ),
                      ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.text(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}
