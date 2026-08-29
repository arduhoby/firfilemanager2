# Windows portable dağıtım

Fir File Manager Windows sürümü kurulum gerektirmeyen portable ZIP olarak
dağıtılır. ZIP dosyasını bir klasöre çıkarın ve içindeki `fir_file_manager.exe`
dosyasını çalıştırın. Kayıt defterine veya sistem klasörlerine yazılmaz.

Release paketinin yanındaki `FirFileManager-Windows-x64.zip.sha256` dosyası ile
indirdiğiniz ZIP'in SHA-256 özetini doğrulayın.

Akıllı Uygulama Denetimi imzasız bir portable paketi engelleyebilir. Bu durumda
kullanıcı kaynak koddan derleyebilir veya kendi Windows cihazında bu güvenlik
özelliğini kapatabilir. Proje Microsoft Store veya kurulum programına bağlı
değildir.

Kaynak koddan Windows derlemesi:

```powershell
flutter pub get
flutter build windows --release
```

Çıktı `build/windows/x64/runner/Release/` klasöründedir.
