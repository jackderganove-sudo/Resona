# Runde 12 – Wiedergabefehler, Lautsprecher, Downloads als Dateien, PS5-Stick

Reihenfolge 1 → 2 → 3 → 4, nach jedem Punkt ein Release. Android-Details:
`docs/progress-android.md` im Android-Repo.

| Punkt | Inhalt | Status |
|---|---|---|
| 1 | iPad: Wiedergabefehler protokollieren, Client-Fallback wie Android, „Erneut versuchen“ | in Arbeit |
| 2 | Beide: Lautsprecher-Auswahl im Player | in Arbeit |
| 3 | Android: Downloads als sichtbare Dateien, „Nur Downloads“ | offen |
| 4 | Android: PS5-Stick | offen |

## 1. iPad: Wiedergabefehler

### Befund
- Die Stream-Auflösung liegt im Paket SwiftyTube 0.0.6. Bisherige Kette des iPads:
  VISIONOS → ANDROID_VR 1.65.10 / 1.61.48 / 1.43.32 → TVHTML5_SIMPLY_EMBEDDED_PLAYER →
  IOS (ohne Prüfung) → TVHTML5 → ANDROID → WEB_REMIX (ohne Prüfung).
- Android (`YTPlayerUtils.kt`): Hauptclient WEB_REMIX, Fallback VISIONOS, ANDROID_VR 1.65.10,
  WEB_REMIX, WEB, MWEB (WEB_CREATOR nur mit Login). Bei HTTP 403/404/410/416 im Player wird der
  Client für das Video 10 min gesperrt und neu aufgelöst.
- Versionsnummern der gemeinsamen Clients sind auf beiden Seiten gleich, veraltet war nichts.
  Aber: TVHTML5_SIMPLY_EMBEDDED_PLAYER antwortet ohne Login inzwischen „YouTube is no longer
  supported in this application“, IOS liefert nur HLS, ANDROID ohne Login keine URLs, TVHTML5
  ohne Login „UNPLAYABLE“. WEB und MWEB fehlten dem iPad ganz.
- Fehler im iPad-Code: Scheiterte das Laden eines *neuen* Songs (z. B. HTTP 403), war seine ID
  noch „pending“; die Fehlerbehandlung verglich mit der alten ID und ignorierte den Fehler →
  stiller Stillstand ohne Fallback und ohne Meldung. Ein zweiter Fehler innerhalb von 30 s
  stoppte ebenfalls still.
- Ursache des Ausfalls an dem einen Tag: nicht mehr belegbar. Vermutung: Die direkten
  VR/visionOS-URLs fielen serverseitig zeitweise aus, der Web-Pfad des iPads trug nicht (nur
  WEB_REMIX ganz am Ende, ohne Prüfung); Android hat WEB_REMIX als Hauptclient.

### Umsetzung
- Eigene Schleife (`StreamClientFallback`), ein Client nach dem anderen: VISIONOS,
  ANDROID_VR 1.65.10 / 1.61.48 / 1.43.32, WEB_REMIX, WEB, MWEB (neu, Version wie Android),
  IOS, TVHTML5 (nur mit Login), ANDROID. Der tote Embedded-Client ist raus.
- Jeder Stream wird mit einer Range-Anfrage geprüft, der HTTP-Status landet im Protokoll.
- Ein Client, der für einen Song scheitert, wird für diesen Song 10 min übersprungen (wie
  Android). Kann der Player einen Stream nicht laden (früh, ≤ 15 s, oder mit HTTP
  403/404/410/416 aus mpvs Log), geht es mit dem nächsten Client weiter. Späte Abbrüche ohne
  HTTP-Fehler (abgelaufene URL) lösen einmal neu auf, mit 30 s Abklingzeit.
- Alle Clients gescheitert: abgelaufener Cache-Eintrag als letzter Versuch, sonst Banner.
- Fehlerprotokoll (letzte 200 Einträge, Application Support): Uhrzeit, Song-ID, Client +
  Version, Stufe (resolve / validate / player / success), HTTP-Status, Fehlertext.
  Geschwärzt: URLs (nur Host + itag), `key=value`-Geheimnisse, E-Mail-Adressen, Zeichenketten
  ab 32 Zeichen. Keine Cookies, keine Kontodaten.
- Einstellungen → Über → „Fehlerprotokoll teilen“ (Textdatei über das Teilen-Menü).
- Banner: „„Titel“ kann nicht abgespielt werden“, verständlicher Grund auf Deutsch (neu:
  „YouTube hat den Stream für alle ausprobierten App-Profile abgelehnt …“), Knöpfe „Erneut
  versuchen“ (vergisst die Sperren für den Song, löst neu auf) und „Details kopieren“.
- Unit-Tests (`StreamClientFallbackTests`): Reihenfolge, Abbruch nach Erfolg, Sperren und
  Ablauf, Protokoll (200, Neustart, Export), Schwärzung, HTTP-Status aus mpv-Logzeilen.

### Nicht geprüft
- Auf einem echten iPad nicht getestet (nur Simulator-CI, dort bekommt YouTube eine
  Bot-Prüfung, die UI-Tests spielen einen Testton). Ob WEB/MWEB ohne Login auf dem iPad
  zuverlässig Streams liefern, zeigt erst das Fehlerprotokoll im Alltag.
