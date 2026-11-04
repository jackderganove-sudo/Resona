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
| E | Player-Hintergrund nur Farbverlauf (Canvas-Farben unsichtbar mitlesen / Cover / statisch), beide Apps | iPad v0.8.17, Android v1.0.8 |
| F | Lyrics-Tiefe im iPad-Hochformat (Blur nur nach Abstand), Tempo-Hinweis „Songlänge unbekannt“ | iPad v0.8.17 |
| G1 | iPad: Immersiv-Layout nach Test von v0.8.16 (Scheibe abgeschnitten, Kopf überlappt, Leerraum, Springen, harter Streifen) | Release v0.8.17; `test5ImmersiveLayout` grün (hoch/quer: Scheibe ganz sichtbar, bleibt beim Aus-/Einblenden an ihrem Platz) |
| G2 | iPad: Drag-Vorschau der Warteschlange (eckig, zu breit, durchscheinend) + Android geprüft | Release v0.8.17; `test3LongQueue` grün (scrollen, wischen, Griff) |
| D1 | KI-Sync + Kalibrierung auf Android (whisper.cpp) | Android v1.0.8/v1.0.9; auf dem Pixel: 497 Wörter, 2,4-fache Songlänge |
| D2 | Glas auf Android | Android v1.0.8; Sheet, Dialoge, Navigation auf dem Pixel gesehen |
| H | Android: Onboarding-Crash, Abspielen aus der Suche, Lyrics-Ruckeln (0,00 % Janky mit Canvas, dafür ohne Zeilen-Blur) | Android v1.0.8, `docs/progress-android.md` |

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
- Messung auf dem Pixel 11 Pro (wip-Build, `dumpsys gfxinfo` über 10 s, `top`):
  spielend 688 Bilder/10 s (≈ 69 fps, 0 % Ruckler, p90 10 ms), CPU ≈ 50–60 %
  eines Kerns inkl. Lauftext und Fortschritt; pausiert 0 Bilder, CPU ≈ 6 % –
  der Verlauf steht mit der Musik still.

## F Lyrics
- Blur nur nach Abstand zur aktiven Zeile (symmetrisch, ab 4 konstant). Die
  alte Grenze „mehr als 10 Zeilen → scharf“ machte im Hochformat das untere
  Viertel wieder scharf. Android hatte keine Grenze, aber stärkere Werte –
  jetzt dieselben wie das iPad.
- Tempo-Prüfung: Die Länge kam beim Laden der Lyrics oft noch nicht aus dem
  Player → „Songlänge unbekannt“. Jetzt Länge aus Queue/Metadaten und neue
  Prüfung, sobald der Player die Länge kennt.
- UI-Test `test4LyricsDepth` mit 48 Platzhalterzeilen (Hoch/Quer/Hoch).

## G1 Immersiv-Layout (Test von v0.8.16)
- **Springen / harter Streifen / Steuerung fällt aus dem Bild** – eine
  Ursache: Die ganze Fläche hatte neben Tippen auch die Cover-Wischgeste.
  Gewann sie gegen die Herunterzieh-Geste zum Einklappen, wurde diese ohne
  `onEnded` abgebrochen und der Player blieb um den Zieh-Versatz nach unten
  verschoben. Dabei rutschten Warteschlange/Songtext aus dem Bild, und oben
  wurde ein harter Streifen des Hintergrunds frei. Jetzt meldet ein
  `@GestureState` auch den Abbruch, der Player springt zurück; die
  Wischgeste liegt nur noch auf der Scheibe.
- **Feste Geometrie** (`ImmersiveLayoutMetrics`): Kopf („Läuft gerade“,
  Album) mit eigener Höhe oben, darunter ein vertikal zentrierter Block –
  Scheibe so groß wie der Platz erlaubt, Titel und Steuerung darunter.
  Steuerung und Kopf blenden nur aus und behalten ihren Platz, die Scheibe
  bewegt sich also nie. In kleinen Fenstern fällt zuerst die
  Schalterreihe weg, dann der Kopf, dann die Scheibe – nichts verlässt den
  sichtbaren Bereich.
- Hintergrund: der Farbverlauf wie in allen Stilen (seit E), kein Cover-/
  Canvas-Hintergrund mehr.
- Tests: `ImmersiveLayoutTests` rechnet 17 Größen durch – 13"/11"/mini hoch
  und quer, Querformat mit Seitenleiste, Split View ⅓/½/⅔, Stage-Manager-
  Fenster – jeweils mit drei Steuerungshöhen. UI-Test
  `test5ImmersiveLayout`: Scheibe ganz sichtbar, Steuerung im Bild und unter
  der Scheibe, Scheibe bleibt beim Aus- und Einblenden an ihrem Platz; hoch
  und quer mit Screenshots. Split View und Stage Manager lassen sich im
  Simulator-Test nicht steuern, sie sind über die Geometrie-Tests abgedeckt.

## G2 Warteschlange: Drag-Vorschau
- Ursache: `List.onMove` hebt eine Momentaufnahme der Zelle an; die Zeilen
  haben einen durchsichtigen Hintergrund, also legte das System seinen
  eigenen eckigen, dunklen Teller darunter (leicht vergrößert, breiter als
  das Panel), und die Zeile darunter schien durch. Das lässt sich bei
  `onMove` nicht zuverlässig gestalten.
- Jetzt eigenes Umsortieren (`QueueReorder`): Die angehobene Zeile ist eine
  undurchsichtige Kopie in der Panel-Farbe (Glas-Tönung ohne Transparenz),
  mit abgerundeten Ecken und leichtem Schatten, auf Panel-Breite. Ihr Platz
  bleibt als Lücke frei, die anderen Zeilen rücken um genau eine Zeile zur
  Seite. Der Griff zieht sofort. (Eine Lang-Druck-Ziehgeste auf der ganzen
  Zeile blockierte im UI-Test das Scrollen und Wischen der Liste – entfernt.)
  VoiceOver hat „Nach oben/unten“-Aktionen. Die
  Einklapp-Geste des Players ist bei offener Seitenleiste ganz aus (sie
  blockierte auch das Wischen zum Entfernen im UI-Test).
- Android auf dem Pixel geprüft (Screenshot mitten im Ziehen): Die Zeile
  war schon undurchsichtig, abgerundet und auf Breite, die anderen weichen
  aus. Ergänzt wurden der leichte Schatten und die Lesbarkeit der aktuellen
  Zeile (weiße Schrift auf hellgrau bei Schwarz-Weiß-Covern).

## Offene UI-Testpunkte (schon vor Runde 11 G rot, nicht durch G verursacht)
- `test1Portrait`: Nach dem Drop-Menü-Teil öffnet das Tippen auf „Songtext“
  den Songtext nicht (Screenshot zeigt weiter den Player); dadurch scheitern
  danach „Schließen-Knopf“ und „nach unten wischen“. In `test4LyricsDepth`
  öffnet dieselbe Pille den Songtext. Vermutung: Ein Kontextmenü des
  Drop-Knopfs (Blitz, Trefferpunkt {-1,-1}) fängt die nächsten Tipps ab.
- `test1Portrait`: „Sprung zum Drop“ prüft den Positionssprung zeitabhängig
  (57 → 55 s, wenn der Drop knapp hinter der Position liegt).
- `test2Landscape`: „Failed to terminate“ – Simulator-Infrastruktur.
