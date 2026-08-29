import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Fir File Manager'**
  String get appTitle;

  /// No description provided for @navLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get navLocal;

  /// No description provided for @navConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get navConnections;

  /// No description provided for @navServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get navServer;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @categoryImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get categoryImages;

  /// No description provided for @categoryDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get categoryDocuments;

  /// No description provided for @categoryAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get categoryAudio;

  /// No description provided for @categoryVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get categoryVideo;

  /// No description provided for @categoryDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get categoryDownloads;

  /// No description provided for @categoryMainStorage.
  ///
  /// In en, this message translates to:
  /// **'Main Storage'**
  String get categoryMainStorage;

  /// No description provided for @actionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get actionCopy;

  /// No description provided for @actionMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get actionMove;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get actionRename;

  /// No description provided for @actionNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get actionNewFolder;

  /// No description provided for @actionPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get actionPaste;

  /// No description provided for @actionSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get actionSelectAll;

  /// No description provided for @actionRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get actionRefresh;

  /// No description provided for @actionOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get actionOpen;

  /// No description provided for @actionOpenDefault.
  ///
  /// In en, this message translates to:
  /// **'Open with Default Application'**
  String get actionOpenDefault;

  /// No description provided for @actionOpenWith.
  ///
  /// In en, this message translates to:
  /// **'Open With'**
  String get actionOpenWith;

  /// No description provided for @actionChooseApplication.
  ///
  /// In en, this message translates to:
  /// **'Choose Application…'**
  String get actionChooseApplication;

  /// No description provided for @actionProperties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get actionProperties;

  /// No description provided for @actionRevealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get actionRevealInFinder;

  /// No description provided for @actionCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get actionCompress;

  /// No description provided for @actionCompressZip.
  ///
  /// In en, this message translates to:
  /// **'Compress to ZIP'**
  String get actionCompressZip;

  /// No description provided for @actionCompressTar.
  ///
  /// In en, this message translates to:
  /// **'Compress to TAR'**
  String get actionCompressTar;

  /// No description provided for @actionCompressTarGz.
  ///
  /// In en, this message translates to:
  /// **'Compress to TAR.GZ'**
  String get actionCompressTarGz;

  /// No description provided for @actionExtract.
  ///
  /// In en, this message translates to:
  /// **'Extract Here'**
  String get actionExtract;

  /// No description provided for @actionExtractTo.
  ///
  /// In en, this message translates to:
  /// **'Extract to…'**
  String get actionExtractTo;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get actionRetry;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get actionConnect;

  /// No description provided for @actionDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get actionDisconnect;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortByName;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'Date Modified'**
  String get sortByDate;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortBySize;

  /// No description provided for @sortByType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sortByType;

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @panelLeft.
  ///
  /// In en, this message translates to:
  /// **'Left Panel'**
  String get panelLeft;

  /// No description provided for @panelRight.
  ///
  /// In en, this message translates to:
  /// **'Right Panel'**
  String get panelRight;

  /// No description provided for @panelActive.
  ///
  /// In en, this message translates to:
  /// **'Active Panel'**
  String get panelActive;

  /// No description provided for @operationCopying.
  ///
  /// In en, this message translates to:
  /// **'Copying {count} items…'**
  String operationCopying(int count);

  /// No description provided for @operationMoving.
  ///
  /// In en, this message translates to:
  /// **'Moving {count} items…'**
  String operationMoving(int count);

  /// No description provided for @operationDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting {count} items…'**
  String operationDeleting(int count);

  /// No description provided for @operationComplete.
  ///
  /// In en, this message translates to:
  /// **'Operation complete'**
  String get operationComplete;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String operationFailed(String error);

  /// No description provided for @operationProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String operationProgress(int current, int total);

  /// No description provided for @connectionTypeSftp.
  ///
  /// In en, this message translates to:
  /// **'SFTP'**
  String get connectionTypeSftp;

  /// No description provided for @connectionTypeFtp.
  ///
  /// In en, this message translates to:
  /// **'FTP'**
  String get connectionTypeFtp;

  /// No description provided for @connectionTypeWebdav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get connectionTypeWebdav;

  /// No description provided for @connectionTypeSmb.
  ///
  /// In en, this message translates to:
  /// **'SMB'**
  String get connectionTypeSmb;

  /// No description provided for @connectionTypeGdrive.
  ///
  /// In en, this message translates to:
  /// **'Google Drive'**
  String get connectionTypeGdrive;

  /// No description provided for @connectionTypeDropbox.
  ///
  /// In en, this message translates to:
  /// **'Dropbox'**
  String get connectionTypeDropbox;

  /// No description provided for @connectionHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get connectionHost;

  /// No description provided for @connectionPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get connectionPort;

  /// No description provided for @connectionUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get connectionUsername;

  /// No description provided for @connectionPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get connectionPassword;

  /// No description provided for @connectionName.
  ///
  /// In en, this message translates to:
  /// **'Connection Name'**
  String get connectionName;

  /// No description provided for @connectionAuthMethod.
  ///
  /// In en, this message translates to:
  /// **'Authentication Method'**
  String get connectionAuthMethod;

  /// No description provided for @connectionAuthPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get connectionAuthPassword;

  /// No description provided for @connectionAuthKey.
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get connectionAuthKey;

  /// No description provided for @connectionAddNew.
  ///
  /// In en, this message translates to:
  /// **'Add New Connection'**
  String get connectionAddNew;

  /// No description provided for @connectionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get connectionEdit;

  /// No description provided for @connectionTest.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get connectionTest;

  /// No description provided for @connectionTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get connectionTestSuccess;

  /// No description provided for @connectionTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionTestFailed(String error);

  /// No description provided for @connectionDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get connectionDisconnected;

  /// No description provided for @connectionReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get connectionReconnecting;

  /// No description provided for @serverStart.
  ///
  /// In en, this message translates to:
  /// **'Start Server'**
  String get serverStart;

  /// No description provided for @serverStop.
  ///
  /// In en, this message translates to:
  /// **'Stop Server'**
  String get serverStop;

  /// No description provided for @serverRunning.
  ///
  /// In en, this message translates to:
  /// **'Server is running'**
  String get serverRunning;

  /// No description provided for @serverStopped.
  ///
  /// In en, this message translates to:
  /// **'Server is stopped'**
  String get serverStopped;

  /// No description provided for @serverSharedFolder.
  ///
  /// In en, this message translates to:
  /// **'Shared Folder'**
  String get serverSharedFolder;

  /// No description provided for @serverPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get serverPort;

  /// No description provided for @serverUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get serverUsername;

  /// No description provided for @serverPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get serverPassword;

  /// No description provided for @serverActiveConnections.
  ///
  /// In en, this message translates to:
  /// **'Active Connections'**
  String get serverActiveConnections;

  /// No description provided for @serverNoConnections.
  ///
  /// In en, this message translates to:
  /// **'No active connections'**
  String get serverNoConnections;

  /// No description provided for @serverFtp.
  ///
  /// In en, this message translates to:
  /// **'FTP Server'**
  String get serverFtp;

  /// No description provided for @serverWebdav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Server'**
  String get serverWebdav;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @errorAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Access denied'**
  String get errorAccessDenied;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found: {path}'**
  String errorNotFound(String path);

  /// No description provided for @errorAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Already exists: {path}'**
  String errorAlreadyExists(String path);

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error: {error}'**
  String errorNetwork(String error);

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Operation timed out'**
  String get errorTimeout;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred'**
  String get errorUnknown;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} item(s)?'**
  String confirmDeleteMessage(int count);

  /// No description provided for @confirmOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get confirmOverwriteTitle;

  /// No description provided for @confirmOverwriteMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} already exists. Overwrite?'**
  String confirmOverwriteMessage(String name);

  /// No description provided for @propertiesName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get propertiesName;

  /// No description provided for @propertiesPath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get propertiesPath;

  /// No description provided for @propertiesSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get propertiesSize;

  /// No description provided for @propertiesType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get propertiesType;

  /// No description provided for @propertiesModified.
  ///
  /// In en, this message translates to:
  /// **'Date Modified'**
  String get propertiesModified;

  /// No description provided for @propertiesPermissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get propertiesPermissions;

  /// No description provided for @propertiesFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get propertiesFolder;

  /// No description provided for @propertiesFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get propertiesFile;

  /// No description provided for @itemsSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String itemsSelected(int count);

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(int count);

  /// No description provided for @emptyFolder.
  ///
  /// In en, this message translates to:
  /// **'This folder is empty'**
  String get emptyFolder;

  /// No description provided for @progressCurrentFile.
  ///
  /// In en, this message translates to:
  /// **'Current file'**
  String get progressCurrentFile;

  /// No description provided for @progressOverall.
  ///
  /// In en, this message translates to:
  /// **'Overall'**
  String get progressOverall;

  /// No description provided for @progressRemaining.
  ///
  /// In en, this message translates to:
  /// **'{size} remaining'**
  String progressRemaining(String size);

  /// No description provided for @progressSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String progressSpeed(String speed);

  /// No description provided for @progressEta.
  ///
  /// In en, this message translates to:
  /// **'ETA {time}'**
  String progressEta(String time);

  /// No description provided for @progressEtaCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating ETA…'**
  String get progressEtaCalculating;

  /// No description provided for @syncPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Smart Synchronization'**
  String get syncPreviewTitle;

  /// No description provided for @syncSourcePanel.
  ///
  /// In en, this message translates to:
  /// **'Selected panel'**
  String get syncSourcePanel;

  /// No description provided for @syncDestinationPanel.
  ///
  /// In en, this message translates to:
  /// **'Destination panel'**
  String get syncDestinationPanel;

  /// No description provided for @syncSelectedSummary.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total} files selected'**
  String syncSelectedSummary(int selected, int total);

  /// No description provided for @syncSelectChanges.
  ///
  /// In en, this message translates to:
  /// **'Select differences'**
  String get syncSelectChanges;

  /// No description provided for @syncSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get syncSelectAll;

  /// No description provided for @syncClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get syncClearAll;

  /// No description provided for @syncStartSelected.
  ///
  /// In en, this message translates to:
  /// **'Synchronize ({count})'**
  String syncStartSelected(int count);

  /// No description provided for @syncColumnFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get syncColumnFile;

  /// No description provided for @syncColumnSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get syncColumnSize;

  /// No description provided for @syncColumnModified.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get syncColumnModified;

  /// No description provided for @syncColumnStatus.
  ///
  /// In en, this message translates to:
  /// **'Comparison'**
  String get syncColumnStatus;

  /// No description provided for @syncStatusNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get syncStatusNew;

  /// No description provided for @syncStatusDifferent.
  ///
  /// In en, this message translates to:
  /// **'Different'**
  String get syncStatusDifferent;

  /// No description provided for @syncStatusEqual.
  ///
  /// In en, this message translates to:
  /// **'Equal'**
  String get syncStatusEqual;

  /// No description provided for @syncMissingDestination.
  ///
  /// In en, this message translates to:
  /// **'Not present'**
  String get syncMissingDestination;

  /// No description provided for @syncNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No differences found. The destination already matches the selected panel.'**
  String get syncNoChanges;

  /// No description provided for @syncResultSummary.
  ///
  /// In en, this message translates to:
  /// **'Synchronization completed: {updated} files replaced and {created} new files copied.'**
  String syncResultSummary(int updated, int created);

  /// No description provided for @syncResultFailures.
  ///
  /// In en, this message translates to:
  /// **'Synchronization finished: {updated} files replaced, {created} new files copied, {failed} failed.'**
  String syncResultFailures(int updated, int created, int failed);

  /// No description provided for @syncCancelled.
  ///
  /// In en, this message translates to:
  /// **'Synchronization cancelled.'**
  String get syncCancelled;

  /// No description provided for @syncStatusInaccessible.
  ///
  /// In en, this message translates to:
  /// **'Inaccessible'**
  String get syncStatusInaccessible;

  /// No description provided for @syncShowSelectedOnly.
  ///
  /// In en, this message translates to:
  /// **'Selected only'**
  String get syncShowSelectedOnly;

  /// No description provided for @syncSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search files'**
  String get syncSearchHint;

  /// No description provided for @syncSaveJob.
  ///
  /// In en, this message translates to:
  /// **'Save task…'**
  String get syncSaveJob;

  /// No description provided for @syncEditJob.
  ///
  /// In en, this message translates to:
  /// **'Edit synchronization task'**
  String get syncEditJob;

  /// No description provided for @syncJobName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get syncJobName;

  /// No description provided for @syncJobNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a task name.'**
  String get syncJobNameRequired;

  /// No description provided for @syncWeekdayRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least one weekday.'**
  String get syncWeekdayRequired;

  /// No description provided for @syncSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get syncSchedule;

  /// No description provided for @syncScheduleManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get syncScheduleManual;

  /// No description provided for @syncScheduleOnce.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get syncScheduleOnce;

  /// No description provided for @syncScheduleDaily.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get syncScheduleDaily;

  /// No description provided for @syncScheduleWeekly.
  ///
  /// In en, this message translates to:
  /// **'Every week'**
  String get syncScheduleWeekly;

  /// No description provided for @syncJobEnabled.
  ///
  /// In en, this message translates to:
  /// **'Automation enabled'**
  String get syncJobEnabled;

  /// No description provided for @syncRequireWifi.
  ///
  /// In en, this message translates to:
  /// **'Run only on Wi-Fi'**
  String get syncRequireWifi;

  /// No description provided for @syncAllowMobileData.
  ///
  /// In en, this message translates to:
  /// **'Allow mobile data'**
  String get syncAllowMobileData;

  /// No description provided for @syncRequireCharging.
  ///
  /// In en, this message translates to:
  /// **'Run only while charging'**
  String get syncRequireCharging;

  /// No description provided for @weekdayMonday.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMonday;

  /// No description provided for @weekdayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTuesday;

  /// No description provided for @weekdayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWednesday;

  /// No description provided for @weekdayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThursday;

  /// No description provided for @weekdayFriday.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFriday;

  /// No description provided for @weekdaySaturday.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySaturday;

  /// No description provided for @weekdaySunday.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySunday;

  /// No description provided for @syncJobSaved.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" was saved.'**
  String syncJobSaved(String name);

  /// No description provided for @syncJobNameConflict.
  ///
  /// In en, this message translates to:
  /// **'A task named \"{name}\" already exists.'**
  String syncJobNameConflict(String name);

  /// No description provided for @syncJobsTitle.
  ///
  /// In en, this message translates to:
  /// **'Fir SmartSync'**
  String get syncJobsTitle;

  /// No description provided for @syncJobsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saved synchronization tasks'**
  String get syncJobsSubtitle;

  /// No description provided for @syncJobsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No synchronization tasks have been saved.'**
  String get syncJobsEmpty;

  /// No description provided for @syncJobsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Open synchronization from a file panel, choose the files, then select Save task.'**
  String get syncJobsEmptyHint;

  /// No description provided for @syncRunSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Synchronization completed: {updated} updated, {created} created.'**
  String syncRunSucceeded(int updated, int created);

  /// No description provided for @syncRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Synchronization failed for {failed} files.'**
  String syncRunFailed(int failed);

  /// No description provided for @syncDeleteJob.
  ///
  /// In en, this message translates to:
  /// **'Delete synchronization task'**
  String get syncDeleteJob;

  /// No description provided for @syncDeleteJobConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" and its schedule?'**
  String syncDeleteJobConfirm(String name);

  /// No description provided for @syncHistoryFor.
  ///
  /// In en, this message translates to:
  /// **'{name} history'**
  String syncHistoryFor(String name);

  /// No description provided for @syncHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No runs have been recorded.'**
  String get syncHistoryEmpty;

  /// No description provided for @syncFailedLabel.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get syncFailedLabel;

  /// No description provided for @syncFailureDetails.
  ///
  /// In en, this message translates to:
  /// **'Failure details'**
  String get syncFailureDetails;

  /// No description provided for @syncRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get syncRunNow;

  /// No description provided for @syncHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get syncHistory;

  /// No description provided for @panelAdd.
  ///
  /// In en, this message translates to:
  /// **'Add panel'**
  String get panelAdd;

  /// No description provided for @panelClose.
  ///
  /// In en, this message translates to:
  /// **'Close panel'**
  String get panelClose;

  /// No description provided for @panelNumber.
  ///
  /// In en, this message translates to:
  /// **'Panel {number}'**
  String panelNumber(int number);

  /// No description provided for @targetPanels.
  ///
  /// In en, this message translates to:
  /// **'Target panels'**
  String get targetPanels;

  /// No description provided for @targetSourcePanel.
  ///
  /// In en, this message translates to:
  /// **'Source panel'**
  String get targetSourcePanel;

  /// No description provided for @targetOperationSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get targetOperationSync;

  /// No description provided for @targetSelectedSummary.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total} selected'**
  String targetSelectedSummary(int selected, int total);

  /// No description provided for @targetSameLocation.
  ///
  /// In en, this message translates to:
  /// **'Same location as the source panel'**
  String get targetSameLocation;

  /// No description provided for @targetConnectionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Connection is unavailable'**
  String get targetConnectionUnavailable;

  /// No description provided for @targetLocalPanelRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a local destination panel for compression'**
  String get targetLocalPanelRequired;

  /// No description provided for @targetContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get targetContinue;

  /// No description provided for @multiTransferResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfer results'**
  String get multiTransferResultTitle;

  /// No description provided for @multiTransferSuccess.
  ///
  /// In en, this message translates to:
  /// **'Transfer completed for {count} target panels'**
  String multiTransferSuccess(int count);

  /// No description provided for @multiTransferPartial.
  ///
  /// In en, this message translates to:
  /// **'{successful} of {total} target panels completed successfully'**
  String multiTransferPartial(int successful, int total);

  /// No description provided for @multiTransferCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get multiTransferCompleted;

  /// No description provided for @multiTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get multiTransferFailed;

  /// No description provided for @multiTransferCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get multiTransferCancelled;

  /// No description provided for @multiTransferSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get multiTransferSkipped;

  /// No description provided for @multiTransferSourcePreserved.
  ///
  /// In en, this message translates to:
  /// **'The source was preserved because not every target completed successfully.'**
  String get multiTransferSourcePreserved;

  /// No description provided for @multiArchiveResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Compression results'**
  String get multiArchiveResultTitle;

  /// No description provided for @multiArchiveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Archive created in {count} target panels'**
  String multiArchiveSuccess(int count);

  /// No description provided for @archiveLocalSourceRequired.
  ///
  /// In en, this message translates to:
  /// **'Compression currently supports files from local panels only.'**
  String get archiveLocalSourceRequired;

  /// No description provided for @multiSyncResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Synchronization results'**
  String get multiSyncResultTitle;

  /// No description provided for @multiSyncSummary.
  ///
  /// In en, this message translates to:
  /// **'{successful} of {total} target panels completed successfully'**
  String multiSyncSummary(int successful, int total);

  /// No description provided for @multiSyncCompleted.
  ///
  /// In en, this message translates to:
  /// **'Synchronization completed'**
  String get multiSyncCompleted;

  /// No description provided for @multiSyncNoChanges.
  ///
  /// In en, this message translates to:
  /// **'Already up to date'**
  String get multiSyncNoChanges;

  /// No description provided for @multiSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Synchronization failed'**
  String get multiSyncFailed;

  /// No description provided for @multiSyncCancelled.
  ///
  /// In en, this message translates to:
  /// **'Synchronization cancelled'**
  String get multiSyncCancelled;

  /// No description provided for @multiSyncSkipped.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get multiSyncSkipped;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
