# Cross-Platform Dosya Yöneticisi — Proje Planı

**Durum:** Planlama tamamlandı, geliştirme başlıyor
**Hedef platformlar:** Windows, macOS, Linux, Android, iOS
**Ana teknoloji:** Flutter + Riverpod

---

## 1. Proje Özeti

Tüm büyük platformlarda çalışan, iki panelli (dual-pane), yerel + ağ (SFTP/FTP/Samba/WebDAV) + bulut depolama entegrasyonlu bir dosya yöneticisi. Uygulama hem **istemci** (uzak sunuculara bağlanma) hem **sunucu** (cihazı FTP/SFTP/WebDAV sunucusu yapma) modunda çalışacak.

### UX Felsefesi (Adaptif Çift Kimlik)

Rakip analizinden çıkan sonuç: iki farklı kullanıcı kitlesi var ve ikisini de tek uygulamada, ekran yönüne göre adapte olan bir arayüzle karşılıyoruz.

| Mod | Ekran/Durum | Referans | Yaklaşım |
|---|---|---|---|
| **Dual-Pane Shell** | Landscape, Tablet, Desktop | Total Commander, FX File Explorer, Owlfiles | İki panel yan yana, klavye kısayolları, adres çubuğu her panelde |
| **Category Shell** | Portrait / Telefon | File Manager Plus | Kategori bazlı ana ekran (Görüntüler, Belgeler, Ses, Video), tek panel, isteğe bağlı ikinci panel |

Her iki shell de aynı `StorageProvider` veri katmanının üzerine oturur — UI, hangi kaynağa (local/SFTP/cloud/SMB) baktığını bilmeden çalışır.

---

## 2. Mimari Genel Bakış

```
lib/
  core/
    storage/
      storage_provider.dart          <- soyut interface (list, read, write, delete, move, rename, mkdir...)
      models/
        file_entry.dart
        connection_profile.dart
      providers/
        local_provider.dart          <- dart:io (desktop) / SAF (Android) / sandbox+picker (iOS)
        sftp_provider.dart           <- dartssh2
        ftp_provider.dart            <- ftpconnect
        webdav_provider.dart         <- webdav_client
        smb_provider.dart            <- native FFI/platform channel (Sprint 6)
        cloud/
          gdrive_provider.dart       <- REST + OAuth2
          dropbox_provider.dart      <- REST + OAuth2
    server/
      ftp_server.dart                <- dart:io raw socket
      sftp_server.dart               <- dartssh2 server tarafı ya da custom SSH impl
      webdav_server.dart             <- shelf + custom WebDAV method handling
  features/
    shell_adaptive/
      dual_pane_shell.dart
      category_shell.dart
      layout_resolver.dart           <- ekran genişliğine göre shell seçimi
    connections/                     <- kayıtlı sunucu/bulut profilleri, keyring
    file_operations/                 <- copy/move/delete/rename/compress, progress tracking
    server_mode/                     <- sunucu aç/kapa UI, aktif bağlantı listesi
  platform/
    android/                         <- SAF platform channel, foreground service
    ios/                             <- File Provider Extension köprüsü
    desktop/                         <- native dosya sistemi izinleri (macOS sandbox entitlements)
```

**Kritik prensip:** Tüm protokoller `StorageProvider` interface'i arkasında soyutlanır. Yeni bir protokol eklemek = yeni bir provider yazmak, UI katmanına dokunmadan.

---

## 3. Teknoloji ve Paket Seçimleri

| İhtiyaç | Paket/Yaklaşım | Not |
|---|---|---|
| State management | `riverpod` | Senin standart pattern'in |
| SFTP client | `dartssh2` | Olgun, aktif bakımlı |
| FTP client | `ftpconnect` | Yeterli olgunlukta |
| WebDAV client | `webdav_client` | Yeterli |
| SMB client | Native FFI (libsmbclient/libdsm) veya platform channel | Dart ekosistemi zayıf — **en riskli parça, Sprint 6'ya bırakıldı** |
| Android SAF | `saf_util`/`saf_stream` + custom platform channel | Scoped storage zorunluluğu |
| iOS dosya erişimi | `file_picker` + custom File Provider Extension (native Swift) | Sandbox kısıtı, ayrı native modül |
| Cloud (Drive/Dropbox) | REST API + OAuth2 (`oauth2` paketi) | Android'de alternatif: SAF üzerinden bulut sağlayıcılarına native entegrasyon (daha az iş, ama sadece Android) |
| Sunucu (FTP/WebDAV) | `dart:io` raw socket + `shelf` (WebDAV için) | Kendi implementasyonun gerekecek, hazır paket yok |
| Arşiv (zip/tar) | `archive` | Olgun |

---

## Sprint 1 — Dual-Pane Çekirdek (Desktop Öncelikli)

**Hedef:** Windows/macOS/Linux'ta çalışan, sadece yerel dosya sistemi üzerinde iki panelli temel dosya yöneticisi.

**Kapsam:**
- Proje iskeleti, feature-based klasör yapısı, Riverpod kurulumu
- `StorageProvider` interface tasarımı ve `local_provider.dart` (dart:io) implementasyonu
- İki panel: bağımsız navigasyon, breadcrumb/adres çubuğu
- Temel işlemler: listele, aç, yeniden adlandır, sil, kopyala, taşı, klasör oluştur
- Çoklu seçim (shift-click, ctrl-click)
- Klavye kısayolları: F5 kopyala, F6 taşı, F8/Delete sil, Tab panel değiştir
- Sıralama (isim/tarih/boyut/tip)

**Kabul Kriterleri:**
- [ ] Uygulama Windows, macOS, Linux'ta açılıyor ve yerel dosya sistemini gösteriyor
- [ ] İki panel bağımsız olarak farklı klasörlere gidebiliyor
- [ ] Kopyala/taşı/sil/yeniden adlandır işlemleri hatasız çalışıyor, ilerleme göstergesi var
- [ ] Temel klavye kısayolları (F5/F6/F8/Tab) çalışıyor
- [ ] Çoklu dosya seçimi ve toplu işlem yapılabiliyor

**Riskler:** Düşük — bu sprint tamamen bilinen Flutter desktop yetenekleri üzerine kurulu.

---

## Sprint 2 — Mobil Adaptasyon (Android SAF + iOS Sandbox)

**Hedef:** Aynı çekirdeği Android ve iOS'a taşımak, adaptif shell sistemini kurmak.

**Kapsam:**
- `layout_resolver.dart`: ekran genişliği/yönüne göre `DualPaneShell` ↔ `CategoryShell` seçimi
- `CategoryShell` UI: Ana Bellek, Görüntüler, Belgeler, Ses, Video kısayolları (File Manager Plus referansı)
- Android: SAF entegrasyonu — `local_provider`'ın Android varyantı, scoped storage uyumlu klasör seçimi
- iOS: `file_picker` ile sandbox içi + kullanıcı seçimli klasör erişimi (henüz File Provider Extension yok, o Sprint 7'de)
- Portrait'te tek panel + "ikinci panel aç" butonu (geçişli/sekmeli)

**Kabul Kriterleri:**
- [ ] Telefon portrait modunda kategori ana ekranı açılıyor
- [ ] Tablet/landscape'te otomatik dual-pane'e geçiyor
- [ ] Android'de SAF üzerinden herhangi bir klasöre erişilebiliyor (scoped storage uyumlu)
- [ ] iOS'ta document picker ile klasör seçimi ve temel dosya işlemleri çalışıyor
- [ ] Aynı `StorageProvider` interface'i her iki platformda da local dosyaları doğru gösteriyor

**Riskler:** Orta — SAF permission akışı ve iOS sandbox kısıtları UX'i karmaşıklaştırabilir, ekstra test süresi gerekebilir.

---

## Sprint 3 — Client Protokolleri: SFTP / FTP / WebDAV

**Hedef:** Uzak sunuculara istemci olarak bağlanabilme (henüz SMB ve sunucu modu yok).

**Kapsam:**
- `sftp_provider.dart` (dartssh2 ile) — şifre + key-based auth
- `ftp_provider.dart` (ftpconnect ile) — FTP/FTPS
- `webdav_provider.dart` (webdav_client ile)
- `connections/` modülü: bağlantı profili ekle/düzenle/sil, şifreli credential saklama (keyring)
- Bağlantı profilleri panel içinde "konum" olarak local ile aynı arayüzde görünüyor

**Kabul Kriterleri:**
- [ ] Kullanıcı yeni bir SFTP/FTP/WebDAV bağlantısı ekleyip kaydedebiliyor
- [ ] Kayıtlı bağlantı bir panelde "klasör" gibi açılıp içinde gezinilebiliyor
- [ ] Uzak-yerel arası kopyalama/taşıma çalışıyor, ilerleme göstergesi var
- [ ] Bağlantı bilgileri (şifre/anahtar) cihazda şifreli saklanıyor
- [ ] Bağlantı koptuğunda anlamlı hata mesajı gösteriliyor, retry mekanizması var

**Riskler:** Düşük-Orta — kütüphaneler olgun, ama büyük dosya transferlerinde ilerleme/iptal mekanizması dikkat ister.

---

## Sprint 4 — Sunucu Modu (Desktop Öncelikli)

**Hedef:** Mac/Windows/Linux cihazını FTP/WebDAV sunucusuna çevirebilme (Owlfiles referansı).

**Kapsam:**
- `ftp_server.dart`: `dart:io` raw socket üzerine minimal FTP server (LIST, RETR, STOR, DELE, MKD komutları)
- `webdav_server.dart`: `shelf` üzerine temel WebDAV method handling (GET, PUT, PROPFIND, DELETE)
- Sunucu aç/kapa UI: paylaşılan klasör seçimi, kullanıcı adı/şifre, port ayarı
- Aktif bağlantı listesi (kim bağlı, ne yapıyor)
- LAN'da otomatik keşif (mDNS/Bonjour) — opsiyonel, zaman kalırsa

**Kabul Kriterleri:**
- [ ] Desktop'ta "Sunucuyu Başlat" ile FTP sunucusu ayağa kalkıyor
- [ ] Başka bir cihazdan (telefon veya PC) standart bir FTP client ile bağlanılabiliyor
- [ ] Aynı şekilde WebDAV sunucusu çalışıyor ve Finder/Explorer'dan bağlanılabiliyor
- [ ] Şifre korumalı erişim çalışıyor
- [ ] Sunucu durdurulduğunda bağlantılar düzgün kapanıyor

**Riskler:** Orta-Yüksek — hazır Dart paketi yok, protokol implementasyonu kendin yazılacak. Zaman tamponu bırak.

---

## Sprint 5 — Cloud Eklentileri

**Hedef:** Google Drive, Dropbox gibi bulut sağlayıcılarına client olarak bağlanma.

**Kapsam:**
- OAuth2 akışı (`oauth2` paketi + platform browser redirect)
- `gdrive_provider.dart`, `dropbox_provider.dart` — REST API üzerinden list/read/write/delete
- Token yenileme ve güvenli saklama
- Android'de alternatif/ek yol: SAF üzerinden zaten sisteme kayıtlı cloud provider'lara erişim (daha az iş, sadece Android)

**Kabul Kriterleri:**
- [ ] Kullanıcı Google hesabıyla giriş yapıp Drive dosyalarını görebiliyor
- [ ] Dropbox için aynısı çalışıyor
- [ ] Bulut-yerel, bulut-SFTP arası kopyalama çalışıyor
- [ ] Token süresi dolduğunda otomatik yenileniyor, kullanıcı tekrar login olmak zorunda kalmıyor

**Riskler:** Orta — OAuth consent screen / API quota onayları (özellikle Google) zaman alabilir, erken başvur.

---

## Sprint 6 — SMB/Samba Desteği

**Hedef:** Windows ağ paylaşımlarına ve NAS cihazlarına SMB üzerinden bağlanma.

**Kapsam:**
- Native SMB client entegrasyonu: platforma göre libsmbclient (Linux/macOS) veya native Windows SMB API, Android için libdsm/native bridge
- `smb_provider.dart`: platform channel üzerinden native tarafla haberleşme
- Ağda otomatik cihaz/paylaşım keşfi (mümkünse)

**Kabul Kriterleri:**
- [ ] Windows paylaşımına (\\\\bilgisayar\\paylaşım) her platformdan bağlanılabiliyor
- [ ] NAS cihazına SMB2/3 ile bağlanılıp dosya listelenip kopyalanabiliyor
- [ ] Kimlik doğrulama (domain/kullanıcı/şifre) destekleniyor

**Riskler:** **Yüksek** — Dart ekosisteminde olgun paket yok (araştırmada bulunanlar deneysel/sınırlı). Platform başına ayrı native implementasyon gerekebilir. Bu sprint için ekstra zaman tamponu planla, gerekirse kapsamı daraltarak (örn. önce sadece desktop + Android, iOS'u sona bırakarak) ilerle.

---

## Sprint 7 — Mobil Sunucu Modu + iOS Files Entegrasyonu

**Hedef:** Sprint 4'teki sunucu modunu mobile taşımak, iOS'ta Files app entegrasyonu.

**Kapsam:**
- Android: Foreground service ile arka planda FTP/WebDAV server çalıştırma, kalıcı bildirim
- iOS: **File Provider Extension** (native Swift, ayrı app extension target) — uygulamanın bağlantılarını iOS Files app'inde bir "konum" olarak göstermek
- iOS'ta gerçek arka plan sunucu modu App Store kısıtları nedeniyle sınırlı/mümkün olmayabilir — bu netleştirilip kapsam buna göre ayarlanacak

**Kabul Kriterleri:**
- [ ] Android'de sunucu modu arka planda, bildirimle birlikte çalışıyor
- [ ] iOS Files app'inde uygulama bir konum olarak görünüyor, başka app'ler dosyalara erişebiliyor
- [ ] Foreground'dan çıkınca Android'de bağlantı kopmuyor (foreground service sayesinde)

**Riskler:** Yüksek — iOS native extension geliştirme ayrı bir öğrenme eğrisi; App Store review süreçleri (özellikle arka plan network erişimi) beklenmedik gecikmelere yol açabilir.

---

## 4. Genel Risk Özeti

| Risk | Sprint | Azaltma Stratejisi |
|---|---|---|
| SMB için olgun Dart paketi yok | 6 | Native bridge, platform başına ayrı iş, zaman tamponu |
| iOS arka plan sunucu kısıtları | 7 | Kapsamı erken netleştir, gerekirse "sadece foreground'da çalışır" olarak sun |
| Kendi FTP/WebDAV server protokol implementasyonu | 4 | RFC'lere sadık minimal implementasyon, üçüncü parti FTP client ile erken test |
| Google/Dropbox OAuth onay süreçleri | 5 | Başvuruları sprint başlamadan önce yap |
| Android SAF + scoped storage UX karmaşıklığı | 2 | Erken prototip, gerçek cihazda test |

---

## 5. Referans Uygulamalar

- **Total Commander (Windows)** — dual-pane UX, klavye kısayolları
- **Owlfiles (macOS/iOS/Android)** — dual-pane + built-in FTP server + SMB/WebDAV/FTP/SFTP/cloud, en yakın "hedef ürün" referansı
- **FX File Explorer (Android)** — dual-pane, SMB/FTP/SFTP/WebDAV, SAF üzerinden cloud erişimi
- **File Manager Plus (Android)** — kategori bazlı basit ana ekran, mainstream kullanıcı UX'i
