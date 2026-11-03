# Runde 11 – Feinschliff, Angleichung iPad/Android, KI-Sync & Glas auf Android

Reihenfolge: A (Android-Fixes) + B (iPad-Fixes) als eigenes Release, dann C
(Angleichung, `docs/angleichung.md` in beiden Repos), dann D (KI-Sync +
Glas auf Android). Android-Details: `docs/progress-android.md` im Android-Repo,
Pixel-Screenshots unter `docs/screens-r11/` dort.

| Schritt | Inhalt | Status |
|---|---|---|
| A1 | Android: Resona-Glyph statt ArchiveTune-Logo (Kopf, Benachrichtigung, Über, Platzhalter, Widgets, Teilen) | Release Android v1.0.7 (auf dem Pixel geprüft) |
| A2 | Android: Lyrics immer als Zeilen (TTML/LRC/Enhanced/Plain) – Selbst-Sync, Editor, Übersetzung | Release Android v1.0.7 (auf dem Pixel geprüft) |
| A3 | Android: ArchiveTune-Überbleibsel (Werbekarte, Deep-Links, Logs, Anime-Platzhalter …) | Release Android v1.0.7 (auf dem Pixel geprüft) |
| A4 | Android: grüner „…“-Knopf | geprüft: ArchiveTune-Schnellaktionen, gewollt; Gestaltung in C |
| B1 | iPad: Immersiv mit Steuerung (Tippen zeigt, Ausblenden nach 4 s, VoiceOver immer) | Release iPad v0.8.16 |
| B2 | iPad: Genre-Kacheln | geprüft: in Suche/Entdecken seit v0.8.12 aktiv, Beleg `docs/screens-r11/ipad-suche-genre-kacheln-v0.8.15.png` |
| B3 | iPad: Warteschlange scrollt, sortiert um, wischt zum Entfernen; UI-Test mit 60 Songs | Release iPad v0.8.16 |
| C | Angleichung (`docs/angleichung.md`): Logo, Texte, Codec-Zeile, Schriftschnitte, Lyrics-Schrift, Lyrics-Tiefe, Theming-Tabelle | in Arbeit |
| E | Player-Hintergrund nur Farbverlauf (Canvas-Farben unsichtbar mitlesen / Cover / statisch), beide Apps | umgesetzt, im Test |
| F | Lyrics-Tiefe im iPad-Hochformat (Blur nur nach Abstand), Tempo-Hinweis „Songlänge unbekannt“ | umgesetzt, im Test |
| D | KI-Sync + Glas auf Android | offen |

## B1 Immersiv
Ursache: Der Hintergrund (Canvas/Cover-Scheibe, ignoriert die Safe Area) lag
mit im Layout-Stapel und machte ihn größer als den Bildschirm – die Steuerung
unten rutschte aus dem Bild, nur „Läuft gerade“ oben blieb. Jetzt liegt der
Hintergrund als `.background`; Titel, Fortschritt, Play/Pause, Vor/Zurück,
Shuffle/Repeat/Drop, Queue/Sleep/Lyrics erscheinen beim Start und auf Tippen,
verschwinden nach 4 s (nicht während des Spulens), bleiben mit VoiceOver an.

## B2 Genre-Kacheln
Der Simulator-Screenshot des Testlaufs von v0.8.15 zeigt die gestaffelten
Kacheln mit eigenen Formen in Suche → Erkunden (dieselbe Komponente nutzen
Entdecken und Genre-Seiten; „Genres entdecken“ steht auf der Startseite nach
den ersten Regalen). Wer keine Änderung sieht, hat vermutlich noch einen
Stand vor v0.8.12 installiert (Feather → Resona aktualisieren).

## B3 Warteschlange
Hauptursache (Simulator-Screenshot `portrait-16-queue` des v0.8.15-Tests): Im
iPad-Hochformat erschien die Queue als kleines Formular-Sheet; Kopf, Chips und
Autoplay-Schalter füllten es, die Liste bekam fast keine Höhe – nichts zu
scrollen. Jetzt öffnen Queue und Player-Menü auf dem iPad auch im Hochformat
als Seitenleiste neben dem Player (wie im Querformat). Weitere Ursachen: (1) Im Querformat liegt die Queue als Seitenleiste im Player; dessen
Herunterzieh-Geste zum Einklappen lief gleichzeitig und zog beim Scrollen nach
unten den ganzen Player mit. Jetzt aus, solange Queue/Menü als Seitenleiste
offen sind. (2) Als Sheet vergrößerte Scrollen auf mittlerer Höhe erst das
Sheet – jetzt hat die Liste Vorrang (`presentationContentInteraction(.scrolls)`).
(3) Die Lang-Druck-Hervorhebung der Zeilen konkurrierte mit Lang-Druck zum
Umsortieren – entfernt. UI-Test `test3LongQueue`: 60 Platzhalter-Songs,
bis zum Ende und zurück scrollen, Wischen zum Entfernen, Umsortieren.

## E Player-Hintergrund = nur Farbverlauf
- iPad: `CanvasColorSampler` spielt den Canvas-Clip unsichtbar (stumm, ohne
  Layer) und quantisiert jede Sekunde ein 24×24-Bild in vier Farben; der
  Mesh-Verlauf blendet weich dorthin. Ohne Canvas fließen die Cover-Farben.
  Pausiert mit der Musik, wenn der Player nicht sichtbar ist und im
  Stromsparmodus. Gilt für alle Player-Stile (Editorial/Immersiv jetzt auch
  auf dem Verlauf) und hinter den Lyrics. Einstellung: Canvas / Cover / statisch.
- Android: Farb-Zeitleiste pro Canvas-Clip (8 Bilder à 24×24, einmal
  dekodiert), im Takt des Clips abgespielt; ersetzt ArchiveTunes
  Hintergrundstile im Player und Lyrics-Standard.
- Messung auf dem Pixel (Bildrate/CPU per adb): folgt mit dem nächsten Build.

## F Lyrics
- Blur nur nach Abstand zur aktiven Zeile (symmetrisch, ab 4 konstant). Die
  alte Grenze „mehr als 10 Zeilen → scharf“ machte im Hochformat das untere
  Viertel wieder scharf. Android hatte keine Grenze, aber stärkere Werte –
  jetzt dieselben wie das iPad.
- Tempo-Prüfung: Die Länge kam beim Laden der Lyrics oft noch nicht aus dem
  Player → „Songlänge unbekannt“. Jetzt Länge aus Queue/Metadaten und neue
  Prüfung, sobald der Player die Länge kennt.
- UI-Test `test4LyricsDepth` mit 48 Platzhalterzeilen (Hoch/Quer/Hoch).
