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
| A1 | 7 Lyrics | Binimum-Anbieter, Enhanced-LRC-Wortzeiten (abgleichen), Übersetzungsquelle erkennen, Versatz ±5000 ms, OpenRouter-Übersetzung (eigener Key, Keychain, eigener Prompt) | mittel | offen |
| A2 | 6 Wiedergabe | Vorladen des nächsten Songs (Schalter), Wiedergabe vor Downloads, Download aus vollständigem Cache, „Audio-Unterbrechungen verhindern“, SponsorBlock im Player, Fehlerhinweise | mittel | offen |
| A3 | 3 Warteschlange | Redesign, YouTube-Empfehlungs-Chips, „Als Nächstes spielen“ | mittel | offen |
| A4 | 8 App | „Was ist neu“ aus Release-Notes, Onboarding (optionaler Login), Update-Ablauf, Bewertungs-/Support-Dialog nur wenn sinnvoll | mittel | offen |
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
