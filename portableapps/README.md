# PortableApps.com paket hazırlığı

Bu klasör PortableApps.com Format 3.9 için kaynak şablonunu içerir. Flutter
Windows release çıktısı `App\FirFileManager` altına kopyalanmalı ve
PortableApps.com Launcher Generator ile `FirFileManagerPortable.exe`
üretilmelidir.

Launcher, `FIR_FILE_MANAGER_PORTABLE_DATA` değişkenini `%PAL:DataDir%` olarak
ayarlar. Böylece uygulamanın ortak ayarları `Data\settings.json` içine yazılır.

Bu şablon tek başına `.paf.exe` değildir; PortableApps.com Launcher ve güncel
PortableApps.com Installer ile paketlenmelidir. Parolalar hâlâ Windows güvenli
depolamasında tutulduğu için tam parola taşınabilirliği ayrıca tasarlanmalıdır.
