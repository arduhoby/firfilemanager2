# Flutter Analyze Hata Raporu

**Tarih:** 2026-08-28  
**Toplam Sorun:** 347  
**Analiz Süresi:** 14.3s

---

## 🔴 KRİTİK HATALAR (Olası Buglar / Çökme Riski)

### 1. `use_build_context_synchronously` — **~10 adet**
BuildContext, async boşlukta (await sonrası) `mounted` kontrolü olmadan kullanılıyor. Bu, widget ağacı değiştiğinde çökmeye yol açar.

| Dosya | Satır | Açıklama |
|-------|-------|----------|
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1326 | BuildContext async gap'de kullanılmış |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1428 | BuildContext async gap'de kullanılmış |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1559 | BuildContext async gap'de kullanılmış |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1621 | BuildContext async gap'de kullanılmış |
| `lib/features/connections/connections_sidebar.dart` | 555 | `mounted` kontrolü eksik/yanlış |
| `lib/features/connections/connections_sidebar.dart` | 565 | `mounted` kontrolü eksik/yanlış |
| `lib/features/connections/connections_sidebar.dart` | 568 | `mounted` kontrolü eksik/yanlış |
| `lib/features/connections/connections_sidebar.dart` | 585 | `mounted` kontrolü eksik/yanlış |
| `lib/features/connections/connections_sidebar.dart` | 594 | `mounted` kontrolü eksik/yanlış |
| `lib/features/connections/connections_sidebar.dart` | 597 | `mounted` kontrolü eksik/yanlış |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 453 | BuildContext async gap'de kullanılmış |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 458 | BuildContext async gap'de kullanılmış |

**Düzeltme:** `mounted` kontrolü ekle veya `BuildContext` kullanımını async gap'ten çıkarıp önce kaydet.

---

### 2. `unawaited_futures` — **~10 adet**
Future await edilmeden bırakılmış, race condition riski var.

| Dosya | Satır | Açıklama |
|-------|-------|----------|
| `lib/features/connections/connections_sidebar.dart` | 553 | Future await edilmedi |
| `lib/features/settings/settings_dialog.dart` | 142 | Future await edilmedi |
| `lib/features/shell_adaptive/double_back_exit_wrapper.dart` | 40 | Future await edilmedi |
| `lib/features/shell_adaptive/double_back_exit_wrapper.dart` | 54 | Future await edilmedi |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1639 | Future await edilmedi |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1779 | Future await edilmedi |
| `lib/features/shell_adaptive/panel_controller.dart` | 92 | Future await edilmedi |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 244 | Future await edilmedi |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 278 | Future await edilmedi |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 452 | Future await edilmedi |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 491 | Future await edilmedi |

**Düzeltme:** `await` ekle veya `unawaited()` ile sarmala (bilinçliysa).

---

### 3. `dead_code` / `dead_null_aware_expression` — **2 adet**
Erişilemez / gereksiz kod.

| Dosya | Satır | Açıklama |
|-------|-------|----------|
| `lib/features/shell_adaptive/dual_pane_shell.dart` | 455 | Dead code - sağ operand asla çalışmaz |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | 455 | Dead null-aware expression - sol operand null olamaz |

**Düzeltme:** Kodu sil veya mantığı düzelt.

---

### 4. `unnecessary_null_comparison` — **1 adet**
Her zaman true olan null kontrolü.

| Dosya | Satır | Açıklama |
|-------|-------|----------|
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1746 | Operand null olamaz, koşul her zaman true |

**Düzeltme:** Gereksiz null check'i kaldır.

---

## 🟡 UYARILAR (Kod Kalitesi)

### `unused_import` — **~10 adet**
Kullanılmayan import'lar.

| Dosya | Import |
|-------|--------|
| `lib/features/connections/connection_dialog.dart` | `dart:io` |
| `lib/features/settings/api_keys_repository.dart` | `dart:io` |
| `lib/features/settings/api_keys_repository.dart` | `package:path_provider/path_provider.dart` |
| `lib/features/settings/api_keys_repository.dart` | `package:path/path.dart` |
| `lib/features/preview/quick_look_dialog.dart` | `../file_operations/file_operations_state.dart` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | `package:file_picker/file_picker.dart` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | `../../core/storage/storage_provider.dart` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | `../../core/theme/glass_container.dart` |
| `lib/features/shell_adaptive/file_panel.dart` | `../../core/storage/models/transfer_progress.dart` |

---

### `unused_field` / `unused_local_variable` / `unused_element` — **~15 adet**
Kullanılmayan alanlar/değişkenler/metotlar.

| Dosya | Tür | İsim |
|-------|-----|------|
| `lib/features/file_operations/mac_app_picker_dialog.dart` | field | `_searchQuery` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | local | `leftState` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | local | `rightState` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | element | `_buildMountedDriveShortcuts` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | element | `_shortenPath` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | element | `_PathLabel` |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | element | `_FnDivider` |
| `lib/features/shell_adaptive/file_panel.dart` | field | `_showAddressBar` |
| `lib/features/shell_adaptive/file_panel.dart` | local | `actions` |
| `lib/features/shell_adaptive/file_panel.dart` | element | `_calculateSizesForSelection` |
| `lib/features/shell_adaptive/file_panel.dart` | element | `_navigateToAddress` |
| `lib/features/shell_adaptive/panel_path_bar.dart` | local | `separator` |
| `lib/features/shell_adaptive/shell_adaptive.dart` | element | `_buildPlaceholder` |
| `lib/features/shell_adaptive/file_operations_actions.dart` | local | `cliCommandGuest` |

---

### `override_on_non_overriding_member` — **1 adet**
Override etiketi ama override edilmiyor.

| Dosya | Satır |
|-------|-------|
| `lib/features/connections/connection_dialog.dart` | 41 |

---

### `unnecessary_await_in_return` — **4 adet**
Return deyiminde gereksiz await.

| Dosya | Satırlar |
|-------|----------|
| `lib/features/connections/connection_repository.dart` | 262, 267, 272, 277 |

---

### `unnecessary_underscores` — **4 adet**
Fazla `_` kullanımı.

| Dosya | Satırlar |
|-------|----------|
| `lib/features/settings/settings_dialog.dart` | 256 (2 adet) |
| `lib/features/shell_adaptive/dual_pane_shell.dart` | 296 (2 adet) |

---

## 🟠 DEPRECATION (Güncellenmesi Gereken API'ler)

### `withOpacity` → `withValues()` — **~15 adet**
`withOpacity` deprecated, `withValues()` kullanılmalı (precision loss önlenir).

| Dosya | Satırlar |
|-------|----------|
| `lib/features/connections/connection_dialog.dart` | 440, 442 |
| `lib/features/settings/api_keys_dialog.dart` | 94, 117, 120, 125, 144, 151, 166, 173 |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1897, 1902, 1961, 1962, 2224, 2226 |
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 718 |

---

### `surfaceVariant` → `surfaceContainerHighest` — **3 adet**
Material 3 renk şeması değişikliği.

| Dosya | Satırlar |
|-------|----------|
| `lib/features/settings/api_keys_dialog.dart` | 117 |
| `lib/features/shell_adaptive/file_operations_actions.dart` | 2102, 2176 |

---

### `value` (FormField) → `initialValue` — **2 adet**
FormField `value` property'si deprecated.

| Dosya | Satırlar |
|-------|----------|
| `lib/features/connections/connection_dialog.dart` | 252, 368 |

---

### `onPopInvoked` → `onPopInvokedWithResult` — **1 adet**
Navigator pop callback'i değişti.

| Dosya | Satır |
|-------|-------|
| `lib/features/shell_adaptive/double_back_exit_wrapper.dart` | 31 |

---

### `deprecated_member_use` (diğerleri) — **Çeşitli**
- `Color.value` → `toARGB32()` veya `.r/.g/.b` — `file_panel.dart:1279`

---

## 🔵 BİLGİLENDİRME (Stil / Performans)

### `discarded_futures` — **~50 adet**
Async olmayan fonksiyonda Future await edilmeden çağrılmış. `unawaited()` ekle veya fonksiyonu `async` yap.

**Örnek dosyalar:**
- `lib/features/bookmarks/bookmarks_menu.dart` (5 adet: 17, 48, 80, 82, 135)
- `lib/features/connections/connections_sidebar.dart` (5 adet: 31, 94, 96, 266, 625)
- `lib/features/connections/connection_dialog.dart` (1 adet: 92)
- `lib/features/connections/connection_repository.dart` (4 adet: 262, 267, 272, 277 - zaten unnecessary_await olarak da işaretli)
- `lib/features/file_operations/mac_app_picker_dialog.dart` (1 adet: 27)
- `lib/features/preview/quick_look_dialog.dart` (1 adet: 31)
- `lib/features/server_mode/server_mode_page.dart` (6 adet: 29, 117, 221, 223, 240, 242)
- `lib/features/settings/api_keys_repository.dart` (1 adet: 37)
- `lib/features/settings/settings_dialog.dart` (6 adet: 43, 63, 87, 103, 154, 187)
- `lib/features/shell_adaptive/dual_pane_shell.dart` (9 adet: 42, 97, 133, 141, 149, 170, 202, 208, 419, 1054)
- `lib/features/shell_adaptive/file_operations_actions.dart` (4 adet: 1782, 2044, 2070, 2119, 2153, 2193, 2258)
- `lib/features/shell_adaptive/file_panel.dart` (7 adet: 85, 168, 177, 189, 192, 674, 742, 1101, 1235, 1285, 1317)
- `lib/features/shell_adaptive/panel_controller.dart` (5 adet: 21, 41, 108, 126)
- `lib/features/shell_adaptive/panel_drive_bar.dart` (7 adet: 36, 38, 444, 537, 545, 548, 620, 628)
- `lib/features/shell_adaptive/panel_path_bar.dart` (11 adet: 61, 114, 129, 168, 179, 295, 314, 332, 354, 379, 412, 433)
- `lib/widgets/cascade_menu/cascade_menu_layer.dart` (1 adet: 60)
- `lib/features/shell_adaptive/shell_adaptive.dart` (2 adet: 29, 30 - const constructor)

---

### `prefer_const_constructors` / `prefer_const_literals_to_create_immutables` — **~20 adet**
Performans için const kullanımı.

**Örnekler:**
- `lib/features/connections/connection_dialog.dart` (261, 263, 264, 265, 266, 267)
- `lib/features/preview/quick_look_dialog.dart` (92 x2)
- `lib/features/shell_adaptive/shell_adaptive.dart` (29, 30)
- `lib/widgets/cascade_menu/cascade_menu_layer.dart` (const constructor)
- `test/features/file_operations/multi_panel_archive_integration_test.dart` (160)
- `test/features/shell_adaptive/panel_layout_test.dart` (11, 14, 21, 31)

---

### `avoid_print` — **~20 adet**
Production kodunda `print` yerine logging framework (örn. `logger` package) kullanılmalı.

**Dosyalar:**
- `lib/features/server_mode/server_mode_page.dart` (71, 74, 80, 85)
- `lib/features/server_mode/server_state.dart` (98)
- `lib/features/settings/api_keys_repository.dart` (49, 63)
- `lib/features/shell_adaptive/double_back_exit_wrapper.dart` (50, 53, 60)
- `scratch/simulate_secure_storage.dart` (4, 6)
- `scratch/test_nextcloud.dart` (7, 11, 13, 14, 17, 21, 23, 24)
- `scratch/test_nextcloud_http.dart` (11, 14, 15, 17, 19, 22, 24)
- `test_enc.dart` (8, 10, 13)

---

### `prefer_final_in_for_each` — **4 adet**
ForEach içinde değişken `final` olmalı.

| Dosya | Satırlar |
|-------|----------|
| `lib/features/settings/api_keys_dialog.dart` | 45, 48, 58, 206 |
| `test_enc.dart` | 9 (2 adet) |

---

### `prefer_single_quotes` — **2 adet**
Tek tırnak tercih edilmeli.

| Dosya | Satırlar |
|-------|----------|
| `scratch/simulate_secure_storage.dart` | 4, 6 |

---

### `prefer_const_declarations` — **2 adet**
Sabit değerler `const` olmalı.

| Dosya | Satırlar |
|-------|----------|
| `scratch/test_nextcloud.dart` | 4, 5 |

---

### `prefer_interpolation_to_compose_strings` — **1 adet**
String birleştirmede interpolation kullan.

| Dosya | Satır |
|-------|-------|
| `lib/features/shell_adaptive/file_operations_actions.dart` | 1754 |

---

### `use_key_in_widget_constructors` — **1 adet**
Public widget constructor'ında `key` parametresi olmalı.

| Dosya | Satır |
|-------|-------|
| `lib/features/shell_adaptive/panel_drive_bar.dart` | 606 |

---

## 📋 ÖZET VE ÖNCELİK SIRASI

| Öncelik | Kategori | Adet | Aksiyon |
|---------|----------|------|---------|
| **1 (Critical)** | `use_build_context_synchronously` | ~12 | **Hemen düzelt** - çökme riski |
| **2 (Critical)** | `unawaited_futures` | ~11 | **Hemen düzelt** - race condition |
| **3 (Critical)** | `dead_code` / `dead_null_aware` | 2 | **Sil** - erişilemez kod |
| **4 (High)** | `unnecessary_null_comparison` | 1 | Kaldır |
| **5 (High)** | Deprecation: `withOpacity` | ~15 | `withValues()` ile değiştir |
| **6 (High)** | Deprecation: `surfaceVariant` | 3 | `surfaceContainerHighest` ile değiştir |
| **7 (Medium)** | Deprecation: `value` → `initialValue` | 2 | Güncelle |
| **8 (Medium)** | Deprecation: `onPopInvoked` | 1 | Güncelle |
| **9 (Low)** | `unused_import` | ~10 | Sil |
| **10 (Low)** | `unused_field/element` | ~15 | Sil veya kullan |
| **11 (Low)** | `discarded_futures` | ~50 | `unawaited()` veya `async` yap |
| **12 (Low)** | `prefer_const_constructors` | ~20 | Const ekle |
| **13 (Low)** | `avoid_print` | ~20 | Logger kullan |
| **14 (Low)** | Diğer stil uyarıları | ~10 | Düzenle |

---

## 🛠️ ÖNERİLEN DÜZELTME SIRASI

1. **Önce kritik hataları düzelt** (kategoriler 1-4)
2. **Sonra deprecation'ları migrate et** (kategoriler 5-8)
3. **Son olarak kod temizliği** (kategoriler 9-14)

Bu sırayla giderseniz en riskli sorunlar önce çözülmüş olur.