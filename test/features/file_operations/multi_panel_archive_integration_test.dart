import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fir_file_manager/core/storage/models/file_entry.dart';
import 'package:fir_file_manager/core/storage/models/transfer_progress.dart';
import 'package:fir_file_manager/features/file_operations/archive_service.dart';
import 'package:fir_file_manager/features/file_operations/file_operations_state.dart';
import 'package:fir_file_manager/features/file_operations/multi_panel_transfer_coordinator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('archive space policy keeps the agreed safety margin', () {
    expect(
      ArchiveSpacePolicy.requiredBytes(1024, format: ArchiveFormat.zip),
      1024 + ArchiveSpacePolicy.minimumSafetyBytes,
    );
    expect(
      ArchiveSpacePolicy.requiredBytes(1024, format: ArchiveFormat.tarGz),
      2048 + ArchiveSpacePolicy.minimumSafetyBytes,
    );
  });

  test('creates the same ZIP archive in every selected local panel', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'fir-file-manager-multi-archive-',
    );
    addTearDown(() => temporaryRoot.delete(recursive: true));

    final sourceDirectory = Directory(p.join(temporaryRoot.path, 'source'));
    final secondTarget = Directory(p.join(temporaryRoot.path, 'target-2'));
    final thirdTarget = Directory(p.join(temporaryRoot.path, 'target-3'));
    await sourceDirectory.create();
    await secondTarget.create();
    await thirdTarget.create();

    final sourceFile = File(p.join(sourceDirectory.path, 'example.txt'));
    await sourceFile.writeAsString('multi-panel archive');
    final entry = FileEntry(
      name: 'example.txt',
      path: sourceFile.path,
      isDirectory: false,
      size: await sourceFile.length(),
    );

    const thirdPanel = PanelId('panel-3');
    const targets = [PanelId.b, thirdPanel];
    final destinationPaths = {
      PanelId.b: secondTarget.path,
      thirdPanel: thirdTarget.path,
    };
    final archiveService = container.read(archiveServiceProvider.notifier);
    final finalProgress = <TransferProgress>[];
    final manifest = await archiveService.createManifest([entry]);
    expect(manifest.totalFiles, 1);
    expect(manifest.totalBytes, await sourceFile.length());
    await archiveService.checkManifestAvailableSpace(
      manifest: manifest,
      destinationDirectories: destinationPaths.values,
      format: ArchiveFormat.zip,
    );
    var compressionCalls = 0;
    var copyCalls = 0;
    String? sourceArchivePath;

    final result = await const MultiPanelTransferCoordinator().execute(
      operation: TransferOperation.zip,
      targetPanelIds: targets,
      transferTarget: (panelId) async {
        TransferProgress? completed;
        final isFirst = compressionCalls == 0;
        if (isFirst) {
          compressionCalls++;
        } else {
          copyCalls++;
        }
        final stream = isFirst
            ? archiveService.compressManifest(
                manifest: manifest,
                destDir: destinationPaths[panelId]!,
                archiveName: 'bundle',
                format: ArchiveFormat.zip,
              )
            : archiveService.copyArchiveTo(
                manifest: manifest,
                sourceArchivePath: sourceArchivePath!,
                destDir: destinationPaths[panelId]!,
                archiveName: 'bundle',
                format: ArchiveFormat.zip,
              );
        await for (final progress in stream) {
          if (progress.isFinished) completed = progress;
        }
        if (isFirst && completed?.state == TransferState.completed) {
          sourceArchivePath = archiveService.archivePath(
            destinationDirectory: destinationPaths[panelId]!,
            archiveName: 'bundle',
            format: ArchiveFormat.zip,
          );
        }
        return completed!;
      },
      publishFinalProgress: finalProgress.add,
    );

    expect(result.isSuccessful, isTrue);
    expect(compressionCalls, 1);
    expect(copyCalls, 1);
    expect(File(p.join(secondTarget.path, 'bundle.zip')).existsSync(), isTrue);
    expect(File(p.join(thirdTarget.path, 'bundle.zip')).existsSync(), isTrue);
    expect(finalProgress, hasLength(1));
    expect(finalProgress.single.state, TransferState.completed);
  });

  test('streams ZIP, TAR and TAR.GZ including hidden UTF-8 paths', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = await Directory.systemTemp.createTemp(
      'fir-file-manager-archive-formats-',
    );
    addTearDown(() => root.delete(recursive: true));

    final source = Directory(p.join(root.path, 'Türkçe klasör'));
    final gitDirectory = Directory(p.join(source.path, '.git'));
    await gitDirectory.create(recursive: true);
    await File(p.join(source.path, 'öğe.txt')).writeAsString('UTF-8 içerik');
    await File(p.join(gitDirectory.path, 'config')).writeAsString('[core]');
    final entry = FileEntry(
      name: p.basename(source.path),
      path: source.path,
      isDirectory: true,
    );
    final service = container.read(archiveServiceProvider.notifier);

    for (final format in ArchiveFormat.values) {
      await for (final progress in service.compress(
        entries: [entry],
        destDir: root.path,
        archiveName: format.name,
        format: format,
      )) {
        if (progress.isFinished) {
          expect(progress.state, TransferState.completed);
          expect(progress.totalFiles, 2);
        }
      }
    }

    final zip = ZipDecoder().decodeBytes(
      await File(p.join(root.path, 'zip.zip')).readAsBytes(),
    );
    final tar = TarDecoder().decodeBytes(
      await File(p.join(root.path, 'tar.tar')).readAsBytes(),
    );
    final tarGz = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(
        await File(p.join(root.path, 'tarGz.tar.gz')).readAsBytes(),
      ),
    );
    for (final archive in [zip, tar, tarGz]) {
      final names = archive.files.map((file) => file.name).toSet();
      expect(names, contains('Türkçe klasör/öğe.txt'));
      expect(names, contains('Türkçe klasör/.git/config'));
    }
    expect(
      root.listSync().where((entity) => entity.path.contains('.partial-')),
      isEmpty,
    );
  });

  test('creates a password-protected ZIP through the shared engine', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = await Directory.systemTemp.createTemp(
      'fir-file-manager-password-archive-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = File(p.join(root.path, 'şifreli-öğe.txt'));
    await source.writeAsString('gizli içerik');
    final service = container.read(archiveServiceProvider.notifier);

    await service
        .compress(
          entries: [
            FileEntry(
              name: p.basename(source.path),
              path: source.path,
              isDirectory: false,
              size: await source.length(),
            ),
          ],
          destDir: root.path,
          archiveName: 'korumalı',
          format: ArchiveFormat.zip,
          password: 'güçlü-şifre',
        )
        .last;

    final archive = ZipDecoder().decodeBytes(
      await File(p.join(root.path, 'korumalı.zip')).readAsBytes(),
      password: 'güçlü-şifre',
      verify: true,
    );
    expect(archive.files.single.name, 'şifreli-öğe.txt');
    expect(utf8.decode(archive.files.single.content), 'gizli içerik');
  });

  test('cancel keeps an existing archive and removes partial output', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final root = await Directory.systemTemp.createTemp(
      'fir-file-manager-cancel-archive-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = File(p.join(root.path, 'large.bin'));
    await source.writeAsBytes(List<int>.filled(1024 * 1024, 7));
    final existing = File(p.join(root.path, 'bundle.zip'));
    await existing.writeAsString('existing archive stays intact');
    final service = container.read(archiveServiceProvider.notifier);
    TransferProgress? finalProgress;

    await for (final progress in service.compress(
      entries: [
        FileEntry(
          name: source.uri.pathSegments.last,
          path: source.path,
          isDirectory: false,
          size: await source.length(),
        ),
      ],
      destDir: root.path,
      archiveName: 'bundle',
      format: ArchiveFormat.zip,
    )) {
      if (progress.state == TransferState.inProgress &&
          progress.filesTransferred == 0) {
        service.cancelCurrentOperation();
      }
      if (progress.isFinished) finalProgress = progress;
    }

    expect(finalProgress?.state, TransferState.cancelled);
    expect(await existing.readAsString(), 'existing archive stays intact');
    expect(
      root.listSync().where((entity) => entity.path.contains('.partial-')),
      isEmpty,
    );
  });
}
