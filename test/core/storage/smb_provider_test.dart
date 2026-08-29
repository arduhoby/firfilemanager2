import 'dart:io';
import 'dart:async';

import 'package:fir_file_manager/core/storage/models/connection_profile.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/core/storage/providers/smb_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:smb_connect/smb_connect.dart';

class _MockSmbConnect extends Mock implements SmbConnect {}

SmbFile _file(String path) => SmbFile(path, path, 'share', 0, 0, 0, 0, 0, true);
void main() {
  setUpAll(() {
    registerFallbackValue(SmbFile.notExists('', '', 'share'));
  });

  test(
    'serializes directory listings before disconnecting the client',
    () async {
      final client = _MockSmbConnect();
      final firstListingGate = Completer<void>();
      var activeListings = 0;
      var maximumConcurrentListings = 0;
      var listingCalls = 0;

      when(() => client.listShares()).thenAnswer((_) async {
        listingCalls++;
        activeListings++;
        if (activeListings > maximumConcurrentListings) {
          maximumConcurrentListings = activeListings;
        }
        if (listingCalls == 1) await firstListingGate.future;
        activeListings--;
        return <SmbFile>[];
      });
      when(() => client.close()).thenAnswer((_) async {});

      final provider = SmbProvider.withClient(
        profile: ConnectionProfile(type: ConnectionType.smb, name: 'Test SMB'),
        password: null,
        client: client,
      );

      final firstListing = provider.list('/');
      await Future<void>.delayed(Duration.zero);
      final secondListing = provider.list('/');
      final disconnect = provider.disconnect();
      await Future<void>.delayed(Duration.zero);

      expect(listingCalls, 1);
      verifyNever(() => client.close());

      firstListingGate.complete();
      await Future.wait([firstListing, secondListing]);
      await disconnect;

      expect(listingCalls, 2);
      expect(maximumConcurrentListings, 1);
      verify(() => client.close()).called(1);
    },
  );

  test(
    'replaces an existing SMB file through staging and backup names',
    () async {
      final client = _MockSmbConnect();
      final temporary = await Directory.systemTemp.createTemp('fir-smb-write-');
      addTearDown(() => temporary.delete(recursive: true));
      final files = <String, SmbFile>{
        '/share/report.txt': _file('/share/report.txt'),
      };

      when(() => client.file(any())).thenAnswer((invocation) async {
        final path = invocation.positionalArguments.single as String;
        return files[path] ?? SmbFile.notExists(path, path, 'share');
      });
      when(() => client.createFile(any())).thenAnswer((invocation) async {
        final path = invocation.positionalArguments.single as String;
        final file = _file(path);
        files[path] = file;
        return file;
      });
      when(
        () => client.openWrite(any()),
      ).thenAnswer((_) async => File('${temporary.path}/payload').openWrite());
      when(() => client.rename(any(), any())).thenAnswer((invocation) async {
        final source = invocation.positionalArguments[0] as SmbFile;
        final destination = invocation.positionalArguments[1] as String;
        files.remove(source.path);
        final renamed = _file(destination);
        files[destination] = renamed;
        return renamed;
      });
      when(() => client.delete(any())).thenAnswer((invocation) async {
        final file = invocation.positionalArguments.single as SmbFile;
        files.remove(file.path);
        return file;
      });
      final provider = SmbProvider.withClient(
        profile: ConnectionProfile(type: ConnectionType.smb, name: 'Test SMB'),
        password: null,
        client: client,
      );

      final updates = await provider
          .write('/share/report.txt', Stream.value([1, 2, 3]))
          .toList();

      expect(updates.last.state.name, 'completed');
      expect(files.containsKey('/share/report.txt'), isTrue);
      expect(files.keys.where((path) => path.contains('.fir-part-')), isEmpty);
      expect(
        files.keys.where((path) => path.contains('.fir-backup-')),
        isEmpty,
      );
      verifyNever(() => client.createFile('/share/report.txt'));
      verify(
        () => client.createFile(any(that: contains('.fir-part-'))),
      ).called(1);
      verify(
        () => client.rename(any(), any(that: contains('.fir-backup-'))),
      ).called(1);
      verify(() => client.rename(any(), '/share/report.txt')).called(1);
    },
  );
  test('writes new SMB files directly without staging rename', () async {
    final client = _MockSmbConnect();
    final temporary = await Directory.systemTemp.createTemp('fir-smb-new-');
    addTearDown(() => temporary.delete(recursive: true));
    final files = <String, SmbFile>{};

    when(() => client.file(any())).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.single as String;
      return files[path] ?? SmbFile.notExists(path, path, 'share');
    });
    when(() => client.createFile(any())).thenAnswer((invocation) async {
      final path = invocation.positionalArguments.single as String;
      final file = _file(path);
      files[path] = file;
      return file;
    });
    when(
      () => client.openWrite(any()),
    ).thenAnswer((_) async => File('${temporary.path}/payload').openWrite());

    final provider = SmbProvider.withClient(
      profile: ConnectionProfile(type: ConnectionType.smb, name: 'Test SMB'),
      password: null,
      client: client,
    );

    final updates = await provider
        .write('/share/new.txt', Stream.value([1, 2, 3]))
        .toList();

    expect(updates.last.state, TransferState.completed);
    verify(() => client.createFile('/share/new.txt')).called(1);
    verifyNever(() => client.rename(any(), any()));
  });
}
