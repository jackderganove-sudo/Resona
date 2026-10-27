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
| 3 | Tastatur-Kürzel (iPad) | offen |
| 4 | „Zum Drop springen“ (Most replayed) | offen |
| 5 | Lyrics-Übersetzung (Translation-Framework) | offen |
| 6 | Playlist-Werkzeuge | offen |
| 7 | Smart Downloads (Standard aus) | offen |
| 8 | KI-Synchronisation (WhisperKit) | offen |

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

## Offene Fragen an dich

## Bekannte Einschränkungen

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
