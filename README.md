# MacTweak

macOS 27 pencerelerini istediğiniz gibi ayarlar: köşe yarıçapı, trafik ışığı düğmeleri, eski uygulamaların başlık çubuğu. Ayar ekranı Sistem Ayarları düzeninde. Yeni ayar modülleri eklenecek.

## Gereksinim

SIP kapalı ve AMFI devre dışı (`boot-args` içinde `amfi_get_out_of_my_way=1`). Bu ikisi olmadan başka uygulamaların içine kod yüklenemez; bu işi yapan hiçbir araç çalışmaz. SIP yalnızca Kurtarma Modu'nda kapatılabilir, hiçbir uygulama bunu yapamaz.

MacTweak root yetkisi istemez ve sistem süreçlerine kod yüklemez.

## Parçalar

| Klasör | Çıktı | Ne yapar |
|---|---|---|
| `core/` | `libmactweak.dylib` | Her uygulamaya `DYLD_INSERT_LIBRARIES` ile yüklenir. Hiçbir çerçeveye bağlanmaz: AppKit'i olmayan süreçlerde (terminal komutları) yüklenir ama hiçbir şey yapmaz. AppKit sınıflarına adlarıyla, objc çalışma zamanından ulaşır. |
| `agent/` | `mactweak-agent` | Kullanıcı LaunchAgent'ı. Tercihleri notify durumlarına yazar ve tutar, çekirdeği `~/Library/Application Support/MacTweak`'e kopyalar, `launchctl setenv` ile ortama ekler, çökme raporlarını izler. |
| `app/` | `MacTweak.app` | SwiftUI ayar uygulaması. |
| `icon/` | `AppIcon.icns` | `icon/main.swift` ikonu vektörle çizer (plaka, şalter, vidalar, el damgası). `icon/private/icon.png` varsa onu kullanır (git'e girmez). |

Çekirdek modülleri: `corners.m` (köşe yarıçapı), `titlebar.m` (başlık çubuğu), `buttons.m` (trafik ışığı temaları). Yeni bir modül için:

1. `core/` altına dosyayı ekleyin.
2. `internal.h`'ye `mt_<ad>_install` bildirimini yazın.
3. `core.m`'deki `install()` fonksiyonuna çağrısını ekleyin.
4. `shared.h`'ye bayrağı ekleyin.
5. `agent.m`'ye tercihi ekleyin.
6. `app/Panes.swift`'e sayfasını ekleyin.

### Ayarlar uygulamalara nasıl ulaşıyor

Korumalı (sandbox) uygulamalar başka alan adının tercihlerini ve dosyaları okuyamaz, ama Darwin notify durumunu okuyabilir (TextEdit'te test edildi). Ajan iki tür durum yazar:

- 64 bitlik bir genel durum: `dev.hakanuzum.mactweak.settings`
- Uygulama başına bir durum: `dev.hakanuzum.mactweak.app.<paket>`

Bit düzeni `core/shared.h`'de. Notify durumu yalnızca bir süreç kaydı açık tuttuğu sürece yaşar, bu yüzden ajan sürekli çalışır. Ajan yoksa çekirdek hiçbir şeye dokunmaz.

Ayar değişince ajan `dev.hakanuzum.mactweak.settings` bildirimini yayınlar. Çekirdek de açık pencerelerin köşe maskesini ve düğmelerini yeniden çizer. Uygulamayı yeniden başlatmak gerekmez; tek istisna eski uygulamaların başlık ölçüleri.

### Kancalar (macOS 27.0.1'de ölçüldü)

- `-[NSThemeFrame _getCachedDefaultWindowCornerRadius]` ve `_getCachedWindowCornerRadii`: köşe maskesi (`NSCGSWindowCornerMask`) bunlardan oluşur. Varsayılan 16 nokta.
- `+[NSThemeFrame/NSTitledFrame _titlebarHeight:hasSolariumAppearance:]` ve ilgili ölçüler: eski SDK'lı uygulamalarda `NO` gelir (başlık 28 nk). Ayar açıksa `YES` (32 nk).
- `-[NSThemeFrame _collapseButtonOrigin]`, `_zoomButtonOrigin`: eski uygulamalarda düğme aralığı 20 → 23 nk. Eski/yeni ayrımı ana programın `LC_BUILD_VERSION` sdk alanından (< 26).
- `-[NSThemeFrame _shouldCenterTrafficLights]`: düğmeleri içeri alır (9 → 20 nk) ve ortalar. Araç çubuklu pencerelerde uygulanmaz.
- `-[_NSThemeWidgetCell drawWithFrame:inView:]`: trafik ışığı temaları. `buttonID` 25 kapat, 26 küçült, 27 büyüt.

Klavye dili baloncuğu (`TUINSCursorUIController`, 11.5 nk) gibi başlıksız pencerelere dokunulmaz.

**Dikkat:** Çekirdeğin kurucusu (constructor), uygulama kendini başlatmadan önce çalışır. Orada AppKit sınıflarına mesaj göndermeyin; ARC'nin eklediği `retain` de bir mesajdır. Mesaj gönderilirse `+initialize` erken çalışır ve SwiftUI, Chrome, Electron gibi uygulamalar çöker. `CLASS()` bu yüzden fonksiyon değil makro.

## Derleme

```sh
./build.sh            # build/MacTweak.app
./build.sh --install  # /Applications/MacTweak.app + çalışan ajanı yeniden başlat
```

Xcode 27 gerekir (`DEVELOPER_DIR` varsayılanı `/Applications/Xcode.app`).

## Güvenlik ağı

- Çöken iş parçacığında `libmactweak.dylib` varsa uygulama otomatik hariç tutulur ve bildirim gösterilir. MacTweak yalnızca yüklüyken 10 dakikada 3 çökme olursa da hariç tutulur.
- `MACTWEAK_DISABLE=1` ortam değişkeniyle başlatılan süreçte çekirdek hiçbir şey yapmaz.
- Güvenli Mod'da oturum ajanları çalışmaz, MacTweak yüklenmez.
- Elle kapatmak: `launchctl bootout gui/$(id -u)/dev.hakanuzum.mactweak.agent; launchctl unsetenv DYLD_INSERT_LIBRARIES`

## Günlük

`~/Library/Logs/MacTweak/agent.log`. Çekirdek için uygulamayı `MACTWEAK_LOG=1` ile başlatın.

## Lisanslar

- `assets/icons/*.svg`: WhiteSur ikon teması (vinceliuice), GPL-3.0 (`assets/WHITESUR-ICONS-GPL-3.0.txt`). Kaynak: github.com/vinceliuice/WhiteSur-icon-theme. Apple logosu içeren ikonlar bilerek seçilmedi. GPL-3.0 yüzünden MacTweak dağıtılacaksa GPL-3.0 uyumlu lisanslanmalı.
- `assets/hand-*.svg`: Microsoft Fluent Emoji, MIT (`assets/FLUENT-EMOJI-LICENSE`). Uygulama ikonundaki el damgası bunlardan çizilir.
