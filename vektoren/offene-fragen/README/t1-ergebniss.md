# Ergebnis T1: Überlebt eine offene Sitzung Passwortwechsel und NOLOGIN?

PostgreSQL 17.10

- frischer Container (`down -v`, `up -d --wait`)
- `setup.sql` vorab als `ba_admin`
- Terminal A: `t_victim` über `-h ba-test-pg` (Passwort `alt`)
- Terminal B: `ba_admin` über den Socket
- Terminal C: neue Anmeldungen über `-h ba-test-pg`

Anmeldung über den Container-Namen, weil die `pg_hba.conf` des Images
für Socket, `127.0.0.1/32` und `::1/128` `trust` setzt und nur die
Zeile `host all all all scram-sha-256` das Passwort prüft. Ein erster
Lauf über `127.0.0.1` hatte deshalb in Terminal C keine
Passwortprüfung und wurde verworfen.

## Schritt 1 (A): Version

```
ba_test=> SELECT version();
                                                       version
----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 17.10 (Debian 17.10-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)
```

## Schritt 2 (A): Ausgangszustand

```
ba_test=> SELECT * FROM t_data;
 id
----
  1
(1 row)
```

## Schritt 3 (B): Passwort wechseln

```
ba_test=# ALTER ROLE t_victim PASSWORD 'neu';
ALTER ROLE
```

## Schritt 4 (A): Abfrage nach Passwortwechsel

```
ba_test=> SELECT * FROM t_data;
 id
----
  1
(1 row)
```

Sitzung lebt.

## Schritt 5 (B): Anmelderecht entziehen

```
ba_test=# ALTER ROLE t_victim NOLOGIN;
ALTER ROLE
```

## Schritt 6 (A): Abfrage nach NOLOGIN

```
ba_test=> SELECT * FROM t_data;
 id
----
  1
(1 row)
```

Sitzung lebt.

## Schritt 7 (B): Sitzung finden

```
ba_test=# SELECT pid, usename, state FROM pg_stat_activity WHERE usename = 't_victim';
 pid | usename  | state
-----+----------+-------
  91 | t_victim | idle
(1 row)
```

## Schritt 8 (B): Sitzung beenden

```
ba_test=# SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 't_victim';
 pg_terminate_backend
----------------------
 t
(1 row)
```

## Schritt 9 (A): Abfrage nach Terminate

```
ba_test=> SELECT * FROM t_data;
FATAL:  terminating connection due to administrator command
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
The connection to the server was lost. Attempting reset: Failed.
The connection to the server was lost. Attempting reset: Failed.
!?>
```

Sitzung beendet. Der automatische Neuverbindungsversuch von psql
scheitert, weil die Rolle inzwischen NOLOGIN hat.

## Terminal C: neue Anmeldung

Kontrolle, dass über `ba-test-pg` das Passwort geprüft wird:

```
$ docker compose exec -e PGPASSWORD=falsch pg-service psql -h ba-test-pg -U ba_admin -d ba_test -c 'SELECT 1'
psql: error: connection to server at "ba-test-pg" (172.18.0.2), port 5432 failed: FATAL:  password authentication failed for user "ba_admin"
```

Altes Passwort:

```
$ docker compose exec -e PGPASSWORD=alt pg-service psql -h ba-test-pg -U t_victim -d ba_test -c 'SELECT 1'
psql: error: connection to server at "ba-test-pg" (172.18.0.2), port 5432 failed: FATAL:  password authentication failed for user "t_victim"
```

Neues Passwort:

```
$ docker compose exec -e PGPASSWORD=neu pg-service psql -h ba-test-pg -U t_victim -d ba_test -c 'SELECT 1'
psql: error: connection to server at "ba-test-pg" (172.18.0.2), port 5432 failed: FATAL:  role "t_victim" is not permitted to log in
```

## Befund

| Schritt | Erwartung | Ergebnis |
|---|---|---|
| 4 | Sitzung lebt | bestätigt |
| 6 | Sitzung lebt | bestätigt |
| 9 | `terminating connection due to administrator command` | bestätigt, Wortlaut identisch |
| C Kontrolle | `password authentication failed for user "ba_admin"` | bestätigt |
| C alt | `password authentication failed for user "t_victim"` | bestätigt |
| C neu | `role "t_victim" is not permitted to log in` | bestätigt |

Passwortwechsel und NOLOGIN beenden eine offene Sitzung nicht. Erst
`pg_terminate_backend` tut es. Eine neue Anmeldung scheitert mit dem
alten Passwort an der Passwortprüfung und mit dem neuen an NOLOGIN;
PostgreSQL prüft das Passwort vor dem Anmelderecht.

## Folge für den Text

3.2.5: Der Satz "Ob eine solche Sitzung den Passwortwechsel
überdauert, sagt die Dokumentation nicht ausdrücklich, weshalb die
Frage in Kapitel 5 geprüft wird" wird zu "Eine solche Sitzung
überdauert den Passwortwechsel und die Sperrung, wie Kapitel 5
zeigt". Schicht 6 behält die Reihenfolge "erst Sitzungen beenden,
dann Credential entwerten" als belegt.