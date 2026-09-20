# Vektor 3.2.5 Fortbestand über die Entdeckung hinaus

## Zweck

Dieser Vektor beschreibt nicht, was ein Angreifer erreicht, sondern was
von ihm bleibt, wenn das Credential entwertet wird. Die drei Eingriffe
Passwortwechsel, Rechteentzug und Sperrung haben in PostgreSQL jeweils
eine Grenze, hinter der der Zugang weiterläuft. Es ist ein Sammelvektor
unter einer neuen Frage: welchen der drei Eingriffe der jeweilige
Zustand überdauert.

Die Antwort liegt in Schicht 5 und Schicht 6. Schicht 6 beendet den
Zugang und beseitigt die hinterlassenen Zustände, in fester Reihenfolge,
und sie antwortet damit auf alle drei Teile des Vektors. Schicht 5 ist
die Voraussetzung dafür, denn ein Zustand kann nur beseitigt werden,
wenn er gefunden wird, und gefunden wird er nur, wenn er aufgezeichnet
ist oder in den Katalogen steht.

Der Test zeigt beide Enden: dass die Zustände die naiven Eingriffe
überdauern, und wie Schicht 5 sie sichtbar und Schicht 6 sie entfernbar
macht.

## Vorgehen

Vier Versuche. Die einzelnen Zustände selbst sind bereits in 3.2.2 (die
angelegte Rolle), 3.2.3 (die Replikation, die den Entzug überdauert) und
3.2.4 (Code und Konfiguration auf dem Server) belegt. Dieser Test deckt
das ab, was dort noch nicht geprüft wurde und den Kern dieses Vektors
bildet:

- **T1** Eine offene Sitzung überdauert Passwortwechsel und `NOLOGIN`,
  erst `pg_terminate_backend` beendet sie.
- **T2** Ein `REVOKE` wirkt in einer laufenden Sitzung sofort, auch
  mitten in einer Transaktion.
- **T3** `DROP ROLE` scheitert, solange die Rolle Objekte besitzt, und
  wird erst durch `DROP OWNED` bzw. `REASSIGN OWNED` entfernbar.
- **T4** In der Voreinstellung zeichnet der Server nichts auf; Schicht 5
  schaltet die Protokollierung ein.

T1 und T2 brauchen zwei gleichzeitige Sitzungen, also zwei Terminals. T3
und T4 laufen in einem. Die Schritt-für-Schritt-Anleitung mit Feldern zum
Eintragen steht in `ablauf.md`.

## Umgebung

- PostgreSQL 17.10, Image `postgres:17.10`, Container `ba-test-pg`,
  Dienst `pg-service`
- Datenbank `ba_test`, Superuser `ba_admin`
- Verbindungen über `docker compose exec`; für T4 wird zusätzlich das
  Serverprotokoll über `docker compose logs` gelesen

## Dateien

| Datei | Läuft als | Inhalt |
|---|---|---|
| `setup-session.sql` | `ba_admin` | Grundzustand für T1 und T2: Rolle `victim`, Tabelle `daten` |
| `setup-persistenz.sql` | `ba_admin` | Grundzustand für T3 und T4: Rolle `attacker` mit eigenem Schema |
| `t-anlegen.sql` | `attacker` | legt eine SECURITY-DEFINER-Funktion an (der überdauernde Zustand) |
| `t3-reaktion.sql` | `ba_admin` | `DROP ROLE` (scheitert), `DROP OWNED`, `DROP ROLE` |
| `t4-vorher.sql` | `ba_admin` | zeigt die Logging-Parameter im Standard |
| `t4-einschalten.sql` | `ba_admin` | `ALTER SYSTEM` plus `pg_reload_conf()` |
| `ablauf.md` | — | händisches Ablaufdokument mit Ergebnisfeldern |

## Szenarien

**T1.** Überdauert eine offene Sitzung Passwortwechsel und Sperrung?
Beide werden erst beim nächsten Verbindungsaufbau geprüft, die offene
Sitzung läuft weiter. Neue Anmeldungen scheitern, mit altem Passwort an
der Passwortprüfung, nach `NOLOGIN` an der Sperrung. Erst
`pg_terminate_backend` beendet die offene Sitzung, die zuvor in
`pg_stat_activity` sichtbar ist.

**T2.** Wirkt ein Rechteentzug auf eine laufende Sitzung? Ja, sofort. Das
Recht wird bei jeder Anweisung geprüft, die nächste Abfrage scheitert,
auch innerhalb einer bereits begonnenen Transaktion, die dadurch
abgebrochen wird.

**T3.** Lässt sich die kompromittierte Rolle einfach entfernen? Nein,
solange sie Objekte besitzt. `DROP ROLE` scheitert, `DROP OWNED` entfernt
Objekte und Rechte, danach gelingt `DROP ROLE`. Ein Angreifer, der
Objekte anlegt, macht seine eigene Entfernung damit aufwendiger.

**T4.** Sieht jemand den hinterlassenen Zustand? In der Voreinstellung
nicht. `log_connections`, `log_disconnections` und `log_statement` stehen
auf `off`, `off` und `none`; das Anlegen erzeugt keine Zeile. Nach dem
Einschalten über Schicht 5 erscheint dieselbe Anweisung im Protokoll.

## Maßnahmen

Schicht 5, Erkennung: Protokollierung einschalten (`t4-einschalten.sql`)
und die Kataloge und Sichten abfragen (`pg_stat_activity` für die
Sitzung, `pg_proc.prosecdef` für SECURITY-DEFINER-Funktionen, `pg_authid`
für Rollen).

Schicht 6, Reaktion, in fester Reihenfolge: Sitzungen mit
`pg_terminate_backend` beenden (T1), Credential mit `ALTER ROLE`
entwerten, Rechte mit `REVOKE`/`DROP OWNED` entziehen (T2), Zustände
beseitigen und die Rolle mit `DROP OWNED`/`REASSIGN OWNED` und `DROP
ROLE` entfernen (T3).

## Ablauf

Händisch nach `ablauf.md`, vier Versuche, jeder mit frischem Volume.

## Erwartung

Der Durchlauf steht noch aus. Erwartet wird:

- T1: die offene Sitzung liefert vor und nach beiden Eingriffen `3`, beide
  neuen Anmeldungen scheitern, nach `pg_terminate_backend` ist die
  Sitzung beendet.
- T2: die erste Abfrage `3`, die zweite nach dem `REVOKE` `permission
  denied for table daten`.
- T3: erstes `DROP ROLE` scheitert, `DROP OWNED` und zweites `DROP ROLE`
  gelingen.
- T4: vorher `off`/`off`/`none` und keine Protokollzeile, nachher die
  Verbindungs- und Anweisungszeile.

## Lesart

- T1 und T2 zeigen den Unterschied zwischen einer Prüfung bei jeder
  Anweisung (Rechteentzug wirkt sofort) und einer Prüfung nur beim
  Verbindungsaufbau (Passwort und `NOLOGIN` erreichen die offene Sitzung
  nicht). Das erklärt, warum die Reaktion mit dem Beenden der Sitzung
  beginnen muss, nicht mit dem Passwortwechsel.
- T3 zeigt, dass die Sperrung nur die eine Rolle trifft und ihr Code
  bleibt, bis er einzeln entfernt ist.
- T4 zeigt, dass der Fortbestand in der Voreinstellung nicht der Tarnung
  geschuldet ist, sondern der fehlenden Aufzeichnung. Ohne Schicht 5 gibt
  es nichts zu finden.

## Nicht getestet

- Die einzelnen überdauernden Zustände selbst (angelegte Rolle,
  Replikation, Code und Konfiguration auf dem Server): bereits in 3.2.2,
  3.2.3 und 3.2.4 belegt
- `pgAudit` für den Lesezugriff des Grundfalls aus 3.2.1: als Erweiterung
  beschrieben, hier nicht installiert
- Auswertung des Protokolls außerhalb der Datenbank: nach Schicht 5 deren
  Grenze und außerhalb der Arbeit

## Hinweise

- Die Logging-Parameter lassen sich nicht per Sitzung setzen; `ALTER
  SYSTEM` plus `pg_reload_conf()` ist der einzige Weg, und die Änderung
  wirkt auf neue Verbindungen und folgende Anweisungen
- Für T1 muss die Anmeldung mit altem Passwort vor dem `NOLOGIN`
  erfolgen, sonst überdeckt die Sperrung die Passwortprüfung
- Die offene Sitzung in Terminal A verbindet über den Socket ohne
  Passwort; der Passwortwechsel betrifft sie deshalb ohnehin nur beim
  nächsten Aufbau, genau das ist der Punkt