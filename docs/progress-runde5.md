# Runde 5 – Gerätebefunde v0.8.5

Wiederaufnahme-Stelle. Reihenfolge: 6 → 7 → 5 → 4 → 3 → 1 → 2.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Crossfade am Gerät: „Plopp“ + nächster Song stumm bis Pause/Play | umgesetzt (b4316b6), Gerätetest nötig |
| 2 | KI-Sync: „Audio konnte nicht umgewandelt werden“ / nur 8–10 % | umgesetzt (7b96e8d), CI-Test mit say-Sprache |
| 3 | Slowed-Lyrics nicht synchron, Faktor unter „Songtext von …“ anzeigen | umgesetzt (e7d8dc6), Gerätetest nötig |
| 4 | Lyrics per Wischen nach unten schließen | erledigt (ee659af) |
| 5 | Übersetzung/Hintergrund/Umschrift nicht abschneiden | erledigt (8210260) |
| 6 | Vollbild-Lyrics quer: Steuerung immer sichtbar, Ruhemodus optional, Titel/Künstler linksbündig | erledigt (c96b958) |
| 7 | UI-Test grün | in Arbeit (Update-Banner im Test aus: 17b4a3d) |

## Befunde vom Gerät (v0.8.5)
Funktioniert: Zum Drop, Sleep-Timer-Fade, Sperrbildschirm/Kontrollzentrum,
AirPlay, Selbst-Synchronisieren, automatische Playlists, Aufteilen (Last.fm),
Smart Downloads, Playlist-Aktualisierung, Seitenleiste, Künstler-Chevron,
Suchvorschläge, ESign-Quelle, ✕ in der Lyrics-Ansicht.

## Diagnose UI-Test (vor Runde 5)
Hochformat: ✕ schließt (Log „UI lyrics close tapped (stack)“ → „shown=false“).
Querformat: ✕ unsichtbar/nicht tippbar, weil der Ruhemodus die Bedienelemente
ausblendet → Punkt 6 behebt das.

## Ursachen und Fixes

### 1 Crossfade am Gerät
mpvs iOS-Audioausgabe (ao_audiounit) ruft beim Herunterfahren
`AVAudioSession.setActive(NO)` auf. Das Stoppen der ausgeblendeten Instanz
deaktivierte die Session für die ganze App, die AudioUnit der neuen Instanz
stand still („Plopp“ = harter Abbruch). Pause/Play half, weil `setPaused(false)`
`assertAudioSession()` aufruft und mpv die AudioUnit neu startet. Im Simulator
(ao=null) gibt es keine Session, deshalb lief es dort.
Fix (`PlayerController.retireFadedInstance`):
- alte Instanz auf Lautstärke 0, 120 ms auslaufen lassen, pausieren, stoppen;
- warten, bis sie im Leerlauf ist, dann sofort `setActive(true)`;
- die aktive Instanz nur dann kurz pausieren → fortsetzen (AudioUnit-Neustart),
  wenn ihr time-pos stehen bleibt;
- Watchdog nach 1,5 s, sonst `ao-reload`.

Logs zum Prüfen: `CROSSFADE after old stop`, `CROSSFADE revived`,
`CROSSFADE watchdog ok / … → ao-reload` (mit pause, core-idle, time-pos,
volume, ao).

### 2 KI-Sync
- „Audio konnte nicht umgewandelt werden“: ffmpeg lief für Streams ohne
  `-cafile` (ffmpeg-kits OpenSSL kennt keine System-Zertifikate), ohne
  User-Agent und ohne Timeout. Jetzt dieselben Argumente wie beim Download;
  ffmpeg-Fehlercode und die letzten Zeilen werden geloggt.
- 8–10 %: WhisperKit überspringt mit `noSpeechThreshold` (Standard 0,6) ganze
  30-s-Fenster, deren „keine Sprache“-Wahrscheinlichkeit hoch ist – typisch für
  Gesang über lauter Musik. Abgeschaltet; die Kompressionsgrenze ist für
  wiederholte Refrains auf 3,0 angehoben. Die Wortzeiten späterer Chunks
  versetzt WhisperKit selbst korrekt (im Quelltext v1.1.1 geprüft).
- Logs: WAV-Länge, Quelle (Download/Stream), Wörter je 30-s-Fenster, Zeit des
  letzten Worts.
- Test: macOS-`say`-Sprache aus generierten Sätzen (≈ 3 min), Erwartung > 80 %
  erkannt und Wörter bis zum Ende.

### 3 Slowed
- Die Originallänge wurde nur über LRCLIB-Einträge mit passendem Künstler
  gesucht. Slowed-Re-Uploads laufen aber meist unter dem Kanal des Uploaders →
  kein Treffer → kein Faktor. Neu: Suche nur nach Titel; ein Eintrag zählt,
  wenn sein Text die gefundenen Lyrics enthält (Abgleich nur im Speicher).
- Von Hand gewählte („Manuell suchen“) und neu gesuchte Lyrics wurden
  dauerhaft unskaliert als eigene Version gespeichert. Jetzt bekommen auch
  diese die Tempo-Prüfung, alte Einträge einmalig beim Laden.
- Cache v3 verwirft alte Einträge.
- Unter „Songtext von …“ steht jetzt der Faktor bzw. der Grund, z. B.
  „Tempo angepasst 1,15× (Original 3:12, diese Version 3:41)“ oder
  „Tempo nicht angepasst: Originallänge nicht gefunden“.
- Der alte Hinweis war vertauscht: Faktor > 1 bedeutet slowed.
- Log: `LYRICS tempo … variant= played= original= source= factor= outcome=`.
