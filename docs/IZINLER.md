# İzinler ve gizlilik

Bu sayfa PikoMacV'nin neyi nerede sakladığını, hangi izinleri neden istediğini ve neleri göremediğini ayrıntısıyla anlatır. Kısa özet için [README](../README.md) bölümüne bakın.

Kısaca: PikoMacV hiçbir ağ bağlantısı kurmaz, analiz ya da telemetri göndermez. Verilerin tamamı bu Mac'te, kendi kullanıcı hesabınızın klasörlerinde durur.

## İstenen izinler

### Erişilebilirlik

Neden gerekir:

1. Seçtiğiniz öğeyi yapıştırmak için hedef uygulamaya ⌘V tuş basışını göndermek.
2. Fare tuşu tetikleyicilerini dinlemek (sistem genelinde fare tuşu olaylarını izleyen bir olay dinleyicisi kurulur).

İzin verilmezse: öğe yalnızca panoya konur, ⌘V'yi siz basarsınız; fare tuşu tetikleyicileri çalışmaz. Klavye kısayolları ve dokunmatik yüzey hareketi bu izne bağlı değildir.

Önemli: Erişilebilirlik izni teknik olarak geniş bir izindir; izin verilen uygulama diğer uygulamalara tuş gönderebilir. PikoMacV bu izni yalnızca yukarıdaki iki iş için kullanır ve kodu açıktır, kendiniz doğrulayabilirsiniz. Başka bir uygulamanın penceresini, ekranını ya da içeriğini okumaz.

Gerekçe ve ayar: Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik. Uygulamayı güncellediğinizde ya da kendiniz derlediğinizde macOS izni yeniden isteyebilir (README'deki sorun giderme bölümüne bakın).

### Touch ID veya cihaz parolası

Yalnızca panelde gizli bir sabitin içeriğini göstermek için göz simgesine bastığınızda sorulur. macOS'un standart doğrulama penceresidir (LocalAuthentication); PikoMacV parmak izinize ya da parolanıza erişmez, yalnızca "doğrulandı / doğrulanmadı" sonucunu alır. Gizli bir sabiti göstermeden yapıştırmak doğrulama gerektirmez.

### Anahtar Zinciri

Gizli sabitlerin içeriği Anahtar Zinciri'nde tutulur; bunun için ayrı bir izin penceresi çıkmaz. Ayrıntılar aşağıda.

### Dokunmatik yüzey hareketi (isteğe bağlı)

Üç parmakla çift dokunma, Apple'ın belgelenmemiş (özel) MultitouchSupport çerçevesi üzerinden algılanır. Çerçeve çalışma anında yüklenir; yalnızca bu tetikleyiciyi kullanmayı seçtiğinizde etkinleşir ve eklenmeden önce canlı bir testten geçer. Bu çerçeve Apple tarafından desteklenmez, bu nedenle bir macOS güncellemesinde davranışı değişebilir. Bu seçeneği hiç eklemezseniz çerçeveyle ilgili hiçbir şey çalışmaz. Çerçeve dokunuşların konumunu ve sayısını görür; PikoMacV bunlardan yalnızca "üç parmakla çift dokunma oldu mu" bilgisini çıkarır ve hiçbir yere kaydetmez (testin tanılama günlüğü hariç, aşağıya bakın).

### İstenmeyen izinler

- **Ekran Kaydı:** istenmez, kullanılmaz.
- **Giriş İzleme, Kamera, Mikrofon, Konum, Kişiler, Takvim, Tam Disk Erişimi:** istenmez.
- **Ağ:** uygulama ağ kodu içermez; hiçbir sunucuyla konuşmaz. Güncelleme denetimi de yoktur. (Yalnızca kurulum betiği, siz çalıştırdığınızda son sürümü GitHub'dan indirir.)

## Neler nerede saklanır

Ana klasör: `~/Library/Application Support/PikoMacV`

| Yol | İçerik |
| --- | --- |
| `history.json` | Pano geçmişi: her öğe için tür, tarih, kaynak uygulamanın adı ve kimliği, metin/bağlantı içeriği, görsel ve RTF dosya adları, dosya yolları ve boyutları. **Metinler bu dosyada düz metin olarak durur.** |
| `pins.json` | Sabitler: ad, gizli olup olmadığı ve (gizli olmayanlarda) içerik. Gizli sabitlerde içerik yoktur; yalnızca ad ve işaret saklanır |
| `settings.json` | Ayarlar: geçmiş sınırı, depo sınırları, tetikleyiciler, yok sayılan uygulamalar, oturum süreleri vb. |
| `blobs/` | Görseller (PNG) ve biçimli metin (RTF) verisi |
| `vault/` | Dosya kopyaları (her biri kendi alt klasöründe) |
| `trackpad-test.log` | Yalnızca dokunmatik yüzey testi çalıştırdıysanız: test zamanı, sonucu, kare sayısı ve dokunuşların neden kabul/ret edildiğine dair tanılama satırları. İçerik veya pano verisi yoktur |

Önbellek: `~/Library/Caches/PikoMacV` klasörü, görselleri dosya olarak yapıştırırken oluşturulan geçici PNG'leri tutar. 24 saatten eski dosyalar uygulama açılırken silinir.

Dosyalar, hesabınızın normal dosya izinleriyle durur. PikoMacV bunları ayrıca şifrelemez. Mac'inizde FileVault açıksa diskin tamamı şifrelidir; geçmişinizi korumak için FileVault kullanmanızı öneririz.

### Gizli sabitler nasıl saklanır

Gizli sabitin içeriği `pins.json`'da, `history.json`'da ya da başka bir dosyada değil, **Anahtar Zinciri'nde** durur. Teknik ayrıntılar:

- Kayıtlar, macOS'in kendi `/usr/bin/security` aracı üzerinden oluşturulur ve okunur; PikoMacV doğrudan Security API'si kullanmaz.
- Kayıt "genel parola" (generic password) türündedir. Servis adı `com.pikomacv.secrets`, hesap adı sabitin rastgele kimliğidir (UUID), etiket "PikoMacV gizli sabit" olur. Kayıtları Anahtar Zinciri Erişimi uygulamasında bu ada göre bulabilirsiniz.
- Değer, komut satırında görünmesin diye aracın standart girdisinden verilir ve onaltılık (hex) kodlanmış hâlde yazılır; yani kayıt, Anahtar Zinciri Erişimi'nde okunaklı metin olarak değil hex olarak görünür. Bu bir güvenlik katmanı değil, yalnızca komut satırı ve karakter sorunlarını önleyen bir kodlamadır.
- Yazılan değer hemen geri okunup doğrulanır.

**Bu tasarımın ödünleşimi (kodun kendi yorumlarında da belirtilir):** Apple geliştirici ekip kimliği olmayan, kendinden imzalı uygulamalarda Anahtar Zinciri öğeleri uygulamanın o anki ikili özetine bağlanır; uygulama güncellenince öğeler okunamaz hâle gelir ve sabitleriniz kaybolurdu. Bunu önlemek için kayıtlar, uygulamadan bağımsız, `-A` seçeneğiyle ("hangi uygulama olursa olsun sormadan okuyabilsin") oluşturulur. Bunun bedeli şudur: **aynı kullanıcı hesabıyla çalışan diğer programlar, bu kayıtları sizden onay istenmeden okuyabilir.** Kullanıcı oturumunuz açıkken Anahtar Zinciri kilitli olmadığı sürece, hesabınız altında çalışan bir program ya da betik, servis adını bilerek bu değerlere ulaşabilir.

Bunun pratik anlamı:

- Touch ID istemi, PikoMacV arayüzünde içeriği gösterme adımını korur (omuz üstünden bakan, ekranı açık bırakılmış Mac'e erişen biri için bir engeldir). Anahtar Zinciri'nin kendisi tarafından uygulanan bir kilit değildir.
- Kötü amaçlı yazılımlara karşı koruma beklemeyin. Gerçekten kritik parolalar (banka, ana parola vb.) için bir parola yöneticisi kullanmanızı öneririz.
- Dosya sistemine ya da yedeklerinize ulaşan biri `pins.json` içinden gizli içeriği çıkaramaz; ama oturum açık bir Mac'te yukarıdaki sınır geçerlidir.

Yapıştırma sırasında içerik Anahtar Zinciri'nden okunur, panoya "gizli" (`org.nspasteboard.ConcealedType`) işaretiyle yazılır ve ayarlanan süre (varsayılan 30 sn) sonunda, pano hâlâ sizin yazdığınız hâlindeyse temizlenir. "Gizli" işareti, bunu destekleyen pano geçmişi uygulamalarının değeri kaydetmemesini sağlar; bunun herkes tarafından uygulanacağının garantisi yoktur. Yapıştırma anında hedef uygulama değeri alır; sonrasında o uygulamanın kendi davranışı geçerlidir.

Bir geçmiş öğesini gizli olarak sabitlediğinizde özgün geçmiş satırı da `history.json` dosyasından silinir; içerik yalnızca Anahtar Zinciri'nde kalır.

## Neler asla kaydedilmez

- Gizli işaretli kopyalamalar: `org.nspasteboard.ConcealedType`, `TransientType` ve `AutoGeneratedType` işaretli pano içeriği atlanır. Parola yöneticileri (1Password, Bitwarden vb.) bu işaretleri kullanır; ancak uygulamanın işareti koyup koymadığı o uygulamaya bağlıdır.
- Ayarlar > Genel > "Yok sayılan uygulamalar" listesindeki uygulamalardan kopyalananlar.
- PikoMacV'nin kendi yazdığı pano içeriği (yapıştırdığınız öğe tekrar kaydedilmez).
- Boş ya da yalnızca boşluktan oluşan metinler.
- Gizli sabitlerin içeriği (geçmişte ve `pins.json`'da).
- Yazdığınız tuşlar: PikoMacV bir tuş kaydedici değildir. Klavye kısayolları sistemin kısayol mekanizmasıyla kaydedilir; yalnızca sizin tanımladığınız kombinasyonlar PikoMacV'ye bildirilir. Panel açıkken yalnızca panelin kendi tuşlarına bakılır.

## Uygulamanın görebildikleri ve göremedikleri

Görebildikleri:

- **Pano içeriği:** metin, bağlantı, görsel ve dosya yolları. Pano her 0,4 saniyede bir değişiklik için denetlenir.
- **Önde olan uygulamanın adı ve kimliği (bundle ID):** hangi uygulamadan kopyalandığını göstermek, uygunluk kurallarını uygulamak ve "yok sayılan uygulamalar"ı işletmek için.
- **Kopyalanan dosyaların içeriği,** boyut sınırı içindeyse: kopya olarak `vault/` içine alınır.
- **Fare tuşu basışları,** yalnızca bir fare tuşu tetikleyicisi tanımladıysanız ve Erişilebilirlik izni varsa. Sadece 2. ve üzeri ("orta" ve yan) tuşların basışları incelenir; atanmış olanlar yutulur, atanmamış olanlar olduğu gibi geçer, hiçbiri saklanmaz.

Göremedikleri ve yapmadıkları:

- Diğer uygulamaların pencere içeriğini, ekranı, ekran görüntülerini okumaz (Ekran Kaydı izni yoktur). Panelin kendisi de ekran paylaşımında ve kayıtlarda görünmez.
- Yazdığınız tuşları kaydetmez.
- Ağ üzerinden hiçbir şey göndermez ya da almaz.
- Tarayıcı geçmişinize, dosyalarınıza (kopyalamadıklarınıza), e-postalarınıza erişmez.
- Gizli sabiti, siz göz simgesine basıp doğrulama yapmadan panelde göstermez.

## Her şeyi silmek

PikoMacV'nin bıraktığı her şeyi temizlemek için:

1. Menü çubuğundaki simgeden "PikoMacV'den çık" deyin.
2. Uygulamayı Uygulamalar klasöründen (ya da `~/Applications`) çöp kutusuna taşıyın.
3. Şu iki klasörü silin:
   ```bash
   rm -rf "$HOME/Library/Application Support/PikoMacV"
   rm -rf "$HOME/Library/Caches/PikoMacV"
   ```
4. Gizli sabitlerin Anahtar Zinciri kayıtlarını silin. Anahtar Zinciri Erişimi'nde "com.pikomacv.secrets" araması yapıp bulunan kayıtları silebilirsiniz, ya da Terminal'de şunu kayıt kalmayana kadar çalıştırabilirsiniz (her çalıştırma bir kaydı siler; kayıt kalmayınca hata verir):
   ```bash
   while security delete-generic-password -s com.pikomacv.secrets >/dev/null 2>&1; do :; done
   ```
5. İsterseniz Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik listesinden PikoMacV'yi kaldırın.

Kaldırma betiği (`uninstall.sh`) 2-4. adımları, terminal etkileşimliyse onayınızı alarak sizin yerinize yapar (varsayılan cevap "hayır"dır; veriler yalnızca "e" derseniz silinir).

Yalnızca geçmişi silmek için Ayarlar > Depolama > "Geçmişi temizle" ya da menü çubuğundaki "Geçmişi temizle" kullanılır; sabitler korunur. Tek bir sabit, panelde ⌘⌫ ile silinir.
