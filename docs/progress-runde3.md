# Runde 3 – Fortschritt

Selbstständige Arbeitsphase. Diese Datei ist die Wiederaufnahme-Stelle: Status,
Entscheidungen, offene Fragen und bekannte Einschränkungen pro Punkt.

> Wichtig: Ich (Claude) habe kein iOS-Gerät und keinen Mac. „Getestet“ heißt hier:
> kompiliert in GitHub Actions + Logik geprüft. Verhalten auf dem Gerät (Audio,
> Timing, Gesten) kann ich nicht selbst hören/sehen – dafür steht am Ende jedes
> Punkts eine konkrete Testliste für dich.

## Plan / Reihenfolge

| # | Punkt | Status |
|---|-------|--------|
| 1 | Crossfade A/B (zwei gleichwertige mpv-Instanzen) | fertig (experimentell, Standard aus) |
| 2 | Sleep-Timer Fade-out | fertig |
| 3 | Tastatur-Kürzel (iPad) | fertig |
| 4 | „Zum Drop springen“ (Most replayed) | fertig |
| 5 | Lyrics-Übersetzung (Translation-Framework) | fertig |
| 6 | Playlist-Werkzeuge | fertig (Aufteilen ohne Genre/Stimmung, s. u.) |
| 7 | Smart Downloads (Standard aus) | fertig |
| 8 | KI-Synchronisation (WhisperKit) | fertig (auf dem Gerät ungetestet, s. u.) |

Push-Rhythmus: nach jedem 2.–3. fertigen Punkt (jeder Push auf main = Release).

## Entscheidungen

### 1. Crossfade
- Neuer Ansatz wie gewünscht: zwei gleichwertige mpv-Instanzen (A/B). Keine
  Übergabe mitten im Song mehr. Kapselung: PlayerController hat weiterhin genau
  EINEN aktiven Handle (`_mpv`), über den alles läuft (Zeit, Dauer, Lyrics-Uhr,
  Sperrbildschirm, Seek, Pause, EQ/Normalisierung, Lautstärke). Der Crossfade
  tauscht nur, welcher Handle aktiv ist – dadurch keine Sonderfälle im Rest der App.
- Beide Handles werden durch dieselbe Funktion erzeugt (`createConfiguredHandle`).
  Der zweite entsteht erst, wenn Crossfade benutzt wird (20 s vor dem Wechsel).
- Event-Schleifen ignorieren Events des inaktiven Handles (sonst würde das
  END_FILE des auslaufenden Songs als Ende des neuen Songs gelten).
- Der nächste Song wird 2,5 s + Fade-Länge vor Songende auf dem anderen Handle
  über den normalen Queue-Weg gestartet (stumm); sobald sein Audio läuft,
  equal-power-Überblendung. Danach wird der alte Handle gestoppt (= neuer Spare).
- „Pausiert vorladen“ habe ich bewusst NICHT gemacht: der normale Startweg
  (Stream auflösen, laden) läuft auf dem neuen Handle, während der alte Song noch
  2,5 s + Fade weiterspielt – das deckt die Ladezeit ab, ohne einen zweiten
  Lade-/Startpfad neben PlaybackManager zu bauen.
- Skip/Pause/Seek während des Fades: alter Handle stoppt sofort, neuer läuft voll.
- Weil ich nicht hören kann, ob es auf dem Gerät sauber klingt: als
  „Überblenden (experimentell)“ markiert, Standard AUS. Mit Crossfade aus läuft
  nichts davon (kein zweiter Handle, Event-Filter ist dann immer „aktiv“).

### 2. Sleep-Timer Fade-out
- Eigener Lautstärkefaktor `sleepFadeGain` (multipliziert mit dem
  Crossfade-Faktor), 10-Hz-Timer, weiche Kurve (smoothstep) bis 0, dann Pause,
  danach Lautstärke zurück. Abbrechen des Timers stellt sofort wieder her.
- Einstellung unter Wiedergabe: Aus / 10 / 30 / 60 s, Standard 30 s.

### 3. Tastatur-Kürzel
- Als SwiftUI-`Commands` an der Szene (Menüs „Wiedergabe“ und „Gehe zu“) → iPadOS
  zeigt sie in der Kürzel-Übersicht (⌘ halten).
- Kürzel ohne Modifier (Leertaste, Pfeile, Esc) sind deaktiviert, solange ein
  Textfeld bearbeitet wird; zusätzlich hat Texteingabe bei UIKit ohnehin Vorrang.
- ⌘L/⌘K öffnen erst den Player, dann Songtext bzw. Warteschlange („pending“-Flags,
  weil der Player beim Auslösen evtl. noch nicht existiert).
- ⌘2 = Suche-Tab (Reihenfolge der Leiste: Start, Suche, Bibliothek).

### 4. Zum Drop springen
- Quelle: `next`-Antwort des WEB-Clients (www.youtube.com) →
  `frameworkUpdates.entityBatchUpdate.mutations[].payload.macroMarkersListEntity`
  (`MARKER_TYPE_HEATMAP`, 100 Segmente mit `intensityScoreNormalized`); älteres
  Format `heatMarkers` wird auch gelesen. Vorab hier per curl geprüft
  (dQw4w9WgXcQ → 100 Segmente). ArchiveTune hat das nicht; Format wie yt-dlp.
- Cache pro Song im Speicher (auch „keine Daten“).
- Drop = Maximum ohne die ersten 6 % (alle starten am Anfang → dort oft 1,0) und
  die letzten 3 %, Start 3 s davor.
- Welle hinter dem Fortschrittsbalken (Cover-Farbe, ~35 → 8 % Deckkraft),
  Blitz-Button neben Shuffle/Wiederholen und im Player-Menü – nur mit Daten.

### 5. Lyrics-Übersetzung
- Sprache per NaturalLanguage (dominante Sprache, Konfidenz > 0,5). Deutsch oder
  Anbieter-Übersetzung vorhanden (≥ 75 % der Zeilen) → keine Übersetzung.
- Übersetzung on-device per `.translationTask` (Translation-Framework). iOS fragt
  beim ersten Mal nach dem Sprachdownload (System-Dialog).
- Einstellung: Aus / Nur auf Wunsch (Standard) / Immer; „Nur auf Wunsch“ =
  Schalter „Ins Deutsche übersetzen“ im Songtext-Menü (pro Song, bis App-Neustart).
- Cache pro Song (Text → Übersetzung) unter Caches/lyrics-translations.
- Anzeige wie Anbieter-Übersetzungen klein/gedimmt unter der Zeile; wird einmal pro
  Song gesetzt → keine Höhenänderung während des Abspielens.

### 6. Playlist-Werkzeuge
- Automatische Playlists aus der lokalen `event`-Tabelle (SQL-Aggregation),
  nutzen die normale Playlist-Seite (Abspielen, Shuffle, Download) und im
  „…“-Menü „Bei YouTube Music speichern“.
- Aufteilen: **YouTube Music liefert pro Song weder Genre noch Stimmung noch Tempo**
  (auch nicht über die Künstlerseite). Statt zu raten, gruppiere ich nach
  vorhandenen Daten: Künstler / Album / Sprache (erkannt am Titel). Kleine Gruppen
  (< 3 Songs) → „Mehr“, max. 8 Gruppen. Gruppen umbenennbar, Songs per Drag & Drop
  oder Kontextmenü verschiebbar, „Erstellen“ legt echte Playlists im Konto an.
- Duplikate: nur für synchronisierte Playlists (braucht die `setVideoId` der
  Einträge aus der lokalen DB). Gleiche Video-ID ODER gleicher Titel + Hauptkünstler;
  der erste Eintrag bleibt.

### 7. Smart Downloads
- Schalter (Standard AUS) + Limit 1/2/5/10 GB (Standard 2 GB) in den
  Download-Einstellungen. Läuft beim Öffnen/Zurückkehren (max. alle 4 h) und direkt
  nach dem Einschalten bzw. Ändern des Limits – immer nur im WLAN.
- Reihenfolge: meistgehört 30 Tage, dann „Gefällt mir“ (neueste zuerst).
  Neue Songs mit 5 MB geschätzt; Smart Downloads über dem Limit bzw. nicht mehr
  gewünscht werden gelöscht (älteste zuerst).
- Abgrenzung manuell/smart zentral im DownloadManager: Nur was ausdrücklich als
  „smart“ in die Warteschlange kommt, wird als Smart Download markiert. JEDER andere
  Download-Weg (Menüs, Playlists/Alben, Auto-Download bei „Gefällt mir“) markiert
  den Song als manuell – auch wenn er vorher smart war. Manuelle Downloads und
  Playlists werden nie automatisch gelöscht.
- Kennzeichnung: kleines Funkel-Symbol in der Download-Liste.

### 8. KI-Synchronisation
- WhisperKit 1.1.x („argmax-oss-swift“, einzige Abhängigkeit swift-argument-parser)
  per SPM. Build in CI grün, IPA nur ~0,7 MB größer (27,9 → 28,6 MB). Modelle
  werden NICHT gebündelt: erster Gebrauch lädt sie (nur im WLAN) nach
  Application Support. „Schnell“ = whisper base (~150 MB), „Genau“ = whisper small
  (~500 MB). Die Größen sind ungefähre Angaben der Modell-Repos.
- Audio: Download-Datei oder aufgelöster Stream → ffmpeg (schon in der App) →
  16 kHz mono WAV (Temp-Datei, wird danach gelöscht). Slowed/Sped-up: direkt auf
  dem Audio der Variante, keine Skalierung.
- Transkription mit Wort-Zeitstempeln, VAD-Chunking, Sprache aus dem Songtext
  (NaturalLanguage) vorgegeben.
- Forced Alignment (eigener `LyricsAligner`): Normalisierung (Groß/Klein, Akzente,
  Satzzeichen, Apostrophe), globale Ausrichtung (Needleman-Wunsch/DTW-artig) mit
  Fuzzy-Ähnlichkeit (Levenshtein ≥ 0,55), zusätzliche erkannte Wörter (Ad-libs)
  sind billig zu überspringen, nicht gefundene Songtext-Wörter werden zwischen den
  Nachbarn nach Wortlänge interpoliert, Zeilenstart = erstes Wort.
  Unter 30 % erkannter Wörter wird abgebrochen (statt Unsinn zu speichern).
- Ergebnis: wort-synchroner eigener Songtext „AI-synced“ (Vorrang vor Anbietern),
  „Zurücksetzen“ im Songtext-Menü, nachkorrigierbar per „Selbst synchronisieren“
  (dabei gehen die Wort-Zeiten verloren, nur Zeilen-Zeiten werden neu gesetzt).
- Läuft weiter, wenn das Sheet geschlossen wird (solange die App offen ist), abbrechbar.

## Offene Fragen an dich

- Aufteilen nach Stimmung/Genre: Soll ich dafür eine externe Quelle nutzen
  (z. B. Last.fm-Tags des Künstlers über deine Last.fm-Anbindung)? Das wäre ein
  zusätzlicher Netzwerkaufruf pro Künstler, daher nicht ungefragt eingebaut.

## Bekannte Einschränkungen

- **Nichts davon konnte ich auf einem Gerät testen** (kein Mac/iPhone). Alles ist in
  GitHub Actions kompiliert; Klang, Timing, Gesten und die KI-Genauigkeit musst du
  prüfen. Die gewünschte Genauigkeits-Doku für die KI-Synchronisation (Pop, Rap,
  Phonk/Brazilian Funk, Slowed) kann ich deshalb nicht liefern – bitte mit den
  Testfällen unten ausprobieren; die App meldet nach jedem Lauf „X % der Wörter
  erkannt“, das ist die Kennzahl.
- Crossfade: experimentell und standardmäßig aus, bis du es auf dem Gerät bestätigst.
- Erwartung KI-Sync (aus Whisper-Erfahrung, nicht gemessen): Pop/klarer Gesang gut;
  Rap schnell, aber meist ausreichend; Phonk/Brazilian Funk mit verzerrten/
  gepitchten Vocals und Portugiesisch eher schwach (kann an der 30-%-Grenze
  scheitern); Slowed meist ok, da auf dem Variant-Audio gearbeitet wird.
- Lyrics-Übersetzung: iOS lädt die Sprachpakete beim ersten Mal (System-Dialog).
- Aufteilen nach Stimmung/Genre: mangels Daten nicht möglich (siehe Frage oben).

## Testliste

### 1. Crossfade (Wiedergabe → Überblenden (experimentell) auf 3 s, dann 10 s)
- Gestreamter Song → nächster gestreamter: hörst du eine Überblendung ohne Ruckler?
- Heruntergeladener Song → nächster: dito.
- Während des Fades „Weiter“ tippen: alter Song muss sofort weg sein.
- Während des Fades pausieren: beide still; Play spielt den neuen Song normal.
- Sperrbildschirm während/nach dem Fade: zeigt den NEUEN Song, Zeit läuft.
- Lyrics nach dem Wechsel: laufen synchron zum neuen Song.
- Crossfade AUS: Songwechsel wie bisher, nichts abgeschnitten.
- Logs (Konsole, Kategorie „Player“, Präfix CROSSFADE) bei Problemen bitte schicken.

### 2. Sleep-Timer
- Sleep-Timer 5 min, Fade 30 s: in den letzten 30 s wird es leiser, dann Pause.
- Danach Play: normale Lautstärke.
- „Songende“ + Fade 10 s: Ausblenden in den letzten 10 s des Songs.
- Timer während des Ausblendens abbrechen: Lautstärke sofort wieder normal.

### 3. Tastatur-Kürzel (iPad mit Tastatur)
- ⌘ gedrückt halten: Übersicht zeigt die Kürzel.
- Leertaste, ←/→ (±10 s), ⌘←/⌘→, ↑/↓ (Lautstärke), ⌘F, ⌘L, ⌘K, ⌘1/2/3, Esc.
- Im Suchfeld tippen: Leertaste/Pfeile müssen normal im Text wirken.

### 4. Zum Drop
- Bekannten Song mit vielen Views abspielen: Welle hinter dem Fortschrittsbalken,
  Blitz-Button neben Shuffle/Wiederholen → springt kurz vor die meistgehörte Stelle.
- Song ohne Daten (z. B. sehr neu/wenig Views): kein Blitz-Button, keine Welle.

### 5. Übersetzung
- Englischen Song öffnen, Songtext-Menü → „Ins Deutsche übersetzen“: iOS fragt
  ggf. nach dem Sprachdownload, danach kleine deutsche Zeilen unter dem Text.
- Einstellung „Immer“: neue fremdsprachige Songs werden automatisch übersetzt.
- Deutscher Song: kein Übersetzen-Effekt.

### 6. Playlist-Werkzeuge
- Bibliothek → „Automatische Playlists“: alle vier öffnen, abspielen, herunterladen,
  „…“ → „Bei YouTube Music speichern“ → Playlist erscheint im Konto.
- Eigene Playlist → „…“ → „Playlist aufteilen“: Gruppierung umschalten, Song in
  andere Gruppe ziehen, Gruppe umbenennen, „Erstellen“.
- Playlist mit doppeltem Song → „Duplikate entfernen“.

### 7. Smart Downloads
- Download-Einstellungen → „Smart Downloads“ an, Limit 1 GB, im WLAN: meistgehörte
  und „Gefällt mir“-Songs werden geladen, Funkel-Symbol in der Download-Liste.
- Limit auf 1 GB senken, wenn schon mehr da ist: älteste Smart Downloads verschwinden,
  selbst geladene Songs/Playlists bleiben.
- Einen Smart-Download-Song manuell herunterladen → Funkel-Symbol verschwindet.

### 8. KI-Synchronisation
- Songtext-Einstellungen → „KI-Modell“: Schnell. Im WLAN einen Song mit nur
  Text/Zeilen-Sync öffnen → Songtext-Menü → „Mit KI synchronisieren“ → Starten.
  Modell-Download mit Fortschritt, dann „Song wird angehört …“, danach „Fertig – X %“.
- Testfälle: 1 englischer Pop-Song, 1 Rap-Song, 1 Phonk/Brazilian-Funk-Song,
  1 Slowed-Song – jeweils X % notieren und prüfen, ob die Wörter mitlaufen.
- Sheet schließen während des Laufs → läuft weiter; „Abbrechen“ stoppt.
- Songtext-Menü → „Zurücksetzen“ → wieder Anbieter-Songtext.
- Im Mobilfunk: Meldung „nur im WLAN“.

