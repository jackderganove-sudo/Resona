# Runde 4 – Simulator-Tests, Screenshots, Crossfade-Messung, Last.fm-Genres

Wiederaufnahme-Stelle für diese selbstständige Runde.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Simulator-Build + Test-Workflow (test.yml) | gebaut, erster CI-Lauf auf `wip` läuft |
| 2 | UI-Tests mit Screenshots + Video + Logs | geschrieben (Hoch + Quer), CI-Lauf ausstehend |
| 3 | Unit-Tests (Aligner, Slowed, Heatmap, Playlists, Scroll, Last.fm-Tags) | geschrieben, CI-Lauf ausstehend |
| 4 | Crossfade messbar machen (Mix-Rekonstruktion, RMS, Goertzel, PNG) | Harness + Auswertung fertig, lokal mit simulierten Daten geprüft |
| 5 | Screenshots prüfen, Fehler fixen, docs/test-report.md | offen (nach CI-Lauf) |
| 6 | Last.fm-Tags fürs Aufteilen nach Genre/Stimmung | erledigt (1248e6a) |

## Entscheidungen
- Test-Targets werden nur im CI-Lauf per Ruby (`xcodeproj`-Gem) angelegt
  (scripts/add_test_targets.rb) → das Release-Projekt bleibt unverändert.
- Testquellen liegen unter Tests/ (außerhalb von Trop/, damit sie nicht in die App
  wandern – Trop/ ist ein synchronisierter Ordner).
- Simulator: mpv mit `ao=null` im Testmodus (Launch-Argument `-ResonaUITest`),
  weil CI-Simulatoren keine verlässliche Audioausgabe haben; die Wiedergabe-Logik
  (Zeit, Queue, Lyrics-Uhr) läuft trotzdem echt in Echtzeit.
- Simulator-Slices: ffmpeg-kit wird schon mit arm64-Simulator-Slice gebaut und
  gecacht (gleicher Cache wie der Release-Build); MPVKit/GRDB/Nuke/WhisperKit sind
  SPM und bringen Simulator-Varianten mit → keine Fakes nötig.
- Crossfade-Messung: DEBUG-Testmodus in der App (keine Release-Auswirkung).
  Testtöne 60 s statt 40 s: die Engine blendet nur bei Songlänge > 2 × Fade + 20 s
  über (beim 10-s-Fall wären 40 s genau die Grenze).
- Gemessen wird der echte Zustand beider mpv-Instanzen alle 10 ms (Position,
  Lautstärke, Pause/Leerlauf). Der hörbare Mix wird daraus rekonstruiert (bekannte
  Sinustöne, mpv-Lautstärke wirkt kubisch: Amplitude = (vol/100)³) und als WAV,
  RMS-/Goertzel-Kurven und PNG ausgegeben.
- Keine echten Songtexte in Tests, Fixtures, Logs, Doku – nur ausgedachte
  Platzhalter. Lyrics-Screenshots bleiben im CI-Artefakt, nicht in docs/.
- Testbarkeit: reine Funktionen herausgezogen, ohne Verhalten zu ändern
  (`LyricsService.tempoAdjusted/needsOriginalDuration`, `LyricsTiming.activeIndex`,
  `PlaylistTools.splitGroups`).
- Last.fm-Genre: `track.getTopTags`, bei wenigen Tags ergänzt um
  `artist.getTopTags` (nur API-Key, kein Login, keine Signatur), 30 Tage auf der
  Platte gecacht, 4 parallele Anfragen. Zuordnung über Schlüsselwörter (exakt, dann
  Wortende), Phonk gewinnt bei klarem Tag gegen Hip-Hop, Stimmung (Chill/Traurig)
  leicht bevorzugt. Option „Genre/Stimmung“ erscheint nur mit API-Key oder
  verbundenem Last.fm.

## Befunde
- Vorab aus dem Code (Messung bestätigt/widerlegt es): `CrossfadeEngine` setzt
  sin/cos linear auf mpvs `volume`-Eigenschaft. mpv wendet die Software-Lautstärke
  kubisch an → in der Fade-Mitte nur 0,35 statt 0,71 Amplitude je Spur, also eine
  Leistungsdelle von etwa −6 dB statt Equal Power.

## Offene Fragen

## Bekannte Einschränkungen
- Die Simulator-Audiowiedergabe ist stumm (ao=null); echte Klangqualität,
  AirPlay, Bluetooth-Latenz und Sperrbildschirm sind nur am Gerät prüfbar.
