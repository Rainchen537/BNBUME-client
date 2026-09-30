part of 'mail_page.dart';

extension _MailInteractions on _MailPageState {
  MailInteractionSettings get _interactionSettings =>
      MailInteractionPreferences.shared.read(_credentials?.userId ?? '');

  void _interactionChanged() {
    _updateMail(() {});
  }

  Future<void> _setSendersMuted(
    List<MailMessageSummary> messages,
    bool muted,
  ) async {
    final owner = _credentials?.userId;
    if (owner == null) return;
    await _runMailMutation(() async {
      for (final sender
          in messages
              .map((m) => mailSenderAddress(m.sender))
              .whereType<String>()
              .toSet()) {
        if (_credentials?.userId != owner) return;
        await MailInteractionPreferences.shared.update(
          owner,
          sender: sender,
          muted: muted,
        );
      }
    });
  }

  Future<void> _setSenderMuted(MailMessageSummary message) async {
    final owner = _credentials?.userId;
    if (owner == null) return;
    try {
      await MailInteractionPreferences.shared.update(
        owner,
        sender: message.sender,
        muted: !_interactionSettings.isMuted(message.sender),
      );
      if (mounted && _credentials?.userId == owner) {
        await _refreshCurrentMailbox();
      }
    } catch (_) {
      if (mounted) {
        BnbuToast.show(context, '邮箱设置保存失败，请重试。', kind: BnbuToastKind.danger);
      }
    }
  }

  Future<void> _markAllRead() async {
    final credentials = _credentials;
    if (credentials == null ||
        _isDeleting ||
        _mailResultsPending ||
        _showRadar) {
      return;
    }
    final generation = _folderRequestGeneration;
    final collection = _collection;
    final folder = _currentFolder;
    bool current() =>
        mounted &&
        identical(credentials, _credentials) &&
        generation == _folderRequestGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const BnbuText('全部已读'),
        content: BnbuText(
          collection == MailCollection.folder
              ? '将当前文件夹的全部邮件标为已读，包括尚未加载及搜索结果之外的邮件。'
              : '将当前分组中的全部邮件标为已读。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const BnbuText('全部已读'),
          ),
        ],
      ),
    );
    if (confirmed != true || !current()) return;
    if (collection != MailCollection.folder) {
      await _setMailRead(
        _collectionMessages
            .where(
              (m) =>
                  !m.isSeen &&
                  (collection != MailCollection.muted ||
                      _interactionSettings.isMuted(m.sender)),
            )
            .toList(),
        true,
      );
      return;
    }
    _updateMail(() => _isDeleting = true);
    try {
      await markMailFolderRead(
        service: _mailService,
        credentials: credentials,
        folder: folder,
        isCurrent: current,
      );
    } catch (_) {
      if (mounted && current()) {
        BnbuToast.show(
          context,
          '部分邮件可能尚未更新，请刷新后重试。',
          kind: BnbuToastKind.warning,
        );
      }
    } finally {
      if (mounted) _updateMail(() => _isDeleting = false);
      if (current()) await _refreshCurrentMailbox();
    }
  }

  List<MailSwipeAction> _configuredRowActions(
    MailMessageSummary message, {
    required bool left,
  }) {
    final choice = left
        ? _interactionSettings.left
        : _interactionSettings.right;
    final colors = context.bnbuTheme;
    final read = MailSwipeAction(
      label: message.isSeen ? '标为未读' : '标为已读',
      icon: message.isSeen ? LucideIcons.mail300 : LucideIcons.mailOpen300,
      color: colors.brandBlue,
      onPressed: () => _setMailRead([message], !message.isSeen),
    );
    final delete = MailSwipeAction(
      label: '删除',
      icon: LucideIcons.trash2300,
      color: Theme.of(context).colorScheme.error,
      onPressed: () => _deleteMailRows([message]),
    );
    return switch (choice) {
      MailSwipeChoice.none => [],
      MailSwipeChoice.read => [read],
      MailSwipeChoice.delete => [delete],
      MailSwipeChoice.readDelete => [
        read,
        if (_radarEffectivelyEnabled)
          MailSwipeAction(
            label: _showRadar ? '标记完成' : '加入雷达',
            icon: LucideIcons.radar300,
            color: colors.textMuted,
            onPressed: () => _toggleRadarMembership([message], !_showRadar),
          ),
        delete,
      ],
      MailSwipeChoice.star => [
        MailSwipeAction(
          label: message.isFlagged ? '取消星标' : '添加星标',
          icon: LucideIcons.star300,
          color: colors.brandBlue,
          onPressed: _organizationService == null
              ? null
              : () => _setMailStarred([message], !message.isFlagged),
        ),
      ],
      MailSwipeChoice.mute => [
        MailSwipeAction(
          label: _interactionSettings.isMuted(message.sender)
              ? '取消免提醒'
              : '发件人免提醒',
          icon: Icons.notifications_off_outlined,
          color: colors.textMuted,
          onPressed: mailSenderAddress(message.sender) == null
              ? null
              : () => _setSenderMuted(message),
        ),
      ],
      MailSwipeChoice.move => [
        MailSwipeAction(
          label: '移动',
          icon: Icons.drive_file_move_outline,
          color: colors.brandBlue,
          onPressed: () => _moveMailRows([message]),
        ),
      ],
    };
  }

  Future<void> _showMailContextMenu(
    MailMessageSummary message,
    Offset position,
  ) async {
    if (_isDeleting || _isSelectingAll) return;
    final credentials = _credentials;
    final generation = _folderRequestGeneration;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final value = await showMenu<String>(
      context: context,
      color: context.bnbuTheme.surfaceMuted,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      constraints: const BoxConstraints(minWidth: 224, maxWidth: 320),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'star',
          enabled: _organizationService != null,
          child: BnbuText(message.isFlagged ? '取消星标' : '添加星标'),
        ),
        PopupMenuItem(
          value: 'read',
          child: BnbuText(message.isSeen ? '标为未读' : '标为已读'),
        ),
        const PopupMenuItem(value: 'select', child: BnbuText('多选')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'mute',
          enabled: mailSenderAddress(message.sender) != null,
          child: BnbuText(
            _interactionSettings.isMuted(message.sender) ? '取消免提醒' : '发件人免提醒',
          ),
        ),
        const PopupMenuItem(value: 'delete', child: BnbuText('删除')),
      ],
    );
    if (!mounted ||
        !identical(credentials, _credentials) ||
        generation != _folderRequestGeneration) {
      return;
    }
    switch (value) {
      case 'star':
        await _setMailStarred([message], !message.isFlagged);
      case 'read':
        await _setMailRead([message], !message.isSeen);
      case 'delete':
        await _deleteMailRows([message]);
      case 'mute':
        await _setSenderMuted(message);
      case 'select':
        _setSelectionMode(true);
        _toggleSelectMessage(message.identityKey);
    }
  }

  bool get _showMutedGroup =>
      !_showRadar &&
      _collection == MailCollection.folder &&
      _currentFolder == MailFolder.inbox &&
      _searchQuery.isEmpty &&
      _interactionSettings.mutedSenders.isNotEmpty;

  Widget _mutedGroupTile() => Material(
    color: context.bnbuTheme.surface,
    child: ListTile(
      key: const ValueKey('mail-muted-group'),
      leading: const Icon(Icons.notifications_off_outlined),
      title: const BnbuText('免提醒邮件'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _chooseCollection('muted'),
    ),
  );
}
