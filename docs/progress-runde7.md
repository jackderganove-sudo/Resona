# Runde 7 – Gerätebefunde v0.8.7

Laut Gerätetest: Crossfade perfekt, KI-Lyrics springen nicht mehr.

Ablauf: Wenn alles fertig ist und Build + Unit-Tests grün sind → wip in main,
Release + apps.json prüfen, ntfy-Benachrichtigung (resona-emil-7h3k9). Nicht auf
UI-Tests warten. Bei Blockern ebenfalls ntfy („Resona: Problem“).

| # | Punkt | Status |
|---|-------|--------|
| 1 | Drop-Menü kaputt (leere Zeile, nichts antippbar) | erledigt (04958c1) |
| 2 | KI-Sync bei Remixes: Teil-Synchronisation, Songtext aus Audio, Meldung mit Optionen | umgesetzt (0f19a00) |
| 3 | KI-Kalibrierung Tempo (robuste Regression Faktor + Versatz) | umgesetzt (0f19a00) |
| 4 | KI im Lyrics-Menü für alle Songs (kalibrieren / synchronisieren, automatische Wahl) | umgesetzt (0f19a00) |
| 5 | Seitenleisten-Beschriftungen umbrechen (liegt auf wip, 5d925e6) | erledigt |

## Umsetzung

### 1 Drop-Menü
Der `Menu` hatte `.menuStyle(.button)` und `.buttonStyle(.expressive)`. SwiftUI
vererbt den Button-Stil an die Menüeinträge, daher die Zeile mit zwei Häkchen
und Einträge, die deaktiviert wirkten. Jetzt ein schlichtes System-Menü:
- Button „Zum Drop springen“;
- Toggle „Meistgehört-Kurve anzeigen“ (nur das System-Häkchen).

Kurzes Tippen springt weiterhin direkt (`primaryAction`).

### 3 KI-Kalibrierung
- Anker: per Alignment zugeordnete Wörter mit Ähnlichkeit ≥ 0,85, mindestens
  3 Buchstaben und bekannter Originalzeit (Wortzeit bzw. erstes Wort einer
  Zeile).
- Fit: Theil–Sen (Median der paarweisen Steigungen, höchstens ≈ 400 Punkte),
  Achsenabschnitt als Median, dann Kleinste Quadrate auf den Inliern
  (Residuum ≤ 1 s).
- Gut, wenn: ≥ 6 Inlier, RMS ≤ 0,6 s, Faktor 0,6–1,6 und die Anker über
  mindestens 30 % des Songs (≥ 20 s) verteilt sind.
- Gespeichert pro Song relativ zu den Original-Anbieterzeiten (automatische
  Slowed-Skalierung herausgerechnet), beim Laden angewendet (manuelles Tempo
  hat Vorrang).
- Unter „Songtext von …“: „Tempo per KI angepasst: 1,193×, +0,4 s
  (24 Ankerpunkte)“.
- Slowed/Sped-up: Einstellung Aus / Nachfragen (Standard, Button unter dem
  Label) / Automatisch im WLAN (einmal pro Sitzung). Bei zu wenigen Ankern:
  „KI-Kalibrierung: nur N sichere Ankerpunkte – der berechnete Tempo-Faktor
  bleibt“.

### 2 Remixe
- Unter 30 % Übereinstimmung: Meldung „Nur X % des Songtexts kommen im Song
  vor – vielleicht ein Remix oder ein falscher Songtext?“ mit drei Optionen:
  - „Nur passende Zeilen synchronisieren“: jede Stelle, an der eine Zeile
    gesungen wird (≥ 70 % ihrer Wörter in Reihenfolge), auch Wiederholungen und
    umgestellte Teile, ohne Überlappung;
  - „Songtext aus Audio erzeugen“: Whisper-Segmente als Zeilen, gekennzeichnet
    als „Songtext per KI transkribiert“;
  - „Anderen Songtext suchen“.
- Die Transkription wird zwischengespeichert, die Optionen brauchen keinen
  neuen Lauf.
- Das größere Modell wird jetzt automatisch versucht, wenn das kleine weniger
  als 3 Wörter pro 10 s hört.

### 4 KI für alle Songs
- Synchronisierte Lyrics: „Mit KI kalibrieren“; ohne guten Fit automatisch
  volle Synchronisation. Daneben „Stattdessen Wort für Wort synchronisieren“.
- Reiner Text: volle Synchronisation bzw. die Remix-Optionen.

### Tests
- Theil–Sen mit Rauschen und 20 % Ausreißern (Faktor ±0,003), 8 verteilte
  Anker, zu wenige Anker, gehäufte Anker (kein Vertrauen), `apply`;
- Anker aus wortsynchronen Platzhalter-Lyrics;
- Zeilenvorkommen mit Wiederholung und Umstellung; unpassendes Audio.
