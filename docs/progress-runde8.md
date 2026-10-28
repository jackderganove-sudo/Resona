# Runde 8 – Gerätebefunde v0.8.8 (66)

Laut Gerätetest: KI-Kalibrierung für Slowed perfekt.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Drop-Menü: Kurven-Eintrag ausgegraut + leere Zeile mit Häkchen | erledigt, im Simulator nachgewiesen (Screenshots in docs/test-report.md) |
| 2 | Mehr Lyrics-Anbieter, Remix-Bevorzugung, Trefferliste in der Suche, danach KI-Kalibrierung anbieten | umgesetzt (a7508c0) |

## 1 Drop-Menü
Ursache: `TropApp` setzt app-weit `.toggleStyle(.m3)`; der `Toggle` im Menü
übernahm diesen eigenen Stil (Text als graue Überschrift, eigene Häkchen als
leere Zeile). Jetzt nur schlichte Buttons: „Meistgehört-Kurve ausblenden/
anzeigen“ (Text wechselt) und „Zum Drop springen“.
Nachweis per UI-Test (Hoch und Quer): Menü per langem Druck geöffnet
(Screenshot), beide Einträge mit Text und aktiv, Kurve verschwindet und
erscheint wieder, Sprung zeigt die Meldung „Zum Drop gesprungen“.

## 2 Lyrics-Anbieter
Neu, alle ohne Konto nutzbar (Referenz: ArchiveTune / ArchiveTune-lyrics):
- **SimpMusic** (`api-lyrics.simpmusic.org/v1/<videoId>`): Community-Lyrics
  **pro YouTube-Upload**, also auch für Remixe/Edits; nächstliegende Dauer
  zuerst.
- **Unison** (`unison.boidu.dev`): pro Video-ID, deren Varianten und eine
  Suche nach Titel/Künstler/Dauer; LRC oder TTML.
- **Megalobiz**: Suche → LRC-Seite (zeilen-synchron).
- **QQ Music**: öffentliche Suche + LRC (Referer y.qq.com).

Jeder Anbieter kann jetzt mehrere Treffer mit Titel, Künstler, Dauer und
„diese Version“ (Video-ID) liefern. Alle erscheinen in den
Songtext-Einstellungen (ein/aus, sortierbar) mit kurzem Hinweis.

Auswahl (automatisch und in der Trefferliste):
- Qualität zuerst (Wort > Zeile > Text).
- Ein synchronisierter Treffer für genau diesen Upload: +6. Bei erkennbaren
  Varianten (Remix/Edit/Live/… im Titel bzw. Slowed/Sped-up) +12, schlägt
  damit auch wortsynchrone Lyrics des Originals.
- Titel mit dem Remix-Namen +8, passende Dauer (±3 s) +2, stark abweichende
  Dauer (> 15 s) −6, passender Künstler +2.

„Manuell suchen“:
- listet jetzt alle Treffer aller Anbieter mit Anbieter, Synchronisationsart,
  Dauer, „Diese Version“, Titel — Künstler und Vorschau, bester zuerst;
- die Suche bekommt die Video-ID, damit SimpMusic/Unison greifen;
- nach der Auswahl eines synchronisierten Treffers wird eine alte Kalibrierung
  verworfen und „Tempo per KI kalibrieren“ angeboten.

Noch nicht umgesetzt: Anbieter mit Konto. Deezer bräuchte das ARL-Cookie des
Kontos (sensibler Token); für Musixmatch wäre ein eigener Login nötig. Beides
ist als eigener Schritt sinnvoll (Keychain + Anleitung wie beim Paxsenix-Key).
