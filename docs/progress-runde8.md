# Runde 8 – Gerätebefunde v0.8.8 (66)

Laut Gerätetest: KI-Kalibrierung für Slowed perfekt.

| # | Punkt | Status |
|---|-------|--------|
| 1 | Drop-Menü: Kurven-Eintrag ausgegraut + leere Zeile mit Häkchen | in Arbeit |
| 2 | Mehr Lyrics-Anbieter, Remix-Bevorzugung, Trefferliste in der Suche, danach KI-Kalibrierung anbieten | offen |

## 1 Drop-Menü
Ursache: `TropApp` setzt app-weit `.toggleStyle(.m3)`; der `Toggle` im Menü
übernahm diesen eigenen Stil (Text als graue Überschrift, eigene Häkchen als
leere Zeile). Jetzt nur schlichte Buttons: „Meistgehört-Kurve ausblenden/
anzeigen“ (Text wechselt) und „Zum Drop springen“.
Nachweis per UI-Test (Hoch und Quer): Menü per langem Druck geöffnet
(Screenshot), beide Einträge mit Text und aktiv, Kurve verschwindet und
erscheint wieder, Sprung zeigt die Meldung „Zum Drop gesprungen“.
