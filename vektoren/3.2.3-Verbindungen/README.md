# Vektor 3.2.3 Ausnutzung bestehender Verbindungen

## Zweck

Dieser Vektor verlässt zum ersten Mal die Datenbank. Er nutzt die
Verbindungen, die das System für den Betrieb zu anderen Systemen
unterhält, in beide Richtungen: der Angreifer erreicht über sie weitere
Systeme (dblink, postgres_fdw) oder schließt sich selbst als Empfänger
an und lässt sich die Daten liefern (Subscription).

Die Antwort darauf ist primär Schicht 4, die Systemgrenze. Sie
verhindert den Aufbau solcher Verbindungen für Rollen, die sie nicht
brauchen. Für den einmaligen Abruf über dblink und postgres_fdw genügt
das. Für die Subscription nicht, denn sobald sie steht, prüft die
Verbindung ihre Rechte nicht erneut, und ein Rechtentzug schließt den
Kanal nicht mehr. Das ist der Fall, in dem der Schaden die Entdeckung
überdauert, und er wird von Schicht 6 beantwortet, die die Verbindung
beendet.

Der Test zeigt beide Enden dieser Kette. Schicht 4 als Prävention gegen
alle drei Wege, Schicht 6 als Reaktion auf die stehende Subscription.

## Vorgehen

Kein Messgerüst, wie in 3.2.2. Ein Skript je Weg, das als seine Rolle
läuft und das Ergebnis direkt in die psql-Ausgabe schreibt. Die
vollständige Anleitung mit Feldern zum Eintragen steht in `ablauf.md`.

Der Test kommt ohne zweiten Server aus. PostgreSQL kann sich per
Loopback mit sich selbst verbinden. Für dblink und postgres_fdw genügt
dabei die `pg_hba`-Zeile für `127.0.0.1`, die auf `trust` steht: beide
kommen ohne Passwort als der genannte Benutzer an. Die Subscription
verlangt für einen Nicht-Superuser dagegen eine passwortauthentifizierte
Verbindung und läuft deshalb über den Hostnamen `ba-test-pg`, der die
`scram`-Zeile trifft; sie bezieht ihre Daten aus einer zweiten Datenbank
`ba_sub` desselben Clusters, mit dem Credential des Replikationskontos
`repl`.

Drei Durchläufe, jeder mit frischem Volume: vorher, nach Schicht 4, und
ein dritter für den Schicht-6-Teil, in dem die Subscription aufgebaut
und dann beendet wird.

## Umgebung

- PostgreSQL 17.10, Image `postgres:17.10`, Container `ba-test-pg`,
  Dienst `pg-service`
- Datenbanken `ba_test` (Publisher) und `ba_sub` (Empfänger)
- Superuser `ba_admin`, Verbindungen über `docker compose exec`
- **Voraussetzung:** Der Server muss mit `wal_level=logical` gestartet
  sein. Ohne diese Einstellung läuft die logische Replikation (E3) nicht
  an. Dem Dienst `pg-service` wird dazu in der `docker-compose.yml` der
  Startbefehl `command: ["postgres", "-c", "wal_level=logical"]` mitgegeben.
- Extensions `dblink` und `postgres_fdw` (im Image enthalten, werden von
  `setup.sql` angelegt)

## Dateien

| Datei | Läuft als | Inhalt |
|---|---|---|
| `setup.sql` | `ba_admin` | Grundzustand: Extensions, Rollen, Foreign Server, Publikation, `ba_sub` |
| `e1-dblink.sql` | `attacker` (ba_test) | Weg nach außen, Selbst-Connect auf localhost als Superuser |
| `e2-fdw.sql` | `attacker` (ba_test) | Weg nach außen, Lesen über ein PUBLIC-User-Mapping |
| `e3-subscription.sql` | `attacker` (ba_sub) | Angreifer als Empfänger, Subscription auf die Publikation |
| `schicht4.sql` | `ba_admin` | Prävention aller drei Wege |
| `ablauf.md` | — | händisches Ablaufdokument, inkl. Schicht-6-Sequenz |

## Rollen und Objekte

| Rolle | Zustand vorher | Aufgabe im Test |
|---|---|---|
| `attacker` | LOGIN; `dblink_connect_u` freigegeben, `USAGE` auf `loop`, `pg_create_subscription`, `CREATE` auf `ba_sub` | alle drei Wege |
| `repl` | LOGIN, `REPLICATION`, `SELECT` auf `oeffentlich` | Konto, unter dem die Subscription an der Gegenstelle ankommt |
| `ba_admin` | Superuser | Ziel des Selbst-Connects (E1) und der fremden Identität (E2) |

Objekte: Tabelle `oeffentlich` mit Publikation `pub` in `ba_test`, dazu
die Empfängertabelle gleichen Namens in `ba_sub`; Foreign Server `loop`
auf `127.0.0.1` mit PUBLIC-Mapping auf `ba_admin` und Fremdtabelle
`ft_authid` über `pg_catalog.pg_authid`.

## Szenarien

| Nr | Rolle | Befehl | Fall aus 3.2.3 |
|---|---|---|---|
| E1 | `attacker` | `dblink_connect_u` auf `127.0.0.1` als `ba_admin`, dann Superuser-Abfragen | Einmaliger Abruf, Sonderfall eigener Server |
| E2 | `attacker` | `SELECT` auf `ft_authid` über das PUBLIC-Mapping | Einmaliger Abruf, postgres_fdw |
| E3 | `attacker` | `CREATE SUBSCRIPTION` auf `pub` | Subscription |

**E1.** Kommt der Angreifer über den eigenen Server als Superuser
zurück? Vorher ja, weil `dblink_connect_u` die Passwortpflicht umgeht
und die trust-Zeile für `127.0.0.1` ihn als `ba_admin` einlässt. Nach
Schicht 4 nein, die Funktion ist wieder Superusern vorbehalten.

**E2.** Bekommt jede Rolle die fremde Identität, ohne dass ihr jemand
ein Mapping gab? Vorher ja, das PUBLIC-Mapping gilt für jede Rolle ohne
eigenes und lässt `attacker` als `ba_admin` an der Gegenstelle ankommen.
Nach Schicht 4 nein, das PUBLIC-Mapping ist weg und `USAGE` entzogen.

**E3.** Kann der Angreifer sich einen dauerhaften Empfänger einrichten?
Vorher ja, mit `pg_create_subscription` und `CREATE` auf `ba_sub`. Nach
Schicht 4 nein. Steht die Subscription aber schon, greift Schicht 4
nicht mehr, und erst Schicht 6 beendet sie.

## Maßnahmen

`schicht4.sql`, Prävention:

1. `REVOKE EXECUTE ON FUNCTION dblink_connect_u(text,text) FROM attacker`
2. `DROP USER MAPPING FOR PUBLIC SERVER loop`, `REVOKE USAGE ON FOREIGN SERVER loop FROM attacker`
3. `REVOKE pg_create_subscription FROM attacker`, `REVOKE CREATE ON DATABASE ba_sub FROM attacker`

Schicht 6, Reaktion auf die stehende Subscription (Schritte in
`ablauf.md`, Durchlauf 3): erst zeigen, dass `REVOKE SELECT ON
oeffentlich FROM repl` den laufenden Kanal nicht schließt (Slot bleibt
`active`, neue Zeilen kommen weiter an), dann `DROP SUBSCRIPTION sub`,
das die Subscription entfernt und den Slot auf der Gegenstelle löscht.

## Ablauf

Händisch nach `ablauf.md`, drei Durchläufe. Grundmuster eines Aufrufs:

```bash
V=vektoren/3.2.3-Verbindungen
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-dblink.sql
```

## Erwartung

Der Durchlauf steht noch aus. Erwartet wird:

| Angriff | vorher | nach Schicht 4 |
|---|---|---|
| E1 dblink | `angemeldet_als = ba_admin`, Zeilen aus `pg_authid` | `42501` bei `dblink_connect_u` |
| E2 fdw | `authid_zeilen` > 0 | „user mapping not found" |
| E3 Subscription | Zeilen `1 eins`, `2 zwei` in `ba_sub` | Fehler, Recht fehlt |

Schicht 6 (Durchlauf 3): Slot `active = t` vor und nach dem Rechtentzug,
Zeile `3 drei` erreicht trotz Entzug `ba_sub`, nach `DROP SUBSCRIPTION`
kein Slot mehr.

## Lesart

- E1 und E2 sind einmalige Abrufe. Schicht 4 schließt sie an der Grenze,
  und danach bleibt kein Weg offen.
- E3 zeigt die Grenze von Schicht 4. Vor dem Aufbau verhindert sie die
  Subscription, nach dem Aufbau nicht mehr, weil die Rechte auf der
  Publisher-Seite nur zu Beginn geprüft werden. Der Rechtentzug lässt
  den Kanal laufen, erst `DROP SUBSCRIPTION` beendet ihn.
- Damit greift hier eine Kette statt einer einzelnen Schicht: Schicht 4
  verhindert, Schicht 5 macht die stehende Verbindung über
  `pg_replication_slots` sichtbar, Schicht 6 beendet sie.

## Nicht getestet

- Physische Replikation (ganzer Cluster samt Passwort-Hashes): braucht
  einen echten Standby, also einen zweiten Dienst; nur im Text
- `run_as_owner` als Codeausführungsrisiko der Subscription: nur
  beschrieben
- Der Kettencharakter über mehrere verknüpfte Systeme (Weiterreichen von
  Server zu Server): nur im Text

## Hinweise

- Bei E1 und E2 ist der Hebel die trust-Zeile für `127.0.0.1`: die
  Verbindung kommt ohne Passwort als `ba_admin` an. E3 nutzt dagegen das
  Credential des Kontos `repl` über eine passwortauthentifizierte
  Verbindung (`ba-test-pg`, scram), weil eine Subscription eines
  Nicht-Superusers das verlangt
- `setup.sql` legt am Ende mit `\c ba_sub` die Empfängertabelle an; der
  Durchlauf beginnt danach in der jeweils genannten Datenbank
- Ohne `wal_level=logical` bricht E3 schon beim `CREATE SUBSCRIPTION` ab
- Weil Publisher (`ba_test`) und Empfänger (`ba_sub`) im selben Cluster
  liegen, muss der Replikationsslot vorab getrennt angelegt werden
  (`pg_create_logical_replication_slot('sub','pgoutput')`), und die
  Subscription läuft mit `create_slot = false`. Sonst hängt der Aufruf.
  Das ist eine dokumentierte Einschränkung für denselben Cluster (CREATE
  SUBSCRIPTION, Notes), keine Eigenschaft des Angriffs; bei einem echten
  entfernten Publisher entfällt der Schritt
- Die Passwörter der Testrollen entsprechen den Rollennamen (`repl`
  meldet sich mit `repl` an)