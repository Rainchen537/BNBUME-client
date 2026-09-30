import '../models/mail_models.dart';
import 'mail_service.dart';

/// Enumerate before mutating so unread-only pagination cannot skip messages.
/// UIDVALIDITY pins every read and write to the same mailbox incarnation.
Future<int> markMailFolderRead({
  required MailService service,
  required MailAccessCredentials credentials,
  required MailFolder folder,
  required bool Function() isCurrent,
}) async {
  final unread = <int>{};
  int? validity;
  for (var page = 1; ; page++) {
    if (!isCurrent()) return 0;
    final snapshot = await service.fetchFolder(
      credentials: credentials,
      folder: folder,
      page: page,
      pageSize: 200,
      expectedMailboxUidValidity: validity,
    );
    if (!isCurrent()) return 0;
    if (snapshot.mailboxUidValidity == null ||
        (validity != null && validity != snapshot.mailboxUidValidity)) {
      throw const MailServiceException('邮箱内容已变化，请刷新后重试。');
    }
    validity = snapshot.mailboxUidValidity;
    unread.addAll(snapshot.messages.where((m) => !m.isSeen).map((m) => m.uid));
    if (page * snapshot.pageSize >= snapshot.totalMessages) break;
    if (snapshot.messages.isEmpty) {
      throw const MailServiceException('暂时无法加载全部邮件，请刷新后重试。');
    }
  }
  final uids = unread.toList();
  var changed = 0;
  for (var start = 0; start < uids.length; start += 200) {
    if (!isCurrent()) return changed;
    final batch = uids.skip(start).take(200).toList();
    await service.markMessagesSeen(
      credentials: credentials,
      folder: folder,
      uids: batch,
      expectedMailboxUidValidity: validity,
    );
    changed += batch.length;
  }
  return changed;
}
