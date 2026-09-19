# Ablauf 3.2.2 Rechteausweitung (händisch)

Alles aus `/home/nikita/docker/ba-test`. Einmal je Terminal setzen, dann
sind die Befehle kurz:

```bash
V=vektoren/3.2.2-Rechteausweitung
```

Drei Durchläufe, jeder mit frischem Volume. Verbindung im Container über
den Socket, die Rolle steckt im `-U`.

---

## Durchlauf 1 — vorher (nur Grundzustand)

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-hijack.sql
docker compose exec -T pg-service psql -U creator  -d ba_test -f - < $V/e2-createrole.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-adminoption.sql
docker compose exec -T pg-service psql -U app      -d ba_test -f - < $V/n1-nutzfall.sql
```

**E1 Hijack** — erwartet: `HIJACK: streng geheim`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-hijack.sql
## E1  search_path-Hijack, Weg 1  (als attacker)
CREATE FUNCTION
     pruef_zugriff     
-----------------------
 HIJACK: streng geheim
(1 row)
```

**E2 CREATEROLE** — erwartet: `CREATE ROLE`, `GRANT ROLE`, dann Grenze `42501` (pg_read_server_files)

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U creator  -d ba_test -f - < $V/e2-createrole.sql
## E2  CREATEROLE, Weg 2a  (als creator)
CREATE ROLE
GRANT ROLE
-- Grenze (vgl. T3): Serverrolle ohne ADMIN-Option nicht erreichbar
psql:<stdin>:6: ERROR:  permission denied to grant role "pg_read_server_files"
DETAIL:  Only roles with the ADMIN option on role "pg_read_server_files" may grant this role.
```

**E3 ADMIN-Option** — erwartet: `GRANT ROLE`, dann `geheim_zeilen = 1`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-adminoption.sql
## E3  ADMIN-Option, Weg 2b  (als attacker)
GRANT ROLE
 geheim_zeilen 
---------------
             1
(1 row)
```

**N1 Nutzfall** — erwartet: `ok`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U app      -d ba_test -f - < $V/n1-nutzfall.sql
## N1  Nutzfall  (als app)
 pruef_zugriff 
---------------
 ok
(1 row)
```

---

## Durchlauf 2 — nach Schicht 2

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/schicht2.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-hijack.sql
docker compose exec -T pg-service psql -U creator  -d ba_test -f - < $V/e2-createrole.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-adminoption.sql
docker compose exec -T pg-service psql -U app      -d ba_test -f - < $V/n1-nutzfall.sql
```

**E1 Hijack** — erwartet: weiter `HIJACK: streng geheim` (Schicht 2 schließt Weg 1 nicht)

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-hijack.sql
## E1  search_path-Hijack, Weg 1  (als attacker)
CREATE FUNCTION
     pruef_zugriff     
-----------------------
 HIJACK: streng geheim
(1 row)

DROP FUNCTION
```

**E2 CREATEROLE** — erwartet: `42501` schon beim `CREATE ROLE`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U creator  -d ba_test -f - < $V/e2-createrole.sql
## E2  CREATEROLE, Weg 2a  (als creator)
psql:<stdin>:3: ERROR:  permission denied to create role
DETAIL:  Only roles with the CREATEROLE attribute may create roles.
-- Grenze (vgl. T3): Serverrolle ohne ADMIN-Option nicht erreichbar
psql:<stdin>:4: ERROR:  role "neu" does not exist
psql:<stdin>:6: ERROR:  permission denied to grant role "pg_read_server_files"
DETAIL:  Only roles with the ADMIN option on role "pg_read_server_files" may grant this role.
```

**E3 ADMIN-Option** — erwartet: `42501` beim `GRANT`, dann `42501` beim Lesen

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-adminoption.sql
## E3  ADMIN-Option, Weg 2b  (als attacker)
psql:<stdin>:3: ERROR:  permission denied to grant role "grp_priv"
DETAIL:  Only roles with the ADMIN option on role "grp_priv" may grant this role.
psql:<stdin>:5: ERROR:  permission denied for table geheim
```

**N1 Nutzfall** — erwartet: `ok`

```
nikita@nikitaserver:~/docker/ba-test$ docker compose exec -T pg-service psql -U app      -d ba_test -f - < $V/n1-nutzfall.sql
## N1  Nutzfall  (als app)
 pruef_zugriff 
---------------
 ok
(1 row)
```

---

## Durchlauf 3 — nach Schicht 3

```bash
docker compose down -v && docker compose up -d --wait
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/schicht3.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e1-hijack.sql
docker compose exec -T pg-service psql -U creator  -d ba_test -f - < $V/e2-createrole.sql
docker compose exec -T pg-service psql -U attacker -d ba_test -f - < $V/e3-adminoption.sql
docker compose exec -T pg-service psql -U app      -d ba_test -f - < $V/n1-nutzfall.sql
```

**E1 Hijack** — erwartet: `ok` (fester Suchpfad schließt Weg 1)

```
[Ergebnis eintragen]
```

**E2 CREATEROLE** — erwartet: weiter `CREATE ROLE`, `GRANT ROLE`, Grenze `42501` (Schicht 3 greift hier nicht)

```
[Ergebnis eintragen]
```

**E3 ADMIN-Option** — erwartet: weiter `GRANT ROLE`, `geheim_zeilen = 1`

```
[Ergebnis eintragen]
```

**N1 Nutzfall** — erwartet: `ok`

```
[Ergebnis eintragen]
```

---

## Lesart

- E1 gelingt vorher und nach Schicht 2, scheitert erst nach Schicht 3.
  Das zeigt: Schicht 3 greift bei Weg 1, wo Schicht 2 versagt.
- E2 und E3 scheitern nach Schicht 2, gelingen aber weiter nach Schicht 3.
  Spiegelbildlich: Schicht 2 greift bei Weg 2, wo Schicht 3 versagt.
- N1 bleibt überall `ok`, keine Schicht sperrt den regulären Aufruf.