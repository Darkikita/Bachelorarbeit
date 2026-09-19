# Offene Fragen T1 bis T3

Drei Fragen, deren Antwort nicht in der PostgreSQL-Dokumentation steht
und deren Ergebnis Textstellen in Kapitel 3 und 4 entscheidet. Sie
laufen vor den Bestätigungstests der Vektoren gegen PostgreSQL 17 im
Container.

## Vorgehen

Jeder Test läuft einzeln ab frischem Container, damit keine Reste
früherer Läufe das Ergebnis verfälschen. `setup.sql` legt als
Superuser die Rollen und die Tabelle an, die alle drei Tests brauchen,
und gibt die Version sowie die Vorkontrollen für T3 aus.

T3 läuft als einzelnes Skript in der Rolle `t_creator`, weil alle
Versuche in einer Sitzung stattfinden und Fehler den Lauf nicht
abbrechen dürfen. T1 und T2 lassen sich nicht skripten, weil sie eine
Sitzung brauchen, die offen bleibt, während in einer zweiten Sitzung
das Recht entzogen oder die Rolle verändert wird. Sie werden deshalb
von Hand in zwei bis drei Terminals nach der Schritttabelle der
jeweiligen Ablaufdatei abgearbeitet.

Die Anmeldung der Testrollen erfolgt immer mit `-h ba-test-pg`, dem
Container-Namen. Die `pg_hba.conf` des Images setzt für den lokalen
Socket, für `127.0.0.1/32` und für `::1/128` die Methode `trust`, also
keine Passwortprüfung. Erst die letzte Zeile `host all all all
scram-sha-256` prüft das Passwort, und die trifft nur eine Verbindung
über die Container-IP. Ohne diesen Umweg wäre in T1 nicht prüfbar, ob
ein Passwort abgelehnt wird, wie der erste Durchlauf am 19.09.2026
gezeigt hat.

Jeder Lauf hält fest: `SELECT version();`, den Wortlaut jeder
Fehlermeldung und das Ergebnis je Versuch. Die Terminalausgaben werden
unverändert von Hand nach `ergebnisse/` kopiert, weil die Meldung
selbst das Ergebnis ist, nicht nur ob ein Befehl gelang. In den
manuellen Sitzungen vorher `\set VERBOSITY verbose` setzen, sonst
zeigt psql den SQLSTATE nicht an.

## Dateien

| Datei | Zweck |
|---|---|
| `README.md` | diese Datei: Vorgehen, Fragen, Erwartungen, Folgen für den Text |
| `setup.sql` | Grundzustand für alle drei Tests, als `ba_admin` |
| `T1.md` | Ablauf T1 Schritt für Schritt, drei Terminals |
| `T2.md` | Ablauf T2 Schritt für Schritt, zwei Terminals |
| `T3.md` | Ablauf T3, ein Terminal, ruft `t3.sql` |
| `t3.sql` | die drei Versuche von T3, als `t_creator` |
| `aufraeumen.sql` | nur nötig, wenn ein Test ohne Neustart wiederholt wird |
| `ergebnisse/` | kopierte Ausgaben, je Test und Terminal eine Datei |

## Zuordnung

| Test | Frage | Vektor (Kap. 3) | Schicht (Kap. 4) |
|---|---|---|---|
| T1 | Überlebt eine offene Sitzung Passwortwechsel und NOLOGIN? | 3.2.5 Fortbestand, "Was den Passwortwechsel überdauert" | Schicht 6 Reaktion, "Sitzungen beenden" |
| T2 | Wirkt REVOKE in einer laufenden Sitzung sofort? | 3.2.5 Fortbestand | Schicht 6 Reaktion, "Rechte entziehen" |
| T3 | Darf eine CREATEROLE-Rolle ohne ADMIN OPTION eine vordefinierte Rolle vergeben? | 3.2.2 Rechteausweitung, "Erzeugte Rechte" | Schicht 2 Least Privilege (CREATEROLE), Schicht 4 Systemgrenze (Serverrollen) |

---

## T1: Überlebt eine offene Sitzung Passwortwechsel und NOLOGIN?

Ablauf in `T1.md`.

**Frage.** Ein Angreifer hat sich mit einem kompromittierten Credential
angemeldet und hält die Sitzung offen. Der Administrator wechselt das
Passwort der Rolle und entzieht ihr danach das Anmelderecht. Läuft die
bestehende Sitzung weiter, oder wird sie durch eine der beiden
Maßnahmen beendet? Und welche der beiden Maßnahmen verhindert eine
neue Anmeldung, mit altem wie mit neuem Passwort?

**Warum offen.** Die Referenz zu ALTER ROLE (17) sagt zu `PASSWORD`
und `NOLOGIN` nichts über laufende Sitzungen. Die Vermutung ist, dass
die Sitzung weiterläuft, weil das Passwort nur bei der Anmeldung
geprüft wird und `idle_session_timeout` in der Voreinstellung null ist
(Kap. 19.11). Das ist Folgerung, kein Beleg.

**Erwartung.** Die Sitzung überlebt Passwortwechsel und NOLOGIN. Erst
`pg_terminate_backend` beendet sie, mit der Meldung `terminating
connection due to administrator command`. Eine neue Anmeldung
scheitert mit dem alten Passwort an der Passwortprüfung und mit dem
neuen an NOLOGIN.

**Folge für den Text.** Bestätigt sich die Erwartung, wird in 3.2.5
der Satz "Ob eine solche Sitzung den Passwortwechsel überdauert, sagt
die Dokumentation nicht ausdrücklich, weshalb die Frage in Kapitel 5
geprüft wird" zu "Eine solche Sitzung überdauert den Passwortwechsel
und die Sperrung, wie Kapitel 5 zeigt". Schicht 6 behält die
Reihenfolge "erst Sitzungen beenden, dann Credential entwerten" als
belegt. Überlebt die Sitzung nicht, muss die Reihenfolge in Schicht 6
umgestellt werden.

---

## T2: Wirkt REVOKE in einer laufenden Sitzung sofort?

Ablauf in `T2.md`.

**Frage.** Eine Rolle hat SELECT auf einer Tabelle und eine offene
Sitzung. Der Administrator entzieht das Recht mit REVOKE. Scheitert
die nächste Abfrage in derselben Sitzung sofort, ohne dass sich die
Rolle neu anmeldet? Und gilt das auch innerhalb einer bereits
begonnenen Transaktion, oder wird das Recht dort nur einmal beim
Transaktionsbeginn geprüft?

**Warum offen.** Die Erwartung ist "ja, sofort", weil PostgreSQL
Rechte bei jeder Anweisung prüft. Die GRANT/REVOKE-Referenz sagt es
aber nicht ausdrücklich. Das Schema-Recht (`USAGE ON SCHEMA public`)
wird in `setup.sql` getrennt vergeben, damit ein späterer Fehler
eindeutig dem Tabellenrecht zuzuordnen ist.

**Erwartung.** Die Abfrage nach REVOKE scheitert mit `permission
denied for table t_data` (SQLSTATE 42501). Ob das auch innerhalb einer
offenen Transaktion gilt, ist offen und wird durch Teil 2 in `T2.md`
beantwortet.

**Folge für den Text.** Bestätigt sich "sofort", bleibt Schicht 6 wie
geschrieben, und der Satz "Ob ein REVOKE in einer laufenden
gewöhnlichen Sitzung sofort wirkt, wird im praktischen Teil geprüft"
wird zur Feststellung. Der Unterschied zur Replikation, bei der Rechte
nur beim Verbindungsaufbau geprüft werden (Kap. 29.10), wird dadurch
schärfer. Wirkt REVOKE nicht sofort, ist das ein neuer Punkt für
3.2.5.

---

## T3: Darf eine CREATEROLE-Rolle ohne ADMIN OPTION eine vordefinierte Rolle vergeben?

Ablauf in `T3.md`, Versuche in `t3.sql`.

**Frage.** Eine Rolle besitzt das Attribut CREATEROLE, aber keine
ADMIN OPTION auf einer vordefinierten Rolle wie
`pg_read_server_files`. Kann sie diese vordefinierte Rolle sich selbst
oder einer von ihr erzeugten Rolle gewähren? Reicht der
CREATEROLE-Weg aus 3.2.2 damit bis zu den Serverrollen, oder endet er
bei selbst erzeugten Rollen?

**Warum offen.** Die Dokumentation widerspricht sich. Kap. 21.5 sagt,
Administratoren einschließlich Rollen mit CREATEROLE könnten
vordefinierte Rollen vergeben, ein Satz, der seit Version 14
unverändert steht. Die GRANT-Referenz (17) verlangt ADMIN OPTION auf
der Zielrolle, außer beim Bootstrap-Superuser. CIS 4.9 (S. 123) nennt
CREATEROLE nicht. Vorkontrolle in `setup.sql`: `t_creator` hat keine
Mitgliedschaft in `pg_auth_members`, `createrole_self_grant` ist leer.

**Erwartung.**

| Versuch | wenn GRANT-Referenz gilt | wenn Kap. 21.5 gilt |
|---|---|---|
| 1 vordefinierte Rolle an sich selbst | `permission denied to grant role "pg_read_server_files"` | Erfolg |
| 2 vordefinierte Rolle an erzeugte Rolle | derselbe Fehler | Erfolg |
| 3 erzeugte Rolle an sich selbst (Kontrolle) | Erfolg | Erfolg |

**Folge für den Text.** Scheitern 1 und 2, endet der CREATEROLE-Weg in
3.2.2 bei selbst erzeugten Rollen. Serverrollen sind nur über ADMIN
OPTION oder Superuser erreichbar. Dazu ein Satz in 3.2.2, ein Halbsatz
in Schicht 4 und eine Fußnote zur Doku-Inkonsistenz. Gelingt 1 oder 2,
bekommt 3.2.2 den Satz, dass CREATEROLE bis zum Server reicht (Kap.
21.5 zitierbar), und Schicht 2 muss CREATEROLE noch restriktiver
fassen.

---

## Start eines Tests

Alle Befehle aus `/home/nikita/docker/ba-test`. Jede Ablaufdatei
beginnt mit denselben drei Zeilen:

```bash
V=vektoren/offene-fragen
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
```

Danach die Schritte aus `T1.md`, `T2.md` oder `T3.md`. Aufräumen
entfällt, weil jeder Lauf mit `down -v` beginnt.