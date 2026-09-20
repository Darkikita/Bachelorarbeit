# Ablauf 3.2.5 Fortbestand über die Entdeckung hinaus (händisch)

Vier Versuche zu Schicht 5 (Erkennung) und Schicht 6 (Reaktion). Alle
Befehle aus dem Verzeichnis der Testumgebung
(`/home/nikita/docker/ba-test`). Pfadabkürzung je Terminal:

```bash
V=vektoren/3.2.5-Fortbestand
```

T1 und T2 brauchen zwei Terminals: eines hält eine Sitzung offen
(Terminal A), das andere greift als Administrator ein (Terminal B). T3
und T4 laufen in einem Terminal. Jeder Versuch beginnt mit frischem
Volume.

---

## T1 — Die Sitzung überdauert Passwortwechsel und Sperrung

Grundzustand:

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup-session.sql
```

**Terminal A** — Sitzung als `victim` öffnen und offen halten:

```bash
docker compose exec -it pg-service psql -U victim -d ba_test
```

Darin:

```sql
SELECT count(*) FROM daten;  
```

```sql
ba_test=> SELECT count(*) FROM daten;
 count 
-------
     3
(1 row) 
```

**Terminal B** — Passwort wechseln, dann neue Anmeldung mit altem Passwort:

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "ALTER ROLE victim PASSWORD 'neu';"
docker compose exec -T -e PGPASSWORD=victim pg-service psql -h ba-test-pg -U victim -d ba_test -c "SELECT 1;"
```

Die neue Anmeldung scheitert mit `password authentication failed`.

```bash
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T -e PGPASSWORD=victim pg-service psql -h ba-test-pg -U victim -d ba_test -c "SELECT 1;"
psql: error: connection to server at "ba-test-pg" (172.18.0.2), port 5432 failed: FATAL:  password authentication failed for user "victim"
```


**Terminal A** — dieselbe offene Sitzung:

```sql
SELECT count(*) FROM daten;   -- erwartet: weiter 3, die Sitzung lebt
```

**Terminal B** — Rolle sperren, dann neue Anmeldung:

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "ALTER ROLE victim NOLOGIN;"
docker compose exec -T pg-service psql -U victim -d ba_test -c "SELECT 1;"
```

Die neue Anmeldung scheitert mit `role "victim" is not permitted to log in`.

```sql
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U victim -d ba_test -c "SELECT 1;"
psql: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: FATAL:  role "victim" is not permitted to log in
```

**Terminal A**:

```sql
SELECT count(*) FROM daten;   
```

```sql
ba_test=> SELECT count(*) FROM daten;
 count 
-------
     3
(1 row)
```

**Terminal B** — die offene Sitzung sichtbar machen (Schicht 5) und beenden (Schicht 6):

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pid, usename, state FROM pg_stat_activity WHERE usename='victim';"
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename='victim';"
```

```sql
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pid, usename, state FROM pg_stat_activity WHERE usename='victim';"
 pid | usename | state 
-----+---------+-------
  96 | victim  | idle
(1 row)

nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename='victim';"
 pg_terminate_backend 
----------------------
 t
(1 row)
```

**Terminal A** — nächste Abfrage:

```sql
SELECT count(*) FROM daten;   -- erwartet: Verbindung beendet (terminating connection due to administrator command)
```

```
ba_test=> SELECT count(*) FROM daten;
FATAL:  terminating connection due to administrator command
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
The connection to the server was lost. Attempting reset: Failed.
```

---

## T2 — Der Rechteentzug wirkt sofort

Grundzustand:

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup-session.sql
```

**Terminal A** — Sitzung als `victim`, Transaktion beginnen:

```bash
docker compose exec -it pg-service psql -U victim -d ba_test
```

```sql
BEGIN;
SELECT count(*) FROM daten;  
```

```sql
ba_test=> BEGIN;
SELECT count(*) FROM daten;
BEGIN
 count 
-------
     3
(1 row)
```

**Terminal B** — Recht entziehen:

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -c "REVOKE SELECT ON daten FROM victim;"
```

**Terminal A** — nächste Abfrage in derselben Transaktion:

```sql
SELECT count(*) FROM daten;  
```

permission denied for table daten, Transaktion abgebrochen

```
ba_test=*> SELECT count(*) FROM daten;
ERROR:  permission denied for table daten
```

---

## T3 — DROP ROLE überdauert die Sperrung

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup-persistenz.sql
docker compose exec -T pg-service psql -U attacker  -d ba_test -f - < $V/t-anlegen.sql
docker compose exec -T pg-service psql -U ba_admin  -d ba_test -f - < $V/t3-reaktion.sql
```

Erwartet in `t3-reaktion`: das erste `DROP ROLE` scheitert (die Rolle
besitzt die Funktion und ihr Schema), dann `DROP OWNED`, dann `DROP ROLE`
erfolgreich.

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin  -d ba_test -f - < $V/t3-reaktion.sql
## T3  Reaktion  (als ba_admin)
-- Direktes Entfernen scheitert, solange die Rolle Objekte besitzt:
psql:<stdin>:3: ERROR:  role "attacker" cannot be dropped because some objects depend on it
DETAIL:  owner of schema attacker
owner of function attacker.hintertuer()
-- Korrekt: erst Objekte und Rechte der Rolle entfernen ...
DROP OWNED
-- ... dann die Rolle:
DROP ROLE
```

---

## T4 — Standardmäßig wird nichts aufgezeichnet

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup-persistenz.sql
```

Standardzustand der Parameter:

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/t4-vorher.sql
```

Ergebniss: `off`, `off`, `none`.

```sql
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/t4-vorher.sql
## T4  Standardzustand der Protokollierung  (als ba_admin)
 log_connections 
-----------------
 off
(1 row)

 log_disconnections 
--------------------
 off
(1 row)

 log_statement 
---------------
 none
(1 row)
```

Angreifer legt Code an, danach ins Protokoll sehen:

```bash
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/t-anlegen.sql
docker compose logs --tail 20 pg-service
```

Ergebniss: keine Zeile über das `CREATE FUNCTION` oder die Verbindung.

```bash
nikita@nikitaserver:~/docker/ba-test$ docker compose logs --tail 20 pg-service
ba-test-pg  | /usr/local/bin/docker-entrypoint.sh: ignoring /docker-entrypoint-initdb.d/*
ba-test-pg  | 
ba-test-pg  | 2026-09-20 00:49:55.009 UTC [48] LOG:  received fast shutdown request
ba-test-pg  | waiting for server to shut down....2026-09-20 00:49:55.011 UTC [48] LOG:  aborting any active transactions
ba-test-pg  | 2026-09-20 00:49:55.013 UTC [48] LOG:  background worker "logical replication launcher" (PID 54) exited with exit code 1
ba-test-pg  | 2026-09-20 00:49:55.013 UTC [49] LOG:  shutting down
ba-test-pg  | 2026-09-20 00:49:55.014 UTC [49] LOG:  checkpoint starting: shutdown immediate
ba-test-pg  | 2026-09-20 00:49:55.054 UTC [49] LOG:  checkpoint complete: wrote 925 buffers (5.6%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.015 s, sync=0.023 s, total=0.041 s; sync files=301, longest=0.002 s, average=0.001 s; distance=4256 kB, estimate=4256 kB; lsn=0/1915A18, redo lsn=0/1915A18
ba-test-pg  | 2026-09-20 00:49:55.058 UTC [48] LOG:  database system is shut down
ba-test-pg  |  done
ba-test-pg  | server stopped
ba-test-pg  | 
ba-test-pg  | PostgreSQL init process complete; ready for start up.
ba-test-pg  | 
ba-test-pg  | 2026-09-20 00:49:55.142 UTC [1] LOG:  starting PostgreSQL 17.10 (Debian 17.10-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
ba-test-pg  | 2026-09-20 00:49:55.142 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
ba-test-pg  | 2026-09-20 00:49:55.143 UTC [1] LOG:  listening on IPv6 address "::", port 5432
ba-test-pg  | 2026-09-20 00:49:55.147 UTC [1] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
ba-test-pg  | 2026-09-20 00:49:55.154 UTC [64] LOG:  database system was shut down at 2026-09-20 00:49:55 UTC
ba-test-pg  | 2026-09-20 00:49:55.162 UTC [1] LOG:  database system is ready to accept connections
```

Schicht 5 einschalten, dann dasselbe noch einmal:

```bash
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/t4-einschalten.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/t-anlegen.sql
docker compose logs --tail 20 pg-service
```

Erwartet: jetzt eine Verbindungszeile (`connection received`/`authorized`)
und eine Anweisungszeile (`statement: CREATE OR REPLACE FUNCTION ...`).

```
nikita@nikitaserver:~/docker/ba-test$ docker compose logs --tail 20 pg-service
ba-test-pg  | 2026-09-20 00:49:55.142 UTC [1] LOG:  starting PostgreSQL 17.10 (Debian 17.10-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
ba-test-pg  | 2026-09-20 00:49:55.142 UTC [1] LOG:  listening on IPv4 address "0.0.0.0", port 5432
ba-test-pg  | 2026-09-20 00:49:55.143 UTC [1] LOG:  listening on IPv6 address "::", port 5432
ba-test-pg  | 2026-09-20 00:49:55.147 UTC [1] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
ba-test-pg  | 2026-09-20 00:49:55.154 UTC [64] LOG:  database system was shut down at 2026-09-20 00:49:55 UTC
ba-test-pg  | 2026-09-20 00:49:55.162 UTC [1] LOG:  database system is ready to accept connections
ba-test-pg  | 2026-09-20 00:53:35.066 UTC [1] LOG:  received SIGHUP, reloading configuration files
ba-test-pg  | 2026-09-20 00:53:35.066 UTC [1] LOG:  parameter "log_connections" changed to "on"
ba-test-pg  | 2026-09-20 00:53:35.066 UTC [1] LOG:  parameter "log_disconnections" changed to "on"
ba-test-pg  | 2026-09-20 00:53:35.066 UTC [1] LOG:  parameter "log_statement" changed to "ddl"
ba-test-pg  | 2026-09-20 00:53:41.532 UTC [289] LOG:  connection received: host=[local]
ba-test-pg  | 2026-09-20 00:53:41.533 UTC [289] LOG:  connection authenticated: user="ba_admin" method=trust (/var/lib/postgresql/data/pg_hba.conf:117)
ba-test-pg  | 2026-09-20 00:53:41.533 UTC [289] LOG:  connection authorized: user=ba_admin database=ba_test application_name=pg_isready
ba-test-pg  | 2026-09-20 00:53:41.534 UTC [289] LOG:  disconnection: session time: 0:00:00.001 user=ba_admin database=ba_test host=[local]
ba-test-pg  | 2026-09-20 00:53:43.147 UTC [296] LOG:  connection received: host=[local]
ba-test-pg  | 2026-09-20 00:53:43.148 UTC [296] LOG:  connection authenticated: user="attacker" method=trust (/var/lib/postgresql/data/pg_hba.conf:117)
ba-test-pg  | 2026-09-20 00:53:43.148 UTC [296] LOG:  connection authorized: user=attacker database=ba_test application_name=psql
ba-test-pg  | 2026-09-20 00:53:43.149 UTC [296] LOG:  statement: CREATE OR REPLACE FUNCTION attacker.hintertuer() RETURNS text
ba-test-pg  |     LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'code des angreifers'::text $$;
ba-test-pg  | 2026-09-20 00:53:43.151 UTC [296] LOG:  disconnection: session time: 0:00:00.004 user=attacker database=ba_test host=[local]
```

### Was vorher fehlte und nachher da ist

Vorher, im Standard, endet das Protokoll nach dem `CREATE FUNCTION` mit
den Startmeldungen des Servers, ohne eine Zeile über die Aktion:

```
... LOG:  database system is ready to accept connections
```

Nachher, nach `ALTER SYSTEM` und Reload, hinterlässt dieselbe Ausführung
diese Zeilen, die vorher nicht da waren:

```
LOG:  connection authorized: user=attacker database=ba_test application_name=psql
LOG:  statement: CREATE OR REPLACE FUNCTION attacker.hintertuer() ...
LOG:  disconnection: session time: 0:00:00.004 user=attacker database=ba_test
```

Dieselbe `CREATE FUNCTION`-Ausführung bleibt vorher spurlos und
hinterlässt nachher drei Spuren: die Anmeldung von `attacker`, die
Anweisung selbst und das Ende der Sitzung. Die `attacker`-Zeilen sind
maßgeblich; eine zusätzliche Verbindungszeile im Log gehört zu
`pg_isready` aus dem Healthcheck.


---

## Lesart

- T1: Eine bestehende Sitzung überdauert Passwortwechsel und `NOLOGIN`,
  weil beide erst beim nächsten Verbindungsaufbau wirken. Neue Anmeldungen
  scheitern, die offene läuft weiter, und erst `pg_terminate_backend`
  beendet sie. Das ist Schicht 6, Schritt 1, sichtbar über Schicht 5
  (`pg_stat_activity`).
- T2: Der Rechteentzug erreicht die laufende Sitzung dagegen sofort, auch
  mitten in einer Transaktion. Er wird bei jeder Anweisung geprüft, anders
  als die einmal geprüfte Replikationsverbindung aus 3.2.3.
- T3: Die Sperrung einer Rolle trifft nur die Rolle. Ihr Code bleibt, und
  `DROP ROLE` scheitert, solange sie Objekte besitzt. Erst `DROP OWNED`
  bzw. `REASSIGN OWNED` je Datenbank macht sie entfernbar. Schicht 6,
  Schritt 4.
- T4: In der Voreinstellung zeichnet der Server weder Verbindungen noch
  Anweisungen auf, es gibt also nichts zu entfernen und nichts zu finden.
  Der Fortbestand ist der Voreinstellung geschuldet. Schicht 5 schaltet
  die Aufzeichnung ein, danach erscheint der hinterlassene Zustand als
  Zeile im Protokoll in dem Moment, in dem er entsteht.