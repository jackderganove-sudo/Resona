# Runde 5 – Gerätebefunde v0.8.5

Wiederaufnahme-Stelle. Reihenfolge: 6 → 7 → 5 → 4 → 3 → 1 → 2.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Crossfade am Gerät: „Plopp“ + nächster Song stumm bis Pause/Play | offen |
| 2 | KI-Sync: „Audio konnte nicht umgewandelt werden“ / nur 8–10 % | offen |
| 3 | Slowed-Lyrics nicht synchron, Faktor unter „Songtext von …“ anzeigen | offen |
| 4 | Lyrics per Wischen nach unten schließen | offen |
| 5 | Übersetzung/Hintergrund/Umschrift nicht abschneiden | offen |
| 6 | Vollbild-Lyrics quer: Steuerung immer sichtbar, Ruhemodus optional, Titel/Künstler linksbündig | offen |
| 7 | UI-Test grün | offen |

## Befunde vom Gerät (v0.8.5)
Funktioniert: Zum Drop, Sleep-Timer-Fade, Sperrbildschirm/Kontrollzentrum,
AirPlay, Selbst-Synchronisieren, automatische Playlists, Aufteilen (Last.fm),
Smart Downloads, Playlist-Aktualisierung, Seitenleiste, Künstler-Chevron,
Suchvorschläge, ESign-Quelle, ✕ in der Lyrics-Ansicht.

## Diagnose UI-Test (vor Runde 5)
Hochformat: ✕ schließt (Log „UI lyrics close tapped (stack)“ → „shown=false“).
Querformat: ✕ unsichtbar/nicht tippbar, weil der Ruhemodus die Bedienelemente
ausblendet → Punkt 6 behebt das.
