import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_bulk_actions.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _credentials = MailAccessCredentials(
  userId: 'bulk-fixture',
  emailAddress: 'bulk@example.test',
  password: 'synthetic-only',
);

class _PagedMailService extends MailService {
  final events = <String>[];
  final writes = <int>[];
  int? badPage;
  int? failedPage;
  void Function(int)? onFetch;
  void Function()? onWrite;

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    expect(credentials, same(_credentials));
    expect(folder, MailFolder.inbox);
    expect(expectedMailboxUidValidity, page == 1 ? null : 42);
    events.add('fetch:$page');
    if (page == failedPage) {
      throw const MailServiceException('Synthetic failure');
    }
    onFetch?.call(page);
    return MailFolderSnapshot(
      emailAddress: credentials.emailAddress,
      incomingServer: 'imap.example.test',
      outgoingServer: 'smtp.example.test',
      fetchedAt: DateTime(2026),
      folder: folder,
      totalMessages: 451,
      currentPage: page,
      pageSize: pageSize,
      mailboxUidValidity: page == badPage ? 43 : 42,
      messages: List.generate(
        451,
        (index) => MailMessageSummary(
          uid: index + 1,
          subject: 'Fixture',
          sender: 'sender@example.test',
          preview: '',
          hasHtmlBody: false,
          date: DateTime(2026),
          isSeen: index == 0,
          mailboxUidValidity: 42,
        ),
      ).skip((page - 1) * pageSize).take(pageSize).toList(),
    );
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {
    expect(credentials, same(_credentials));
    expect(folder, MailFolder.inbox);
    expect(expectedMailboxUidValidity, 42);
    expect(uids.length, lessThanOrEqualTo(200));
    events.add('write');
    writes.addAll(uids);
    onWrite?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<int> run(_PagedMailService service, [bool Function()? current]) =>
      markMailFolderRead(
        service: service,
        credentials: _credentials,
        folder: MailFolder.inbox,
        isCurrent: current ?? () => true,
      );

  test(
    'all pages are enumerated before writes; seen mail is excluded',
    () async {
      final service = _PagedMailService();
      expect(await run(service), 450);
      expect(service.events, [
        'fetch:1',
        'fetch:2',
        'fetch:3',
        'write',
        'write',
        'write',
      ]);
      expect(service.writes, List.generate(450, (index) => index + 2));
    },
  );

  test('changed mailbox validity aborts without any write', () async {
    final service = _PagedMailService()..badPage = 2;
    await expectLater(run(service), throwsA(isA<MailServiceException>()));
    expect(service.writes, isEmpty);
  });

  test('fetch failure cannot silently mark an incomplete list', () async {
    final service = _PagedMailService()..failedPage = 2;
    await expectLater(run(service), throwsA(isA<MailServiceException>()));
    expect(service.writes, isEmpty);
  });

  test(
    'account or folder switch after a fetch cancels before writing',
    () async {
      var current = true;
      final service = _PagedMailService()..onFetch = (_) => current = false;
      expect(await run(service, () => current), 0);
      expect(service.writes, isEmpty);
    },
  );

  test('account switch during a write prevents remaining batches', () async {
    var current = true;
    final service = _PagedMailService()..onWrite = () => current = false;
    expect(await run(service, () => current), 200);
    expect(service.writes.length, 200);
  });
}
