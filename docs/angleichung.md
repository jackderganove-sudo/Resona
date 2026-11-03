# Angleichung iPad ↔ Android (Runde 11, Teil C)

Gleiche Datei in beiden Repos (`Resona/docs/angleichung.md`,
`Resona-Android/docs/angleichung.md`). Grundlage: Pixel-Screenshots (v1.0.6 /
wip 1.0.7) und iPad-Simulator-Screenshots des Testlaufs v0.8.15.
Regel: bessere Lösung gewinnt, die andere App wird angepasst. Formfaktor-
Unterschiede (iPad-Seitenleiste statt Tab-Leiste, Seitenpanels statt Sheets)
bleiben bewusst.

| Element | Gewinner | Begründung | erledigt |
|---|---|---|---|
| App-Logo im Kopf/Rail | iPad (Resona-Glyph) | ArchiveTune-Zeichen auf Android war ein Überbleibsel | ja – Android v1.0.7 |
| Navigation | beide | Tab-Leiste (Telefon) / Seitenleiste (iPad) je nach Formfaktor | – |
| Chips-Zeile Startseite | gleich | beide YouTube-Music-Chips | ja |
| Quick-Picks-Hero-Karussell | gleich | beide | ja |
| Featured-Playlist-Karten | gleich | iPad seit v0.8.12, Android nativ | ja |
| Gestaffelte Genre-Kacheln | gleich | iPad seit v0.8.12 (nach ArchiveTune), Android nativ | ja |
| Grüner „…“-Schnellaktionsknopf (Musikerkennung, Together, Shuffle) | Android | einziger Zugang zur Musikerkennung; iPad hat keine Musikerkennung | Android bleibt; iPad: offen (Musikerkennung fehlt) |
| Bibliothek-Kacheln | iPad-Namen | „Lieblingssongs“ statt „Songs, die ich mag“ | ja – Android |
| „Was ist neu“ | iPad-Begriffe | Android war auf Deutsch unübersetzt; jetzt „Neu in Resona“, Neu/Verbessert/Behoben | ja – Android |
| Player Standard-Stil | gleich | Android-Player (ArchiveTune V-Design) und iPad sehen schon gleich aus: Cover, Titel + Teilen/Like/…, Wellen-Fortschritt, Pillen-Steuerung, Warteschlange/Sleep/Songtext unten | ja |
| Player Editorial/Immersiv | gleich | Android hat beide aus ArchiveTune 15 (V10 Editorial, Immersive Player), das iPad seit v0.8.12 nachgebaut; iPad-Immersiv jetzt mit einblendbarer Steuerung wie Android | ja |
| Codec-Zeile | iPad | „Opus · WEBM • kbps • kHz • MB“ ist genauer als Androids „WEBM • kbps • MB“ | ja – Android (alle drei Player-Designs) |
| Mini-Player | gleich | Cover, Titel/Künstler, Zurück/Play/Weiter | ja |
| Lyrics-Ansicht | gleich | Kopf mit Cover, ✕ und …, Fortschritt + Steuerung unten | ja |
| Warteschlange | gleich | beide mit Empfehlungs-Chips, Sperren, Auswahl | ja |
| Einstellungen | iPad-Gruppierung | Konto/Verlauf · Aussehen/Wiedergabe/Canvas/Songtext/Inhalt · Integration/Equalizer/Speicher/Über – Android hat mehr Unterseiten | offen (Android) |
| Glas-Look (Mini-Player, Leisten, Sheets, Player) | iPad | Teil D2 | offen |
| KI-Sync/-Kalibrierung | iPad | Teil D1 | offen |

## Theming (Ergänzung)

| Element | Gewinner | Ergebnis / Begründung | erledigt |
|---|---|---|---|
| Schriftfamilie | gleich (Poppins) | beide Poppins; Android hatte nur einen Schnitt (Medium/Bold künstlich) → jetzt dieselben vier Schnitte wie das iPad (Regular/Medium/SemiBold/Bold, OFL) | ja – Android |
| Typo-Skala (Display/Headline/Title/Body/Label) | gleich | zentral definiert auf beiden (iPad `M3TypeStyle.spec`, Android `Type.kt` → `MaterialTheme.typography`), identische Werte: Größe, Zeilenhöhe, Gewicht, Laufweite (M3-Grundskala) | ja (geprüft) |
| Lyrics-Schrift | iPad (Systemschrift fett) | iPad nutzt SF Pro; Android lieferte SF Pro als Datei mit (Lizenz verbietet das außerhalb von Apple) → Android-Systemschrift fett | ja – Android |
| Akzent aus dem Cover, Hell/Dunkel | gleich | beide leiten das Farbschema dynamisch aus dem Cover ab (M3 tonal) | ja (geprüft auf Screenshots) |
| AMOLED/Schwarz | Android | Android hat „Pure Black“; iPad: „Einfarbig“-Hintergrund im Player, kein App-weites Schwarz | offen (iPad) |
| Eckenradien | gleich | beide M3-Formen (extraLarge 28, large 16, medium 12) | ja (geprüft) |
| Icons | je Plattform | iPad: SF Symbols, Android: Material Symbols – SF Symbols dürfen auf Android nicht verwendet werden; beide outlined, ähnliche Strichstärke | bewusst so |
| Dialoge / Bottom-Sheets | iPad (Glas) | Android-Dialoge nutzen M3-Container (surfaceContainerHigh) statt Glas → mit D2 (gemeinsame Glas-Komponente) | offen (D2) |
| Systemleisten | gleich | beide randlos, Inhalte unter Status-/Navigationsleiste | ja (geprüft) |
