# Ergebnis T3: Darf eine CREATEROLE-Rolle ohne ADMIN OPTION eine vordefinierte Rolle vergeben?

PostgreSQL 17.10.

- frischer Container (`down -v`, `up -d --wait`)
- `setup.sql` vorab als `ba_admin`
- Terminal A: `t_creator` über `-h ba-test-pg`, `\set VERBOSITY verbose`
- Terminal B: `ba_admin` über den Socket

## Vorkontrolle (setup.sql)

```
$ docker compose exec -T pg-service psql -U ba_admin -d ba_test -f - < $V/setup.sql
                                                       version
----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 17.10 (Debian 17.10-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)

CREATE ROLE
CREATE TABLE
INSERT 0 1
GRANT
GRANT
CREATE ROLE
 roleid | member | admin_option
--------+--------+--------------
(0 rows)

 createrole_self_grant
-----------------------

(1 row)
```

`t_creator` startet ohne Mitgliedschaften, `createrole_self_grant`
ist leer.

## Ablauf

Schritt 1–2 (A):
```
ba_test=> \set VERBOSITY verbose
ba_test=> SELECT current_user;
 current_user
--------------
 t_creator
(1 row)
```

Schritt 3 (A), Versuch 1:
```
ba_test=> GRANT pg_read_server_files TO t_creator;
ERROR:  42501: permission denied to grant role "pg_read_server_files"
DETAIL:  Only roles with the ADMIN option on role "pg_read_server_files" may grant this role.
LOCATION:  check_role_membership_authorization, user.c:2156
```

Schritt 4 (A):
```
ba_test=> CREATE ROLE t_new LOGIN PASSWORD 'test';
CREATE ROLE
```

Schritt 5 (A), Versuch 2:
```
ba_test=> GRANT pg_read_server_files TO t_new;
ERROR:  42501: permission denied to grant role "pg_read_server_files"
DETAIL:  Only roles with the ADMIN option on role "pg_read_server_files" may grant this role.
LOCATION:  check_role_membership_authorization, user.c:2156
```

Schritt 6 (A), Versuch 3 (Kontrolle):
```
ba_test=> GRANT t_new TO t_creator WITH SET TRUE, INHERIT TRUE;
GRANT ROLE
```

Schritt 7 (B):
```
ba_test=# SELECT roleid::regrole, member::regrole, admin_option, inherit_option, set_option FROM pg_auth_members WHERE member IN ('t_creator'::regrole, 't_new'::regrole);
 roleid |  member   | admin_option | inherit_option | set_option
--------+-----------+--------------+----------------+------------
 t_new  | t_creator | t            | f              | f
 t_new  | t_creator | f            | t              | t
(2 rows)
```

Erste Zeile: automatische ADMIN OPTION aus `CREATE ROLE` (Schritt 4).
Zweite Zeile: ausdrücklicher Grant aus Schritt 6. Keine Zeile für
`pg_read_server_files`.

## Befund

| Versuch | wenn GRANT-Referenz gilt | wenn Kap. 21.5 gilt | Ergebnis |
|---|---|---|---|
| 1 | 42501 | GRANT ROLE | 42501 |
| 2 | 42501 | GRANT ROLE | 42501 |
| 3 | GRANT ROLE | GRANT ROLE | GRANT ROLE |

Die GRANT-Referenz gilt. Eine Rolle mit CREATEROLE, aber ohne ADMIN
OPTION auf einer vordefinierten Rolle kann diese weder sich selbst
noch einer selbst erzeugten Rolle gewähren. Die DETAIL-Zeile benennt
die Bedingung ausdrücklich. CREATEROLE selbst wirkt wie beschrieben:
Die erzeugte Rolle trägt die automatische ADMIN OPTION, und der
Selbst-Grant mit SET und INHERIT gelingt. Der Weg endet bei den selbst
erzeugten Rollen.


## Folge für den Text

Der CREATEROLE-Weg aus 3.2.2 endet bei den selbst erzeugten Rollen.
Vordefinierte Rollen erreicht er nicht, dafür braucht es die ADMIN
OPTION auf der jeweiligen Rolle oder den Superuser. Das steht so in
der GRANT-Referenz und ist durch Versuch 1 und 2 belegt.

Für Schicht 4 heißt das, dass CREATEROLE allein keine Serverrolle
verleiht. Die Grenze, die dort beschrieben wird, liegt bei der ADMIN
OPTION, nicht beim Attribut.

Kap. 21.5 der Dokumentation nennt Rollen mit CREATEROLE als mögliche
Vergebende vordefinierter Rollen. Das Verhalten in 17.10 und die
GRANT-Referenz derselben Version widersprechen dem. Der Satz in
Kap. 21.5 ist seit Version 14 unverändert und beschreibt das Modell
vor der Einschränkung von CREATEROLE in Version 16.

Schicht 2 ist durch das Ergebnis nicht betroffen. CREATEROLE bleibt
Verwaltungskonten vorbehalten, aber eine engere Fassung ist nicht
nötig, weil das Attribut nicht bis zum Server reicht.