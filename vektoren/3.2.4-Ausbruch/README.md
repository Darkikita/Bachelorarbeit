# Vektor 3.2.4 Ausbruch aus der Datenbank

## Zweck

Dieser Vektor verlässt das Rechtemodell der Datenbank. PostgreSQL sieht
Funktionen vor, mit denen ein SQL-Befehl auf das Dateisystem des Servers
zugreift oder ein Programm ausführt, und beides geschieht mit den Rechten
des Betriebssystemnutzers, unter dem der Server läuft, nicht mit denen der
Rolle. Der Vektor setzt voraus, dass die kompromittierte Rolle die
Serverrollen ausdrücklich erhalten hat oder Superuser ist. Er ist damit
die Folge einer Vergabe, kein Weg von unten.

Die Antwort ist Schicht 4, die Systemgrenze, und zwar allein durch Least
Privilege: Die Serverrollen werden an keine Anwendungs- oder Login-Rolle
vergeben. Innerhalb des Rechtemodells greift sonst nichts, denn die
Rechteprüfung der Datenbank wird umgangen, nicht verletzt. Was jenseits
davon liegt, in dem was der Betriebssystemnutzer darf, ist die Grenze der
Arbeit und wird nur beschrieben.

Der Test zeigt beide Zustände: den Ausbruch über alle drei Wege im
Grundzustand und den Entzug der Rollen als Abwehr.

## Vorgehen

Ein Skript je Weg, das als `attacker` läuft und das Ergebnis direkt in
die psql-Ausgabe schreibt. Kein Messgerüst, keine Matrix. Zwei
Durchläufe, jeder mit frischem Volume: vorher und nach Schicht 4. Die
Anleitung mit Feldern zum Eintragen steht in `ablauf.md`.

Der Test kommt ohne zweiten Server, ohne zweite Datenbank und ohne
Konfigänderung aus.

## Umgebung

- PostgreSQL 17.10, Image `postgres:17.10`, Container `ba-test-pg`,
  Dienst `pg-service`
- Datenbank `ba_test`, Superuser `ba_admin`
- Verbindungen über `docker compose exec`

## Dateien

| Datei | Läuft als | Inhalt |
|---|---|---|
| `setup.sql` | `ba_admin` | Grundzustand: `attacker` mit den drei Serverrollen, Scratch-Tabelle |
| `e1-read.sql` | `attacker` | Lesen einer Serverdatei per `COPY` (`pg_read_server_files`) |
| `e2-write.sql` | `attacker` | Schreiben einer Serverdatei (`pg_write_server_files`) |
| `e3-program.sql` | `attacker` | Ausführen eines Programms (`pg_execute_server_program`) |
| `schicht4.sql` | `ba_admin` | Entzug der drei Serverrollen |
| `ablauf.md` | — | händisches Ablaufdokument mit Ergebnisfeldern |

## Szenarien

| Nr | Rolle | Befehl | Serverrolle |
|---|---|---|---|
| E1 | `attacker` | `COPY t FROM 'pg_hba.conf'` | `pg_read_server_files` |
| E2 | `attacker` | `COPY (...) TO '/tmp/...'`, zurücklesen | `pg_write_server_files` |
| E3 | `attacker` | `COPY ausgabe FROM PROGRAM 'id'` | `pg_execute_server_program` |

**E1.** Liest die Rolle Dateien außerhalb der Datenbank? Vorher ja, ein
Auszug aus `pg_hba.conf` über `COPY` mit Dateipfad. Nach Schicht 4 nein,
`COPY` aus einer Datei ist wieder Superusern vorbehalten.

**E2.** Schreibt die Rolle Dateien als Betriebssystemnutzer? Vorher ja,
die geschriebene Datei lässt sich zurücklesen. Nach Schicht 4 nein.

**E3.** Führt die Rolle Programme auf dem Server aus? Vorher ja, die
Ausgabe von `id` zeigt den Betriebssystemnutzer `postgres`. Nach Schicht
4 nein.

## Maßnahme

`schicht4.sql`: `REVOKE pg_read_server_files, pg_write_server_files,
pg_execute_server_program FROM attacker`. Die Serverrollen gehören an
keine Anwendungs- oder Login-Rolle und an keine, die eine solche als
Mitglied hat.

## Ablauf

Händisch nach `ablauf.md`, zwei Durchläufe. Grundmuster eines Aufrufs:

```bash
V=vektoren/3.2.4-Ausbruch
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-program.sql
```

## Erwartung

Der Durchlauf steht noch aus. Erwartet wird:

| Angriff | vorher | nach Schicht 4 |
|---|---|---|
| E1 Lesen | Auszug aus `pg_hba.conf` | `42501` |
| E2 Schreiben | `COPY 1`, Inhalt `HIJACK durch attacker` | `42501` |
| E3 Programm | `id`-Ausgabe als `postgres` | `42501` |

## Lesart

- Alle drei Wege hängen allein an der Vergabe der Serverrollen. Werden
  sie entzogen, ist der Ausbruch zu.
- E3 belegt, dass das Kommando als Betriebssystemnutzer `postgres` läuft,
  nicht als Datenbankrolle. Die Rechteprüfung der Datenbank wird umgangen,
  nicht verletzt, weshalb kein `GRANT` oder `REVOKE` auf Objekten wirkt.
- E1 und E2 belegen den im Text beschriebenen Weg zur zweiten Stufe:
  `pg_hba.conf` ist les- und schreibbar. Das Umbiegen der
  Authentifizierung selbst bleibt im Text.

## Nicht getestet

- Untrusted Sprachen wie `plpython3u`: im Standard-Image nicht
  installiert und ohnehin Superusern vorbehalten; nur beschrieben
- Härtung des Betriebssystemnutzers (eigenes Konto, keine interaktive
  Anmeldung, Binaries nicht im Besitz): Betriebssystemebene, außerhalb
  der Arbeit
- Das tatsächliche Umschreiben von `pg_hba.conf` und Umbiegen der
  Authentifizierung: nur beschrieben, um die laufende Konfiguration nicht
  zu verändern

## Hinweise

- `attacker` ist eine gewöhnliche Login-Rolle ohne Superuser-Status; der
  Ausbruch beruht allein auf den drei geerbten Serverrollen
- Der Dateizugriff läuft über `COPY`, nicht über `pg_read_file`. Die
  Mitgliedschaft in `pg_read_server_files` erlaubt den Dateizugriff über
  `COPY` und hebt die Pfadbeschränkung auf, sie vergibt aber kein
  `EXECUTE` auf `pg_read_file`; das wäre ein separater Grant. Genau die
  Unterscheidung, die der Text mit „wer sie ausführen darf" trifft
- Die Skripte legen je eine temporäre Tabelle an; nichts bleibt zwischen
  den Läufen stehen
- Die geschriebene Datei `/tmp/ba_beweis.txt` liegt im Container und
  verschwindet mit dem Volume-Neustart