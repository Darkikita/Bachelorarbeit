# Vektor 3.2.1 Reichweite des Credentials gegen Schicht 2

## Zweck

Misst, was eine kompromittierte Rolle im Grundfall aus Abschnitt 3.2.1
erreicht (Zustand `vorher`) und was nach den vier Maßnahmen aus
Abschnitt 4.2 davon bleibt (Zustand `nachher`). Der Angreifer besitzt
das Credential genau einer Rolle und sonst nichts.

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
also mit den Rechten der aufrufenden Rolle. Sie führt den Befehl in
einem Ausnahmeblock aus, liest Zeilenzahl und `SQLSTATE` und erzwingt
danach einen Rollback. Der Datenbestand bleibt dadurch über alle
Angriffe unverändert, auch nach `DROP` und `DELETE`. Das Ergebnis wird
außerhalb des Ausnahmeblocks in `ergebnis` geschrieben und überlebt.

Lesart einer Zeile:

- `sqlstate = 00000`: Befehl gelungen, `zeilen` ist die Zeilenzahl,
  bei `DROP` ist sie 0
- `sqlstate = 42501`: verweigert (`insufficient_privilege`), `zeilen`
  ist leer. Der Code deckt zwei Meldungen ab, `permission denied for
  table` und `permission denied to set role`

## Rollen und Objekte

| Rolle | LOGIN | Zustand vorher | Aufgabe im Test |
|---|---|---|---|
| `app_over` | ja | Eigentümer von `kunden`, `intern`, `f()` | Grundfall aus 3.2.1 |
| `app_owner` | nein | nichts | erhält in der Maßnahme das Eigentum |
| `attacker` | ja | Mitglied `grp_mid` → `grp_mid` Mitglied `grp_read` → `SELECT` auf `intern` | gewöhnliche Rolle mit geerbter Kette |
| `admin_cr` | ja | `CREATEROLE`, keine Objektrechte | Kontrolle, läuft nur mit |
| `grp_read`, `grp_mid` | nein | Kette | — |

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

## Maßnahmen (`schicht2.sql`)

1. `REASSIGN OWNED BY app_over TO app_owner` — Eigentum weg von der
   Anwendungsrolle
2. `REVOKE ALL ON ALL TABLES ... FROM app_over`, dann
   `GRANT SELECT, INSERT ON kunden TO app_over` — Rechte je Operation
3. `REVOKE EXECUTE ON FUNCTION f() FROM PUBLIC` — Voreinstellung
   zurückgenommen
4. Kette aufgelöst, `GRANT grp_read TO attacker WITH INHERIT FALSE` —
   flach, Zugriff nur noch ausdrücklich

## Ablauf

Aus `/home/nikita/docker/ba-test`:

```bash
docker compose down -v && docker compose up -d
# warten bis docker compose ps "healthy" zeigt
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < vektoren/3.2.1-Reichweite/rahmen.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < vektoren/3.2.1-Reichweite/setup.sql
vektoren/3.2.1-Reichweite/lauf.sh vorher
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < vektoren/3.2.1-Reichweite/schicht2.sql
vektoren/3.2.1-Reichweite/lauf.sh nachher
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
  > doku/ergebnismatrix-3.2.1.tex
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

## Nicht getestet

- Verwaltungsbefugnisse aus 4.2 (Superuser `NOLOGIN`, `set_user`,
  `pg_monitor`): nur im Text beschrieben
- `ALTER DEFAULT PRIVILEGES`: nicht in den Szenarien

## Hinweise

- `rahmen.sql` ein zweites Mal auszuführen erzeugt zwei Fehler
  (`already exists`), verändert aber nichts
- `docker compose down -v` löscht das Volume `ba-test-data`. Nur aus
  diesem Ordner aufrufen, im alten Ordner träfe es `pg-data1`
- Die Passwörter in `setup.sql` entsprechen den Rollennamen. Sie sind
  Testwerte ohne Bedeutung für die Messung, weil die Verbindung im
  Container über den Unix-Socket läuft