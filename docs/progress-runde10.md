# Runde 10 – ArchiveTune-Canary-Features (iPad) + Resona für Android

Quelle: öffentlicher Quellcode `github.com/rukamori/ArchiveTune`, Branch `dev`
(Stand 2026-11-02), verglichen mit `v14.1.0` (866 Commits). Übernahme mit
Erlaubnis des Entwicklers; beide GPLv3. Credits: ArchiveTune (rukamori) und
Mitwirkende in „Über“ und `docs/CREDITS.md`.

Grundsatz: Resonas eigener Stil und eigene Features haben Vorrang (Frosted
Glass, Cover-Theming, M3-Dialoge, KI-Sync/-Kalibrierung, Lyrics-Anbieter, Zum
Drop, Crossfade, Seitenleiste …). Neue Funktionen werden in diesen Stil
integriert; wo Resona schon eine bessere Lösung hat, wird nur Fehlendes ergänzt.

Nicht übertragbar (nur Android): Android Auto/AAOS, Always-on-Display,
Widgets, Google-Drive-Backup, Chromecast, LeakCanary, natives Modul-/
Extension-System, Listen Together (Server von ArchiveTune).

## Teil A – Reihenfolge (je Gruppe ein Zwischenrelease)

| Schritt | Gruppe | Inhalt | Aufwand | Status |
|---|---|---|---|---|
| A1 | 7 Lyrics | Binimum-Anbieter, Enhanced-LRC-Wortzeiten (abgleichen), Übersetzungsquelle erkennen, Versatz ±5000 ms, OpenRouter-Übersetzung (eigener Key, Keychain, eigener Prompt) | mittel | Release v0.8.11 |
| A2 | 6 Wiedergabe | Vorladen des nächsten Songs (Schalter), Wiedergabe vor Downloads, Download aus vollständigem Cache, „Audio-Unterbrechungen verhindern“, SponsorBlock im Player, Fehlerhinweise | mittel | erledigt, im Test |
| A3 | 3 Warteschlange | Redesign, YouTube-Empfehlungs-Chips, „Als Nächstes spielen“ | mittel | erledigt, im Test |
| A4 | 8 App | „Was ist neu“ aus Release-Notes, Onboarding (optionaler Login), Update-Ablauf, Bewertungs-/Support-Dialog nur wenn sinnvoll | mittel | erledigt, im Test |
| A5 | 1 Player & Design | V10 Editorial Player, Acryl-/Blur-Stile, Immersive Player mit Canvas (Spotify + Tidal, Frame-Capture, rotierendes Artwork), Form-Morphing Mini-Player ↔ Navigationsleiste, Künstler-Auswahl, Codec-Anzeige abgleichen, Artwork-Platzhalter | groß | offen |
| A6 | 2 Startseite | Community, Featured-Playlist-Karten, Quick-Picks-Hero-Karussell + abwechslungsreichere Quick Picks, gestaffelte Genre-Kacheln mit eigenen Formen, Genre-Entdeckung, Browse-Header | groß | offen |
| A7 | 4 Statistiken | Year in Music / Recap-Stories (Animationen, Artwork-Wall, Teilen als Bild), Hör-Statistiken + Zurücksetzen | groß | offen |
| A8 | 5 Bibliothek | Podcasts, „Gespeicherte Titel“, Tags/Sortierung, Leer-Zustände, CSV-Export, Cover-Aktualisierung, lokale Musik (Dateien-App, Metadaten) | sehr groß | offen |

Teil B startet, sobald Teil A auf Gerätetests wartet, und läuft dann
abwechselnd mit Teil A weiter.

## Teil B – Resona für Android (docs/progress-android.md im Android-Repo)

1. Fork `rukamori/ArchiveTune` → `jackderganove-sudo/Resona-Android` (Basis `dev`).
2. Branding: Name „Resona“, adaptives Resona-Icon, applicationId
   `dev.jackderganove.resona`, eigene Update-Quelle (GitHub-Releases),
   Telemetrie/Crash-Reporting/Update-Server von ArchiveTune aus bzw. auf eigene.
3. CI: GitHub Actions (ubuntu), signierte Release-APKs (arm64 + universal) bei
   jedem Push auf main, Release-Notes aus Commits. Keystore neu, nicht im Repo,
   als Secret; lokaler Pfad wird mitgeteilt. README: Obtainium.
4. Resona-Extras portieren (Logik aus dem iPad-Code): Frosted-Glass-Komponente,
   zusätzliche Lyrics-Anbieter + versionsbewusste Auswahl/Trefferliste,
   KI-Sync/-Kalibrierung (whisper.cpp), Slowed-Erkennung, Selbst-Sync, Zum Drop,
   Crossfade, Sleep-Timer-Fade, Playlist-Werkzeuge, Smart Downloads,
   Batch-Auswahl, Übersetzung.
5. Nach dem ersten Release: ntfy „Resona Android vX ist da“ mit APK-Link.

## Entscheidungen
- ArchiveTune-Code wird gelesen, nicht kopiert: das iPad nutzt Swift/SwiftUI,
  übernommen werden Abläufe, Endpunkte und Parameter.
- Zwischenreleases über den bestehenden Weg (wip → Build + Unit-Tests →
  main → Release → ntfy).

## Umsetzung Teil A

### A1 Lyrics
- Binimum (TTML, oft wortgenau) als Anbieter; Enhanced-LRC mit mehreren
  Zeitstempeln pro Zeile verschiebt die Wortzeiten mit.
- Versatz pro Song ±5 s; KI-Übersetzung über OpenRouter (eigener Key in der
  Keychain, Modell, eigener Prompt, Test-Knopf), Fallback auf Apple; die
  Quelle der Übersetzung steht unter dem Anbieter.

### A2 Wiedergabe
- Stream-Auflösung der Wiedergabe hat Vorrang vor Downloads (Downloads warten
  bis zu 8 s); „Nächsten Song vorladen“ als Schalter.
- „Audio-Unterbrechungen verhindern“: auf iOS als „Mit anderen Apps mischen“
  (aus = Standard; an = andere Apps unterbrechen Resona nicht, dafür fehlt
  die Sperrbildschirm-Steuerung teilweise). In ArchiveTune wieder entfernt.
- SponsorBlock: Modus „Überspringen-Knopf statt automatisch“, pro Song
  abschaltbar im Player-Menü.
- Fehler-Banner mit Ursache (Bot-Check, nicht verfügbar, Altersgrenze, Netz)
  und kopierbaren Details.
- Nicht übertragbar: „Download aus dem vollständigen Wiedergabe-Cache“ – mpv
  hält den Cache nur im Speicher, ein Abgreifen wäre unzuverlässig.

### A3 Warteschlange
- YouTube-Empfehlungs-Chips (Beliebt, Neu entdecken, Raritäten, Genres …)
  über dem Verlauf; ein Chip ersetzt die kommenden Songs, aktueller Song und
  Verlauf bleiben. Funktioniert ohne Login.
- „Als Nächstes spielen“ verschiebt den Song (Wischen nach rechts oder
  Zeilenmenü) statt eine Kopie einzufügen.
- Mehrfachauswahl: als Nächstes spielen / entfernen; neuer Leer-Zustand.

### A4 App
- „Neu in Resona“ nach einem Update aus den GitHub-Release-Notes, sortiert in
  Neu / Verbessert / Behoben, alle Versionen seit der zuletzt gesehenen; auch
  unter Einstellungen → Über. Das Update-Banner zeigt dieselbe Sortierung.
- Onboarding beim allerersten Start mit optionaler Anmeldung („Ohne Konto
  fortfahren“ gleichwertig). Bestehende Installationen sehen es nicht.
- Bewertungsdialog bewusst nicht übernommen: Resona wird per ESign geladen,
  es gibt keinen Store, in dem man bewerten könnte.

### A5 Player & Design
- Neue Player-Stile unter Darstellung → Player-Stil:
  - **Editorial** (nach ArchiveTunes V10): flache Fläche in der Cover-Farbe,
    das Cover als „Die-Cut“, das vom Squircle (Pause) zur Wellenscheibe
    (Wiedergabe) morpht und sich langsam dreht; große kursive Serifen-Zeile,
    Bento-Steuerung (Wort-Pille PLAY/PAUSE, runde Weiter/Zurück-Knöpfe,
    Fortschritt in der Akzentfarbe). Tippen aufs Cover = Play/Pause, Wischen
    = Titel wechseln.
  - **Immersiv**: der Canvas füllt den Bildschirm; ohne Canvas unscharfes
    Cover mit sich drehender Cover-Scheibe; Steuerung auf einem Verlauf unten.
  - Schalter „Cover beim Abspielen drehen“ (steht, sobald ein Canvas läuft).
- Hintergrund-Stil „Unscharfes Cover“ zusätzlich zu Album-Art und Einfarbig.
- Künstler-Auswahl: bei mehreren Künstlern fragt der Player, welcher
  geöffnet werden soll.
- Codec-Anzeige: „Opus · WEBM • 132 kbps • 48 kHz • 3,4 MB“ statt nur Container.
- Artwork-Platzhalter: Verlauf in den Theme-Farben mit dem Anfangsbuchstaben.
- Frame-Capture gab es schon (Canvas-Farben fürs Theme).
- Nicht übernommen:
  - **Tidal-Canvas**: ArchiveTune nutzt dafür einen im Tidal-Webplayer
    eingebetteten fremden Zugangstoken; das übernehme ich nicht. Spotify-Canvas
    (mit eigenem Login) bleibt.
  - **Form-Morphing Mini-Player ↔ Navigationsleiste**: auf dem iPad sitzt der
    Mini-Player nicht in einer Android-Bottom-Navigation; Resona hat stattdessen
    das Cover-Morphing in die Lyrics-Ansicht.
  - Acryl-Stile: Resonas Milchglas deckt das bereits ab.

### A6 Startseite
- Genre-Kacheln (Entdecken und Genre-Seiten) gestaffelt wie ein Mauerwerk,
  jede mit eigener Form (rund, Bogen, Pille, Blatt, Ticket) und Höhe – pro
  Genre immer gleich.
- „Genres entdecken“ auf der Startseite nach den ersten Regalen: täglich
  wechselnde Auswahl aus YouTube Musics Stimmungen & Genres.
- Genre-Seiten mit Farb-Header (Browse-Header) statt nur großem Titel.
- Featured-Playlist-Karten: das erste Playlist-Regal und „Aus der Community“
  als große Karten mit unscharfem Cover, Cover, Titel, Autor und Play.
- Quick Picks abwechslungsreicher: höchstens zwei Songs pro Künstler am
  Anfang, der Rest dahinter. Das Hero-Karussell gab es schon.
- Community: unverändert (braucht wie bei ArchiveTune ein Konto).
