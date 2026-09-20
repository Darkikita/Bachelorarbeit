# Ablauf 3.2.3 Ausnutzung bestehender Verbindungen (händisch)

Voraussetzung: Der Server muss mit `wal_level=logical` gestartet sein.
Ohne diese Einstellung läuft die logische Replikation (E3) nicht an. Dem
Dienst `pg-service` wird dazu in der `docker-compose.yml` der Startbefehl
mitgegeben:

```yaml
    command: ["postgres", "-c", "wal_level=logical"]
```

Alle Befehle werden aus dem Verzeichnis der Testumgebung
(`/home/nikita/docker/ba-test`) ausgeführt. Die Pfadabkürzung wird je
Terminal einmal gesetzt:

```bash
V=vektoren/3.2.3-Verbindungen
```

Drei Durchläufe, jeder mit frischem Volume. E1 und E2 laufen in
`ba_test`, E3 in `ba_sub`.

---

## Durchlauf 1 — vorher (nur Grundzustand)

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-dblink.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-fdw.sql
# Slot vorab anlegen (nötig, weil Publisher und Empfänger im selben Cluster liegen)
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pg_create_logical_replication_slot('sub','pgoutput');"
docker compose exec -T pg-service psql -U attacker -d ba_sub  -f - < $V/e3-subscription.sql
```

**E1 dblink** — erwartet: `angemeldet_als = ba_admin`, dann eine Zeilenzahl aus `pg_authid`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-dblink.sql
## E1  dblink Selbst-Connect auf localhost  (als attacker, in ba_test)
 dblink_connect_u 
------------------
 OK
(1 row)

 angemeldet_als 
----------------
 ba_admin
(1 row)

 authid_zeilen 
---------------
            18
(1 row)

 dblink_disconnect 
-------------------
 OK
(1 row)
```

**E2 fdw** — erwartet: `authid_zeilen` > 0 (attacker liest pg_authid über das PUBLIC-Mapping)

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-fdw.sql
## E2  postgres_fdw oeffentliches Mapping  (als attacker, in ba_test)
 authid_zeilen 
---------------
            18
(1 row)
```

**E3 Subscription** — erwartet: `CREATE SUBSCRIPTION`, dann die Zeilen `1 eins` und `2 zwei` in `ba_sub`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pg_create_logical_replication_slot('sub','pgoutput');"
 pg_create_logical_replication_slot 
------------------------------------
 (sub,0/1DB8DA0)
(1 row)

nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_sub  -f - < $V/e3-subscription.sql
## E3  Subscription als Empfaenger  (als attacker, in ba_sub)
CREATE SUBSCRIPTION
 pg_sleep 
----------
 
(1 row)

 id | wert 
```

---

## Durchlauf 2 — nach Schicht 4

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/schicht4.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-dblink.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-fdw.sql
# kein Slot nötig: E3 scheitert schon an der Rechteprüfung, bevor der Slot gebraucht wird
docker compose exec -T pg-service psql -U attacker -d ba_sub  -f - < $V/e3-subscription.sql
```

**E1 dblink** — erwartet: `42501` bei `dblink_connect_u` (nur noch Superuser)

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-dblink.sql
## E1  dblink Selbst-Connect auf localhost  (als attacker, in ba_test)
psql:<stdin>:4: ERROR:  permission denied for function dblink_connect_u
psql:<stdin>:6: ERROR:  password or GSSAPI delegated credentials required
DETAIL:  Non-superusers must provide a password in the connection string or send delegated GSSAPI credentials.
psql:<stdin>:8: ERROR:  password or GSSAPI delegated credentials required
DETAIL:  Non-superusers must provide a password in the connection string or send delegated GSSAPI credentials.
psql:<stdin>:9: ERROR:  connection "c" not available
```

**E2 fdw** — erwartet: Fehler „user mapping not found for user attacker"

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-fdw.sql
## E2  postgres_fdw oeffentliches Mapping  (als attacker, in ba_test)
psql:<stdin>:5: ERROR:  user mapping not found for user "attacker", server "loop"
```

**E3 Subscription** — erwartet: Fehler, `pg_create_subscription` fehlt bzw. kein `CREATE` auf `ba_sub`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_sub  -f - < $V/e3-subscription.sql
## E3  Subscription als Empfaenger  (als attacker, in ba_sub)
psql:<stdin>:16: ERROR:  permission denied to create subscription
DETAIL:  Only roles with privileges of the "pg_create_subscription" role may create subscriptions.
 pg_sleep 
----------
 
(1 row)

 id | wert 
----+------
(0 rows)
```

---

## Durchlauf 3 — Schicht 6 (Dauer der Subscription)

Hier bleibt Schicht 4 weg. Die Subscription wird aufgebaut, dann zeigt
sich, dass ein Rechtentzug den laufenden Kanal nicht schließt und erst
das Beenden der Subscription wirkt.

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
# Slot vorab anlegen (gleiches Cluster, siehe Durchlauf 1)
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pg_create_logical_replication_slot('sub','pgoutput');"
docker compose exec -T pg-service psql -U attacker -d ba_sub  -f - < $V/e3-subscription.sql
```

**Beleg, dass der Kanal steht** — erwartet: eine Zeile, `active = t`

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT slot_name, active FROM pg_replication_slots;"
```

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT slot_name, active FROM pg_replication_slots;"

 slot_name | active 
-----------+--------
 sub       | t
(1 row)
```

**Rechtentzug auf der Publisher-Seite** (SELECT auf der publizierten Tabelle)

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "REVOKE SELECT ON oeffentlich FROM repl;"
```

**Kanal steht weiter** — erwartet: `active = t` unverändert

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT slot_name, active FROM pg_replication_slots;"
```

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "REVOKE SELECT ON oeffentlich FROM repl;"
REVOKE

nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT slot_name, active FROM pg_replication_slots;"
 slot_name | active 
-----------+--------
 sub       | t
(1 row)
```

**Und er liefert weiter** — neue Zeile beim Publisher, taucht trotz Entzug beim Empfänger auf

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "INSERT INTO oeffentlich VALUES (3,'drei');"
sleep 1
docker compose exec -T pg-service psql -U attacker -d ba_sub -c "SELECT * FROM oeffentlich ORDER BY id;"
```

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "INSERT INTO oeffentlich VALUES (3,'drei');"
sleep 1
docker compose exec -T pg-service psql -U attacker -d ba_sub -c "SELECT * FROM oeffentlich ORDER BY id;"
INSERT 0 1
 id | wert 
----+------
  1 | eins
  2 | zwei
  3 | drei
(3 rows)
```

**Schicht 6: Subscription beenden** (löscht zugleich den Slot auf der Gegenstelle)

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_sub -c "DROP SUBSCRIPTION sub;"
```

**Kanal ist weg** — erwartet: keine Zeile mehr

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT slot_name, active FROM pg_replication_slots;"
```

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_sub -c "DROP SUBSCRIPTION sub;"
NOTICE:  dropped replication slot "sub" on publisher
DROP SUBSCRIPTION

nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test \
  -c "SELECT slot_name, active FROM pg_replication_slots;"
 slot_name | active 
-----------+--------
(0 rows)
```

---

## Lesart

- E1 und E2 gelingen vorher und scheitern nach Schicht 4. Der Zugang
  nach außen wird an der Grenze geschlossen, nicht im Rechtemodell.
- E3 gelingt vorher und scheitert nach Schicht 4, solange die
  Subscription noch nicht steht. Steht sie aber (Durchlauf 3), greift
  Schicht 4 nicht mehr: der Rechtentzug lässt den Kanal laufen, weil die
  Rechte nur beim Aufbau geprüft werden. Erst Schicht 6 beendet ihn.
- Das ist die Kette aus dem Text: Schicht 4 verhindert den Aufbau,
  Schicht 5 macht die stehende Verbindung sichtbar (die
  `pg_replication_slots`-Abfragen), Schicht 6 reißt sie ab. Keine Schicht
  allein deckt den Vektor ab.