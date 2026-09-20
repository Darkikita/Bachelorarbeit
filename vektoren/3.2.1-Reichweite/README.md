# Vektor 3.2.1 Reichweite des Credentials gegen Schicht 2

## Zweck

Abschnitt 3.2.1 beschreibt, was ein Angreifer erreicht, der das
Credential genau einer Rolle besitzt und sonst nichts. Der Grundfall
ist eine Anwendungsrolle, die zugleich liest, schreibt und die Tabellen
besitzt, dazu Rechte, die ihr über Mitgliedschaftsketten und
PUBLIC-Voreinstellungen zufallen, ohne dass sie jemand vergeben hätte.
Abschnitt 4.2 antwortet darauf mit vier Maßnahmen: eine Rolle je Zweck,
Objektrechte nach Bedarf, Verwaltungsbefugnisse nur wo nötig,
Mitgliedschaften ohne Ketten.

Dieser Test misst beides. Erst, was jede Rolle im Grundfall darf
(Zustand `vorher`), dann, was nach den Maßnahmen davon bleibt
(Zustand `nachher`). Die Differenz ist die Wirkung der Schicht, und
eine Zeile, die vorher wie nachher gelingt, zeigt ihre Grenze.

## Vorgehen

Jeder Durchlauf beginnt mit einem frischen Volume, damit keine Reste
früherer Läufe das Ergebnis verfälschen. `rahmen.sql` legt einmal je
Durchlauf die Ergebnistabelle und die Messfunktion an. `setup.sql`
baut den Grundfall aus 3.2.1 absichtlich unsicher nach. `lauf.sh`
lässt dann jede Testrolle dieselben acht Befehle aus `angriffe.sql`
ausführen und schreibt das Ergebnis mit dem Zustand `vorher` in die
Tabelle. Danach wendet `schicht2.sql` die vier Maßnahmen an, und
`lauf.sh` wiederholt die acht Befehle mit dem Zustand `nachher`.

Die Angriffe sind in beiden Zuständen identisch. Nur so ist die
Differenz allein den Maßnahmen zuzuschreiben und nicht einer
Änderung am Test. Jede Schicht wird einzeln gegen den Grundzustand
gemessen, also vor jeder weiteren Schicht wieder mit frischem Volume
begonnen.

Die Verbindung läuft im Container über den Unix-Socket. Die Passwörter
in `setup.sql` sind deshalb Testwerte ohne Bedeutung, weil die
Anmeldung hier nicht geprüft wird. Für diesen Vektor ist das richtig,
denn gemessen wird, was eine Rolle darf, nicht, ob sie sich anmelden
kann.

## Umgebung

- PostgreSQL 17.10, Image `postgres:17.10`, Container `ba-test-pg`,
  Dienst `pg-service`
- Datenbank `ba_test`, Superuser `ba_admin`
- Alle Verbindungen über `docker compose exec` innerhalb des Containers
- Jeder Durchlauf beginnt mit einem frischen Volume

## Dateien

| Datei | Läuft als | Inhalt |
|---|---|---|
| `rahmen.sql` | `ba_admin` | Ergebnistabelle und Messfunktion `pruef`, einmal je Durchlauf |
| `setup.sql` | `ba_admin` | Grundfall: Rollen, Tabellen, Funktion, Mitgliedschaftskette |
| `angriffe.sql` | jede Testrolle | Die acht Befehle, identisch in beiden Zuständen |
| `schicht2.sql` | `ba_admin` | Die vier Maßnahmen aus 4.2 |
| `lauf.sh` | Host | Führt `angriffe.sql` für alle drei Testrollen aus |

## Messfunktion

`pruef(nr, zustand, befehl, setrole)` läuft mit `SECURITY INVOKER`,
also mit den Rechten der aufrufenden Rolle. Das ist die Bedingung
dafür, dass die Messung stimmt: Die Funktion darf nicht mehr können
als die Rolle, die sie aufruft, sonst würde sie selbst zum
Eskalationspfad.

Sie führt den Befehl in einem Ausnahmeblock aus, liest Zeilenzahl und
`SQLSTATE` und erzwingt danach einen Rollback. Der Datenbestand bleibt
dadurch über alle Angriffe unverändert, auch nach `DROP` und `DELETE`,
und alle Rollen sehen in beiden Zuständen denselben Ausgangsbestand.
Das Ergebnis wird außerhalb des Ausnahmeblocks in `ergebnis`
geschrieben und überlebt den Rollback.

Lesart einer Zeile:

- `sqlstate = 00000`: Befehl gelungen, `zeilen` ist die Zeilenzahl,
  bei `DROP` ist sie 0
- `sqlstate = 42501`: verweigert (`insufficient_privilege`), `zeilen`
  ist leer. Der Code deckt zwei Meldungen ab, `permission denied for
  table` und `permission denied to set role`

## Rollen und Objekte

| Rolle | LOGIN | Zustand vorher | Aufgabe im Test |
|---|---|---|---|
| `app_over` | ja | Eigentümer von `kunden`, `intern`, `f()` | Grundfall aus 3.2.1, die überprivilegierte Anwendungsrolle |
| `app_owner` | nein | nichts | erhält in der Maßnahme das Eigentum |
| `attacker` | ja | Mitglied `grp_mid` → `grp_mid` Mitglied `grp_read` → `SELECT` auf `intern` | gewöhnliche Rolle mit geerbter Kette |
| `admin_cr` | ja | `CREATEROLE`, keine Objektrechte | Kontrolle, läuft nur mit |
| `grp_read`, `grp_mid` | nein | Kette | — |

`app_over` ist der Grundfall aus 3.2.1 in einer Rolle: Sie verbindet,
liest, schreibt und besitzt. `attacker` steht für die zweite Aussage
des Abschnitts, dass Rechte auch ohne Vergabe auf eine Rolle gelangen,
über Mitgliedschaft und über Voreinstellungen. `admin_cr` läuft als
Kontrolle mit, um zu zeigen, dass ein Verwaltungsattribut allein noch
keine Objektrechte trägt. `app_owner` existiert im Grundfall nur, damit
die Maßnahme ein Ziel für das Eigentum hat.

Tabellen: `kunden` 20 Zeilen (`id`, `name`, `iban`), `intern` 10 Zeilen
(`id`, `notiz`). Funktion `f()` gibt einen Text zurück, `EXECUTE` für
`PUBLIC` ist Voreinstellung. `GRANT CREATE ON SCHEMA public TO PUBLIC`
stellt die Voreinstellung bis PostgreSQL 14 nach und ist der
Vorher-Zustand für 3.2.2, hier ohne Wirkung.

## Szenarien

| Nr | Befehl | Rolle mit Aussage | Absatz in 4.2 |
|---|---|---|---|
| A1 | `SELECT`, `UPDATE`, `DELETE` auf `intern` | `app_over` | Objektrechte nach Bedarf |
| A2 | `DROP TABLE kunden` | `app_over` | Eine Rolle je Zweck |
| A3 | `SELECT f()` | `attacker` | PUBLIC-Voreinstellung |
| A4 | `SELECT` auf `intern` über die Kette | `attacker` | Mitgliedschaften ohne Ketten, `INHERIT` |
| A5 | `SET ROLE grp_read`, dann `SELECT` | `attacker` | Mitgliedschaften ohne Ketten, `SET` |
| N1 | `INSERT` in `kunden` | `app_over` | Nutzfall, Grenze der Schicht |

`A1-select` und `A4-kette` sind derselbe Befehl. Die Nummer hängt an der
Rolle, bei `app_over` zählt A1, bei `attacker` A4.

**A1.** Darf die Anwendungsrolle auf einer Tabelle alles, obwohl ihre
Aufgabe nur einen Teil davon braucht? Vorher ja, weil sie Eigentümerin
ist. Nachher nur noch, was `GRANT` je Operation vergibt, und `intern`
gehört nicht dazu.

**A2.** Kann ein Credential der Anwendungsrolle das Schema zerstören?
Vorher ja, weil Eigentum das Recht zu `DROP` mitbringt und sich davon
nicht trennen lässt. Nachher nein, weil das Eigentum bei `app_owner`
liegt, einer Rolle ohne Anmelderecht.

**A3.** Kann jede Rolle jede Funktion aufrufen, ohne dass ihr das
jemand erlaubt hat? Vorher ja, weil PostgreSQL `EXECUTE` für `PUBLIC`
voreinstellt. Nachher nein, nach `REVOKE ... FROM PUBLIC`.

**A4.** Erreicht eine Rolle über eine Kette von Mitgliedschaften Daten,
die ihr niemand direkt gegeben hat? Vorher ja, weil `INHERIT` die
Rechte entlang der Kette mit der Anmeldung bereitstellt. Nachher nein,
weil die Kette aufgelöst ist.

**A5.** Bleibt der Zugriff nach der Maßnahme ausdrücklich erreichbar?
Ja, mit `SET ROLE`. Das ist gewollt und die Grenze zu A4: `INHERIT
FALSE` nimmt den Zugriff nicht, es macht ihn sichtbar.

**N1.** Arbeitet die Anwendung nach der Maßnahme weiter? Muss vorher
wie nachher gelingen, sonst hätte die Schicht gesperrt statt begrenzt.

## Maßnahmen (`schicht2.sql`)

1. `REASSIGN OWNED BY app_over TO app_owner` — Eigentum weg von der
   Anwendungsrolle (Absatz "Eine Rolle je Zweck")
2. `REVOKE ALL ON ALL TABLES ... FROM app_over`, dann
   `GRANT SELECT, INSERT ON kunden TO app_over` — Rechte je Operation
   (Absatz "Objektrechte nach Bedarf")
3. `REVOKE EXECUTE ON FUNCTION f() FROM PUBLIC` — Voreinstellung
   zurückgenommen (Absatz "Objektrechte nach Bedarf")
4. Kette aufgelöst, `GRANT grp_read TO attacker WITH INHERIT FALSE` —
   flach, Zugriff nur noch ausdrücklich (Absatz "Mitgliedschaften ohne
   Ketten")

## Ablauf

Aus `/home/nikita/docker/ba-test`:

```bash
V=vektoren/3.2.1-Reichweite

docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/rahmen.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
$V/lauf.sh vorher
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/schicht2.sql
$V/lauf.sh nachher
```

Rohausgabe (48 Zeilen):

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT nr, rolle, zustand, zeilen, sqlstate FROM ergebnis ORDER BY nr, rolle, zustand;"
```

Export als Matrix (24 Zeilen) für die Arbeit:

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -P format=latex -P footer=off \
  -c "SELECT nr, rolle,
        max(CASE WHEN zustand = 'vorher'  THEN CASE WHEN sqlstate = '00000' THEN zeilen::text ELSE sqlstate END END) AS vorher,
        max(CASE WHEN zustand = 'nachher' THEN CASE WHEN sqlstate = '00000' THEN zeilen::text ELSE sqlstate END END) AS nachher
      FROM ergebnis GROUP BY nr, rolle ORDER BY nr, rolle;" \
  > vektoren/3.2.1-Reichweite/ergebnismatrix-3.2.1.tex
```

## Erwartung und Ergebnis

Durchlauf am 16.09.2026. Alle 48 Zeilen entsprechen der Erwartung.

| Nr | Rolle | vorher | nachher |
|---|---|---|---|
| A1-select/update/delete | `app_over` | 10 | 42501 |
| A2-drop | `app_over` | 00000 | 42501 |
| A3-execute | `attacker` | 1 | 42501 |
| A4-kette | `attacker` | 10 | 42501 |
| A5-setrole | `attacker` | 10 | 10 |
| N1-nutzfall | `app_over` | 1 | 1 |
| alle außer A3 | `admin_cr` | 42501 | 42501 |
| A3-execute | `admin_cr` | 1 | 42501 |

## Lesart

- A4 gegen A5: Die Kette ist weg, der Zugriff auf `grp_read` bleibt,
  aber nur noch nach ausdrücklichem `SET ROLE`. `INHERIT FALSE` nimmt
  keinen Zugriff, es macht ihn sichtbar. Ein Angreifer, der die Gruppe
  nicht kennt, erreicht sie nicht mehr
- N1: Die Anwendung arbeitet nach der Maßnahme weiter. Die Schicht
  begrenzt auf den Zweck, sie sperrt nicht
- `admin_cr`: `CREATEROLE` trägt keine Objektrechte. Die Ebene aus
  3.2.1 bemisst sich nicht am Attribut allein, sondern an dem, was der
  Rolle eingeräumt wurde
- A3: `EXECUTE` für `PUBLIC` reicht vorher für jede Rolle, auch für die
  Kontrollrolle

## Folge für den Text

Die vier Maßnahmen aus 4.2 wirken je einzeln nachweisbar auf den
Grundfall aus 3.2.1, und der Nutzfall bleibt erhalten. Die Matrix geht
als `doku/ergebnismatrix-3.2.1.tex` in `sec:ergebnismatrix`. A5 belegt
den Satz in 4.2, dass `INHERIT FALSE` die Rechte erst nach `SET ROLE`
bereitstellt und ein kompromittiertes Credential sie nicht mit sich
trägt, solange der Angreifer die Gruppe nicht kennt. `admin_cr` stützt
die Trennung der Ebenen in 3.2.1.

## Nicht getestet

- Verwaltungsbefugnisse aus 4.2 (Superuser `NOLOGIN`, `set_user`,
  `pg_monitor`): nur im Text beschrieben
- `ALTER DEFAULT PRIVILEGES`: nicht in den Szenarien
- Der zweite Weg aus 3.2.2 (`CREATEROLE`, `ADMIN OPTION`): `admin_cr`
  legt hier keine Rollen an, das gehört zu 3.2.2

## Hinweise

- `rahmen.sql` ein zweites Mal auszuführen erzeugt zwei Fehler
  (`already exists`), verändert aber nichts
- `docker compose down -v` löscht das Volume `ba-test-data`. Nur aus
  diesem Ordner aufrufen, im alten Ordner träfe es `pg-data1`
- Die Passwörter in `setup.sql` entsprechen den Rollennamen. Sie sind
  Testwerte ohne Bedeutung für die Messung, weil die Verbindung im
  Container über den Unix-Socket läuft