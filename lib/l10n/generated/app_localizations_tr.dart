// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'Fir Dosya Yöneticisi';

  @override
  String get navLocal => 'Yerel';

  @override
  String get navConnections => 'Bağlantılar';

  @override
  String get navServer => 'Sunucu';

  @override
  String get navSettings => 'Ayarlar';

  @override
  String get categoryImages => 'Görüntüler';

  @override
  String get categoryDocuments => 'Belgeler';

  @override
  String get categoryAudio => 'Ses';

  @override
  String get categoryVideo => 'Video';

  @override
  String get categoryDownloads => 'İndirilenler';

  @override
  String get categoryMainStorage => 'Ana Bellek';

  @override
  String get actionCopy => 'Kopyala';

  @override
  String get actionMove => 'Taşı';

  @override
  String get actionDelete => 'Sil';

  @override
  String get actionRename => 'Yeniden Adlandır';

  @override
  String get actionNewFolder => 'Yeni Klasör';

  @override
  String get actionPaste => 'Yapıştır';

  @override
  String get actionSelectAll => 'Tümünü Seç';

  @override
  String get actionRefresh => 'Yenile';

  @override
  String get actionOpen => 'Aç';

  @override
  String get actionOpenDefault => 'Varsayılan Uygulamayla Aç';

  @override
  String get actionOpenWith => 'Şununla Aç';

  @override
  String get actionChooseApplication => 'Uygulama Seç…';

  @override
  String get actionProperties => 'Özellikler';

  @override
  String get actionRevealInFinder => 'Finder\'da Göster';

  @override
  String get actionCompress => 'Sıkıştır';

  @override
  String get actionCompressZip => 'ZIP olarak sıkıştır';

  @override
  String get actionCompressTar => 'TAR olarak sıkıştır';

  @override
  String get actionCompressTarGz => 'TAR.GZ olarak sıkıştır';

  @override
  String get actionExtract => 'Buraya Çıkar';

  @override
  String get actionExtractTo => 'Çıkar…';

  @override
  String get actionClose => 'Kapat';

  @override
  String get actionCancel => 'İptal';

  @override
  String get actionRetry => 'Tekrar Dene';

  @override
  String get actionSave => 'Kaydet';

  @override
  String get actionConnect => 'Bağlan';

  @override
  String get actionDisconnect => 'Bağlantıyı Kes';

  @override
  String get actionAdd => 'Ekle';

  @override
  String get actionEdit => 'Düzenle';

  @override
  String get actionRemove => 'Kaldır';

  @override
  String get sortByName => 'İsim';

  @override
  String get sortByDate => 'Değiştirilme Tarihi';

  @override
  String get sortBySize => 'Boyut';

  @override
  String get sortByType => 'Tür';

  @override
  String get sortAscending => 'Artan';

  @override
  String get sortDescending => 'Azalan';

  @override
  String get panelLeft => 'Sol Panel';

  @override
  String get panelRight => 'Sağ Panel';

  @override
  String get panelActive => 'Aktif Panel';

  @override
  String operationCopying(int count) {
    return '$count öğe kopyalanıyor…';
  }

  @override
  String operationMoving(int count) {
    return '$count öğe taşınıyor…';
  }

  @override
  String operationDeleting(int count) {
    return '$count öğe siliniyor…';
  }

  @override
  String get operationComplete => 'İşlem tamamlandı';

  @override
  String operationFailed(String error) {
    return 'İşlem başarısız: $error';
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
  String get connectionHost => 'Sunucu';

  @override
  String get connectionPort => 'Port';

  @override
  String get connectionUsername => 'Kullanıcı Adı';

  @override
  String get connectionPassword => 'Şifre';

  @override
  String get connectionName => 'Bağlantı Adı';

  @override
  String get connectionAuthMethod => 'Kimlik Doğrulama Yöntemi';

  @override
  String get connectionAuthPassword => 'Şifre';

  @override
  String get connectionAuthKey => 'Özel Anahtar';

  @override
  String get connectionAddNew => 'Yeni Bağlantı Ekle';

  @override
  String get connectionEdit => 'Bağlantıyı Düzenle';

  @override
  String get connectionTest => 'Bağlantıyı Test Et';

  @override
  String get connectionTestSuccess => 'Bağlantı başarılı';

  @override
  String connectionTestFailed(String error) {
    return 'Bağlantı başarısız: $error';
  }

  @override
  String get connectionDisconnected => 'Bağlantı kesildi';

  @override
  String get connectionReconnecting => 'Yeniden bağlanılıyor…';

  @override
  String get serverStart => 'Sunucuyu Başlat';

  @override
  String get serverStop => 'Sunucuyu Durdur';

  @override
  String get serverRunning => 'Sunucu çalışıyor';

  @override
  String get serverStopped => 'Sunucu durduruldu';

  @override
  String get serverSharedFolder => 'Paylaşılan Klasör';

  @override
  String get serverPort => 'Port';

  @override
  String get serverUsername => 'Kullanıcı Adı';

  @override
  String get serverPassword => 'Şifre';

  @override
  String get serverActiveConnections => 'Aktif Bağlantılar';

  @override
  String get serverNoConnections => 'Aktif bağlantı yok';

  @override
  String get serverFtp => 'FTP Sunucusu';

  @override
  String get serverWebdav => 'WebDAV Sunucusu';

  @override
  String get settingsLanguage => 'Dil';

  @override
  String get settingsTheme => 'Tema';

  @override
  String get settingsThemeLight => 'Açık';

  @override
  String get settingsThemeDark => 'Koyu';

  @override
  String get settingsThemeSystem => 'Sistem';

  @override
  String get errorAccessDenied => 'Erişim reddedildi';

  @override
  String errorNotFound(String path) {
    return 'Bulunamadı: $path';
  }

  @override
  String errorAlreadyExists(String path) {
    return 'Zaten mevcut: $path';
  }

  @override
  String errorNetwork(String error) {
    return 'Ağ hatası: $error';
  }

  @override
  String get errorTimeout => 'İşlem zaman aşımına uğradı';

  @override
  String get errorUnknown => 'Bilinmeyen bir hata oluştu';

  @override
  String get confirmDeleteTitle => 'Sil';

  @override
  String confirmDeleteMessage(int count) {
    return '$count öğeyi silmek istediğinize emin misiniz?';
  }

  @override
  String get confirmOverwriteTitle => 'Üzerine Yaz';

  @override
  String confirmOverwriteMessage(String name) {
    return '$name zaten mevcut. Üzerine yazılsın mı?';
  }

  @override
  String get propertiesName => 'İsim';

  @override
  String get propertiesPath => 'Yol';

  @override
  String get propertiesSize => 'Boyut';

  @override
  String get propertiesType => 'Tür';

  @override
  String get propertiesModified => 'Değiştirilme Tarihi';

  @override
  String get propertiesPermissions => 'İzinler';

  @override
  String get propertiesFolder => 'Klasör';

  @override
  String get propertiesFile => 'Dosya';

  @override
  String itemsSelected(int count) {
    return '$count seçili';
  }

  @override
  String itemsCount(int count) {
    return '$count öğe';
  }

  @override
  String get emptyFolder => 'Bu klasör boş';

  @override
  String get progressCurrentFile => 'Geçerli dosya';

  @override
  String get progressOverall => 'Toplam';

  @override
  String progressRemaining(String size) {
    return '$size kaldı';
  }

  @override
  String progressSpeed(String speed) {
    return '$speed/sn';
  }

  @override
  String progressEta(String time) {
    return 'ETA $time';
  }

  @override
  String get progressEtaCalculating => 'ETA hesaplanıyor…';

  @override
  String get syncPreviewTitle => 'Akıllı Senkronizasyon';

  @override
  String get syncSourcePanel => 'Seçili panel';

  @override
  String get syncDestinationPanel => 'Hedef panel';

  @override
  String syncSelectedSummary(int selected, int total) {
    return '$total dosyanın $selected tanesi seçili';
  }

  @override
  String get syncSelectChanges => 'Farklıları seç';

  @override
  String get syncSelectAll => 'Tümünü seç';

  @override
  String get syncClearAll => 'Tümünü temizle';

  @override
  String syncStartSelected(int count) {
    return 'Senkronize et ($count)';
  }

  @override
  String get syncColumnFile => 'Dosya';

  @override
  String get syncColumnSize => 'Boyut';

  @override
  String get syncColumnModified => 'Değiştirilme';

  @override
  String get syncColumnStatus => 'Karşılaştırma';

  @override
  String get syncStatusNew => 'Yeni';

  @override
  String get syncStatusDifferent => 'Farklı';

  @override
  String get syncStatusEqual => 'Eş';

  @override
  String get syncMissingDestination => 'Hedefte yok';

  @override
  String get syncNoChanges =>
      'Fark bulunamadı. Hedef panel seçili panelle zaten eşleşiyor.';

  @override
  String syncResultSummary(int updated, int created) {
    return 'Senkronizasyon tamamlandı: $updated dosya yenisiyle değiştirildi, $created yeni dosya kopyalandı.';
  }

  @override
  String syncResultFailures(int updated, int created, int failed) {
    return 'Senkronizasyon bitti: $updated dosya yenisiyle değiştirildi, $created yeni dosya kopyalandı, $failed dosya başarısız oldu.';
  }

  @override
  String get syncCancelled => 'Senkronizasyon iptal edildi.';

  @override
  String get syncStatusInaccessible => 'Erişilemiyor';

  @override
  String get syncShowSelectedOnly => 'Yalnız seçilenler';

  @override
  String get syncSearchHint => 'Dosyalarda ara';

  @override
  String get syncSaveJob => 'Görevi kaydet…';

  @override
  String get syncEditJob => 'Senkron görevini düzenle';

  @override
  String get syncJobName => 'Görev adı';

  @override
  String get syncJobNameRequired => 'Bir görev adı girin.';

  @override
  String get syncWeekdayRequired => 'En az bir gün seçin.';

  @override
  String get syncSchedule => 'Zamanlama';

  @override
  String get syncScheduleManual => 'Manuel';

  @override
  String get syncScheduleOnce => 'Bir kez';

  @override
  String get syncScheduleDaily => 'Her gün';

  @override
  String get syncScheduleWeekly => 'Her hafta';

  @override
  String get syncJobEnabled => 'Otomasyon etkin';

  @override
  String get syncRequireWifi => 'Yalnız Wi-Fi ile çalıştır';

  @override
  String get syncAllowMobileData => 'Mobil veriye izin ver';

  @override
  String get syncRequireCharging => 'Yalnız şarj olurken çalıştır';

  @override
  String get weekdayMonday => 'Pzt';

  @override
  String get weekdayTuesday => 'Sal';

  @override
  String get weekdayWednesday => 'Çar';

  @override
  String get weekdayThursday => 'Per';

  @override
  String get weekdayFriday => 'Cum';

  @override
  String get weekdaySaturday => 'Cmt';

  @override
  String get weekdaySunday => 'Paz';

  @override
  String syncJobSaved(String name) {
    return '\"$name\" kaydedildi.';
  }

  @override
  String syncJobNameConflict(String name) {
    return '\"$name\" adlı bir görev zaten var.';
  }

  @override
  String get syncJobsTitle => 'Fir SmartSync';

  @override
  String get syncJobsSubtitle => 'Kayıtlı senkron görevleri';

  @override
  String get syncJobsEmpty => 'Henüz bir senkron görevi kaydedilmedi.';

  @override
  String get syncJobsEmptyHint =>
      'Bir dosya panelinden senkronizasyonu açın, dosyaları seçin ve Görevi kaydet seçeneğini kullanın.';

  @override
  String syncRunSucceeded(int updated, int created) {
    return 'Senkronizasyon tamamlandı: $updated güncellendi, $created oluşturuldu.';
  }

  @override
  String syncRunFailed(int failed) {
    return '$failed dosyanın senkronizasyonu başarısız oldu.';
  }

  @override
  String get syncDeleteJob => 'Senkron görevini sil';

  @override
  String syncDeleteJobConfirm(String name) {
    return '\"$name\" görevi ve zamanlaması silinsin mi?';
  }

  @override
  String syncHistoryFor(String name) {
    return '$name geçmişi';
  }

  @override
  String get syncHistoryEmpty => 'Henüz bir çalışma kaydedilmedi.';

  @override
  String get syncFailedLabel => 'Başarısız';

  @override
  String get syncFailureDetails => 'Hata ayrıntıları';

  @override
  String get syncRunNow => 'Şimdi çalıştır';

  @override
  String get syncHistory => 'Geçmiş';

  @override
  String get panelAdd => 'Panel ekle';

  @override
  String get panelClose => 'Paneli kapat';

  @override
  String panelNumber(int number) {
    return 'Panel $number';
  }

  @override
  String get targetPanels => 'Hedef paneller';

  @override
  String get targetSourcePanel => 'Kaynak panel';

  @override
  String get targetOperationSync => 'Senkron';

  @override
  String targetSelectedSummary(int selected, int total) {
    return '$total hedeften $selected tanesi seçili';
  }

  @override
  String get targetSameLocation => 'Kaynak panelle aynı konum';

  @override
  String get targetConnectionUnavailable => 'Bağlantı kullanılamıyor';

  @override
  String get targetLocalPanelRequired =>
      'Sıkıştırma için yerel bir hedef panel seçin';

  @override
  String get targetContinue => 'Devam et';

  @override
  String get multiTransferResultTitle => 'Aktarım sonuçları';

  @override
  String multiTransferSuccess(int count) {
    return 'Aktarım $count hedef panel için tamamlandı';
  }

  @override
  String multiTransferPartial(int successful, int total) {
    return '$total hedef panelden $successful tanesi başarıyla tamamlandı';
  }

  @override
  String get multiTransferCompleted => 'Tamamlandı';

  @override
  String get multiTransferFailed => 'Başarısız';

  @override
  String get multiTransferCancelled => 'İptal edildi';

  @override
  String get multiTransferSkipped => 'Başlatılmadı';

  @override
  String get multiTransferSourcePreserved =>
      'Bütün hedefler başarıyla tamamlanmadığı için kaynak korundu.';

  @override
  String get multiArchiveResultTitle => 'Sıkıştırma sonuçları';

  @override
  String multiArchiveSuccess(int count) {
    return 'Arşiv $count hedef panelde oluşturuldu';
  }

  @override
  String get archiveLocalSourceRequired =>
      'Sıkıştırma şu anda yalnızca yerel paneldeki dosyaları destekliyor.';

  @override
  String get multiSyncResultTitle => 'Senkron sonuçları';

  @override
  String multiSyncSummary(int successful, int total) {
    return '$total hedef panelden $successful tanesi başarıyla tamamlandı';
  }

  @override
  String get multiSyncCompleted => 'Senkron tamamlandı';

  @override
  String get multiSyncNoChanges => 'Zaten güncel';

  @override
  String get multiSyncFailed => 'Senkron başarısız';

  @override
  String get multiSyncCancelled => 'Senkron iptal edildi';

  @override
  String get multiSyncSkipped => 'Başlatılmadı';
}
