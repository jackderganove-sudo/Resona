# Testbericht – Simulator-Tests (Runde 4)

Automatisierte Tests im iPad-Simulator über GitHub Actions
(`.github/workflows/test.yml`, `scripts/simulator_tests.sh`). Läuft bei jedem
Push auf `main` (und `wip`) sowie manuell; erzeugt **kein** Release und nutzt
**keine** Secrets oder Zugangsdaten (kein YouTube-Login, keine Last.fm-Schlüssel).

## Umgebung

| | |
|---|---|
| Gerät | iPad Pro 13-inch (M5), Simulator |
| System | iPadOS 26.5 (Simulator-Runtime des Runners; Deployment-Target der App: 18.0) |
| Build | Debug, arm64-Simulator, Xcode latest-stable auf `macos-latest` |
| Sprache | Deutsch (`-AppleLanguages (de)`) |
| Audio | mpv mit `ao=null` (keine Audioausgabe im CI-Simulator, Wiedergabe läuft in Echtzeit) |

**Was im Simulator wirklich läuft:** die komplette App inklusive mpv, ffmpeg-kit
(eigener arm64-Simulator-Slice, gecacht), GRDB-Datenbank, Netzwerk (Suche,
Vorschläge, Cover, Künstler-/Album-/Playlist-Seiten, Songtext-Anbieter), Lyrics-
Darstellung und Crossfade-Engine. Keine Fakes für Frameworks.

**Was ersetzt wird:**
- *YouTube-Streams.* YouTube beantwortet Anfragen von GitHub-Runner-IPs mit
  „Sign in to confirm you’re not a bot“ (im Konsolenlog nachgewiesen). Im UI-Test
  (`-ResonaUITest`, nur DEBUG) spielt deshalb jeder Song einen lokal erzeugten
  Testton. Titel, Künstler, Cover, Farben, Länge aus den Metadaten und Songtexte
  bleiben echt. Release-Builds enthalten diesen Pfad nicht.
- *Crossfade-Messung.* Es gibt keinen Audioausgang, den man aufnehmen könnte.
  Gemessen wird deshalb der echte Zustand beider mpv-Instanzen alle 10 ms
  (Position, Lautstärke, Pause/Leerlauf). Daraus wird der Mix rekonstruiert:
  bekannte Sinustöne, mpv-Lautstärke wirkt kubisch.

## Ergebnisse

### Unit-Tests – alle bestanden (Stand Runde 6)
| Bereich | Tests |
|---|---|
| LyricsAligner (KI-Sync) | exakte Erkennung, fehlende, zusätzliche und falsch geschriebene Wörter, Normalisierung, nichts erkannt, fremdes Audio (< 30 %), Ausreißer-Zeiten, unsortierte Erkennung, Sing-Schreibweisen/Zahlen, längste nicht fallende Folge, monotone Zeiten |
| KI-Sync Ende-zu-Ende | ≈ 3 min synthetische Sprache (macOS `say`, generierte Sätze): ffmpeg-Umwandlung in voller Länge, Whisper über alle 30-s-Fenster (≈ 90 Wörter je Fenster), 99 % zugeordnet |
| Slowed/Sped-up | Titel-Erkennung, Skalierung ×1,15/×0,85 inkl. Wortzeiten, Längen-Mismatch ohne „slowed“ im Titel, < 2 % unverändert, unplausibler Faktor bzw. fehlende Originallänge → Klartext, Tempo-Diagnose (angewendet / gleiche Länge / unplausibel / Länge unbekannt), Text-Abgleich für die Originalsuche |
| „Alle Zeiten gleich“ | alle `[00:00.00]` bzw. alle gleich → Klartext; echte Zeiten bleiben |
| Zeilen-IDs / Scroll | eindeutige IDs bei Refrains, identisch nach Neuladen und Skalierung; aktive Zeile monoton, genau ein Wechsel pro Zeile; Scroller retargetet nur bei Zeilenwechsel (nicht bei Messrauschen < 0,5 pt), nie rückwärts; ganze Pixel |
| Heatmap | aktuelles und altes Antwortformat (gespeicherte Beispiel-JSONs), keine Heatmap, Drop-Erkennung ohne Anfangs-/End-Spitzen, nie negativ |
| Playlist-Werkzeuge | automatische Playlists aus Test-Verlauf (Monat, insgesamt, lange nicht gehört, neu entdeckt), Duplikate, Aufteilen (Künstler, Album, max. 7 Gruppen + „Mehr“) |
| Last.fm-Tags | Antwort parsen, Fehlerantwort, Tag → Gruppe, Phonk vor Hip-Hop, Stimmung vor schwachem Genre |
| Crossfade-Mathematik | Kubikwurzel kehrt mpvs Lautstärkekurve um; Leistungssumme über den ganzen Fade = 1 |

Alle Testtexte sind ausgedachte Platzhalter, keine echten Songtexte.

### Crossfade – 5/5 bestanden (nach Fix)

| Fall | Überlappung | Leistung min/max | Lücken | Ergebnis |
|---|---|---|---|---|
| 3 s | 2,95 s | 0,0 / 0,0 dB | keine | ✅ |
| 10 s | 9,87 s | 0,0 / 0,0 dB | keine | ✅ |
| Skip während des Fades | 1,36 s bis zum Skip | 0,0 / 0,0 dB | ≤ 50 ms beim Laden des nächsten Songs | ✅ alter + eingeblendeter Song sofort weg |
| Pause während des Fades | 1,36 s bis zur Pause | 0,0 / 0,0 dB | nur die Pause | ✅ Fade bricht ab, nach Fortsetzen neuer Song mit voller Lautstärke |
| Crossfade aus | – | – | 150 ms beim Songwechsel | ✅ keine Überlappung |

![Crossfade 3 s](test-report/crossfade-fade3.png)
![Crossfade 10 s](test-report/crossfade-fade10.png)
![Skip während des Fades](test-report/crossfade-skip.png)
![Pause während des Fades](test-report/crossfade-pause.png)
![Crossfade aus](test-report/crossfade-off.png)

Je Diagramm: Amplitude je Song und Leistungssumme, Goertzel-Tonstärke je Frequenz,
RMS in dBFS, Position je Song.

## Gefunden und behoben

1. **Crossfade nicht Equal Power – Delle von −6 dB** (Messung, erster CI-Lauf:
   Leistung min −6,02 dB bei 3 s und 10 s). `CrossfadeEngine` setzte sin/cos
   linear auf mpvs `volume`; mpv wendet die Software-Lautstärke aber kubisch an.
   In der Fade-Mitte lagen beide Songs deshalb bei 0,35 statt 0,71 Amplitude.
   Fix: Lautstärke = Kubikwurzel der gewünschten Amplitude
   (`CrossfadeEngine.volumeFactor`). Danach gemessen 0,0 dB über den ganzen Fade;
   mit Unit-Test abgesichert.
2. **Equalizer: Preset-Chips abgeschnitten.** Die horizontale Leiste endete
   hart am Rand der 720-pt-Spalte („Höhen reduzieren“ halb sichtbar). Die Chips
   brechen jetzt um.
3. **Testinfrastruktur:**
   - Testdaten der Unit-Tests tauchten in „Weiterhören“ und im Verlauf auf → werden jetzt nach jedem Test gelöscht.
   - Screenshots im Querformat lagen gedreht im Artefakt → werden beim Export aufgerichtet.
   - Dateinamen automatischer Anhänge brachen den Artefakt-Upload → bereinigt.
   - Fehlende IDs für Zurück- und Schließen-Buttons ergänzt.

## Gefunden, nicht geändert

- **Duplikate mit gleicher Video-ID:** `playlist_song_map` hat einen
  UNIQUE-Schlüssel (playlist_id, song_id). Dieselbe Video-ID kann lokal nur einmal
  pro Playlist gespeichert werden. „Duplikate finden“ erkennt deshalb nur gleiche
  Titel + Künstler mit anderer Video-ID (Re-Uploads), nicht doppelt eingefügte
  identische Songs. Eine Behebung bräuchte eine Datenbank-Migration und eine
  Anpassung der Sync-Logik – bewusst nicht in dieser Runde.
- **Kurzer Stillstand des Main-Threads beim Songwechsel:** 60–125 ms ohne
  Messwert in jedem Fall, auch ohne Crossfade. Das Audio läuft durch, möglicherweise
  ruckelt die UI dabei ein Frame. Im Simulator nicht weiter eingrenzbar.
- **Lücke bei „Crossfade aus“:** 150 ms Stille zwischen zwei lokalen Dateien
  (normaler mpv-Dateiwechsel im Simulator). Am Gerät mit Gapless-Album-Übergängen
  nachprüfen.

## UI-Rundgang (Hoch- und Querformat) – beide Tests bestanden

| | |
|---|---|
| ![Start](test-report/hoch-start.jpg) | ![Suche](test-report/hoch-suche.jpg) |
| ![Player](test-report/hoch-player.jpg) | ![Warteschlange](test-report/hoch-warteschlange.jpg) |
| ![Künstler](test-report/hoch-kuenstler.jpg) | ![Einstellungen](test-report/hoch-einstellungen.jpg) |
| ![Equalizer](test-report/hoch-equalizer.jpg) | |

| | |
|---|---|
| ![Player quer](test-report/quer-player.jpg) | ![Bibliothek quer](test-report/quer-bibliothek.jpg) |
| ![Album quer](test-report/quer-album.jpg) | ![Equalizer quer](test-report/quer-equalizer.jpg) |


Start, alle Tabs, Suche „numb“ → Live-Vorschläge → Song abspielen, Mini-Player,
Player, Songtext (im Querformat Vollbild-Songtext), Warteschlange, Player-Menü,
Sleep-Timer, Künstler-, Album- und Playlist-Seite aus der Suche, alle
Einstellungsseiten inkl. Equalizer. Nach jedem Schritt ein Screenshot
(`XCTAttachment`, `.keepAlways`). Dazu ein Video des Laufs, xcresult und
Konsolenlog als Artefakte.

Geprüft auf abgeschnittene Texte, falsche Farben, Überlappungen, leere
Flächen, englische Texte und einen Mini-Player, der Inhalte verdeckt. Gefunden
und behoben:
- Equalizer-Presets abgeschnitten (umbrechen jetzt);
- im Querformat-Seitenpanel abgeschnittene Kachel-Beschriftungen des
  Player-Menüs („Zur Playlist hinzuf…“) und Warteschlangen-Chips
  („Warteschla…“) – jetzt zweizeilig bzw. untereinander.

Alle Texte deutsch, außer Eigennamen (Anbieter, „Songs“, „Canvas“).

Test-Infrastruktur, die nötig war, um den Rundgang stabil zu bekommen:
- kein Update-Banner im Test;
- Lyrics per Wischen (Koordinaten) schließen, weil Element-Abfragen in der
  animierten Lyrics-Ansicht sehr langsam sind;
- Player im Querformat per Wischgeste einklappen;
- Sleep-Timer über „Abbrechen“ schließen.

Screenshots mit Songtexten bleiben bewusst nur im CI-Artefakt und werden hier
nicht eingebunden.

## Am Gerät gefunden und behoben (Runden 5–6)

- **Crossfade:**
  - nächster Song stumm bzw. „Plopp“: mpvs iOS-Audioausgabe deaktiviert beim
    Beenden die AVAudioSession;
  - kurze Aussetzer: Session-Modus wechselte zwischen mpv (MoviePlayback) und
    App (Default).
  - Jetzt: Session identisch zu mpv, festes Ausgabeformat, die ausgeblendete
    Instanz wird geparkt statt gestoppt, die zweite Instanz wird vorab
    aufgewärmt. Im Simulator weiterhin 5/5, am Gerät erneut zu prüfen.
- **KI-Sync:**
  - ffmpeg ohne CA-Datei (Streams);
  - WhisperKit übersprang „stille“ 30-s-Fenster (Gesang über Musik);
  - Zeiten nicht monoton (springende Zeilen).
- **Slowed:**
  - Originallänge nur über den Künstler gesucht (Re-Uploads laufen unter dem
    Kanal);
  - von Hand gewählte Lyrics wurden nie skaliert;
  - Hinweis vertauscht;
  - jetzt mit Diagnose unter „Songtext von …“ und Gegenprüfung über die
    Audiospur auf YouTube Music.

## Nur am echten Gerät prüfbar

- Echte Audioausgabe: Klang, Crossfade hörbar, Equalizer, Lautstärkenormalisierung, AirPlay/Bluetooth-Latenz.
- YouTube-Streams selbst (im CI wegen Bot-Prüfung durch Testton ersetzt).
- Sperrbildschirm, Kontrollzentrum, Hintergrundwiedergabe, Unterbrechungen (Anrufe, Siri).
- Sleep-Timer mit Ausblenden über echte Zeiträume, Hintergrund-Aktualisierung.
- KI-Sync (WhisperKit braucht Neural Engine und lädt ein Modell; nur der Abgleich ist unit-getestet).
- Last.fm-Genres mit echtem Schlüssel (im CI ohne Schlüssel – nur Parsing und Zuordnung getestet).
- Performance und Flüssigkeit der Lyrics-Animation bei 120 Hz (ProMotion).
- Installation per ESign und Update über die App-Quelle.

## Ausführen

```bash
gh workflow run test.yml --ref main
```

Artefakte: `test-output-<n>` (Screenshots, Crossfade-Diagramme/WAVs/Rohdaten,
Logs), `ui-video-<n>` und `xcresult-<n>`.
