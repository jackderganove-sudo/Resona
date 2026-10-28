# Runde 4 – Simulator-Tests, Screenshots, Crossfade-Messung, Last.fm-Genres

Wiederaufnahme-Stelle für diese selbstständige Runde.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Simulator-Build + Test-Workflow (test.yml) | offen |
| 2 | UI-Tests mit Screenshots + Video + Logs | offen |
| 3 | Unit-Tests (Aligner, Slowed, Heatmap, Playlists, Scroll) | offen |
| 4 | Crossfade messbar machen (Mix-Rekonstruktion, RMS, Goertzel, PNG) | offen |
| 5 | Screenshots prüfen, Fehler fixen, docs/test-report.md | offen |
| 6 | Last.fm-Tags fürs Aufteilen nach Genre/Stimmung | offen |

## Entscheidungen
- Test-Targets werden nur im CI-Lauf per Ruby (`xcodeproj`-Gem) angelegt
  (scripts/add_test_targets.rb) → das Release-Projekt bleibt unverändert.
- Testquellen liegen unter Tests/ (außerhalb von Trop/, damit sie nicht in die App
  wandern – Trop/ ist ein synchronisierter Ordner).
- Simulator: mpv mit `ao=null` im Testmodus (Launch-Argument `-ResonaUITest`),
  weil CI-Simulatoren keine verlässliche Audioausgabe haben; die Wiedergabe-Logik
  (Zeit, Queue, Lyrics-Uhr) läuft trotzdem echt in Echtzeit.
- Crossfade-Messung: DEBUG-Testmodus in der App (keine Release-Auswirkung).

## Offene Fragen

## Bekannte Einschränkungen
