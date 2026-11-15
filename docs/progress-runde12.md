# Runde 12 – Wiedergabefehler, Lautsprecher, Downloads als Dateien, PS5-Stick

Reihenfolge 1 → 2 → 3 → 4, nach jedem Punkt ein Release. Android-Details:
`docs/progress-android.md` im Android-Repo.

| Punkt | Inhalt | Status |
|---|---|---|
| 1 | iPad: Wiedergabefehler protokollieren, Client-Fallback wie Android, „Erneut versuchen“ | Release iPad v0.8.19 (Unit-Tests grün, auf dem iPad nicht getestet) |
| 2 | Beide: Lautsprecher-Auswahl im Player | iPad v0.8.20, Android v1.0.12 (ohne echten Lautsprecher getestet) |
| 3 | Android: Downloads als sichtbare Dateien, „Nur Downloads“ | Android v1.0.12 |
| 4 | Android: PS5-Stick | Android v1.0.12, Format für die PS5 in v1.0.13 (siehe Abschluss unten) |

## 1. iPad: Wiedergabefehler

### Befund
- Die Stream-Auflösung liegt im Paket SwiftyTube 0.0.6. Bisherige Kette des iPads:
  VISIONOS → ANDROID_VR 1.65.10 / 1.61.48 / 1.43.32 → TVHTML5_SIMPLY_EMBEDDED_PLAYER →
  IOS (ohne Prüfung) → TVHTML5 → ANDROID → WEB_REMIX (ohne Prüfung).
- Android (`YTPlayerUtils.kt`): Hauptclient WEB_REMIX, Fallback VISIONOS, ANDROID_VR 1.65.10,
  WEB_REMIX, WEB, MWEB (WEB_CREATOR nur mit Login). Bei HTTP 403/404/410/416 im Player wird der
  Client für das Video 10 min gesperrt und neu aufgelöst.
- Versionsnummern der gemeinsamen Clients sind auf beiden Seiten gleich, veraltet war nichts.
  Aber: TVHTML5_SIMPLY_EMBEDDED_PLAYER antwortet ohne Login inzwischen „YouTube is no longer
  supported in this application“, IOS liefert nur HLS, ANDROID ohne Login keine URLs, TVHTML5
  ohne Login „UNPLAYABLE“. WEB und MWEB fehlten dem iPad ganz.
- Fehler im iPad-Code: Scheiterte das Laden eines *neuen* Songs (z. B. HTTP 403), war seine ID
  noch „pending“; die Fehlerbehandlung verglich mit der alten ID und ignorierte den Fehler →
  stiller Stillstand ohne Fallback und ohne Meldung. Ein zweiter Fehler innerhalb von 30 s
  stoppte ebenfalls still.
- Ursache des Ausfalls an dem einen Tag: nicht mehr belegbar. Vermutung: Die direkten
  VR/visionOS-URLs fielen serverseitig zeitweise aus, der Web-Pfad des iPads trug nicht (nur
  WEB_REMIX ganz am Ende, ohne Prüfung); Android hat WEB_REMIX als Hauptclient.

### Umsetzung
- Eigene Schleife (`StreamClientFallback`), ein Client nach dem anderen: VISIONOS,
  ANDROID_VR 1.65.10 / 1.61.48 / 1.43.32, WEB_REMIX, WEB, MWEB (neu, Version wie Android),
  IOS, TVHTML5 (nur mit Login), ANDROID. Der tote Embedded-Client ist raus.
- Jeder Stream wird mit einer Range-Anfrage geprüft, der HTTP-Status landet im Protokoll.
- Ein Client, der für einen Song scheitert, wird für diesen Song 10 min übersprungen (wie
  Android). Kann der Player einen Stream nicht laden (früh, ≤ 15 s, oder mit HTTP
  403/404/410/416 aus mpvs Log), geht es mit dem nächsten Client weiter. Späte Abbrüche ohne
  HTTP-Fehler (abgelaufene URL) lösen einmal neu auf, mit 30 s Abklingzeit.
- Alle Clients gescheitert: abgelaufener Cache-Eintrag als letzter Versuch, sonst Banner.
- Fehlerprotokoll (letzte 200 Einträge, Application Support): Uhrzeit, Song-ID, Client +
  Version, Stufe (resolve / validate / player / success), HTTP-Status, Fehlertext.
  Geschwärzt: URLs (nur Host + itag), `key=value`-Geheimnisse, E-Mail-Adressen, Zeichenketten
  ab 32 Zeichen. Keine Cookies, keine Kontodaten.
- Einstellungen → Über → „Fehlerprotokoll teilen“ (Textdatei über das Teilen-Menü).
- Banner: „„Titel“ kann nicht abgespielt werden“, verständlicher Grund auf Deutsch (neu:
  „YouTube hat den Stream für alle ausprobierten App-Profile abgelehnt …“), Knöpfe „Erneut
  versuchen“ (vergisst die Sperren für den Song, löst neu auf) und „Details kopieren“.
- Unit-Tests (`StreamClientFallbackTests`): Reihenfolge, Abbruch nach Erfolg, Sperren und
  Ablauf, Protokoll (200, Neustart, Export), Schwärzung, HTTP-Status aus mpv-Logzeilen.

### Nicht geprüft
- Auf einem echten iPad nicht getestet (nur Simulator-CI, dort bekommt YouTube eine
  Bot-Prüfung, die UI-Tests spielen einen Testton). Ob WEB/MWEB ohne Login auf dem iPad
  zuverlässig Streams liefern, zeigt erst das Fehlerprotokoll im Alltag.

## 2. Lautsprecher-Auswahl (beide Apps)

- Knopf in der unteren Player-Leiste zwischen Sleep-Timer und Songtext (iPad und Android an
  derselben Stelle, in jedem Player-Stil sichtbar). Auf dem Gerät selbst ein runder Knopf,
  bei externer Ausgabe eine Pille mit Icon + Name (z. B. „Echo Dot“) in der Cover-Farbe;
  der Mini-Player zeigt Icon + Name ebenfalls, nur bei externer Ausgabe.
- Sheet „Lautsprecher“ im Glas-Look, gleiche Reihenfolge und Texte: aktuelle Ausgabe
  („Verbunden“, Haken) → „Ausgabe wählen“ (System-Liste) → neue Bluetooth-Geräte.
- iPad: „Ausgabe wählen“ ist AVRoutePickerView (iPad, Bluetooth-Geräte in Reichweite,
  AirPlay); AVRouteDetector meldet, ob andere Ausgaben da sind (nur solange das Sheet offen
  ist). Hinweis „Neues Bluetooth-Gerät? Einmal in den iPad-Einstellungen koppeln“ mit
  „Einstellungen öffnen“ (App-Einstellungen – mehr erlaubt iOS nicht). Keine eigene Suche.
- Android: zusätzlich „Dieses Gerät“ und die gekoppelten Bluetooth-Audiogeräte (Verbunden /
  In Reichweite / Gekoppelt), „In der Nähe suchen“ (nur Audio-Geräte), Antippen koppelt und
  verbindet. Direktes Verbinden ist auf Android 13+ nur System-Apps erlaubt; dann öffnet
  Resona die System-Ausgabeauswahl, wo ein Tipp verbindet. Shizuku: geprüft, aber nicht
  eingebaut – es gibt keinen Shell-Befehl zum Verbinden, und der Weg über interne
  Bluetooth-Schnittstellen ist ohne Tests mit echtem Gerät zu unsicher.
- Getestet auf dem Pixel ohne Lautsprecher: Sheet, „Bluetooth ist aus / Einschalten“,
  System-Ausgabeauswahl öffnet sich. Nicht getestet: Suchen, Koppeln, Verbinden mit echtem
  Lautsprecher/Echo Dot; iPad nur Unit-Tests (Ausgabe-Arten, Icons, Namen).

## 3./4. Android: Downloads als Dateien, PS5-Stick
Details in `docs/progress-android.md` (Android-Repo). Auf dem iPad offen: PS5-Stick mit
gleicher Struktur und gleichem Manifest, Stick per Dokumentauswahl, manueller Sync – erst
nach dem Test auf der PS5.

---

# Runde 12 – Abschluss (selbstständig, ohne Rückfragen)

Auftrag in 7 Punkten, Emil war nicht erreichbar. Android-Teil: `docs/progress-runde12.md`
im Android-Repo (PS5-Format v2 + MP3/FLAC + Cover-Test → v1.0.13, Wiedergabefehler →
v1.0.14, gesammelte Gerätetests).

| Punkt | Inhalt | Stand |
|---|---|---|
| 1 | Android: PS5-Format v2, Cover-Test-Ordner | Android v1.0.13 |
| 2 | Android: Wiedergabefehler wie iPad v0.8.19 | Android v1.0.14 |
| 3 | iPad: CTC-Alignment wie Android | Release iPad **v0.8.21** |
| 4 | CTC mit deutschen Platzhaltertexten | Test grün auf beiden; kein MMS |
| 5 | Lyrics-Tiefe Android | nicht gemessen (kein Gerät) |
| 6 | Glas unter Android 12; iPad-UI-Test test1Portrait | siehe unten |
| 7 | PS5-Stick fürs iPad | vorbereitet, nur im Entwicklermodus |

## 3. KI-Sync: CTC auf dem iPad

- Gleiches Modell wie Android: wav2vec2-base-960h int8 (ONNX, ≈ 95 MB, einmal geladen nach
  Application Support/aisync), ONNX Runtime per SwiftPM (`onnxruntime-swift-package-manager`
  1.24.2, 4 Threads). Fenster von 30 s, je Fenster normalisiert, Log-Softmax, Viterbi-Pfad
  über die Buchstaben der Lyrics (`CtcAligner`, Unicode-Skalare, Umlaute gefaltet).
- Ablauf: Lyrics bekannt und ≥ 80 % lateinische Buchstaben → CTC; die Wörter gehen durch
  denselben `LyricsAligner` und dieselbe Tempo-Kalibrierung wie bei Whisper. Liefert CTC
  kein brauchbares Ergebnis → automatisch WhisperKit. WhisperKit bleibt für „Lyrics aus
  Audio“, nicht-lateinische Lyrics und als Fallback.
- Tests (gleich wie Android `CtcAlignerTest`): Buchstaben/Umlaute, Trenner, Wörter an der
  richtigen Stelle, nicht gehörte Wörter fehlen, gleicher Aligner, deutsche Platzhalter,
  Log-Softmax. Neu nur auf dem iPad: `AISyncPipelineTests.testCtcAlignsTheSameSpeech` –
  dieselbe synthetische Sprache (macOS `say`, erfundene Sätze) wie der Whisper-Test.
- Laufzeit im Simulator (GitHub-Runner, macOS 26, Apple Silicon):
  - Whisper base, gleiche Sprachdatei: 80,5 s (Testlauf vom 15.11.)
  - CTC: CTC_LAUFZEIT
  - Zum Vergleich Android (Pixel 11 Pro, echter Song 169 s): CTC 10,2 s, Zeilenfehler
    Median 0,07 s.
- Auf einem echten iPad nicht gemessen.

## 4. Deutsch
Siehe Android-Doku, gleiche Entscheidung: kein MMS jetzt, weil Whisper als Fallback greift
und MMS ≈ 10× größer ist; erst nach Messung mit echten deutschen Songs.

## 6. iPad-UI-Test test1Portrait
Fehlerbild (Lauf 15.11., Stand vor dem Fix): „close button appears after a tap“ – der Tipp
auf die Songtext-Pille kam bei einem übrig gebliebenen Drop-Menü nicht an, danach folgten
alle weiteren Player-Schritte. Fix: Drop-Menü mit Wiederholungen öffnen (Button oder
Menüpunkt), Rest-Menü vorher schließen, Pille erneut tippen, wenn der Player noch vorne
liegt; Drop-Sprung geprüft als „zwei Sprünge landen an derselben Stelle“ statt „> 4 s
bewegt“; Live-Vorschläge nur notiert (hängen von YouTubes Antwort an den Runner ab).
Ergebnis: UI_ERGEBNIS

## 7. PS5-Stick fürs iPad (nicht freigegeben)
- Einstellungen → Speicher (Downloads) → Abschnitt „Developer (testing)“ nur im
  Entwicklermodus → Schalter „PS5 stick (preview)“ → Seite „PS5 stick“.
- Stick per Dokumentauswahl (Ordner, Bookmark bleibt), Playlists wählen, „Sync now“ oder
  „Sync and remove playlists no longer chosen“ (mit Rückfrage).
- Gleiche Struktur und gleiches Manifest wie Android: `Music/<Playlist>/<Nr> - <Künstler> -
  <Titel>.m4a`, `Music/.resona-sync.json` (Schlüssel `<Playlist-ID>/<Song-ID>`, Feld
  `format`; liest auch Android-Manifeste ohne Standardwerte), FAT32-sichere Namen nach
  denselben Regeln, nur Dateien aus dem Manifest werden verschoben oder gelöscht,
  Umnummerieren in zwei Schritten (kein Überschreiben bei 01 ↔ 02).
- Kopiert werden die vorhandenen iPad-Downloads (ffmpeg-M4A, Marke `M4A `, `stco`, JPEG-Cover
  – laut PS5-Test spielbar) und als Formatversion 2 eingetragen; nicht geladene Songs werden
  übersprungen und gezählt. Kein eigenes Umwandeln, kein MP3, kein Cover-Test-Ordner.
- Tests `StickSyncTests` (Namen, Android-Manifest, erster/zweiter Abgleich, Umbenennen,
  Entfernen, Umnummerieren, abgewählte Playlist). Auf einem iPad mit Stick nicht getestet.

## Entscheidungen ohne Rückfrage (iPad)
- CTC sofort als Standard released (Unit-Tests grün), da Whisper bei schlechtem Ergebnis
  automatisch übernimmt.
- PS5-Stick nur im Entwicklermodus + Schalter; wird mit dem nächsten Release ausgeliefert,
  bleibt aber unsichtbar, bis der Cover-Test an der PS5 gemacht ist.
- Stick-Abgleich ohne MP3/Cover-Test-Varianten (erst nach dem PS5-Ergebnis entscheiden).
