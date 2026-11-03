# Mobil Menajerlik Oyunu — Simülasyon Tasarım Çalışması

Tarih: 2026-10-20
Durum: Ön tasarım. Teknoloji seçimi bilinçli olarak ertelendi. Bu belge "ne" ve "nasıl çalışır" sorusuna cevap verir; "hangi dil/framework" sorusuna değil.

---

## 1. Niyet

Championship Manager (özellikle CM 01/02) hissini veren, telefonda dikey (portrait) oynanan bir futbol menajerlik oyunu. Oyuncu bir kulübün **teknik direktörüdür**; üstünde bir **yönetim kurulu/başkan** vardır. Yönetim bütçeyi verir, beklenti koyar, memnuniyetsizse kovar. Teknik direktör kadro, taktik, transfer, antrenman ve altyapıdan yükseltme kararlarını verir; yönetimden bütçe artışı ve tesis yatırımı ister. Başarılı olursa başka kulüplerden iş teklifi alır; kovulursa işsiz kalır ve yeni iş arar. Zaman gün gün ilerler; her gün antrenman, sakatlık, transfer, sözleşme, maç olayları işlenir. Oyunun kalbi maç simülasyonudur: inandırıcı skorlar, inandırıcı lig tabloları, "bir şey oluyor" hissi veren maç anlatımı.

Her şey kurgusaldır: kulüp, takım, oyuncu, personel isimleri, formalar, logolar, stadyumlar. Arayüz dili (Türkçe/İngilizce) değişince bu isimler değişmez.

Bu belgedeki tüm sayısal değerler (katsayılar, olasılıklar, süreler) başlangıç değerleridir. Kalibrasyon düzeneği (Bölüm 9) ile ayarlanacaklardır.

---

## 2. Hedefler, hedef olmayanlar, anti-hedefler

**Hedefler**
- Bir sezonu baştan sona oynamak zevkli olsun: maç günü gerilimi, transfer dönemi telaşı, sakatlık krizleri.
- Simülasyon tutarlı olsun: iyi takımlar genelde kazanır ama sürprizler olur; lig tabloları gerçekçi görünür.
- Dikey ekranda tek elle oynanabilsin. Her ekran tek sütun, yukarıdan aşağı okunur.
- Maç, CM 01/02 tarzı 2D kuşbakışı sahada yuvarlak "boncuk" oyuncularla izlensin; altında metin anlatım aksın. İkisi aynı olaydan beslensin.
- Oyun dünyası sonsuz yaşasın: oyuncular gelişir, yaşlanır, sakatlanır, emekli olur; altyapıdan yenileri gelir. 30 sezon sonra da dünya dengeli kalsın.
- Türkçe ve İngilizce, ilk sürümden itibaren.
- Çekirdek simülasyon motoru arayüzden tamamen bağımsız olsun; başsız (UI'sız) çalıştırılıp test edilebilsin.
- Deterministik olsun: aynı tohum (seed) + aynı girdiler = aynı sonuç. Hem test hem hata ayıklama için şart.

**Kapsam kararı (2026-10-20, kullanıcı):** Klasik CM'in (01/02) tüm özellikleri hedef. Geliştirme süresi kısıt değil; eksiksiz ve sonsuz döngülü bir oyun önceliklidir. Özellikler fazlara bölünür (Bölüm 11) ama hiçbiri "hedef dışı" değildir. Bölüm 16, Bölüm 3-10'da olmayan tüm CM sistemlerini tanımlar.

**Hedef olmayanlar (kalıcı)**
- 3D maç görselleştirmesi veya fizik tabanlı 2D (topun ve oyuncuların fizikle hareket ettiği motor). 2D görsel, motorun ürettiği olayların canlandırmasıdır; sonucu etkilemez (Bölüm 5.7).
- Çok oyunculu / online.
- Gerçek kulüp, oyuncu, personel isimleri, formalar, logolar. Lisans sorunu; her şey kurgusal.
- Basın toplantısı ve oyuncu diyalogları (bunlar FM dönemi özellikleri, CM 01/02'de yoktu). Haber ve medya tepkisi var (Bölüm 16.10).
- Kulüp sahipliği / başkanlık rolü. Oyuncu teknik direktördür; para yönetimi "verilen bütçeyi harcamak ve yönetimden daha fazlasını istemek" düzeyindedir. Bilet fiyatı, stadyum, krediyi yönetim belirler (Bölüm 16.9).

**Anti-hedefler (teknik olarak çalışsa bile başarısızlık sayılır)**
- Her maçın aynı hissettirmesi. (Anlatım tekdüze, skorlar hep 1-0, 2-1.)
- Determinizm hissi: en güçlü takım her zaman kazanıyor.
- Dejenere transfer piyasası: tüm yıldızlar tek kulüpte toplanıyor, yapay zeka kulüpler iflas ediyor veya 45 kişilik kadro kuruyor.
- Günün işlenmesi telefonda 1 saniyeden uzun sürmesi.
- "Pay-to-win" mekaniği gerektiren tasarım kararları.

---

## 3. Oyunun omurgası: Gün döngüsü

Her şey tek bir fonksiyona bağlanır: `advanceDay(world, rng) -> world + events[]`.

**Simetri ilkesi: dünya kullanıcıdan bağımsız yaşar.** Kullanıcının kulübü motor için özel değildir; sadece teknik direktör koltuğunda AI yerine kullanıcı oturur. Diğer tüm kulüpler aynı gün döngüsünden geçer: antrenman yapar, sakatlanır, transfer yapar, sözleşme uzatır, menajer kovar, altyapıdan oyuncu çıkarır, küme düşer, yönetimi değişir. Kullanıcı işsizken ya da milli takımdayken de dünya aynen akar. Kullanıcının kulübündeki her karar bir "komut"tur (kadro, taktik, teklif, istek); kullanıcı komut vermezse AI menajerin varsayılan kararı uygulanır (ör. kadroyu yardımcıya bırakmak). Bu ilkenin testi: Bölüm 9 ve 17'deki tüm uzun simülasyonlar **kullanıcısız** koşar; kullanıcı eklenince dünyanın istatistikleri değişmemelidir.

Kullanıcı "Devam" tuşuna basar; bir gün işlenir; eğer o gün kullanıcıyı ilgilendiren bir olay varsa (maç, teklif, sakatlık, sözleşme) döngü durur ve ekrana gelir. Yoksa bir sonraki güne geçilir ("maça kadar devam et" kısayolu).

Günün işlem sırası (sıra önemli, değiştirilmemeli):

1. **Takvim** — Bugünün olayları: lig maçı mı, kupa mı, transfer penceresi açılıyor/kapanıyor mu, sözleşme bitiş tarihi mi, sezon sonu mu.
2. **Oyuncu günlük güncellemesi** (her oyuncu için, tüm kulüpler):
   - Kondisyon toparlanması
   - Sakatlık iyileşmesi (kalan gün sayısı azalır, iyileşince "maç formu düşük" dönemi başlar)
   - Moral ve form sönümlemesi (nötr değere doğru yaklaşma)
   - Antrenman etkisi (küçük günlük artış, gelişim eğrisine göre)
   - Antrenmanda sakatlanma zarı
3. **Yapay zeka kulüpler** — Bugün sırası gelen kulüpler (round-robin, günde N kulüp) kadro ihtiyacını değerlendirir, transfer teklifi yapar, teklifleri cevaplar, sözleşme uzatır, kadroyu belirler. (Bölüm 7)
4. **Transfer işlemleri** — Bekleyen tekliflerin süresi dolar, kabul edilenler tamamlanır, oyuncu kulüp değiştirir.
5. **Maçlar** — Bugünün tüm maçları simüle edilir. Kullanıcı maçı "detaylı mod", diğerleri "hızlı mod" ile ama aynı motorla. (Bölüm 5)
6. **Maç sonrası** — Puan tablosu, gol krallığı, moral/form güncellemeleri, maçta olan sakatlıklar ve kartlar işlenir, ceza (kart birikimi) uygulanır.
7. **Finans** — Haftalık: maaş ödemesi, maç günü geliri, sponsorluk. (Basit tutulur.)
8. **Haber/Gelen kutusu** — Kullanıcıyı ilgilendiren olaylar mesaja dönüştürülür.
9. **Sezon sonu** (yılda bir) — Şampiyon, küme düşme/çıkma, yaş ilerletme, emeklilik, sözleşme bitimleri, yeni fikstür, kadro sayısı dengeleme.

**Performans bütçesi.** Dünya boyutu oyun başında seçilir (Bölüm 16.12): küçük 4 ülke, orta 8, büyük 16. Büyük dünya: 16 ülke × ~60 kulüp × 28 oyuncu + altyapı ≈ 30.000 oyuncu, maç günü 500'e kadar maç × ~150 adım. Hedef: telefonun tek çekirdeğinde 1 gün < 300 ms (maç günü), < 50 ms (diğer günler). Bu, Faz 0'da büyük dünyayla ölçülür; tutmuyorsa maçlar arka planda iş parçacığında koşar, arayüz "işleniyor" gösterir.

---

## 4. Veri modeli (özet)

Alanlar dilden bağımsız, kavramsal olarak verilmiştir.

**Oyuncu (Player)**
- Kimlik: id, ad, uyruk, doğum tarihi, boy
- Pozisyonlar: ana pozisyon + yeterlilik haritası (GK, DL, DC, DR, DM, ML, MC, MR, AMC, ST için 0-20 yatkınlık)
- Nitelikler (1-20, CM geleneği), üç grup:
  - *Teknik:* pas, şut, top kontrolü, dripling, orta, kafa, uzun top, bitiricilik, müdahale (tackling)
  - *Zihinsel:* karar verme, pozisyon alma, önsezi, soğukkanlılık, iş oranı, takım oyunu, agresiflik, konsantrasyon
  - *Fiziksel:* hız, ivmelenme, dayanıklılık, güç, denge, zıplama, çeviklik
  - *Kaleci:* refleks, hava hakimiyeti, elle oynama, bire bir, komuta
- Gizli nitelikler: potansiyel (PA, 1-200), mevcut yetenek (CA, 1-200, niteliklerden türetilir), sakatlık yatkınlığı (1-20), tutarlılık, önemli maç performansı, profesyonellik
- Durum: kondisyon (0-100), maç formu/keskinlik (0-100), moral (0-100), form (son 5 maç puanı ortalaması), sakatlık (varsa tip + kalan gün), ceza (kalan maç), sarı kart sayısı
- Sözleşme: kulüp, haftalık ücret, bitiş tarihi, rol (ilk 11 / rotasyon / yedek / genç), serbest kalma bedeli (opsiyonel)
- İstatistik: sezonluk ve kariyer (maç, gol, asist, ortalama puan, kart)

**Kulüp (Club)** — id, ad, kısa ad, lig, itibar (1-100), forma renkleri (ev/deplasman: ana + ikincil renk; 2D boncuklar bunu giyer), logo (prosedürel: şekil + renk), stadyum adı ve kapasitesi, bütçe (transfer + maaş tavanı), kasa bakiyesi, tesisler (antrenman, tıbbi, altyapı: 1-10), taktik (formasyon + ayarlar), kadro, altyapı kadrosu, teknik direktör (kullanıcı veya AI), yönetim beklentisi (şampiyonluk / üst sıra / orta / küme düşmeme), yönetim güveni (0-100).

**Teknik direktör (Manager)** — id, ad, uyruk, itibar (1-100), tercih edilen formasyon/tarz, kulüp (veya işsiz), sözleşme (maaş, bitiş), kariyer kaydı (kulüpler, kupalar, galibiyet oranı). Kullanıcı da bu varlıktır; AI kulüplerin de teknik direktörleri vardır ve onlar da kovulur/transfer olur.

**Lig (League)** — id, ülke, seviye, kulüpler, fikstür, puan tablosu, küme düşme/çıkma sayıları, itibar.

**Maç (Match)** — tarih, ev/deplasman kulüp, yarışma, kadrolar, taktikler, sonuç, olay listesi (dakika, tip, oyuncu, açıklama), istatistik (şut, isabetli şut, topla oynama, korner, faul, kart).

**Transfer teklifi (TransferOffer)** — alıcı, satıcı, oyuncu, bedel, ödeme şekli, durum, son geçerlilik tarihi.

**Olay (Event)** — Günlük döngünün ürettiği her şey. Haber sistemi ve test düzeneği bu listeden beslenir.

---

## 5. Maç simülasyonu — en zor parça

### 5.1 Üç yaklaşım ve seçim

| Yaklaşım | Nasıl | Artı | Eksi |
|---|---|---|---|
| **A. İstatistiksel** (Poisson/xG) | Takım güçlerinden beklenen gol hesapla, Poisson'dan örnekle | 10 satır kod, kolay kalibre | Olay yok, anlatım yok, oyuncu istatistiği yok |
| **B. Topa sahip olma tabanlı** (possession/olay motoru) | Maçı ~100-130 "hücum" adımına böl, her hücumu fazlarla çöz | Anlatım, oyuncu bazlı istatistik, taktik etkisi, oyuncu değişikliği | Orta karmaşıklık, kalibrasyon gerektirir |
| **C. Fiziksel 2D ajan** (FM tarzı) | 22 ajan sahada hareket eder | En zengin | Tek kişilik mobil proje için fazla ağır; yıllarca ayar gerektirir |

**Karar: B + görselleştirme katmanı.** Tüm maçlar için tek motor. Kullanıcı maçı 2D sahada ve anlatımla izlenir; diğer maçlar aynı motorla görsel/anlatım üretilmeden koşar. Tek motor şart: farklı motorlar farklı dağılım üretir, lig tabloları tutarsızlaşır.

2D görsel (boncuklar) için C yaklaşımına gidilmez. Motor her hücum adımında **koordinatlı mikro-olay dizisi** üretir (pas A→B, sürme, orta, şut; her biri saha koordinatıyla). Anlatım bu diziyi cümleye çevirir, 2D katman aynı diziyi canlandırır (Bölüm 5.7). Sonuç motorda belirlenir; görsel sadece gösterir. CM 01/02'nin yaptığı da özünde budur.

A yaklaşımı sadece "Faz 0" iskelet için geçici olarak kullanılır (Bölüm 11), sonra atılır.

### 5.2 Maç öncesi: takım güç profilleri

Her takım için ilk 11'den ve taktikten şu sayılar türetilir (hepsi yaklaşık 1-20 ölçeğinde):

- **Orta saha kontrolü (MID):** orta saha oyuncularının pas, takım oyunu, iş oranı, karar verme, dayanıklılık ağırlıklı ortalaması + formasyondaki orta saha sayısı etkisi.
- **Hücum, üç koridor (ATT_L, ATT_C, ATT_R):** o koridordaki hücum oyuncularının hız, dripling, orta/pas, bitiricilik, önsezi ağırlıklı ortalaması.
- **Savunma, üç koridor (DEF_L, DEF_C, DEF_R):** müdahale, pozisyon alma, kafa, güç, konsantrasyon, hız.
- **Kaleci (GK):** refleks, bire bir, elle oynama, pozisyon alma.
- **Duran top hücum / savunma:** kafa, zıplama, uzun top, orta.
- **Tempo / pres:** taktik ayarı, kondisyonu daha hızlı tüketir.

Her oyuncunun katkısı şu çarpanla ölçeklenir:

```
etkinlik = nitelik
         × pozisyonYatkınlığı(0.6–1.0)
         × kondisyon_faktörü(0.75–1.0)      // kondisyon 100 → 1.0, 50 → 0.75
         × maçFormu_faktörü(0.9–1.0)
         × moral_faktörü(0.95–1.05)
         × form_faktörü(0.95–1.05)
```

Ev sahibi avantajı: ev sahibinin tüm hücum ve orta saha değerlerine ×1.06 (kalibre edilecek; gerçek futbolda ev galibiyeti ~%45, beraberlik ~%25, deplasman ~%30). (Faz 1a kararı: çarpan yalnız hücumda; orta sahada ev avantajı 1. adımda toplamsal log-odds terimi `homeLogOdds` olarak uygulanır — bkz. engine README "Tuning constants that differ from the spec".)

### 5.3 Maç döngüsü

Maç, 90 dakika + uzatma boyunca **hücum (possession) adımları** halinde ilerler. Her adım 30-90 saniye arası rastgele sürer (tempoya göre); toplamda maç başına ~110-130 hücum, takım başına ~55-65.

Her hücum adımı:

```
1. TOPA SAHİP OLAN TAKIM
   p_ev = logistic( k1 × (MID_ev − MID_dep) )        // k1 ≈ 0.25; eşit takımlarda %50
   (Faz 1a kararı: p_ev = (1−c)/2 + c × logistic(k1 × ΔMID + homeLogOdds × ev payı),
    c = midContestShare × (1 − ortalama midBypass); k1 1.0 — spec eğrisi 5.6 ancak
    sınırlı bir orta saha payıyla tutuyor; bkz. engine README.)
   Bazı hücumlar bir önceki hücumun doğal devamıdır (korner, taç, top kaybı sonrası
   kontra). Kontra: topu kaybeden takımın hücumu bittiğinde %15 ihtimalle diğer takım
   "kontra" bayrağıyla hücum eder; kontrada savunma değeri ×0.8.

2. HÜCUM KORİDORU SEÇİMİ
   Taktik ağırlıklarına göre sol/orta/sağ (ör. kanat oyunu: 35/30/35; içeriden: 20/60/20).

3. ŞANS YARATMA
   p_şans = logistic( k2 × (ATT_koridor − DEF_koridor) + b_şans )
   b_şans öyle ayarlanır ki eşit takımlarda hücum başına ~%20 şans çıkar
   (→ maç başına takım başına ~12 şut). k2 ≈ 0.20.
   Şans yoksa: adım "sıradan hücum" olarak biter; küçük ihtimalle faul/taç/korner.

4. ŞANS TİPİ (koridora ve takım profiline göre ağırlıklı)
   ara pası (through ball), orta (cross), uzak şut (long shot), bireysel aksiyon (dribble),
   korner, serbest vuruş, penaltı (nadir: maç başına ~0.25)

5. ŞUTU ÇEKEN OYUNCU
   Koridor ve şans tipine göre ağırlıklı seçim: ara pası → forvetler; orta → kafası iyi
   olanlar; uzak şut → uzak şut niteliği yüksek orta saha. Asist: pas/orta niteliği
   yüksek olanlardan.

6. ŞANSIN KALİTESİ (xG, 0-1)
   Şans tipinin taban xG'si (penaltı 0.76, ara pası 0.30, orta 0.12, uzak şut 0.05,
   bireysel 0.20, korner 0.08, serbest vuruş 0.07)
   × (1 + 0.02 × (hücumcu.bitiricilik + hücumcu.soğukkanlılık − 20))
   × (1 − 0.015 × (kaleci.GK − 10))

7. SONUÇ
   r ~ U(0,1)
   r < xG            → GOL
   r < xG + 0.25     → kaleci kurtardı (isabetli şut)
   r < xG + 0.45     → blok / direk (nadiren direk: anlatım için)
   aksi              → dışarı (isabetsiz şut)
   Kurtarış → %30 korner (yeni hücum, aynı takım), %70 kaleci topu oyuna sokar.

8. YAN ETKİLER (her adımda)
   - Faul: p ≈ 0.10/adım; faul yapan: savunan takımdan agresiflik ağırlıklı seçim.
     Faul → sarı kart p ≈ 0.12 (agresiflik ve kaleye yakınlık ile artar), kırmızı p ≈ 0.008.
     İkinci sarı → kırmızı. 10 kişi kalan takımın MID ve DEF değerleri ×0.85.
   - Sakatlık: p ≈ 0.0025/adım/oyuncu-maruziyeti → maç başına ~0.3 sakatlık.
     (Bölüm 6'da detay.)
   - Kondisyon: her oyuncu dakika başına ~0.25 puan kaybeder
     (dayanıklılık 20 → 0.18, dayanıklılık 5 → 0.35; yüksek tempo/pres ×1.3).
     Kondisyon < 70 olunca etkinlik hissedilir düşer; AI bu noktada değişiklik düşünür.

9. YAPAY ZEKA TAKTİK KARARLARI (her 5 dakikada bir kontrol)
   - 60'+ ve geride: mentalite bir kademe yukarı (hücum ↑, savunma ↓).
   - 75'+ ve önde: mentalite bir kademe aşağı.
   - Kondisyonu < 65 olan oyuncu için değişiklik (en iyi yedek, aynı pozisyon).
   - Sakatlanan oyuncu için zorunlu değişiklik; hak bitmişse 10 kişi.
   - Kullanıcı maçında kullanıcı aynı kararları kendisi verir (motor duraklar).

10. UZATMA
    Her yarı 1-6 dk; kart, sakatlık ve gol sayısına göre artar.

11. MİKRO-OLAY DİZİSİ (adımın çıktısı)
    Her hücum adımı 2-6 mikro-olaydan oluşan bir dizi döndürür. Örnek, "sağ koridor, orta, kafa, kurtarış":
      {t:0.0, tip:pas,   kimden:MC(5), kime:MR(7), nereden:(52,30), nereye:(70,78)}
      {t:2.5, tip:sürme, kim:MR(7),    nereden:(70,78), nereye:(85,88)}
      {t:4.0, tip:orta,  kimden:MR(7), kime:ST(9),  nereden:(85,88), nereye:(60,94)}
      {t:5.5, tip:kafa,  kim:ST(9),    hedef:(50,100), sonuç:kurtarış, gk:GK(1)}
    Koordinatlar: saha 100×100, hücum eden takım yukarı doğru. Noktalar koridor+bölgeden
    rastgele örneklenir (görsel RNG, sonuç RNG'den ayrı akış). Oyuncu seçimi adım 5'tekiyle
    tutarlıdır. Anlatım ve 2D bu diziyi kullanır; hızlı modda üretilmez.
```

**Oyuncu maç puanı (1-10):** Taban 6.0; gol +1.0, asist +0.5, kurtarış +0.1 (kaleci), kaybedilen topla sahip olma adımı −0.05, kritik hata −0.5, kart −0.3/−1.0, takım galibiyeti +0.3, temiz sayfa (savunma/kaleci) +0.5. Form ve moral bu puandan beslenir.

### 5.4 Detaylı ve hızlı mod

Aynı motor, iki çıktı seviyesi:

- **Hızlı mod:** sadece sonuç + olay listesi (gol, kart, sakatlık, değişiklik) + istatistik. Anlatım metni üretilmez.
- **Detaylı mod (kullanıcı maçı):** her adım için anlatım satırı üretilir ve kullanıcı istediği hızda izler. Her adımda duraklatıp taktik/değişiklik yapabilir. Önemli olaylar (gol, penaltı, kırmızı kart, sakatlık) otomatik duraklatır.

**Determinizm kuralı:** Hızlı ve detaylı mod aynı seed ile aynı sonucu vermeli. Anlatım üretimi rastgelelik tüketmemeli (ayrı bir RNG akışı kullanır). Bu, "maçı hızlı geç" ile "maçı izle" arasındaki tutarlılığı garantiler.

### 5.5 Dikey ekranda maç sunumu

Yukarıdan aşağı:

1. Skor çubuğu: ev 2 - 1 dep, dakika, hız kontrolü (▶ ▶▶ ▶▶▶ ⏸)
2. **2D saha** (ekranın ~%45'i, dikey saha tam oturur): 22 boncuk + top. Ev takımı aşağıdan yukarı hücum eder; devre arasında yön değişir. Boncuk üzerinde forma numarası; dokununca ad ve kondisyon. Gol, kart, sakatlık anında kısa vurgu (büyüyen halka, renk). (Bölüm 5.7)
3. Anlatım akışı: son 5-8 olay, en yenisi altta. Gol satırı vurgulu. Anlatım, 2D'deki hareketle eş zamanlı.
4. Alt sekmeler: Taktik | Kadro (değişiklik) | İstatistik | Diğer maçlar

Anlatım cümleleri, olay tipine göre 8-15 varyasyon içeren şablon havuzlarından çekilir ("{A}, {B}'nin ara pasıyla ceza sahasına giriyor… şut… {GK} köşeden çıkardı!"). Tekdüzelik anti-hedefini bu havuzların zenginliği karşılar. Havuzlar Türkçe ve İngilizce ayrı yazılır; Türkçe şablonlar ek uyumu için yardımcı kullanır ("{A:in}" → "Arda'nın").

### 5.7 2D görselleştirme katmanı (boncuklar)

Fizik yok; **koreografi** var. Her boncuk, her karede şu hedefe doğru yumuşak hareket eder (lerp, hız oyuncunun hız niteliğiyle sınırlı):

```
hedef = formasyonKonumu(oyuncu)                       // 4-4-2'de MR için (75, 50) gibi
      + takımKayması(top.konum)                       // takım şekli topla birlikte kayar: x'in %40'ı, y'nin %30'u
      + mentaliteKayması                              // hücumcu mentalite: tüm hat +8 ileri
      + rolKayması(mikro-olay)                        // pas alacak oyuncu topa koşar; şut çeken ceza sahasına girer
      + küçük gürültü                                 // boncuklar "kıpırdasın"
```

Top, mikro-olay dizisindeki `nereden → nereye` arasında, olayın süresi (`t` farkı) boyunca hareket eder; pas düz çizgi, orta/uzun top hafif yay (gölgeyle), sürme top boncuğa yapışık. Topsuz dönemde (adımlar arası) top "sahip" boncukla gider.

Savunan takımın boncukları, kendi formasyon konumu + topa doğru kayma ile yerleşir; müdahale eden savunmacı (motor seçer) top taşıyıcıya koşar. Kaleci kale çizgisinde topun x'ini takip eder; kurtarış animasyonu top kaleye giderken boncuk topa doğru atılır.

Ölçek: dikey ekranda saha 360×520 px civarı; boncuk çapı 14-16 px. Kare hızı 30 fps yeter. Hız kontrolü (▶▶, ▶▶▶) olay sürelerini kısaltır; "⏭ hızlı bitir" geri kalanı hızlı modda koşar.

Kalibrasyon ile ilişkisi: bu katman sonucu etkilemediği için Bölüm 9 testleri 2D olmadan koşar. 2D ayrı bir "görsel kabul" listesiyle doğrulanır: boncuklar birbirine girmiyor, top ışınlanmıyor, pas alan oyuncu topun geldiği yerde, ofsayt çizgisi mantıksız değil, 90 dakika boyunca akıcı.

Teknik gereksinim: tek bir çizim yüzeyi (canvas) + kare döngüsü. Oyun motoru şart değil; her modern arayüz çatısı bunu yapar.

### 5.6 Yetenek farkı → sonuç eğrisi (tasarım hedefi)

Motorun en önemli özelliği: güç farkıyla kazanma ihtimali arasındaki eğri. Hedef:

| Güç farkı (CA ort.) | Güçlü takımın galibiyet % | Beraberlik % | Zayıfın galibiyet % |
|---|---|---|---|
| 0 | 45 (ev) | 26 | 29 |
| +10 | 55 | 24 | 21 |
| +20 | 65 | 20 | 15 |
| +40 | 78 | 14 | 8 |

Bu tablo kalibrasyonun kabul kriteridir. Gerçek futbolda lider ile sonuncu arasında bile "%80'i geçmeyen" kazanma oranı vardır; bu sağlanmazsa oyun determinist hissettirir.

---

## 6. Sakatlıklar

### 6.1 Kaynaklar ve olasılıklar

Günlük sakatlık zarı üç yerden atılır:

| Kaynak | Taban olasılık | Çarpanlar |
|---|---|---|
| Maç içi | 0.0025 / hücum adımı / oyuncu (→ maç başına ~0.3) | sakatlık yatkınlığı (1→×0.5, 20→×2.0), kondisyon<70 (×1.5), kondisyon<50 (×2.5), yaş>31 (×1.3), sert müdahale alan oyuncu (faul anında ×4), tempo yüksek (×1.2) |
| Antrenman | 0.004 / gün / oyuncu (→ 25 kişilik kadroda ayda ~3) | yatkınlık, yaş, antrenman yoğunluğu (hafif ×0.6, ağır ×1.6), tesis kalitesi (10 → ×0.7) |
| Yeniden sakatlanma | iyileşme sonrası 21 gün boyunca tüm olasılıklar ×2 | tıbbi tesis iyileştirir |

Gerçeklik referansı: Premier Lig kulüpleri sezonda ortalama ~35 sakatlık yaşıyor (2015/16, JLT verisi); kulüp başına kaybedilen gün sayısı 200 ile 2.400 arasında (ortalama ~1.000). Hedefimiz: kulüp başına sezonda 25-40 sakatlık, herhangi bir anda ortalama 2-4 oyuncu sakat.

### 6.2 Şiddet ve tür

Şiddet önce seçilir (kümülatif dağılım), sonra tür:

| Şiddet | Olasılık | Süre | Örnek türler |
|---|---|---|---|
| Hafif | %45 | 1-7 gün | ezilme, hafif burkulma, kas yorgunluğu |
| Orta-hafif | %30 | 1-3 hafta | hamstring gerilmesi, kasık, ayak bileği burkulması |
| Orta | %15 | 3-8 hafta | kas yırtığı, diz bağı zorlanması, omuz |
| Ciddi | %8 | 2-5 ay | menisküs, kırık, Aşil zorlanması |
| Çok ciddi | %2 | 5-12 ay + kalıcı nitelik kaybı (hız/ivmelenme/zıplama −1 ila −3) | ön çapraz bağ, Aşil kopması, kırık bacak |

Maç içi sakatlıklarda dağılım ciddiye doğru kayar (hafif %35, ciddi %12); antrenmanda hafife doğru.

### 6.3 İyileşme ve dönüş

- Süre, tıbbi tesis (1-10) ile ×(1.15 − 0.03×tesis) ölçeklenir; yaş>30 ×1.15.
- İyileşen oyuncunun **maç formu** 40'a düşer; her maç/antrenman günü artar (~+5/maç, +1/gün). Tam forma 4-6 haftada döner. Bu dönem "yeni döndü, henüz keskin değil" hissini verir.
- Moral: uzun sakatlıkta düşer.
- Haber: kullanıcının oyuncusu sakatlanınca gelen kutusuna tahmini dönüş tarihiyle mesaj. Tahmin ±%20 hatalı olabilir (doktor "3 hafta" der, 4 olur).

---

## 7. Transferler ve sözleşmeler

### 7.1 Oyuncu piyasa değeri

```
değer = tabanDeğer(CA)                         // üstel: CA 100 → 0.5M, 140 → 5M, 170 → 40M, 190 → 120M (para birimi soyut)
      × yaşÇarpanı(yaş, PA)                    // 19-24 ve PA yüksekse ×1.5-2.5; 30+ hızla düşer ×0.5 (32) ×0.25 (34)
      × sözleşmeÇarpanı(kalan ay)              // <6 ay ×0.4, 6-12 ay ×0.7, 12-24 ay ×1.0, 36+ ay ×1.15
      × ligÇarpanı(satıcı ligi itibarı)        // 0.6-1.3
      × pozisyonÇarpanı                        // forvet ×1.15, kaleci ×0.85
      × formÇarpanı                            // son sezon performansı ±%15
```

Kulüp "istenen bedel" = değer × önemÇarpanı (ilk 11'de ise ×1.6, rotasyon ×1.2, yedek ×0.9, satılık listede ×0.75) × kulübün satma iştahı (bütçe sıkışıksa ↓).

### 7.2 Yapay zeka kulüp davranışı (günlük, round-robin)

Her gün kulüplerin ~1/7'si sıraya gelir (her kulüp haftada bir "düşünür"). Pencere açıkken:

1. **Kadro analizi:** her pozisyon için ilk 11 kalitesi, derinlik (yeterli oyuncu sayısı), yaş profili. Puanla: `ihtiyaç = (hedefKalite − mevcutKalite) + derinlikEksiği + yaşlanmaCezası`.
2. **Satış listesi:** fazla oyuncular (pozisyonda 4+), 31+ yaş ve düşen, mutsuzlar, yüksek maaş / düşük katkı. Bütçe açığı varsa değerli oyuncular da.
3. **Alım:** en yüksek ihtiyaçlı 1-2 pozisyon için kısa liste: tüm oyuncular arasından filtre (pozisyon, CA ≥ hedef, yaş uygun, değer ≤ bütçe, maaş ≤ tavan) → en iyi 5'ten rastgele ağırlıklı seçim (hep en iyiyi seçmesin). Teklif = istenen bedelin %80-100'ü. Günde en fazla 1 teklif, aynı anda en fazla 2 açık teklif.
4. **Gelen teklifleri cevapla:** teklif ≥ istenen ise kabul; %85-100 arası ise karşı teklif; altı ret. Aynı oyuncuya birden fazla teklif varsa en yüksek.
5. **Sözleşme yenileme:** 12 aydan az kalan ve değerli oyuncular için uzatma teklifi.
6. **Kadro sınırı:** 18 ≤ kadro ≤ 28 sert sınır. Üstündeyse alım yok, satış baskısı; altındaysa serbest oyuncu/ucuz alım.

### 7.3 Oyuncu kararı

Kulüpler anlaştıktan sonra oyuncu şunları tartar:
- Maaş artışı (en ağır)
- Kulüp itibarı farkı (büyük kulübe gitmek ister; küçüğe gitmek için itibar yüksekse red)
- Oynama süresi vaadi (rol: ilk 11 > rotasyon)
- Lig itibarı
- Yaş: 30+ para ağırlıklı, 22- gelişim/oynama ağırlıklı

`kabul = logistic(ağırlıklı toplam)`; ret gelirse haber: "Oyuncu kulübünüzün büyüklüğünü yeterli bulmadı."

### 7.4 Kullanıcı tarafı

- Oyuncu arama ekranı (filtreler) → teklif ver (bedel, ödeme planı: peşin / 2 taksit) → kulüp cevabı 1-3 gün sonra → oyuncuyla sözleşme (maaş, süre, rol) → tamamlanma.
- Gelen teklifler: kabul / ret / karşı teklif.
- Sözleşme uzatma; serbest bırakma (kalan sözleşmenin %50'si tazminat).
- Transfer isteği: oynamayan veya mutsuz oyuncu 2 ay sonra talep eder; reddedilirse moral düşer.

### 7.5 Pencereler ve serbest oyuncular

- Yaz penceresi: sezon sonundan lig başlangıcından ~3 hafta sonrasına. Kış: 1-31 Ocak (lig takvimine göre).
- Pencere dışında sadece serbest oyuncu imzalanabilir.
- Sözleşmesi biten ve yenilenmeyen oyuncu serbest havuzuna düşer; AI kulüpler buradan ucuza alır. 6 ay kulüpsüz kalan 33+ yaş oyuncu emekli olur.

### 7.6 Dejenerasyon önleyiciler (anti-hedef kontrolü)

- Maaş tavanı: toplam maaş ≤ gelirin %70'i. Aşan kulüp alım yapamaz.
- Kadro üst sınırı 28.
- "En iyi 5'ten rastgele" seçimi: tüm kulüpler aynı oyuncuya saldırmasın.
- Yıldız oyuncular küçük kulüplere gitmez; ama büyük kulüplerin kadro ve maaş sınırı vardır → dağılım kendiliğinden yayılır.
- Sezon sonu "piyasa sağlık raporu" testi: kulüp başına ortalama CA sapması, en zengin 3 kulübün toplam CA payı, iflas eden kulüp sayısı (0 olmalı) — Bölüm 9.

---

## 8. Oyuncu yaşam döngüsü: gelişim, yaşlanma, emeklilik, altyapı

Oyun sonsuza kadar oynanabilir. Bunun şartı: dünyaya giren oyuncu sayısı ≈ çıkan oyuncu sayısı, ve kalite dağılımı sabit. Döngü şu:

```
altyapıdan çıkış (15-17 yaş) → gelişim (16-24) → zirve (25-29) → düşüş (30+) → emeklilik (33-37)
                                                 ↘ kariyeri bitiren sakatlık (nadir, her yaşta)
```

### 8.1 Gelişim

**Gelişim eğrisi (CA → PA):** Günlük antrenman, oyuncuya küçük "gelişim puanı" verir:
```
günlükGelişim = tabanHız(yaş) × (PA − CA)/100 × antrenmanKalitesi × oynamaSüresiÇarpanı × profesyonellik
tabanHız: 16-20 yüksek, 21-24 orta, 25-28 düşük, 29+ sıfır (artık düşüş)
oynamaSüresi: son 10 maçta ≥ 6 maç oynayan ×1.3, hiç oynamayan ×0.7
```
Birikmiş puan aylık olarak niteliklere dağıtılır (antrenman odağına göre ağırlıklı: "hız odağı" fiziksellere daha çok). Kullanıcı aylık nitelik değişimlerini ok işaretleriyle görür.

### 8.2 Yaşlanma ve emeklilik

**Yaşlanma:** 30 yaşından itibaren her sezon sonunda fiziksel nitelikler düşer; düşüş hızlanır:

| Yaş | Fiziksel (hız, ivmelenme, dayanıklılık, zıplama, çeviklik) | Teknik | Zihinsel |
|---|---|---|---|
| 30-31 | −1 (rastgele 2-3 nitelik) | 0 | +0/+1 |
| 32-33 | −1 ila −2 (çoğu nitelik) | −0/−1 | 0 |
| 34+ | −2 ila −3 | −1 | 0 |

Kaleciler 3 yıl gecikmeli yaşlanır. Profesyonellik yüksek olanlar düşüşü yavaşlatır (×0.7). CA, niteliklerden yeniden hesaplandığı için kendiliğinden düşer; piyasa değeri ve AI ilgisi onunla birlikte iner. Kullanıcı, eski yıldızının "artık ilk 11'i taşıyamadığını" maç puanlarından hisseder.

**Emeklilik kararı** her sezon sonunda:
```
p_emekli = taban(yaş) × kulüpsüzÇarpanı × düşüşÇarpanı
taban: 32→%5, 33→%12, 34→%25, 35→%45, 36→%70, 37+→%100
kulüpsüz 6+ ay: ×2.5;  CA son 2 sezonda %15+ düştüyse: ×1.5;  ilk 11'de düzenli oynuyorsa: ×0.6
```
Kararı veren oyuncu sezonun son 3 ayında "sezon sonunda bırakıyor" diye duyurur (haber, kullanıcıya veda maçı hissi). Sezon sonunda listeden çıkar; kariyer istatistikleri "emekli oyuncular" kaydında kalır (rekor tabloları için).

**Kariyeri bitiren sakatlık:** Bölüm 6.2'deki "çok ciddi" kategorisinde ek zar: 30 yaş altı %8, 30+ %25 ihtimalle oyuncu iyileşemez ve hemen emekli olur. Kullanıcıya özel haber ve sözleşme tazminatı (kalan sözleşmenin %100'ü, sigorta yok).

### 8.3 Altyapıdan oyuncu çıkışı

Her sezon sonunda (ve yaz penceresi başında) her kulüp bir **altyapı dalgası** alır:

```
sayı = 3 + round(altyapıTesisi/3)                     // tesis 1 → 3, tesis 10 → 6 oyuncu
yaş  = 15-17 (çoğu 16)
PA   ~ uzun kuyruklu dağılım:
       ortalama = 60 + ligİtibarı×0.4 + altyapıTesisi×3        // alt ligde ~75, üst ligde ~110
       %70'i ortalama ±20 (vasat), %25'i +20…+45 (iyi), %5'i +45…+80 (cevher)
CA   = PA × U(0.30, 0.45)                             // ham
pozisyon: kulübün ihtiyacından bağımsız, rastgele (gerçekte öyledir)
uyruk: kulüp ülkesi %85, komşu/diğer %15
isim: uyruğa göre isim üretici
sakatlık yatkınlığı, profesyonellik: rastgele; kalıcı
```

Çıkan oyuncular kulübün "altyapı kadrosu"na girer (ana kadro sınırına sayılmaz, 18 yaşına kadar), düşük maaşlı 3 yıllık sözleşmeyle. Kullanıcı birkaçını ana kadroya alır, geri kalanı 19 yaşında serbest bırakılır ya da alt lig kulüplerine düşer. AI kulüpler aynı mantıkla eler (PA'ya göre, hafif gürültülü; "cevheri kaçırma" hikâyesi doğar).

Popülasyon dengesi: sezonda emekli olan + kariyeri biten ≈ altyapıdan çıkan − elenen. Bu denge Bölüm 9'daki 30 sezonluk testle doğrulanır; tutmuyorsa `sayı` ve elenme eşiği ayarlanır.

### 8.4 Kulüp itibarı da yaşar

Sonsuz döngüde kulüpler de yükselip düşmeli; yoksa 30 sezon sonra aynı 3 kulüp hep şampiyon olur. Kulüp itibarı (1-100) her sezon sonunda:
```
itibar += 0.15 × (hedefİtibar(sıra, lig) − itibar)     // bu sezonki bitişe doğru %15 kayma
```
Üst lig şampiyonu hedef 95, orta sıra 60, alt lig dibi 20. İtibar, transferde oyuncu kararını, gelir modelini ve altyapı kalitesini etkiler. Yavaş kayma (%15) hanedanları korur ama sonsuz kılmaz.

### 8.5 Yönetim kurulu ve teknik direktör kariyeri

**Yönetim güveni (0-100)** her hafta güncellenir:
```
güven += 0.1 × (hedefGüven − güven)
hedefGüven = 50 + 2.5 × (beklenenSıra − gerçekSıra)      // beklentinin 10 sıra üstü → 75; 10 sıra altı → 25
           + kupaBaşarısı(+10) + bütçeAşımı(−15) + sonBeşMaçFormu(±8)
```
Güven < 20 ve sezonun en az 10 haftası geçtiyse: kovulma zarı (haftada %25). Güven > 80: sözleşme uzatma teklifi, bütçe artış isteklerine olumlu bakış.

**Yönetimden istekler** (kullanıcı menüsü, her istek ayda bir):
- Transfer bütçesi artışı / maaş bütçesinden transfere kaydırma
- Tesis yatırımı: antrenman, tıbbi, altyapı (1-10; her kademe kulüp gelirinin belli bir katı; yönetim güven ve kasaya göre kabul eder; inşaat 6-12 ay sürer)
- Yeni sözleşme isteği
Kabul olasılığı: `logistic(güven, kasa, kulüp itibarı, istek büyüklüğü)`. Ret, güvene küçük zarar.

**Sezon başı bütçe:** Yönetim, kulüp finansından (Bölüm 14-6) transfer ve maaş bütçesini belirler ve beklentiyi açıklar. Kullanıcı bütçeyi harcar; aşamaz. Kasa ve gelir/gider özeti salt okunur görünür.

**İş piyasası (menajer transferi):**
- Her AI kulübün teknik direktörü vardır; aynı güven mekaniğiyle kovulur. Boşalan koltuk için kulüp, itibarı uygun menajerlerden (kullanıcı dahil) seçer.
- Kullanıcının menajer itibarı sezon sonunda kayar: `itibar += 0.2 × (hedef − itibar)`, hedef = kulüp itibarı + beklentiye göre başarı (±15).
- İş teklifi: kendi kulübünden daha itibarlı bir kulüp boşalırsa ve kullanıcının itibarı eşik üstündeyse, gelen kutusuna teklif düşer (maaş, beklenti, bütçe). Kabul → eski kulüple sözleşme feshi (tazminat yeni kulüpten), yeni kulüpte başlangıç. Transfer penceresi dışında da olabilir.
- Kullanıcı istifa edebilir; işsizken günler ilerler, boşalan koltuklara başvurur; itibarı yeterse görüşme → teklif. Uzun işsizlik itibarı yavaş düşürür.
- Kovulma oyun sonu değildir: "işsiz menajer" ekranı + açık pozisyon listesi.

### 8.6 Moral, form, kondisyon

**Moral (0-100):** sonuç (galibiyet +5, mağlubiyet −5, büyük mağlubiyet −8), oynama süresi (3 maç oynamadıysa −3/hafta), sözleşme/transfer olayları, takım arkadaşlarının morali (küçük bulaşma). Her gün 50'ye doğru %3 sönümlenir.

**Form:** son 5 maç puanının ortalaması; 6.0 nötr. Maç etkinliğini ±%5 etkiler.

**Kondisyon (0-100):** maçta düşer (Bölüm 5), günde +12 toparlanır (dayanıklılık ve yaşla değişir: 20 yaş +14, 33 yaş +9). 3 günde bir maç oynayan takımda yorgunluk birikir; bu rotasyonu anlamlı kılar.

---

## 9. Kalibrasyon ve test düzeneği

Motor başsız çalıştığı için şu testler otomatik koşar:

**Tekil maç dağılımı (10.000 maç, eşit güçte takımlar):**
- Gol ortalaması 2.5-2.9 / maç
- Ev %43-47, beraberlik %24-28, deplasman %27-31
- Şut 10-14 / takım, isabetli 3.5-5
- Sarı kart 3-4 / maç, kırmızı 0.15-0.25
- Sakatlık 0.25-0.4 / maç
- Skor dağılımı: 0-0 %7-9, 1-1 %11-13, 1-0 %9-12.5; 5+ gollü maç %8-13 (2.56 gol/maç Poisson'da 1-0 zaten %11.6, 5+ %11.7; Faz 1a kararı)

**Güç farkı eğrisi:** Bölüm 5.6 tablosu ±5 puan toleransla.

**Sezon simülasyonu (20 takım, 38 maç, 100 sezon):**
- Şampiyon puanı 78-95, sonuncu 18-32, ortanca ~50
- En güçlü 3 takımın her biri, kulüp-sezonlarının en az %80'inde ilk 4'te (sd 13'lük Gauss ligde "üçü birden" kriteri 3.–4. takım arası 2–5 CA farkı yüzünden ölçülemez; Faz 1a kararı)
- Ama en güçlü takım, 100 sezonun en fazla 70'inde şampiyon (sürpriz payı)
- Gol kralı 20-32 gol

**Uzun vade (30 sezon, 5 lig) — sonsuz yaşam döngüsü testi:**
- Kulüp başına yıllık sakatlık 25-40
- Toplam CA dağılımının Gini katsayısı sezonlar boyunca artmıyor (yıldız toplanma kontrolü)
- İflas eden kulüp: 0
- Kadro büyüklüğü hep 18-28
- Toplam oyuncu sayısı ±%10 içinde sabit (altyapı girişi = emeklilik + kariyer bitimi + elenme)
- Yaş dağılımı sabit: 16-20 %18, 21-25 %32, 26-30 %30, 31+ %20 (±5 puan)
- 30 sezon sonunda ortalama CA ve en iyi 50 oyuncunun ortalama CA'sı başlangıcın ±%5'i içinde (enflasyon/deflasyon yok)
- Yılda ligde en az 1-2 "cevher" (PA 160+) doğuyor; 10 yılda en az bir altyapı çıkışlı oyuncu ilk 50'de
- Kulüp itibarı sıralaması 30 sezonda en az %40 değişiyor (hanedan kontrolü), ama 1 sezonda %15'ten fazla değişmiyor
- Emeklilik yaşı ortalaması 33-35; kariyeri biten sakatlık yılda ligde 1-3

**Ek sistemler (Bölüm 16) için uzun vade kontrolleri (aynı 30 sezonluk koşu):**
- Kiralık: 21-23 yaş oyuncuların %15-25'i sezonda kiralık; kiralık dönen oyuncuların gelişimi, kalanlardan ölçülebilir yüksek
- Ön sözleşme: ocak-haziran arası serbest kalacak oyuncuların %30-50'si ön anlaşma yapıyor
- Milli takım: her arada çağrılan oyuncu sayısı tam 23 × ülke; milli görevden sakat dönme sezonda kulüp başına 0.5-1.5; turnuva takvimi 4 yıllık döngüde çakışmasız
- Kıta kupası kontenjanları: 30 sezonda en az bir ülke kontenjan kazanıyor/kaybediyor, hiçbir ülke tüm kontenjanları toplamıyor
- Personel: boş rol oranı %5'in altında; emekli oyuncu → personel geçişi yılda ligde 5-15
- Finans: kulüp başına yıllık gelir/gider farkı ortalama −%5…+%10; 12 ay ekside kalan kulüp sayısı sezonda ligde ≤ 2; kulüp satın alınması yılda ligde 0-2
- AI menajer: ortalama görev süresi 1.5-3.5 sezon; sezonda ligde 3-7 kovulma
- Kayıt dosyası: 100 sezon sonunda büyük dünyada < 100 MB (Bölüm 18)

Bu düzenek, motordaki her katsayı değişikliğinden sonra koşar. Kalibrasyonun kendisi iteratiftir; ilk hafta büyük ölçüde buna harcanacaktır.

---

## 10. Dikey mobil bilgi mimarisi

Alt sekme çubuğu (5): **Ana** | **Kadro** | **Transfer** | **Lig** | **Gelen Kutusu**

- **Ana:** tarih, "Devam" (büyük buton), sonraki maç kartı, son 3 haber, hızlı durum (sakat sayısı, bütçe).
- **Kadro:** liste (pozisyon, ad, yaş, kondisyon çubuğu, moral ikonu, form, durum ikonu). Dokun → oyuncu profili (nitelikler 3 sekme, sözleşme, istatistik, işlem butonları). Taktik alt ekranı: formasyon şablonu + sürükle-bırak yerine "pozisyona dokun → oyuncu seç".
- **Transfer:** arama/filtre, kısa liste, açık teklifler (gelen/giden).
- **Lig:** puan tablosu, fikstür/sonuçlar, gol krallığı, diğer ligler.
- **Gelen kutusu:** olay akışı, bazıları aksiyonlu (teklif → kabul/ret).

Maç günü: "Devam" → maç ekranı (Bölüm 5.5) → maç sonu özeti → ana ekran.

---

## 11. Önerilen yapım sırası

Her faz oynanabilir bir ürün bırakır.

| Faz | İçerik | Bitti sayılır |
|---|---|---|
| **0. İskelet** | Veri modeli (ülke, lig piramidi, kulüp, oyuncu, menajer), kurgusal dünya üretici (çok ülkeli, forma/logo dahil), oyun başlangıcı (menajer profili, dünya boyutu, kulüp seçimi/işsiz), kayıt yuvaları, gün döngüsü, fikstür, puan tablosu, geçici Poisson maç, minimal arayüz, performans ölçümü | Bir sezon baştan sona "Devam"la oynanıyor; tablo mantıklı; büyük dünyada gün süresi bütçede |
| **1a. Maç motoru** | Bölüm 5 motoru (uzatma 30 dk + penaltı atışları, mikro-olay dizisi dahil), tam taktik seti (16.1), hava/zemin, yarışma kuralları (değişiklik hakkı, kart eşikleri), kalibrasyon düzeneği, anlatım (TR+EN), metin tabanlı maç ekranı | Kalibrasyon testleri yeşil; kullanıcı maçı metinle izleyip müdahale ediyor |
| **1b. 2D saha** | Bölüm 5.7 koreografi katmanı, boncuklar (forma renkli), top, hız kontrolü, izleme modları (tam / geniş özet / önemli anlar / sadece anlatım / sadece sonuç), görsel kabul listesi | Bir maç her modda akıcı izleniyor |
| **2. Oyuncu durumu ve takvim** | Kondisyon, sakatlık, moral, form, ceza, AI rotasyon, antrenman programı (16.2), pozisyon eğitimi, yerli kupa(lar) + süper kupa, hazırlık dönemi ve dostluk maçı ayarlama, milli aralar (takvimde boşluk), dünya üreticisinin kamuya açık olgulara göre kalibrasyonu (20.2) | Sezonluk sakatlık/kondisyon testleri yeşil; rotasyon zorunlu hissediliyor; ülke başına veri bantları yeşil |
| **3. Transfer (tam)** | Değer modeli, AI kulüp davranışı, teklif akışı, taksit/takas/maddeler, sözleşme ayrıntıları (bonus, serbest kalma bedeli, statü), kiralık, ön sözleşme, kulüplere teklif, söylentiler, huzursuz oyuncu, yabancı sınırı ve lisans kuralları (16.3), kullanıcı veri paketi (mod) sistemi (20.3) | 10 sezon piyasa sağlık testi yeşil; kiralık oranı hedefte; örnek bir veri paketi yüklenip sezon oynanıyor |
| **4. Yaşam döngüsü ve kariyer** | Gelişim/yaşlanma, emeklilik, kariyeri bitiren sakatlık, altyapı dalgası, kulüp itibarı kayması, sezon devri, küme düşme/çıkma, tam finans (16.9), yönetim güveni/istekler/kovulma, kulüp satın alınması, AI menajerler ve iş piyasası, ödüller, tarih ve rekorlar (16.10) | 30 sezon uzun vade testleri yeşil; AI menajerler kovulup işe alınıyor |
| **5. Personel, gözlemci, altyapı** | Personel rolleri ve piyasası (16.4), gözlemci görevleri ve raporları (16.5), altyapı yönetimi (tesis, antrenör, yükseltme/eleme), antrenman kalitesi personele bağlanır | Personel kalitesinin gelişim ve sakatlık üzerinde ölçülebilir etkisi var |
| **6. Dünya** | Çoklu ülke tam aktif, kıta kupaları (iki kademe, katsayı), kıtalararası kupa, milli takımlar: çağrılar, elemeler, turnuvalar, kullanıcının milli takım yönetimi (16.6-16.7) | 4 yıllık uluslararası döngü hatasız dönüyor; milli takımdan sakat dönme haberleri |
| **7. Cila ve ürün** | Haber/medya zenginliği, bulut kayıt, erişilebilirlik, mağaza/monetizasyon kararı (ürün kararı; tasarım pay-to-win'e kapalı) | Ürün kararına göre |

Faz 1a en riskli ve en değerli; Faz 0 bittiği anda başlanmalı ve motor **arayüzden önce** kalibre edilmeli. Faz 1b (2D) motora dokunmaz; 1a bitmeden başlanmamalı, yoksa görsel için motor eğilip bükülür.

Faz 0'da genç üretim ve emeklilik çok basit haliyle (rastgele 16 yaş oyuncu ekle, 35+ çıkar) olmalı; yoksa bir sezonluk iskelet bile ikinci sezonda bozulur. Faz 0'ın veri modeli, Bölüm 16'daki tüm sistemleri (milli takım, personel, kiralık) baştan içermeli; alanlar boş kalabilir ama şema sonradan kırılmamalı.

### 11.1 Model dağılımı (Claude Fable 5.1 / Claude Opus 5.5)

Kural: belirsizliği ve dengeyi çözen işler Fable, spesifikasyonu net olan hacimli işler Opus. Ana oturum her zaman Fable'dır (orkestrasyon, plan, çekirdek, inceleme); Opus işleri alt ajan olarak Fable tarafından dağıtılır ve dönen kod Fable tarafından incelenir. Kullanıcı model yönetmez.

| Faz | Fable | Opus |
|---|---|---|
| 0 | Veri modeli, şema sürümleme, determinizm/RNG, isolate ve depolama arayüzü, dünya üretici çekirdeği, performans ölçümü | Minimal ekranlar, isim havuzları, widget testleri |
| 1a | Motor, kalibrasyon döngüsü, taktik çarpanları, mikro-olay dizisi | Anlatım şablon havuzları (TR/EN), tablo güdümlü birim testleri, metin maç ekranı |
| 1b | Görsel kabul incelemesi | Koreografi katmanı, çizim, animasyon, izleme modları |
| 2 | Takvim üretici (lig, kupa, milli ara, çakışma) | Sakatlık, kondisyon, moral, form, ceza, antrenman, tatil modu, ekranlar |
| 3 | AI kulüp davranışı, değer modeli, piyasa dejenerasyon önleyiciler | Teklif/pazarlık ekranları, sözleşme formları, kiralık ve ön sözleşme akışları, senaryo testleri |
| 4 | 30 sezon denge kalibrasyonu, finans modeli, yönetim güveni, iş piyasası, arşivleme politikası | Ödüller, tarih ve rekor ekranları, haber şablonları |
| 5 | İnceleme | Personel, gözlemci, altyapı yönetimi (tamamı) |
| 6 | Kıta kupası kontenjan ve katsayı, 4 yıllık turnuva döngüsü, takvim çakışmaları | Milli takım kadro seçimi, ekranlar, milli görev etkileri |
| 7 | İnceleme | Haber zenginliği, ses, bulut, erişilebilirlik, analitik, mağaza, geniş ekran düzeni |
| Tümü | Değişmez listesi, istatistiksel kontroller, fuzz düzeneği, faz sonu kod incelemesi, her kalibrasyon katsayısı değişikliği | Tablo güdümlü birim/senaryo testleri, widget ve altın görüntü testleri |

---

## 12. Teknoloji: Flutter + Dart (karar, 2026-10-20)

**Karar:** Flutter (arayüz) + Dart (motor, ayrı paket). Gerekçe: proje yalnızca yönlendirilecek, tüm kod Claude tarafından yazılacak; her şeyin metin dosyası olması, motorun komut satırında koşması ve testlerin gözetimsiz çalışması bu çalışma biçimi için belirleyici. Unity, editör bağımlılığı nedeniyle elendi.

**Yapı:**
- `engine/` — saf Dart paketi, Flutter bağımlılığı yok. Dünya, gün döngüsü, maç motoru, tüm sistemler. Komut satırından koşar (`dart run` ile kalibrasyon, uzun simülasyon, araçlar).
- `app/` — Flutter uygulaması. Ekranlar, 2D maç çizimi (CustomPainter + Ticker; gerekirse Flame), yerelleştirme (ARB dosyaları + Türkçe ek yardımcısı), kayıt (dosya + sıkıştırma; sorgu gerekirse drift/SQLite).
- `data/` — dünya üretici çıktısı (sabit dünya), ülke/lig/kural tabloları, isim havuzları, anlatım şablonları.
- Maç günü simülasyonu arayüzü dondurmasın diye ayrı isolate'ta koşar.

**Flutter'ın bu kapsam için yeterliliği (kontrol listesi):**
| İhtiyaç | Flutter karşılığı | Eksik? |
|---|---|---|
| 22 boncuk + top, 30-60 fps, lerp | CustomPainter + Ticker | Yok |
| Gol efekti, halka, yanıp sönme, geçişler | Implicit/explicit animasyonlar, isterse Rive/Lottie | Yok |
| Tablolar, listeler, formlar, sekmeler | Flutter'ın ana işi; 30k satır için builder + sayfalama | Yok |
| Çift dil, anında geçiş | intl + ARB; ek uyumu özel yardımcı | Yok |
| Ses (düdük, kalabalık) ve titreşim | audioplayers, haptics | Yok |
| Arka plan hesap | Isolate | Yok |
| Yerel kayıt, göç | dosya + sürümlü şema; drift/SQLite seçenek | Yok |
| Reklam / mağaza içi satın alma (Faz 7) | google_mobile_ads, in_app_purchase | Yok |
| iOS + Android tek kod | Evet; bonus: masaüstü/web derlemesi | Yok |
| 3D, fizik | Gerek yok (hedef dışı) | — |

Bilinen riskler: büyük dünyada bellek (30k oyuncu nesnesi; Faz 0'da ölçülür), uygulama boyutu (anlatım havuzları ve veri; hedef < 60 MB), düşük segment Android'de 2D kare hızı (boncuk sayısı sabit, risk düşük).

**Web ve masaüstü (ileride):** Flutter aynı koddan web, macOS, Windows ve Linux derler; motor saf Dart olduğu için her yerde aynı çalışır. Bunu ucuz tutmak için Faz 0'dan itibaren üç kural:
1. Dikey düzen varsayılan ama sabit değil: ekranlar genişlik eşiklerine göre yerleşir (telefon: tek sütun; tablet/masaüstü: liste solda, detay sağda; maç ekranında saha solda, anlatım sağda). Faz 0'da sadece telefon düzeni yazılır, ama hiçbir ekran sabit piksel genişliğe bağlanmaz.
2. Dosya ve depolama tek bir arayüzün arkasında: mobilde dosya sistemi, web'de tarayıcı depolaması (IndexedDB) + "kaydı indir/yükle", masaüstünde dosya. Motor ve ekranlar depolamanın nerede olduğunu bilmez.
3. Çekirdekte mobil-özel eklenti yok (reklam, satın alma, titreşim gibi şeyler ayrı katmanda, platformda yoksa sessizce devre dışı).
Web'de bilinen sınırlar: büyük kayıt dosyaları tarayıcı kotasına tabi (genelde yüzlerce MB, sorun değil), isolate yerine web worker (Flutter destekliyor), ilk yükleme boyutu. Masaüstünde Steam gibi mağazalar eklentiyle mümkün. Bunlar Faz 7 sonrası ürün kararıdır; tasarım engel koymaz.

Tasarımın koyduğu ve Flutter'ın karşıladığı kısıtlar:

1. **Motor ayrı bir modül olmalı** ve arayüzden bağımsız, komut satırından koşabilmeli (kalibrasyon düzeneği için). Dil ne olursa olsun bu sınır çizilmeli.
2. **Seed'lenebilir RNG** şart; platformun varsayılan `random()`'ı kullanılmamalı.
3. **Veri hacmi küçük** (2.500-10.000 oyuncu, tek JSON/SQLite kayıt dosyası birkaç MB). Sunucu gerekmiyor; tamamen çevrimdışı çalışabilir.
4. **Arayüz, liste ağırlıklı** (tablolar, kartlar, formlar) **artı bir 2D çizim yüzeyi** (maç ekranı: 22 boncuk + top, 30 fps, lerp animasyon). Fizik yok. İki uç aday: (a) uygulama çatısı + canvas (Flutter CustomPainter, React Native Skia vb.): liste ekranları güçlü, 2D yeterli; (b) oyun motoru (Unity, Godot): 2D güçlü, liste/form ekranları daha zahmetli. Projenin %85'i liste ekranı olduğu için (a) daha doğal; ekip Unity biliyorsa (b) makul.
5. **Çift dil**: tüm metinler dizgi tablosunda; anlatım şablon motoru Türkçe ek uyumunu destekler.
6. **Hesap yükü düşük**; aday her platform yeter. Seçim, geliştirme hızı ve ekibin bildiği dille yapılmalı.

---

## 13. Önceki örnekler ve kaynaklar

- CM 01/02: nitelik 1-20, metin anlatım, kondisyon/moral, basit ama bağımlılık yapan transfer döngüsü. Bu belgenin ana ilham kaynağı.
- Football Manager: aynı soyun zirvesi; 2D/3D motor bu projenin hedef dışı.
- Açık kaynak: [Openfoot Manager](https://github.com/openfootmanager/openfootmanager) (Rust, dakika-dakika Markov tabanlı motor), [open-football](https://github.com/ZOXEXIVO/open-football), [footballSimulationEngine](https://github.com/gallagheraiden/footballsimulationengine) (Node, pozisyon tabanlı). Motor tasarımı için fikir kaynağı; kod alınmayacak.
- Sakatlık gerçeklik verisi: Premier Lig 2015/16 kulüp başına ~35 sakatlık ([Insurance Business](https://www.insurancebusinessmag.com/uk/news/breaking-news/football-injury-league-table-revealed-36690.aspx)); kulüp başına kaybedilen gün 192-2.364 ([City AM](https://cityam.com/?p=291351)); 2023/24 en kötü kulüp ~1.900 gün ([Sky Sports](https://www.skysports.com/football/news/11095/13254604)).

---

## 14. Yapımcı kontrolünden çıkan kararlar (benim kararlarım)

Belge bağımsız bir "yapımcı gözüyle" okutuldu; şu boşluklar bulundu ve aşağıdaki gibi kapatıldı. Hepsi değiştirilebilir.

1. **Gün, üç parçada işlenir, atomik değil.** `advanceDay` = `günBaşı` (takvim, oyuncu güncellemesi, AI kulüpler, transfer işlemleri) → `maçlar` (kullanıcı maçı burada askıya alınır, etkileşimli) → `günSonu` (maç sonrası, finans, haber, sezon sonu). Kullanıcıya gelen teklifler gün sonunda gelen kutusuna düşer, ertesi gün cevaplanır; maç öncesi karar baskısı yaratılmaz.
2. **Kayıt sadece gün sınırında.** Yerel kayıt Faz 0'dan itibaren var; dünya durumunun anlık görüntüsü (snapshot). Girdi günlüğü/replay yok. Uygulama maç ortasında kapanırsa maç baştan oynanır; seed kaydedildiği için müdahale yoksa aynı sonuç çıkar.
3. **Hızlı modda kullanıcı takımını AI yönetir.** Detaylı modda AI'nın kararları varsayılan olarak otomatik uygulanır; kullanıcı müdahale ederse sonuç sapar, bu kabul edilir. Determinizm garantisi "müdahale yoksa" içindir. Kullanıcı maç ortasında "hızlı bitir" diyebilir; kalan kısım AI kararlarıyla koşar.
4. **Kupa Faz 2'de.** Tek eleme, hafta içi oynanan bir yerli kupa. Motor Faz 1'den itibaren 30 dk uzatma ve penaltı atışlarını çözer (uzatmada kondisyon düşüşü devam eder; penaltılar Bölüm 5.3 adım 6-7 ile, taban xG 0.76, atıcı sırası AI/kullanıcı seçer).
5. **Kurgusal dünya sabittir.** Veri üretici bir geliştirme aracıdır; ürettiği dünya (kulüpler, oyuncular, isimler) bir kez üretilip oyunla gönderilir. Her yeni oyun aynı dünyayla başlar (CM'de olduğu gibi herkes aynı kulüpleri tanır). Rastgele üretim sadece sezon sonu genç oyuncu üretiminde kullanılır.
6. **Finans ölçeği.** Haftalık gelir = ligİtibarPayı + kulüpİtibarı × sabit + evMaçıGeliri(kapasite × doluluk × bilet). Değerler öyle seçilir ki orta sıra bir üst lig kulübü yılda toplam CA 140'lık ~2 oyuncu alabilsin. Bakiye eksiye düşen kulüp alım yapamaz; AI kulüp 3 ay eksideyse en değerli oyuncusunu satılık listeye koyar (iflas etmez, bu "iflas eden kulüp: 0" testinin mekanizmasıdır). Kullanıcı eksideyse: alım engeli + yönetim uyarısı; 6 ay sürerse kovulma puanına eklenir.
7. ~~Kovulma = oyun sonu~~ **Kullanıcı kararıyla değişti:** kovulma oyun sonu değil; menajer iş piyasası Faz 4'te (Bölüm 8.5).
8. **Kiralık transfer ilk sürümde yok.** AI kadro dengesini satış/serbest bırakma ile tutar. Kiralık Faz 5.
9. **Dil:** Türkçe ve İngilizce birlikte (kullanıcı kararı). Metinler Faz 1'den itibaren dizgi tablosundan gelir (kod içine gömülmez). Anlatım havuzları iki dilde ayrı yazılır (çeviri değil, her dilde doğal cümle). Türkçe şablonlar ek uyumunu (-ın/-in/-un/-ün, -a/-e, ünsüz yumuşaması) çözen küçük bir yardımcı kullanır.

---

## 15. Kullanıcının karar vermesi gereken açık sorular

Bu belge aşağıdaki varsayımlarla yazıldı. Her biri yapılacak işi değiştirir:

1. ~~Maç sunumu~~ **Karar verildi:** 2D boncuklu saha + metin anlatım (Bölüm 5.7).
2. ~~Veri~~ **Karar verildi:** Her şey kurgusal (isimler, formalar, logolar), dilden bağımsız. ~~Kullanıcı veri paketi yükleme: hedef dışı.~~ **Güncellendi (2026-10-27):** kullanıcı veri paketi (mod) yükleme kapsamda, Bölüm 20.
3. ~~Kapsam~~ **Karar verildi:** 1 ülke, 2-3 kademe lig + 1 kupa ile başlanır.
4. ~~Gerçekçilik seviyesi~~ **Karar verildi:** tam finans modeli, yönetim yönetir, kullanıcı görür ve ister (16.9).
5. **Lig takvimi:** Ağustos-Mayıs varsayılan; ülke verisi yaz ligi (Mart-Kasım) tanımlayabilir (16.6).
6. ~~Taktik derinliği~~ **Karar verildi:** tam CM seti, bireysel talimatlar dahil (16.1).
7. ~~Hikâye öğeleri~~ **Karar verildi:** Yönetim kurulu, güven, istekler, kovulma, iş teklifleri, istifa, işsizlik (Bölüm 8.5).
8. ~~Dil~~ **Karar verildi:** Türkçe + İngilizce baştan.
9. ~~İsimler~~ **Karar verildi:** dilden bağımsız.
10. **Lig yapısı sabittir** (varsayım): kulüp hangi ligde oynayacağını seçmez, küme düşer/çıkar. Kıta kupasına katılım sıralamayla kazanılır (Faz 6). Hazırlık maçlarını kullanıcı ayarlar; ayarlamazsa yardımcı antrenör ayarlar (16.2, 16.4).
11. ~~Ülke adları~~ **Karar verildi:** gerçek ülke ve şehir adları; bayraklar gerçek (kamu malı); federasyon logosu kurgusal (Bölüm 20).
12. ~~Para birimi~~ **Karar verildi:** soyut tek birim, sembol ayardan seçilir; kur yok.
13. **Platform:** iOS ve Android telefon, dikey; tablet düzeni sonraki iş (varsayım). Teknoloji seçimiyle birlikte netleşir.
14. **Monetizasyon:** Faz 7'de ürün kararı. Tasarım pay-to-win'e kapalı; tek seferlik ücret, reklam veya kozmetik seçenekleri tasarımı değiştirmez.

Tasarım düzeyinde başka açık soru kalmadı; sıradaki karar teknoloji (Bölüm 12).

---

## 16. Tam CM kapsamı: ek sistemler

Bölüm 3-10'da olmayan ve klasik CM'de bulunan her sistem. Her biri için: ne yapar, motora/döngüye nasıl bağlanır, hangi fazda. Sayılar başlangıç değeridir.

### 16.1 Taktik: tam set (Faz 1a)

CM'in taktik ekranının tamamı. Her ayar Bölüm 5 motorunda bir çarpana bağlanır; "etkisi olmayan ayar" olmaz.

| Ayar | Seçenekler | Motora etkisi |
|---|---|---|
| Formasyon | Hazır şablonlar + ızgarada serbest yerleşim (her oyuncu 5×6 ızgarada bir hücre) | Koridor/hat ağırlıkları hücreden türetilir |
| Oyuncu okları (ileri/geri koşu) | Her oyuncu için yok / ileri / geri | Oyuncunun hücum katkısı ×1.25 ve savunma ×0.85 (veya tersi) |
| Mentalite | 5 kademe (çok savunmacı → çok hücumcu) | Hücum ×(0.85…1.15), savunma ters yönde; şans yaratma eşiği kayar |
| Pas stili | Kısa / karışık / direkt / uzun top | Uzun top: orta saha mücadelesi atlanır (%30), şans tipi dağılımı kafa/ortaya kayar; kısa pas: orta saha kontrolü ×1.1, top kaybı kontra riski ↓ |
| Tempo | Yavaş / normal / hızlı | Hücum adımı süresi, kondisyon tüketimi ×(0.85…1.3) |
| Genişlik | Dar / normal / geniş | Koridor ağırlıkları (geniş: kanat %40/%40) |
| Pres / baskı | Düşük / normal / yüksek | Rakip orta saha ×0.92, kendi kondisyon ×1.25, kontra riski ↑ |
| Müdahale sertliği | Yumuşak / normal / sert | Faul ×(0.8…1.3), kart ×(0.8…1.4), rakibe sakatlık ×(0.9…1.4), top kazanma ×(0.95…1.1) |
| Markaj | Alan / adam | Adam markajı: belirli rakibin etkinliği ×0.85, markajcının hücum katkısı ×0.8 |
| Ofsayt tuzağı | Açık / kapalı | Rakip ara pası xG ×0.75; %12 "tuzak bozuldu" → xG ×1.6 |
| Kontra atak | Açık / kapalı | Kontra ihtimali %15 → %28, kontra hücum ×1.15 |
| Oyun kurucu / hedef adam | Oyuncu seçimi | Hücum adımlarında ilgili oyuncunun seçilme ağırlığı ×2 |
| Bireysel talimatlar | İleri koşu, topla ilerleme, uzak şut, ara pası, orta (yakın/uzak direk), topu tut, serbest rol | Şans tipi ve oyuncu seçim ağırlıkları |
| Duran top kullanıcıları | Korner sol/sağ, serbest vuruş sol/sağ, penaltı, uzun taç | Bölüm 5.3 adım 5 bu listeyi kullanır |
| Kaptan / kaptan yardımcısı | Oyuncu seçimi | Kaptanın liderlik/etki niteliği takım moral sönümlemesini ve zor maç performansını etkiler |

Üç taktik yuvası; maç içinde tek dokunuşla geçiş. Devre arası tam taktik erişimi.

Motor bu ayarların hepsini **tek bir "takım profili" nesnesine** derler (Bölüm 5.2); maç döngüsü ayarları doğrudan okumaz. Böylece kalibrasyon profil düzeyinde yapılır.

### 16.2 Antrenman ve pozisyon eğitimi (Faz 2, personel bağlantısı Faz 5)

Haftalık program, oyuncu başına veya grup başına (kaleciler, savunma, orta saha, hücum, gençler):

- Kategoriler: aerobik, güç, taktik, top kontrolü, şut, duran top, kalecilik. Her kategori 0-5 yoğunluk; haftalık toplam sınırlı; dinlenme günleri.
- Her kategori bir nitelik kümesine gelişim ağırlığı verir (Bölüm 8.1'deki "antrenman odağı" bunun genelleşmiş hali).
- Aşırı yoğunluk: sakatlık ×1.6, moral −; yetersiz: gelişim ×0.6, kondisyon toparlanma ×0.9.
- Antrenör kalitesi (Faz 5'e kadar sabit 10/20): gelişim ×(0.7…1.3).
- **Pozisyon eğitimi:** oyuncuya yeni mevki atanır; yatkınlık (Bölüm 4) ayda +1 artar, çok yönlülük niteliğine göre hızlanır; 12 (yeterli) ve 16 (doğal) eşikleri haber üretir.
- Hazırlık kampı: sezon öncesi 1-2 hafta, kondisyon ve takım uyumu artışı, küçük sakatlık riski.
- **Yedek takım maçları:** ilk 11 dışında kalanlar ve altyapı oyuncuları için iki haftada bir yedek takım maçı (aynı motor, hızlı mod, sonuç haber olarak). Maç formu (keskinlik) bununla korunur; CM'de oynamayan oyuncunun "maç eksiği" hissi buradan gelir. Kullanıcı yedek kadroyu yardımcı antrenöre bırakabilir.

### 16.3 Transfer ve sözleşme: tam ayrıntı (Faz 3)

Bölüm 7'nin üstüne:

**Teklif türleri**
- Peşin; taksit (2-4 taksit, 24 aya kadar); takas (oyuncu + para; AI karşı tarafın değer modeliyle oyuncuyu fiyatlar); kiralık (aşağıda).
- Maddeler: satıştan pay (%5-50), küme düşme serbest kalma, maç sayısına bağlı ek ödeme, milli maç sayısına bağlı ek ödeme. AI, maddeleri "beklenen değer"e çevirip teklifi karşılaştırır.
- "Kulüplere teklif et": oyuncu satılık/kiralık listesine istenen bedelle konur; 1-2 hafta içinde ilgilenen AI kulüpler teklif verir.

**Sözleşme**
- Haftalık ücret, imza parası, gol/asist/maç bonusu, temiz sayfa bonusu (kaleci/savunma), serbest kalma bedeli (opsiyonel), süre 1-5 yıl, statü (önemli oyuncu / ilk 11 / rotasyon / yedek / genç yetenek / altyapı), forma numarası.
- Oyuncunun istediği ücret: değer, yaş, statü, kulüp itibarına göre; pazarlık 3 tur, her turda oyuncu toleransı daralır; "görüşmeyi kesti" sonucu 1 ay bekleme.
- Yarı zamanlı / amatör sözleşme (alt ligler): ücret çok düşük, antrenman etkisi ×0.7.

**Kiralık**
- Süre: sezon sonuna / 6 ay / 1 yıl. Ücret paylaşımı %0-100, kiralama bedeli opsiyonel, geri çağırma hakkı, "ana kulübe karşı oynayamaz" (veri kuralı).
- AI: 23 yaş altı ve ilk 11'de olmayan oyuncuları kiraya verir; bütçesi dar ve derinlik eksiği olan kulüpler kiralık arar. Kiralanan oyuncu oynarsa gelişim ×1.3 (Bölüm 8.1 oynama çarpanı).
- Hedef: sezonda 21-23 yaş oyuncuların %15-25'i bir yerde kiralık.

**Ön sözleşme (Bosman)**
- Sözleşmesine 6 aydan az kalan oyuncuyla, ocak ayından itibaren, bedelsiz ön anlaşma; oyuncu 1 Temmuz'da katılır. Mevcut kulübe haber gider; kulüp ocakta ucuza satmayı değerlendirir.

**Söylentiler ve huzursuzluk**
- AI kulüp bir oyuncuyu kısa listeye alınca %30 ihtimalle "ilgileniyor" haberi. Büyük kulüp ilgisi + oyuncunun kendi kulübü daha küçükse: huzursuzluk (moral −10/ay, "transfer istiyor" durumu, performans ×0.95). Yeni sözleşme veya 3 ay ilgi kesilmesi huzursuzluğu giderir.

**Ülke kuralları (veri tabanlı, her ülke için)**
- Yabancı oyuncu sınırı: kadro kaydında ve/veya maç kadrosunda en fazla N yabancı. "Yabancı" tanımı: ülke grubu dışı (ör. kıta birliği). Sınır aşımı: kadro kaydı reddi; kullanıcıya uyarı ve engel.
- Lisans/çalışma izni: bazı ülkelerde grup dışı oyuncu için milli maç sayısı eşiği; eşik altı red, itiraz hakkı (%30 şans).
- Kadro kaydı: sezon başı ve kış penceresi sonrası 25 kişilik liste (ülkeye göre), yerli yetişmiş kotası (opsiyonel kural).
- Değişiklik hakkı, uzatma/penaltı kuralı, rövanş, deplasman golü: yarışma başına veri.

### 16.4 Personel (Faz 5)

| Rol | Nitelikler (1-20) | Etkisi |
|---|---|---|
| Yardımcı antrenör | taktik, adam yönetimi, oyuncu değerlendirme | Kadro/taktik önerisi, dostluk maçı düzenleme, "yardımcı raporu" (kadro zayıflıkları) |
| Antrenör (kategori başına 1-3) | hücum, savunma, kondisyon, taktik, teknik, gençlerle çalışma, disiplin | 16.2'de antrenman kalitesi çarpanı |
| Kaleci antrenörü | kalecilik, gençlerle çalışma | Kaleci gelişimi |
| Fizyoterapist (1-3) | fizyoterapi | Sakatlık süresi ×(1.1 − 0.02×nitelik); yeniden sakatlanma ↓ |
| Gözlemci (1-6) | yetenek değerlendirme, potansiyel değerlendirme, bölge bilgisi | 16.5 |
| Altyapı antrenörü | gençlerle çalışma, oyuncu değerlendirme | Altyapı dalgası ortalama PA +, eleme isabeti |

Personel sözleşmesi (ücret maaş bütçesinden, süre), işe alma/kovma (tazminat), AI kulüplerin personel piyasası (basit: boş rol → havuzdan itibara uygun aday). Personel yaşlanır ve emekli olur; emekli olan bazı oyuncular personel havuzuna girer (sonsuz döngünün personel ayağı). Kulüp tesis seviyesi personel sayısı üst sınırını belirler.

### 16.5 Gözlemcilik (Faz 5)

CM 01/02 sadakati: tüm oyuncuların nitelikleri her zaman görünür. Gözlemcinin katkısı:
- **Görev:** ülke/bölge tarama (filtreyle: pozisyon, yaş, maks. bedel), belirli oyuncu/kulüp izleme, rakip analizi (sonraki rakibin tahmini 11'i ve zayıf yanı).
- **Rapor** (7-21 gün sonra): yıldız puanı mevcut/potansiyel (gözlemci niteliğine göre hatalı, ±1 yıldız), tavsiye metni, gizli niteliklere ipucu (sakatlık yatkınlığı, tutarlılık, önemli maç), tahmini bedel ve ücret, "kulüp satmaya sıcak mı".
- Tarama sonuçları gelen kutusuna "bulgu" olarak düşer; kısa listeye tek dokunuşla eklenir.
- AI kulüpler aynı mekanizmayı kullanmaz (Bölüm 7.2 doğrudan filtre); sadece kullanıcı deneyimi içindir.

### 16.6 Çoklu ülke ve kıta kupaları (Faz 6; veri modeli Faz 0)

- **Ülke:** ad, kıta/birlik, lig piramidi (1-3 kademe, kademe başına kulüp sayısı, küme düşme/çıkma ve play-off kuralı), yerli kupa(lar), süper kupa, kurallar (16.3), isim üretici (ad/soyad havuzu), takvim (yaz/kış ligi), katsayı.
- **Ülke adları:** gerçek ülke adları kullanılır (ülke adı lisansa tabi değildir); bayrak basit renk şeridi; federasyon logosu prosedürel. Kurgusal ülke isteniyorsa veri değişir, kod değişmez (açık soru, Bölüm 15-11).
- **Kıta kupaları:** iki kademe (Şampiyonlar / İkinci). Kontenjan ülke katsayısına göre (son 5 yıl kıta kupası performansı); eleme turları, 8×4 grup, çift maçlı eleme, tek maçlı final. Takvim hafta içi; yerli kupayla çakışma çözümü takvim üreticide.
- **Kıtalararası kupa:** iki kıta şampiyonu arasında tek maç, aralık ayı.
- Gelir etkisi: katılım + tur primleri (16.9).
- Kullanıcı, oyun başında kaç ülkenin dünyada olacağını seçer (4/8/16); hepsi tam simüle edilir. Ülke listesi ve piramit yapısı veridir, kodda sabit değildir.

### 16.7 Milli takımlar (Faz 6; takvim boşlukları Faz 2)

- Her ülkenin A milli takımı ve 21 yaş altı takımı vardır; AI menajerli.
- **Takvim:** sezonda 5 milli ara (eylül, ekim, kasım, mart, haziran), her biri 9 gün, 2 maç. Ligler durur; kupalar durur.
- **Çağrı:** aranın 10 gün öncesinde, o uyruktaki tüm oyuncular arasından pozisyon bazlı en iyi 23 (CA, form, kondisyon, sakat değil; AI menajerin "tercih" gürültüsü ±%10). Kulübe haber. Oyuncu 9 gün kulüpten ayrı: antrenman almaz, kondisyon milli maçlara göre düşer, sakatlanabilir ("milli takımdan sakat döndü"), moral +.
- **Yarışmalar:** kıta şampiyonası ve dünya kupası dönüşümlü, 2 yılda bir büyük turnuva (4 yıllık döngü), elemeler aralarda gruplar halinde. Yaz turnuvası: haziran-temmuz, katılan oyuncular hazırlık dönemine 2-3 hafta geç ve yorgun başlar.
- **Milli maç sayısı** oyuncu kaydında; lisans kuralı (16.3) ve değer modelinde (+%5/10 maç, tavan %25) kullanılır.
- **Kullanıcı milli takım yönetir:** menajer itibarı eşiği geçince federasyon teklifi (kulüple eş zamanlı); kadro seçimi, taktik, aralarda maçlar; federasyon güveni ve kovulma aynı mekanik (Bölüm 8.5). Milli takım menajerliği maaşı ayrı. İşsiz menajer sadece milli takım yönetebilir.
- Motor aynıdır; milli takım profili (Bölüm 5.2) "takım uyumu" çarpanı ile ×0.95 başlar, turnuva boyunca artar.

### 16.8 Maç günü ayrıntıları (Faz 1a/1b)

- **İzleme modları ve süre hedefleri.** Mobilde bir oturum 5-10 dakikadır; maç günü (maç öncesi + maç + maç sonrası) varsayılan modda 3 dakikayı geçmemeli. Referans: CM 01/02'de tam anlatım normal hızda ~5-8 dk, önemli anlar ~1-2 dk sürüyordu (hatıra, ölçüm değil).

| Mod | Ne gösterir | Hedef süre (1× hız) | Not |
|---|---|---|---|
| Sadece sonuç | Skor + olay listesi | anında | Diğer takımların maçları da böyle |
| Sadece anlatım | Metin akışı, 2D kapalı, kullanıcı kaydırarak okur | 1-2 dk | Düşük pil/veri; eski CM hissi |
| **Önemli anlar (varsayılan)** | Goller, penaltılar, kırmızı kartlar, sakatlıklar, xG ≥ 0.25 şanslar, direkten dönenler; her klip 6-10 sn (hücumun başından sonuna) | **60-100 sn** | ~8-14 klip; klipler arası saat hızla akar (ticker), skor çubuğu ve diğer maçlardan gol bildirimleri görünür |
| Geniş özet | Şansla biten tüm hücumlar + öncesindeki 1-2 mikro-olay | 2-3 dk | ~25-35 klip |
| Tam maç | Her hücum adımı 2D'de; oyun dakikası ≈ 2.5-3 sn | 4-5 dk | 2× → ~2.5 dk, 4× → ~1 dk; kritik maçlar için |

  Hız kontrolü (1×/2×/4×) her modda; "⏭ bitir" geri kalanı hızlı modda koşar. Mod maç içinde değiştirilebilir (ör. 80'de 2-2 iken tam maça geç). Önemli olaylar her modda otomatik duraklatır (ayarlanabilir).

- **Klip seçimi (önemli anlar / geniş özet):** motor tüm hücum adımlarını önem puanıyla işaretler: gol 100, penaltı 90, kırmızı kart 80, sakatlık 70, xG×100 (şanslar), direk 60, sarı kart 20, "gergin maçta 85'+ hücum" +15. Mod, puan eşiğine göre klipleri seçer; üst sınır (14 / 35) aşılırsa en düşük puanlılar düşer; en az 1 klip her 15 dakikalık dilimden (maç "boş" hissettirmesin). Klip, hücumun ilk mikro-olayından son olayına kadar oynatılır; gol kliplerinde 1.5 sn tekrar.

- **Tempo hissi:** şut öncesi mikro-olay %30 yavaşlatılır, gol sonrası 2 sn kutlama duraklaması; bunlar süre hedefine dahil. Maç öncesi ekran (kadro onayı) ve maç sonrası özet toplam 60-90 sn hedefler; "kadroyu yardımcıya bırak" ile maç öncesi tek dokunuşa iner.
- **Hava ve zemin:** maç başında ülke/ay dağılımından örneklenir (güneşli, yağmurlu, çok yağmurlu, karlı, rüzgârlı); zemin kalitesi stadyuma ve mevsime bağlı (1-10). Etki: yağmur/kötü zemin → kısa pas ×0.92, uzun top ×1.05, kaleci hata ×1.3, sakatlık ×1.15; sıcak → kondisyon tüketimi ×1.15.
- **Seyirci:** kapasite × doluluk; doluluk = f(kulüp itibarı, rakip itibarı, form, yarışma aşaması, hava). Ev avantajı dolulukla ölçeklenir (×1.03…1.08). Gelir modeline girer.
- **Devre arası:** kullanıcı taktik/değişiklik; fizyoterapist sakatlık değerlendirmesi ("devam edebilir / çıkmalı").
- **Maç sonu:** istatistik, oyuncu puanları, maçın adamı, sakatlık/ceza özeti, yardımcı antrenör yorumu, lig tablosu farkı.
- **Ceza kuralları (yarışma başına veri):** sarı kart birikimi eşikleri (ör. 5/10/15 → 1/2/3 maç), kırmızı kart cezası türe göre (iki sarı 1, sert faul 3, şiddet 4), ceza sadece aynı yarışmada; sezon sonu birikim sıfırlanır (eşik kuralı veriye bağlı).
- **Yedek kadro:** maç kadrosu 18 (veri), değişiklik hakkı 3 veya 5 (veri).

### 16.9 Finans: tam model (Faz 4)

Yönetim yönetir, kullanıcı görür ve ister. Aylık rapor ekranı; sezon sonu bilanço.

**Gelir**
- Maç günü: seyirci × bilet fiyatı (yönetim belirler, itibara göre) + loca/localar (kapasite %5'i × 8 kat fiyat).
- Yayın geliri: lig havuzu (ülke katsayısı × lig itibarı) × sıra payı (eşit %50 + sıraya göre %50).
- Sponsorluk: kulüp itibarı × ülke pazarı; 1-3 yıllık anlaşma, yenilenince güncellenir.
- Prim: lig sırası, kupa turları, kıta kupası katılım/tur/grup galibiyeti.
- Ürün satışı: itibar × yıldız oyuncu etkisi (en itibarlı 3 oyuncu).
- Transfer gelirleri, satıştan pay maddeleri.

**Gider**
- Oyuncu ve personel maaşları (haftalık), bonuslar, imza paraları.
- Transfer ödemeleri (taksitler takvimde), kiralık bedelleri.
- Stadyum bakımı (kapasite × sabit), altyapı ve tesis işletmesi (seviye × sabit), tesis inşaatı (yönetim onaylı, taksitli).
- Kredi faizi: kasa eksideyse yıllık %8; yönetim 12 ay üst üste ekside kalırsa acil satış (Bölüm 14-6) ve bütçe sıfırlanır.

**Yönetim davranışı**
- Sezon başı: önümüzdeki sezon gelir tahmini → maaş bütçesi (%55-70) ve transfer bütçesi (kalan − güvenlik payı).
- Bilet fiyatı: itibar ve doluluğa göre otomatik; kullanıcı istek açamaz (yönetim alanı).
- Stadyum büyütme: doluluk 3 ay %95+ ve kasa uygunsa yönetim kendisi başlatır; kullanıcı da isteyebilir.
- **Kulüp satın alınması:** nadir olay (yılda ligde ~1 kulüp); yeni yönetim: güven sıfırlanır (50), beklenti ve bütçe değişir (zengin alıcı: ×2-4 transfer bütçesi, beklenti +1 kademe; tasarruf alıcı: bütçe ×0.5, satış baskısı).

### 16.10 Haber, medya, ödüller, tarih (Faz 4; haber altyapısı Faz 0)

**Haber/gelen kutusu:** maç öncesi önizleme (rakip form, sakatlar, tahmini 11, tarihçe), maç raporu, transfer tamamlandı/söylenti/red, oyuncu huzursuz, sözleşme bitiyor, sakatlık ve dönüş, yönetim açıklaması (güven değişimi), milli çağrı, ödül, personel olayları, taraftar tepkisi (büyük galibiyet/mağlubiyet). Her haber tipi TR/EN şablon havuzundan; aksiyonlu haberler (teklif, sözleşme) doğrudan ekrana götürür.

**Ödüller** (lig başına): ayın oyuncusu, ayın genç oyuncusu, ayın menajeri; yılın oyuncusu, yılın genç oyuncusu, yılın menajeri, yılın takımı (11), gol kralı, en az gol yiyen kaleci. Kıta ve dünya ölçeğinde yılın oyuncusu. Ödüller itibarı, değeri ve morali etkiler; menajer ödülü yönetim güvenine +.

**Tarih ve rekorlar:** geçmiş sezon şampiyonları ve kupa kazananları (lig/kupa/kıta/dünya), kulüp tarihçesi (kupalar, en pahalı alım/satım, en çok maç/gol, geçmiş menajerler), oyuncu kariyer geçmişi (sezon sezon kulüp, maç, gol, asist, puan; milli maç/gol), menajer kariyer geçmişi (kulüpler, galibiyet oranı, kupalar), lig rekorları (sezonda en çok puan/gol, en uzun yenilmezlik), karşılıklı maç geçmişi, "onur listesi" (emekli oyuncular, efsane menajerler). Hepsi sonsuz döngüde birikir; saklama ve budama politikası Bölüm 18.

### 16.11 AI menajerler (Faz 4)

Her AI kulübün menajeri vardır: itibar, tercih formasyon ve stil (hücumcu/dengeli/savunmacı, kısa/uzun pas), nitelikler (taktik, oyuncu değerlendirme, gençlere güven, adam yönetimi). Kulübün taktiğini ve transfer hedeflerini bu profil belirler (ör. gençlere güven yüksek → 23 yaş altı alım ağırlığı ×1.5). Yönetim güveniyle kovulur, iş piyasasında yer değiştirir, ödül alır, emekli olur; yeni menajerler emekli oyuncular ve rastgele üretimden gelir. Kullanıcı rakip menajerin profilini görür (maç önizlemesinde).

### 16.12 Oyun başlangıcı, kayıt, ayarlar (Faz 0)

- **Yeni oyun:** menajer profili (ad, uyruk, yaş, geçmiş deneyim: otomatik → başlangıç itibarı), dünya boyutu (4/8/16 ülke; büyük dünya kayıt boyutu ve gün süresi uyarısı), başlangıç kulübü (herhangi bir ülke/lig, filtre: itibar, bütçe, beklenti) veya işsiz başlama, ilk transfer penceresi kapalı seçeneği, dünya tohumu (seed; aynı tohum aynı dünya, ileride paylaşım için).
- **Kayıt:** 5 yuva, otomatik kayıt (her gün sınırında, son 3 gün döndürülür), elle kayıt; kayıt dosyası sıkıştırılmış tek dosya; bulut Faz 7.
- **Kayıt şema sürümleme (Faz 0'dan itibaren):** sonsuz döngülü oyunda kullanıcının 10 sezonluk kaydı uygulama güncellemelerinden sağ çıkmalı. Her kayıt şema sürüm numarası taşır; her faz bir "göç" (migration) adımı ekler; eski kayıt açılınca sırayla göçer. Her fazın kabul kriterine "önceki fazın kaydı açılıyor ve oynanıyor" eklenir.
- **İlk oyun rehberi:** ilk sezonun ilk haftasında ekran başına tek satırlık ipuçları (kadro, taktik, devam, maç, transfer); kapatılabilir. Faz 7'de cilalanır, Faz 0'da iskeleti olur.
- **Tatile çık (CM klasiği, Faz 2):** kullanıcı bir tarihe veya olaya kadar (sonraki maç, pencere açılışı, sezon sonu) dünyayı kendi kulübünü yardımcı antrenöre bırakarak ilerletir. Simetri ilkesi gereği bu sadece "kullanıcı komut vermiyor" demektir; yardımcı kadroyu, değişiklikleri ve küçük kararları verir, transfer ve sözleşme gibi büyük kararlar bekletilir ("tatil dönüşü raporu"). Kesme kuralları ayarlanabilir: teklif gelince, sakatlık olunca, kovulma riskinde dur.
- **Ses (Faz 1b/7):** düdük, gol uğultusu, kalabalık seviyesi dolulukla, arayüz dokunuş sesleri; müzik yok (CM sadakati), hepsi kapatılabilir. Tüm ses ve font varlıkları açık lisanslı veya üretilmiş; lisanslı varlık yok.
- **Analitik ve gizlilik (Faz 7):** çökme raporu ve isteğe bağlı anonim kullanım ölçümü; kişisel veri yok; mağaza gizlilik beyanı buna göre. Tasarım kararı: oyun çevrimdışı tam çalışır, hiçbir özellik ağ gerektirmez (bulut kayıt hariç).
- **Ayarlar:** dil (TR/EN, anında), para birimi gösterimi (soyut birim; "₺/€/£" sadece sembol), izleme modu varsayılanı, haber yoğunluğu (az/normal/çok), renk körlüğü dostu forma kontrastı (2D için).

---

## 17. Test stratejisi

Oyunun tüm özelliklerini bir insanın elle test etmesi mümkün değil. Testler ürünün parçasıdır; her faz kendi test katmanlarıyla "bitti" sayılır. İlke: **elle yazılmış senaryo testleri ölçeklenmez; simülasyon + değişmezler ölçeklenir.** İkisi birlikte kullanılır.

### 17.1 Katmanlar

| Katman | Ne | Ölçek | Ne zaman koşar |
|---|---|---|---|
| **Birim** | Motor fonksiyonları: değer modeli, xG, yaşlanma, güven, bütçe… Her formül için sınır ve tipik değerler | Binlerce; çoğu tablo-güdümlü (spesifikasyondaki tablolar doğrudan test verisi olur) | Her değişiklikte |
| **Senaryo** | Belirli durum → beklenen sonuç. "Ocakta 5 ay sözleşmesi kalan oyuncu ön sözleşme teklifi alır, 1 Temmuz'da katılır." "5. sarı kart → 1 maç ceza, sadece o yarışmada." | Yüzlerce-binlerce; spesifikasyon cümlelerinden türetilir, her Bölüm 16 maddesi en az 3 senaryo | Her değişiklikte |
| **Değişmezler** | Her günün sonunda dünyanın sağlamasını yapan kurallar (17.2). Uzun simülasyonlarda her gün koşar | ~100-200 kural × 10.000+ gün | Her değişiklikte (kısa sim), gecelik (30 sezon) |
| **İstatistiksel** | Bölüm 9: 10.000 maç, 100 sezon, 30 sezon dağılım kontrolleri; toleranslı | Onlarca kontrol, milyonlarca örnek | Motor/kalibrasyon değişince; gecelik |
| **Determinizm** | Aynı seed iki kez → bit-bit aynı dünya; hızlı mod = detaylı mod (müdahale yok); isolate'ta koşan = ana iş parçacığında koşan | Birkaç test, her sistemi kapsar | Her değişiklikte |
| **Regresyon (altın)** | Sabit seed ile 1 sezonun özet hash'i (tablo, transferler, sakatlıklar). Değişince ya bilinçli kalibrasyon ya hata | Faz başına bir altın dosya | Her değişiklikte |
| **Fuzz / maymun** | Rastgele kullanıcı aksiyonları (teklif, taktik, değişiklik, istifa…) + gün ilerletme, değişmezler açık | Gecelik, saatlerce | Gecelik |
| **Göç** | Her fazın kayıt dosyası sabit örnek olarak saklanır; yeni sürüm hepsini açıp 1 sezon oynar | Faz sayısı kadar örnek | Her değişiklikte |
| **Performans** | Büyük dünyada gün süresi, bellek, kayıt boyutu; bütçe aşımı test hatası | Birkaç ölçüm | Gecelik |
| **Arayüz: widget** | Her ekran sahte dünyayla açılır, TR ve EN'de taşma/kesilme yok, aksiyonlar motora doğru komutu gönderir | Ekran başına 5-20 | Her değişiklikte |
| **Arayüz: altın görüntü** | Ekranların referans görüntüleri (iki dil, iki tema, 2 ekran boyutu) | Ekran başına 4-8 | Her değişiklikte |
| **Arayüz: entegrasyon** | Uçtan uca akışlar simülatörde: yeni oyun → ilk hafta → transfer → maç izle → kaydet → aç | 20-40 akış | Gecelik |

### 17.2 Değişmezler (örnek liste, tam liste motorla birlikte büyür)

- Her oyuncu tam olarak bir kulüpte ya da serbesttir; kiralık oyuncunun ana kulübü ve geçici kulübü farklıdır.
- Kadro 18-28; maç kadrosu yarışma kuralına uyar; cezalı, sakat veya milli görevdeki oyuncu ilk 11'de değildir.
- Kondisyon, moral, maç formu 0-100; nitelikler 1-20; CA ≤ PA; yaş 15-45.
- Sözleşme bitişi > başlangıcı; sözleşmesi bitmiş oyuncu kulüpte değildir.
- Maaş toplamı ≤ maaş bütçesi (kullanıcı kulübü için zorunlu; AI için satış baskısı tetiklenmiş olmalı).
- Her lig fikstürü: her takım her takımla 2 kez; her maç tam bir kez oynanmış; tablo puanları = maçlardan hesaplanan.
- Puan tablosu toplam gol attı = toplam gol yedi.
- Transfer: para iki kulüp arasında korunur (taksitler dahil); aynı oyuncu için iki kabul edilmiş teklif yok.
- Gelen kutusu: aksiyonlu her haber geçerli bir varlığa işaret eder.
- Takvim: aynı gün aynı takım iki maç oynamaz; milli arada lig maçı yok.
- Kayıt → yükle → kayıt: ikinci dosya birinciyle aynı.
- Tarih: bir sezonun şampiyonu o sezon tablosunun birincisidir; rekorlar monoton.

### 17.3 Kabul kuralı

Bir faz, şu dört şey yeşilken biter: tüm birim/senaryo testleri, değişmezler 30 sezon boyunca ihlalsiz, istatistiksel kontroller toleransta, önceki fazların kayıtları açılıyor. Kalibrasyon katsayısı değişince altın dosya bilinçli güncellenir ve değişiklik notu yazılır.

Test sayısı hedefi değil, kapsama hedefi: Bölüm 5-8 ve 16'daki her cümle en az bir testle karşılanır. Planlama aşamasında (Faz planları) her maddeye test kimliği eşlenir.

---

## 18. Veri büyümesi ve performans (sonsuz döngü)

### 18.1 Ne büyür, ne büyümez

| Veri | Davranış | Büyük dünya tahmini |
|---|---|---|
| Canlı dünya (oyuncular, kulüpler, personel, menajerler, sözleşmeler, fikstür) | **Sabit.** Nüfus kontrolü (Bölüm 8.3) giren = çıkan tutar | ~30.000 oyuncu × ~0.5 KB ≈ 15 MB bellekte, sıkıştırılmış kayıtta ~5 MB |
| Maç ayrıntısı (hücum adımları, mikro-olaylar) | **Hiç saklanmaz.** Motor deterministik: kullanıcı kulübünün maçları için sadece (seed, kadrolar, taktikler, motor sürümü) ≈ 1 KB saklanır; "tekrar izle" aynı motor sürümüyle yeniden üretir, sürüm değiştiyse tekrar yok | sezonda ~60 KB |
| Maç özeti (skor, golcüler, kartlar, istatistik) | Kullanıcı kulübü: sonsuza kadar. Diğerleri: son 3 sezon, sonra silinir | sezonda ~25.000 maç × 150 B ≈ 4 MB sıcakta, soğuğa geçerken ~10 KB |
| Oyuncu sezon istatistiği | Canlı oyuncuda satır olarak durur (kariyer boyu ≤ 20 satır). Emeklilikte: "kayda değer" ise onur listesine, değilse kariyer toplamına indirgenip oyuncu silinir | sezonda ~1.5 MB sıcakta, soğukta ~100 KB |
| Lig tabloları, kupa sonuçları, ödüller | Sezon sonunda **nihai tablo** ve kazananlar kalır; haftalık tablolar atılır | sezonda ~50 KB |
| Transferler | Son 3 sezon tam liste; sonra sadece rekorlar ve kulüp "en pahalı alım/satım" | sezonda ~100 KB → ~5 KB |
| Gelen kutusu / haberler | Son 300 + yıldızlı olanlar; sezon sonunda eskiler silinir | sabit, ~200 KB |
| Rekorlar, kulüp onur listesi, menajer kariyerleri, efsane oyuncular | Sonsuza kadar; küçük | sezonda ~50 KB |

**Hedef:** soğuk tarih sezon başına < 500 KB sıkıştırılmış. 100 sezon < 60 MB. Canlı dünya + son 3 sezon ≈ 25 MB. Toplam 100 sezonluk kayıt < 100 MB.

"Kayda değer oyuncu" tanımı (onur listesine girer, geri kalanı silinir): üst ligde 100+ maç **veya** herhangi bir ödül **veya** milli takımda 20+ maç **veya** kulüp rekoru **veya** kullanıcının kulübünde 50+ maç. Sezonda emekli olan ~2.000 oyuncunun ~%10'u kalır.

### 18.2 Üç katmanlı saklama

```
SICAK   bu sezon            bellekte, tam ayrıntı, her kayıtta yazılır
ILIK    son 3 sezon         maç özetleri + transfer listeleri; diskte, açılınca yüklenir
SOĞUK   daha eski           nihai tablolar, kazananlar, rekorlar, onur listesi, kullanıcı maçları;
                            sezon başına bir dosya, bir kez yazılır, bir daha değişmez (immutable)
```

Sezon devrinde "arşivleme" adımı: ılık → soğuk indirgeme, silme politikaları, onur listesi güncelleme. Bu adım da deterministiktir ve test edilir.

### 18.3 Kayıt dosyası düzeni

```
save_slot_1/
  world.bin            canlı dünya (sıcak); her kayıtta yeniden yazılır (~5-10 MB sıkıştırılmış)
  recent/              ılık: son 3 sezon, sezon başına bir dosya
  history/             soğuk: sezon başına bir dosya, immutable
  index.json           şema sürümü, sezon listesi, özet sayılar, bütünlük hash'leri
```

- **Yükleme:** sadece `world.bin` + `index`. Tarih ekranları ilgili sezon dosyasını açılınca okur (tembel yükleme). Yükleme süresi sezon sayısından bağımsız.
- **Kayıt:** sadece `world.bin` yeniden yazılır; ılık/soğuk dosyalar sezon devrinde bir kez yazılır. Otomatik kayıt ayrı isolate'ta; hedef < 1 s, arayüz donmaz.
- **Biçim:** kompakt ikili (ör. MessagePack veya alan sıralı özel biçim) + sıkıştırma. JSON değil (3-5 kat büyük, yavaş). Şema sürümü ve göç adımları (16.12).
- Bulut senkronu (Faz 7) sadece değişen dosyaları gönderir; soğuk dosyalar bir kez yüklenir.

### 18.4 Günlük işlem süresi sezonla büyümemeli

Gün süresi canlı dünyanın boyutuna bağlıdır, oyunun yaşına değil. Bunu garantileyen kurallar:
- Hiçbir günlük işlem tarih dosyalarını okumaz. Tarih sadece arayüz için vardır.
- Oyuncu nesnesi üzerinde büyüyen tek şey kariyer satırları (≤ 20); gün döngüsü onları okumaz.
- Dizinler: kulüp → oyuncular, uyruk → oyuncular, tarih → maçlar, pozisyon → serbest oyuncular. Tam tarama yalnızca sezon devrinde.
- AI kulüp düşünme round-robin (günde 1/7); transfer kısa listeleri dizinden, tam taramadan değil.
- Takım güç profili (Bölüm 5.2) kadro/taktik değişince yeniden hesaplanır, maç başında değil.
- Maç günü: maçlar isolate'ta, paralel çalıştırılabilir (maçlar birbirinden bağımsız, her birinin kendi seed'i var; determinizm korunur).

### 18.5 Bellek

- Canlı dünya tamamen bellekte (~15-25 MB büyük dünyada). Düşük segment telefonlarda sorun değil.
- Anlatım şablonları ve isim havuzları: tek kopya, sabit.
- Tarih ekranları: açılan sezon dosyası okunur, kapanınca bırakılır.
- 2D maç: sabit boyutlu nesne havuzu (22 boncuk + top + klipler), maç başına ayırma yok.

### 18.6 Testler (Bölüm 17'ye ek)

- 100 sezonluk gecelik koşu: kayıt boyutu her sezon ölçülür; soğuk sezon dosyası < 500 KB; toplam < 100 MB.
- Gün süresi: 100. sezondaki ortalama gün süresi ≤ 1.2 × 1. sezon (büyüme yok).
- Yükleme süresi 100. sezonda ≤ 1.2 × 1. sezon.
- Arşivleme adımı deterministik; onur listesi kriterleri senaryo testli.
- Silme güvenliği: silinen oyuncuya/maça işaret eden hiçbir canlı referans kalmaz (değişmez).
- Bellek: 100. sezonda canlı dünya bellek kullanımı ≤ 1.1 × 1. sezon.


---

## 19. Monetizasyon seçenekleri (karar Faz 7'de; tasarım etkisi Faz 0'da)

Anti-hedef sabit: **oyun içinde avantaj satılmaz.** Satılmayacaklar: oyun içi para/bütçe, anında iyileşme, nitelik artışı, gözlemci/antrenman hızlandırma, transfer garantisi, "şanslı maç". Bunların hepsi sonsuz döngüyü ve simetri ilkesini bozar.

| Model | Nasıl | Artı | Eksi | Uyum |
|---|---|---|---|---|
| **A. Tek seferlik ücret (premium)** | Mağazada ücretli indirme | En basit, en temiz; PC/Steam'de zaten norm | Mobilde erişim düşük, deneme yok | İyi |
| **B. Ücretsiz dene + tek seferlik kilit açma** | İlk sezon (veya küçük dünya, tek ülke) ücretsiz; sınırsız sezon + tüm dünya tek ödemeyle | Simülasyonu yaşatıp sonra satıyor; P2W yok | Sınır noktasının iyi seçilmesi gerekir | **En iyi** |
| **C. Ücretsiz + reklam, "reklamı kaldır" satın alma** | Maç günleri arasında geçiş reklamı; ödül reklamı yok | Erişim en geniş | Uzun oturumlu menajerlik oyununda reklam deneyimi bozar; banner arayüzü sıkıştırır | Orta |
| **D. İçerik paketleri** | Ek ülke/lig paketleri (kurgusal), büyük dünya, tarih modu | FM Mobile'ın modeli; sürekli gelir | Sadece B/A üstüne eklenti olarak anlamlı | B ile iyi |
| **E. Kozmetik** | Forma tasarımcısı, temalar, logo paketleri, anlatım tarzı paketleri | Zararsız | Düşük gelir | Ek |
| **F. Abonelik** | Aylık ücret | — | Çevrimdışı tek oyunculu oyuna uymaz, güven kırar | Hayır |

**Öneri:** B + D (+ E isteğe bağlı). Ücretsiz indirme; ilk sezon tam özellikli ve küçük dünyada ücretsiz; tek ödemeyle sınırsız sezon ve orta dünya; büyük dünya ve ek ülke paketleri ayrı. PC/web'de A (tek fiyat, her şey dahil). Reklam yok; istenirse daha sonra C'nin ödül reklamı sadece kozmetik için eklenebilir.

**Faz 0'a etkisi (küçük):** "yetki" (entitlement) kavramı: dünya boyutu ve sezon sayısı sınırı kayıtta değil, cihaz yetki durumundan okunur; yeni oyun ekranı ve sezon devri bunu kontrol eder. Çevrimdışı doğrulama (mağaza makbuzu önbelleği). Başka hiçbir sistem monetizasyonu bilmez.

---

## 20. Veri kaynakları, lisans ve kullanıcı veri paketleri (karar 2026-10-27)

Hukuki görüş değildir; mağazaya çıkmadan önce bir avukat kontrolü planlanır.

### 20.1 Gönderilen veride ne gerçek, ne kurgusal

| Veri | Durum | Gerekçe |
|---|---|---|
| Ülke ve şehir adları, bayraklar | Gerçek | Kamuya açık olgu / kamu malı |
| Lig adları, federasyon logoları | Kurgusal | Marka hakkı (SMK 6769 ve muadilleri) |
| Kulüp adları, logoları, formaları, stadyum adları | Kurgusal | Marka hakkı; "benzer ad" (ör. Galata SK) karıştırma riski taşır, kullanılmaz |
| Oyuncu, teknik direktör, başkan, personel adları ve görüntüleri | Kurgusal | Kişi hakları (TMK 24–26, FSEK 86); "kim olduğu anlaşılan benzer ad" tam olarak yasaklanan şeydir, kullanılmaz |
| Başka oyunların veri tabanları (ör. FM nitelik puanları) | Kullanılmaz | Tekil nitelik puanları yaratıcı eserdir; isim değiştirmek kopyayı meşrulaştırmaz |
| Oyun kuralları, takvim yapıları, lig formatları | Gerçek | Olgu; telife tabi değil |

Anti-hedef (Bölüm 2) aynen geçerli: gönderilen pakette gerçek kulüp/oyuncu/personel yoktur.

### 20.2 Gerçekçilik: kamuya açık olgulardan kalibrasyon (Faz 2)

Kurgusal dünyanın "gerçek gibi" hissetmesi tekil verilerden değil dağılımlardan gelir. Dünya üreticisi (Faz 0) ülke başına şu hedef bantlara karşı kalibre edilir; bantlar kamuya açık olgulardan türetilir (federasyon kadro kuralları, UEFA/FIFA katsayı ve sıralamaları, kamuya açık transfer/maaş ölçekleri, Wikipedia lig yapıları):

- Lig piramidi: kademe sayısı, kademe başına kulüp sayısı, küme düşme/çıkma sayıları.
- Kadro: kulüp başına oyuncu sayısı bandı, mevki dağılımı, yaş profili (Bölüm 9 bantları ülke başına özelleşebilir), yabancı oranı.
- Kalite kademeleri: kademeler arası ortalama CA farkı, bir ligde "dünya sınıfı" (CA ≥ 170) oyuncu sayısı bandı, ülke itibarı sıralaması.
- Ekonomi: kademe başına bütçe/maaş/transfer ölçeği (soyut para biriminde oranlar korunur), stadyum kapasitesi bandı.
- Altyapı akışı: yılda kulüp başına çıkan oyuncu sayısı ve kalitesi.

Her bant bir test olur (Bölüm 17 katmanı: uzun simülasyon + üretim anı). Bantlar `docs/data/calibration/<ülke>.md` altında kaynağıyla birlikte yazılır; sayılar olgu, kaynak gösterilir.

### 20.3 Kullanıcı veri paketleri — mod sistemi (Faz 3)

Kullanıcı, kurgusal dünyanın üstüne kendi veri paketini yükleyebilir. Gerçek isimli paketleri topluluk yapar ve dağıtır; **biz hiçbir gerçek isimli paketi üretmez, barındırmaz, mağazada sunmayız.** Sorumluluk paketi yapan ve yükleyendedir; paket yükleme ekranı bunu açıkça söyler (TR/EN).

**Paket kapsamı (kademeli):**
1. **İsim paketi:** ülke, lig, kulüp, stadyum, oyuncu, personel adlarını değiştirir; motor kimlikleri (id) değişmez. Yeni oyunda uygulanır, mevcut kayıtlara da uygulanabilir (isimler kayıtta değil, kimlik haritasında tutulur).
2. **Görsel paketi:** logo ve forma tanımları (forma şablonu + renkler veya küçük PNG; Bölüm 18 boyut sınırı).
3. **Dünya paketi:** lig yapısı, kulüp listesi, kadrolar ve nitelikler (tam dünya tanımı). Yalnızca yeni oyunda; üretici bu paketi çekirdek olarak alıp eksikleri (altyapı, alt ligler) kurgusal üretir.

**Biçim:** tek dosya (zip içinde JSON + görseller), şema sürümlü; motor şeması gibi geçiş (migration) kuralı. Doğrulama: zorunlu alanlar, kimlik tutarlılığı, boyut sınırları, nitelik aralıkları (1–20), toplam oyuncu sayısı dünya boyutu üst sınırı içinde. Geçersiz paket yüklenmez, hata listesi gösterilir.

**Motor etkisi:** yalnızca dünya üreticisine "çekirdek tanım" girişi ve isim/görsel çözümlemeye bir dolaylama katmanı. Simülasyon, kalibrasyon ve determinizm paketten bağımsız kalır (aynı paket + aynı seed = aynı dünya).

**Testler:** örnek paket yükle → şema doğrulama → sezon oyna → değişmezler yeşil; bozuk paket örnekleri reddedilir; isim paketi uygulanmış kayıt eski sürümle açılır (geriye uyumluluk).

