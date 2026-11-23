# AIRTRACE v1.0.0 — Test Raporu

**Tarih:** 23 Kasım 2026
**Derleme:** CI çalıştırması #11 (`main`), Flutter 3.50.1 stable, Android build-tools 37.0.0

Bu rapordaki bütün sonuçlar GitHub Actions üzerinde **gerçek** derlemelerden ve **gerçek** canlı veriyle yapılan testlerden alınmıştır. Testlerde hiçbir yerde sahte uçak verisi kullanılmamıştır.

## Özet

| Aşama | Ortam | Sonuç |
|---|---|---|
| Statik analiz (`flutter analyze`) | Ubuntu | ✅ Sorun bulunamadı |
| Birim + widget testleri | Ubuntu | ✅ 26 / 26 geçti |
| Canlı API testleri (gerçek ağ) | Ubuntu | ✅ 2 / 2 geçti |
| Windows: kurulum, açılış ve kaldırma | Windows Server (windows-latest) | ✅ Geçti |
| Windows: uçtan uca (gerçek veri) | Windows masaüstü | ✅ Geçti |
| Android: release APK derlemesi | Ubuntu | ✅ Geçti |
| Android: uçtan uca (gerçek veri) | Android 14 emülatörü (API 34, Pixel 6) | ✅ Geçti |
| APK imzası (`apksigner verify`) | Yerel | ✅ v2 + v3 imza doğrulandı |

## İstenen kontrol listesi

| Kontrol | Windows | Android | Kanıt |
|---|---|---|---|
| Uygulama açılıyor mu? | ✅ | ✅ | Kurulumdan 20 sn sonra süreç çalışıyor. Uçtan uca testte açılış doğrulandı |
| Harita yükleniyor mu? | ✅ | ✅ | Açılışta dünya görünümü (zoom 2) geliyor. Ekran görüntüleri `docs/screenshots` klasöründe |
| Gerçek uçak verisi geliyor mu? | ✅ | ✅ | İlk veri 3 sn'de geldi. Dünya genelinde 9.210 (Windows) ve 4.029 (Android) uçak |
| Uçaklar doğru konumda mı? | ✅ | ✅ | ADS-B.lol kayıtlarının tamamı sorgu çemberinin içinde. Frankfurt çevresinde 672 uçak |
| Uçak yönleri doğru mu? | ✅ | ✅ | Birim testi: 0°, 90°, 180° ve 270° için burun yönü doğrulandı |
| Bilgi kartı çalışıyor mu? | ✅ | ✅ | Uçuş kodu, ülke, hız ve irtifa alanları görünüyor |
| Arama çalışıyor mu? | ✅ | ✅ | Uçuş koduyla arandı, sonuç seçilince uçağa odaklandı |
| Favoriler kaydediliyor mu? | ✅ | ✅ | ☆ ile eklendi |
| Favoriler korunuyor mu? | ✅ | ✅ | Diskten yeniden okununca kayıt duruyor |
| Harita kontrolleri çalışıyor mu? | ✅ | ✅ | Yakınlaştır/uzaklaştır ±1 zoom. "Konumuma dön" butonu görünüyor* |
| Bağlantı kesilmesi doğru yönetiliyor mu? | ✅ | ✅ | "Bağlantı yok" uyarısı çıkıyor. Kesintide 9.277 uçağın tamamı ekranda kaldı |
| Yeniden bağlantı çalışıyor mu? | ✅ | ✅ | İnternet geri gelince otomatik olarak "Canlı" durumuna döndü |
| API limitleri korunuyor mu? | ✅ | ✅ | ADS-B.lol'a 30 sn'de 3 istek (10 sn döngü). OpenSky'a 2 dk'da 1 istek (kredi bütçesi) |
| Bellek tüketimi makul mü? | ✅ | ✅ | Release sürümde açılışta 184 MB. Debug test sürümünde 9.281 uçakla 520 MB, Android'de 4.087 uçakla 454 MB |

\* Konum izni penceresi otomatik testte açılamadığı için "Konumuma dön" butonunun konum alma kısmı otomatik test edilmedi. İzin verilmezse uygulamanın çalışmaya devam ettiği kod incelemesiyle doğrulandı.

## Windows kurulum testi (çıktı)

```
Kurulum: True -> C:\Users\runneradmin\AppData\Local\Programs\AIRTRACE\AIRTRACE.exe
Başlat menüsü kısayolları: 2
Masaüstü kısayolu: True
20 sn sonra çalışıyor: True  RAM(MB): 184
Kaldırma sonrası exe var mı: False
```

## Canlı API testleri

| Sağlayıcı | Sorgu | Sonuç |
|---|---|---|
| ADS-B.lol | Frankfurt, 150 nm yarıçap | 271 uçak, hepsi çemberin içinde |
| OpenSky (anonim) | 47–54°K, 5–15°D kutusu | 500 uçak, hepsi kutunun içinde. Kalan kredi: 398 |

## Birim ve widget testlerinin kapsamı

- **Ayrıştırıcılar:** ADS-B.lol ve OpenSky alan sırası ve birimler. Yerdeki uçak için irtifa uydurulmuyor. Eski konumlar eleniyor
- **Rota:** Yalnızca `plausible=true` olan rotalar kabul ediliyor
- **Statik veri:** ICAO hex adresinden Türkçe ülke adı, havayolu adı, havalimanları
- **Geometri ve hareket:** Mesafe hesabı ve ara değerleme (60 sn sınırı, yerdeki uçağa tahmin yapılmaması)
- **Depo:** Eski veri yeni verinin üzerine yazmıyor. Kimlik bilgileri birleştiriliyor. Çevrimdışıyken kayıtlar silinmiyor
- **Planlayıcı:** Dar görünüm, dünya görünümü ve kota dolduğunda yedeğe geçiş
- **OpenSky bütçesi:** Anonim kullanımda 147 sn, hesapla 20 sn. Kota bitince gece yarısına kadar bekleme
- **Diğer:** Türkçe karakterlere duyarsız arama, 5 sıralama modu, kümelendirme, Türkçe biçimlendirme
- **Favoriler:** Kalıcılık ve bozuk kayıt dayanıklılığı
- **Widget testleri:** İnternet yokken masaüstü ve mobil düzende boş harita ve açık uyarı gösteriliyor, sahte uçak üretilmiyor

## Düzeltilen hatalar

Test sürecinde bulunup giderilen hatalar:

1. `Viewport` adı Flutter'daki sınıfla çakışıyordu → `MapViewport` olarak değiştirildi.
2. latlong2 kütüphanesinin `Path` sınıfı çizim API'siyle çakışıyordu → import yalnızca gerekli sınıfla sınırlandı.
3. Gradle Kotlin DSL dosyasında import'lar yanlış yerdeydi → dosyanın başına taşındı.
4. Simge rengi kaynağı ezilmişti ve Android derlemesi kırılıyordu → kaynak geri eklendi.
5. Widget testinde büyük asset'ler sahte zaman bölgesinde takılıyordu → gerçek async bölgede yükleniyor.
6. Mobilde harita atfı taşıyordu → kısaltılabilir atıf widget'ı yazıldı.
7. Başlangıç kamerası zoom 13 açılıyordu → başlangıçta dünya görünümü açılıyor.
8. `"İrtifa".toUpperCase()` → "İRTIFA" sonucu veriyordu → etiketler doğrudan Türkçe büyük harfle yazıldı.
9. Bilgi paneli açılırken genişlik animasyonu taşma yapıyordu → panel sabit genişlikte çizilip kırpılıyor.
10. Mobil bilgi kartı büyük yazı boyutunda taşıyordu → kart içerik yüksekliğine uyan düzene geçirildi.
11. Zaman aşımı yanlışlıkla "bağlantı yok" sayılıyordu → sağlayıcı hatası olarak sınıflandırıldı.
12. **CARTO, Eylül 2026'dan beri anahtar istiyor** ve haritada "API KEY REQUIRED" filigranı çıkıyordu → varsayılan altlık OpenStreetMap yapıldı ve lacivert renk matrisi eklendi. CARTO anahtarı isteğe bağlı olarak Ayarlar'dan girilebiliyor.

## Test edilemeyenler (açıkça)

- **Fiziksel Android telefon:** Testler Android 14 emülatöründe yapıldı, gerçek bir telefonda test yapılmadı.
- **Fiziksel Windows PC:** Testler GitHub'ın Windows Server sanal makinesinde yapıldı.
- **Windows SmartScreen:** Kurulum dosyası ücretli bir sertifikayla imzalı olmadığı için ilk açılışta uyarı çıkabilir.
- **OpenSky hesabıyla (4.000 kredi) çalışma:** Hesap bilgisi olmadığı için yalnızca anonim mod test edildi.
- **Gerçek GPS ile "Konumuma dön":** Bkz. yukarıdaki not.
