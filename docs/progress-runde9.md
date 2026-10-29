# Runde 9 – Vollbild-Lyrics clean, Lyrics-Anbieter mit Konto

| # | Punkt | Status |
|---|-------|--------|
| 1 | Statusleiste + Home-Indikator in der Lyrics-Ansicht ausblenden | erledigt (fa9721f) |
| 2 | ✕/⋯ standardmäßig unsichtbar, Tippen auf freie Fläche blendet 3 s ein | erledigt (fa9721f) |
| 3 | Optionen „Statusleiste ausblenden“ / „Schließen-/Menü-Buttons automatisch ausblenden“ (Standard an) | erledigt (fa9721f) |
| 4 | UI-Test anpassen | angepasst (Tippen auf Kopfzeile blendet ✕ ein, Prüfung versteckt/sichtbar) |
| 5 | Deezer (ARL, Login-WebView) + Musixmatch mit eigenem Login | umgesetzt (b01f116), Gerätetest nötig |

ntfy-Thema: resona-emil-7h3k9 (das „.5“ in der Anfrage war die Punktnummer).

## 1–3 Vollbild-Lyrics
- Statusleiste: `.statusBarHidden` + `.persistentSystemOverlays(.hidden)`
  (Home-Indikator blendet sich aus), nur solange die Lyrics-Ansicht offen ist.
- ✕/⋯ (Hoch: in der Kopfzeile, Quer: oben rechts) standardmäßig unsichtbar und
  nicht antippbar. Jedes Tippen außer auf eine Lyrics-Zeile (die springt)
  blendet sie für 3 s weich ein; bei offenem Lyrics-Menü bleiben sie sichtbar.
  Schließen weiterhin per Wischen nach unten.
- Einstellungen → Songtext → Anzeige: „Statusleiste ausblenden“ und
  „Schließen-/Menü-Buttons automatisch ausblenden“ (beide Standard an).

## 5 Anbieter mit Konto
- **Deezer:**
  - „Anmelden“ öffnet deezer.com in einer Web-Ansicht mit wegwerfbarem
    Speicher; sobald das `arl`-Cookie auftaucht und `deezer.getUserData`
    einen Benutzer liefert, landet es in der Keychain. Alternativ
    „ARL einfügen“ mit Anleitung.
  - Lyrics: ARL → JWT (`auth.deezer.com/login/arl`) → Titel über die
    öffentliche Deezer-Suche → GraphQL `GetLyrics` auf `pipe.deezer.com`
    (wortweise, zeilenweise oder Text).
  - Abgelaufenes JWT wird einmal erneuert; ein abgelehntes ARL zeigt
    „Bitte erneut anmelden“.
- **Musixmatch:**
  - eigenes Benutzer-Token (Desktop-API, `web-desktop-app-v1.0`) per
    „Token einfügen“ mit Anleitung; geprüft über `user.get` („Angemeldet
    als …“).
  - Wird es abgelehnt (401): „Bitte erneut anmelden“, dann weiter mit dem
    anonymen Gast-Token.
  - Ein automatisches Web-Login ist nicht verlässlich möglich (das Token
    taucht nur in den Entwicklertools auf).
- Beide in den Songtext-Einstellungen ein-/ausschaltbar und sortierbar.
  Bereich „Konten“ mit Status, Abmelden und „Kostenloses Konto erstellen“.
  Ohne Login werden sie still übersprungen. Sie fließen in die
  Qualitätsauswahl und in „Manuell suchen“ ein.
- Sicherheit: Geheimnisse nur in der Keychain, nie geloggt (Logs nennen nur
  „signed in“ / „rejected“).
- Hinweis: Beide Wege sind inoffiziell (wie Spotify/Musixmatch-Gast in der App
  schon) und können gegen die Nutzungsbedingungen der Dienste verstoßen bzw.
  sich ändern.
