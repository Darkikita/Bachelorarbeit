# Ablauf 3.2.4 Ausbruch aus der Datenbank (händisch)

Kein zweiter Server, keine Konfigänderung, eine Datenbank. Alle Befehle
werden aus dem Verzeichnis der Testumgebung
(`/home/nikita/docker/ba-test`) ausgeführt. Die Pfadabkürzung wird je
Terminal einmal gesetzt:

```bash
V=vektoren/3.2.4-Ausbruch
```

Zwei Durchläufe, jeder mit frischem Volume.

---

## Durchlauf 1 — vorher (nur Grundzustand)

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-read.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-write.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-program.sql
```

**E1 Lesen** — erwartet: ein Auszug aus `pg_hba.conf`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-read.sql
## E1  Serverdatei lesen  (pg_read_server_files, als attacker)
CREATE TABLE
COPY 128
                                 zeile                                 
-----------------------------------------------------------------------
 # PostgreSQL Client Authentication Configuration File
 # ===================================================
 #
 # Refer to the "Client Authentication" section in the PostgreSQL
 # documentation for a complete description of this file.  A short
 # synopsis follows.
 #
 # ----------------------
 # Authentication Records
 # ----------------------
 #
 # This file controls: which hosts are allowed to connect, how clients
 # are authenticated, which PostgreSQL user names they can use, which
 # databases they can access.  Records take one of these forms:
 #
(15 rows)
```

**E2 Schreiben** — erwartet: `COPY 1`, dann der zurückgelesene Inhalt `HIJACK durch attacker`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-write.sql
## E2  Serverdatei schreiben  (pg_write_server_files, als attacker)
COPY 1
CREATE TABLE
COPY 1
        inhalt         
-----------------------
 HIJACK durch attacker
(1 row)
```

**E3 Programm** — erwartet: die Ausgabe von `id`, ausgeführt als `postgres`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-program.sql
## E3  Programm ausfuehren  (pg_execute_server_program, als attacker)
CREATE TABLE
COPY 1
                            ausgefuehrt_als                             
------------------------------------------------------------------------
 uid=999(postgres) gid=999(postgres) groups=999(postgres),101(ssl-cert)
(1 row)
```

---

## Durchlauf 2 — nach Schicht 4

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/schicht4.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-read.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-write.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-program.sql
```

**E1 Lesen** — erwartet: `42501`, Mitgliedschaft in `pg_read_server_files` nötig (`COPY from a file`)

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-read.sql
## E1  Serverdatei lesen  (pg_read_server_files, als attacker)
CREATE TABLE
psql:<stdin>:8: ERROR:  permission denied to COPY from a file
DETAIL:  Only roles with privileges of the "pg_read_server_files" role may COPY from a file.
HINT:  Anyone can COPY to stdout or from stdin. psql's \copy command also works for anyone.
 zeile 
-------
(0 rows)
```

**E2 Schreiben** — erwartet: `42501`, Mitgliedschaft in `pg_write_server_files` nötig

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e2-write.sql
## E2  Serverdatei schreiben  (pg_write_server_files, als attacker)
psql:<stdin>:3: ERROR:  permission denied to COPY to a file
DETAIL:  Only roles with privileges of the "pg_write_server_files" role may COPY to a file.
HINT:  Anyone can COPY to stdout or from stdin. psql's \copy command also works for anyone.
CREATE TABLE
psql:<stdin>:6: ERROR:  permission denied to COPY from a file
DETAIL:  Only roles with privileges of the "pg_read_server_files" role may COPY from a file.
HINT:  Anyone can COPY to stdout or from stdin. psql's \copy command also works for anyone.
 inhalt 
--------
(0 rows)
```

**E3 Programm** — erwartet: `42501`, Mitgliedschaft in `pg_execute_server_program` nötig

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-program.sql
## E3  Programm ausfuehren  (pg_execute_server_program, als attacker)
CREATE TABLE
psql:<stdin>:5: ERROR:  permission denied to COPY to or from an external program
DETAIL:  Only roles with privileges of the "pg_execute_server_program" role may COPY to or from an external program.
HINT:  Anyone can COPY to stdout or from stdin. psql's \copy command also works for anyone.
 ausgefuehrt_als 
-----------------
(0 rows)
```

---

## Lesart

- Alle drei Wege gelingen vorher und scheitern nach Schicht 4. Der
  Ausbruch hängt allein an der Vergabe der Serverrollen; werden sie
  entzogen, ist er zu.
- E3 zeigt, dass das Kommando als der Betriebssystemnutzer `postgres`
  läuft, nicht als die Datenbankrolle. Kein `GRANT` oder `REVOKE` auf
  Tabellen ändert daran etwas, die Rechteprüfung wird umgangen, nicht
  verletzt.
- E1 und E2 belegen zusammen den im Text beschriebenen Weg zur zweiten
  Stufe: `pg_hba.conf` ist les- und schreibbar, woraus sich die
  Authentifizierung umbiegen ließe. Dieser Schritt selbst bleibt im
  Text, um die laufende Serverkonfiguration nicht zu verändern.