// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Fir File Manager';

  @override
  String get navLocal => 'Local';

  @override
  String get navConnections => 'Connections';

  @override
  String get navServer => 'Server';

  @override
  String get navSettings => 'Settings';

  @override
  String get categoryImages => 'Images';

  @override
  String get categoryDocuments => 'Documents';

  @override
  String get categoryAudio => 'Audio';

  @override
  String get categoryVideo => 'Video';

  @override
  String get categoryDownloads => 'Downloads';

  @override
  String get categoryMainStorage => 'Main Storage';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionMove => 'Move';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionRename => 'Rename';

  @override
  String get actionNewFolder => 'New Folder';

  @override
  String get actionPaste => 'Paste';

  @override
  String get actionSelectAll => 'Select All';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionOpen => 'Open';

  @override
  String get actionOpenDefault => 'Open with Default Application';

  @override
  String get actionOpenWith => 'Open With';

  @override
  String get actionChooseApplication => 'Choose Application…';

  @override
  String get actionProperties => 'Properties';

  @override
  String get actionRevealInFinder => 'Reveal in Finder';

  @override
  String get actionCompress => 'Compress';

  @override
  String get actionCompressZip => 'Compress to ZIP';

  @override
  String get actionCompressTar => 'Compress to TAR';

  @override
  String get actionCompressTarGz => 'Compress to TAR.GZ';

  @override
  String get actionExtract => 'Extract Here';

  @override
  String get actionExtractTo => 'Extract to…';

  @override
  String get actionClose => 'Close';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionSave => 'Save';

  @override
  String get actionConnect => 'Connect';

  @override
  String get actionDisconnect => 'Disconnect';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionRemove => 'Remove';

  @override
  String get sortByName => 'Name';

  @override
  String get sortByDate => 'Date Modified';

  @override
  String get sortBySize => 'Size';

  @override
  String get sortByType => 'Type';

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get panelLeft => 'Left Panel';

  @override
  String get panelRight => 'Right Panel';

  @override
  String get panelActive => 'Active Panel';

  @override
  String operationCopying(int count) {
    return 'Copying $count items…';
  }

  @override
  String operationMoving(int count) {
    return 'Moving $count items…';
  }

  @override
  String operationDeleting(int count) {
    return 'Deleting $count items…';
  }

  @override
  String get operationComplete => 'Operation complete';

  @override
  String operationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String operationProgress(int current, int total) {
    return '$current / $total';
  }

  @override
  String get connectionTypeSftp => 'SFTP';

  @override
  String get connectionTypeFtp => 'FTP';

  @override
  String get connectionTypeWebdav => 'WebDAV';

  @override
  String get connectionTypeSmb => 'SMB';

  @override
  String get connectionTypeGdrive => 'Google Drive';

  @override
  String get connectionTypeDropbox => 'Dropbox';

  @override
  String get connectionHost => 'Host';

  @override
  String get connectionPort => 'Port';

  @override
  String get connectionUsername => 'Username';

  @override
  String get connectionPassword => 'Password';

  @override
  String get connectionName => 'Connection Name';

  @override
  String get connectionAuthMethod => 'Authentication Method';

  @override
  String get connectionAuthPassword => 'Password';

  @override
  String get connectionAuthKey => 'Private Key';

  @override
  String get connectionAddNew => 'Add New Connection';

  @override
  String get connectionEdit => 'Edit Connection';

  @override
  String get connectionTest => 'Test Connection';

  @override
  String get connectionTestSuccess => 'Connection successful';

  @override
  String connectionTestFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get connectionDisconnected => 'Disconnected';

  @override
  String get connectionReconnecting => 'Reconnecting…';

  @override
  String get serverStart => 'Start Server';

  @override
  String get serverStop => 'Stop Server';

  @override
  String get serverRunning => 'Server is running';

  @override
  String get serverStopped => 'Server is stopped';

  @override
  String get serverSharedFolder => 'Shared Folder';

  @override
  String get serverPort => 'Port';

  @override
  String get serverUsername => 'Username';

  @override
  String get serverPassword => 'Password';

  @override
  String get serverActiveConnections => 'Active Connections';

  @override
  String get serverNoConnections => 'No active connections';

  @override
  String get serverFtp => 'FTP Server';

  @override
  String get serverWebdav => 'WebDAV Server';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get errorAccessDenied => 'Access denied';

  @override
  String errorNotFound(String path) {
    return 'Not found: $path';
  }

  @override
  String errorAlreadyExists(String path) {
    return 'Already exists: $path';
  }

  @override
  String errorNetwork(String error) {
    return 'Network error: $error';
  }

  @override
  String get errorTimeout => 'Operation timed out';

  @override
  String get errorUnknown => 'An unknown error occurred';

  @override
  String get confirmDeleteTitle => 'Delete';

  @override
  String confirmDeleteMessage(int count) {
    return 'Are you sure you want to delete $count item(s)?';
  }

  @override
  String get confirmOverwriteTitle => 'Overwrite';

  @override
  String confirmOverwriteMessage(String name) {
    return '$name already exists. Overwrite?';
  }

  @override
  String get propertiesName => 'Name';

  @override
  String get propertiesPath => 'Path';

  @override
  String get propertiesSize => 'Size';

  @override
  String get propertiesType => 'Type';

  @override
  String get propertiesModified => 'Date Modified';

  @override
  String get propertiesPermissions => 'Permissions';

  @override
  String get propertiesFolder => 'Folder';

  @override
  String get propertiesFile => 'File';

  @override
  String itemsSelected(int count) {
    return '$count selected';
  }

  @override
  String itemsCount(int count) {
    return '$count items';
  }

  @override
  String get emptyFolder => 'This folder is empty';

  @override
  String get progressCurrentFile => 'Current file';

  @override
  String get progressOverall => 'Overall';

  @override
  String progressRemaining(String size) {
    return '$size remaining';
  }

  @override
  String progressSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String progressEta(String time) {
    return 'ETA $time';
  }

  @override
  String get progressEtaCalculating => 'Calculating ETA…';

  @override
  String get syncPreviewTitle => 'Smart Synchronization';

  @override
  String get syncSourcePanel => 'Selected panel';

  @override
  String get syncDestinationPanel => 'Destination panel';

  @override
  String syncSelectedSummary(int selected, int total) {
    return '$selected of $total files selected';
  }

  @override
  String get syncSelectChanges => 'Select differences';

  @override
  String get syncSelectAll => 'Select all';

  @override
  String get syncClearAll => 'Clear all';

  @override
  String syncStartSelected(int count) {
    return 'Synchronize ($count)';
  }

  @override
  String get syncColumnFile => 'File';

  @override
  String get syncColumnSize => 'Size';

  @override
  String get syncColumnModified => 'Modified';

  @override
  String get syncColumnStatus => 'Comparison';

  @override
  String get syncStatusNew => 'New';

  @override
  String get syncStatusDifferent => 'Different';

  @override
  String get syncStatusEqual => 'Equal';

  @override
  String get syncMissingDestination => 'Not present';

  @override
  String get syncNoChanges =>
      'No differences found. The destination already matches the selected panel.';

  @override
  String syncResultSummary(int updated, int created) {
    return 'Synchronization completed: $updated files replaced and $created new files copied.';
  }

  @override
  String syncResultFailures(int updated, int created, int failed) {
    return 'Synchronization finished: $updated files replaced, $created new files copied, $failed failed.';
  }

  @override
  String get syncCancelled => 'Synchronization cancelled.';

  @override
  String get syncStatusInaccessible => 'Inaccessible';

  @override
  String get syncShowSelectedOnly => 'Selected only';

  @override
  String get syncSearchHint => 'Search files';

  @override
  String get syncSaveJob => 'Save task…';

  @override
  String get syncEditJob => 'Edit synchronization task';

  @override
  String get syncJobName => 'Task name';

  @override
  String get syncJobNameRequired => 'Enter a task name.';

  @override
  String get syncWeekdayRequired => 'Select at least one weekday.';

  @override
  String get syncSchedule => 'Schedule';

  @override
  String get syncScheduleManual => 'Manual';

  @override
  String get syncScheduleOnce => 'Once';

  @override
  String get syncScheduleDaily => 'Every day';

  @override
  String get syncScheduleWeekly => 'Every week';

  @override
  String get syncJobEnabled => 'Automation enabled';

  @override
  String get syncRequireWifi => 'Run only on Wi-Fi';

  @override
  String get syncAllowMobileData => 'Allow mobile data';

  @override
  String get syncRequireCharging => 'Run only while charging';

  @override
  String get weekdayMonday => 'Mon';

  @override
  String get weekdayTuesday => 'Tue';

  @override
  String get weekdayWednesday => 'Wed';

  @override
  String get weekdayThursday => 'Thu';

  @override
  String get weekdayFriday => 'Fri';

  @override
  String get weekdaySaturday => 'Sat';

  @override
  String get weekdaySunday => 'Sun';

  @override
  String syncJobSaved(String name) {
    return '\"$name\" was saved.';
  }

  @override
  String syncJobNameConflict(String name) {
    return 'A task named \"$name\" already exists.';
  }

  @override
  String get syncJobsTitle => 'Fir SmartSync';

  @override
  String get syncJobsSubtitle => 'Saved synchronization tasks';

  @override
  String get syncJobsEmpty => 'No synchronization tasks have been saved.';

  @override
  String get syncJobsEmptyHint =>
      'Open synchronization from a file panel, choose the files, then select Save task.';

  @override
  String syncRunSucceeded(int updated, int created) {
    return 'Synchronization completed: $updated updated, $created created.';
  }

  @override
  String syncRunFailed(int failed) {
    return 'Synchronization failed for $failed files.';
  }

  @override
  String get syncDeleteJob => 'Delete synchronization task';

  @override
  String syncDeleteJobConfirm(String name) {
    return 'Delete \"$name\" and its schedule?';
  }

  @override
  String syncHistoryFor(String name) {
    return '$name history';
  }

  @override
  String get syncHistoryEmpty => 'No runs have been recorded.';

  @override
  String get syncFailedLabel => 'Failed';

  @override
  String get syncFailureDetails => 'Failure details';

  @override
  String get syncRunNow => 'Run now';

  @override
  String get syncHistory => 'History';

  @override
  String get panelAdd => 'Add panel';

  @override
  String get panelClose => 'Close panel';

  @override
  String panelNumber(int number) {
    return 'Panel $number';
  }

  @override
  String get targetPanels => 'Target panels';

  @override
  String get targetSourcePanel => 'Source panel';

  @override
  String get targetOperationSync => 'Sync';

  @override
  String targetSelectedSummary(int selected, int total) {
    return '$selected of $total selected';
  }

  @override
  String get targetSameLocation => 'Same location as the source panel';

  @override
  String get targetConnectionUnavailable => 'Connection is unavailable';

  @override
  String get targetLocalPanelRequired =>
      'Select a local destination panel for compression';

  @override
  String get targetContinue => 'Continue';

  @override
  String get multiTransferResultTitle => 'Transfer results';

  @override
  String multiTransferSuccess(int count) {
    return 'Transfer completed for $count target panels';
  }

  @override
  String multiTransferPartial(int successful, int total) {
    return '$successful of $total target panels completed successfully';
  }

  @override
  String get multiTransferCompleted => 'Completed';

  @override
  String get multiTransferFailed => 'Failed';

  @override
  String get multiTransferCancelled => 'Cancelled';

  @override
  String get multiTransferSkipped => 'Not started';

  @override
  String get multiTransferSourcePreserved =>
      'The source was preserved because not every target completed successfully.';

  @override
  String get multiArchiveResultTitle => 'Compression results';

  @override
  String multiArchiveSuccess(int count) {
    return 'Archive created in $count target panels';
  }

  @override
  String get archiveLocalSourceRequired =>
      'Compression currently supports files from local panels only.';

  @override
  String get multiSyncResultTitle => 'Synchronization results';

  @override
  String multiSyncSummary(int successful, int total) {
    return '$successful of $total target panels completed successfully';
  }

  @override
  String get multiSyncCompleted => 'Synchronization completed';

  @override
  String get multiSyncNoChanges => 'Already up to date';

  @override
  String get multiSyncFailed => 'Synchronization failed';

  @override
  String get multiSyncCancelled => 'Synchronization cancelled';

  @override
  String get multiSyncSkipped => 'Not started';
}
