import 'package:fir_file_manager/core/storage/models/connection_profile.dart';
import 'package:fir_file_manager/core/storage/providers/cloud/google_drive_provider.dart';
import 'package:fir_file_manager/core/storage/storage_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder OAuth client ID is rejected before browser launch', () async {
    final provider = GoogleDriveProvider(
      profile: ConnectionProfile(
        type: ConnectionType.gdrive,
        name: 'Google Drive',
        authMethod: AuthMethod.oauth2,
      ),
      clientId: 'YOUR_GOOGLE_DRIVE_CLIENT_ID',
      clientSecret: 'YOUR_GOOGLE_DRIVE_CLIENT_SECRET',
    );

    await expectLater(
      provider.connect(),
      throwsA(
        isA<StorageException>().having(
          (error) => error.message,
          'message',
          contains('Google Drive OAuth yapılandırılmamış'),
        ),
      ),
    );
  });
}
