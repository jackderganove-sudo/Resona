# Runde 6 – Gerätebefunde v0.8.6

Funktioniert laut Gerätetest: Übersetzung bricht um, Vollbild-Lyrics,
Wischen zum Schließen, Slowed-Erkennung deutlich besser, KI-Sync deutlich besser.

Reihenfolge: 4 → 3 → 2b → 2a → 1.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Crossfade: kurze Aussetzer (alter Song beim Ausblenden, neuer beim Start) | umgesetzt (5358d3c), Gerätetest nötig |
| 2a | KI-Sync: bei manchen Songs nur 9 % | umgesetzt (f085fa2), Gerätetest + Logs nötig |
| 2b | KI-Lyrics springen (nicht monotone Zeiten) | erledigt (3cf94e0) |
| 3 | Slowed: noch etwas zu langsam; Originallänge genauer, Feinabstimmung ±0,01 | umgesetzt (21535ba) |
| 4 | Meistgehört-Kurve ausschaltbar (Blitz-Menü + Einstellungen, Standard an) | erledigt (28211dc) |

## Ursachen und Fixes

### 1 Crossfade-Aussetzer
mpvs `ao_audiounit` (Quelltext geprüft) setzt bei **jedem** Start einer
Audioausgabe die Session auf Kategorie Playback, Modus **MoviePlayback**,
`setActive(YES)`; beim Beenden ruft es `setActive(NO)` auf. Resona setzte in
`assertAudioSession()` Modus **.default** und Policy **.longFormAudio**. Jeder
Ausgabestart und jedes Fortsetzen schaltete die Session hin und her; jede
Umkonfiguration unterbricht kurz alle laufenden AudioUnits (Aussetzer im alten
Song, als die zweite Ausgabe startete). Das Stoppen der alten Instanz in Runde 5
deaktivierte die Session ganz, das Wiederbeleben (Pause → Play) war der zweite
Aussetzer.
Fix:
- Session-Konfiguration identisch zu mpv; mpvs eigene Aufrufe sind damit
  wirkungslos.
- Festes Ausgabeformat für alle Songs und beide Instanzen (48 kHz, Stereo,
  Float). Mit `gapless-audio` bleibt die Ausgabe über Dateiwechsel offen.
- Die ausgeblendete Instanz wird nie gestoppt: Lautstärke 0, 120 ms auslaufen
  lassen, pausieren, stille Datei laden (`keep-open`) → kein `setActive(NO)`.
- Die zweite Instanz wird beim Anlegen „aufgewärmt“ (stille Datei, pausiert,
  Lautstärke 0).
- Logs mit Zeitstempel: `CROSSFADE t=… start / swap / fading / finished /
  old instance paused + parked / active instance runs`. Wiederbeleben gibt es
  nur noch als Watchdog (Log „stalled → revive“).

### 2a KI-Sync 9 %
- Liefert das kleine Modell < 30 %, wird automatisch das größere versucht
  (Download nur im WLAN); das bessere Ergebnis zählt.
- Aligner toleranter:
  - phonetischer Vergleich für Wörter ab 4 Buchstaben (höchstens 0,9);
  - Sing-Schreibweisen ('cause/cuz → because, til, ya, em, …in → …ing);
  - Ziffern als Zahlwörter;
  - Schwelle 0,5.
- Die Logs je 30-s-Fenster (seit Runde 5) zeigen am Gerät, ob ein Fenster leer
  bleibt.

### 2b Springende KI-Lyrics
- Erkannte Wörter werden nach Zeit sortiert (parallele Chunks kamen
  unsortiert).
- Ausreißer-Anker fallen weg: Es zählt nur die längste nicht fallende Folge,
  der Rest wird interpoliert.
- Wort- und Zeilenzeiten sind streng steigend (mindestens 0,05 s pro Wort,
  0,2 s pro Zeile), auch beim Laden aller Lyrics.

### 3 Slowed zu langsam
- Die LRCLIB-Originallänge wird gegen die Länge der Audiospur (ATV) des
  Originals auf YouTube Music geprüft. Liegen beide innerhalb von 6 %, zählt die
  Audiospur; beide Werte werden geloggt.
- Im Lyrics-Menü: Tempo-Feinabstimmung mit −/+ in 0,01-Schritten (gedrückt
  halten wiederholt).
