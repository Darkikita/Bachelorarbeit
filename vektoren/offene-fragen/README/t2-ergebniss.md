# Ergebnis T2: Wirkt REVOKE in einer laufenden Sitzung sofort?

PostgreSQL 17.10.

- frischer Container (`down -v`, `up -d --wait`)
- `setup.sql` vorab als `ba_admin`
- Terminal A: `t_victim` über `-h ba-test-pg`, `\set VERBOSITY verbose`
- Terminal B: `ba_admin` über den Socket

## Teil 1: außerhalb einer Transaktion

Schritt 1–2 (A):
```
ba_test=> \set VERBOSITY verbose
ba_test=> SELECT version();
                                                       version
----------------------------------------------------------------------------------------------------------------------
 PostgreSQL 17.10 (Debian 17.10-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
(1 row)
```

Schritt 3 (A):
```
ba_test=> SELECT * FROM t_data;
 id
----
  1
(1 row)
```

Schritt 4 (B):
```
ba_test=# REVOKE SELECT ON t_data FROM t_victim;
REVOKE
```

Schritt 5 (A):
```
ba_test=> SELECT * FROM t_data;
ERROR:  42501: permission denied for table t_data
LOCATION:  aclcheck_error, aclchk.c:2843
```

## Teil 2: innerhalb einer offenen Transaktion

Schritt 6 (B):
```
ba_test=# GRANT SELECT ON t_data TO t_victim;
GRANT
```

Schritt 7–9 (A):
```
ba_test=> SELECT * FROM t_data;
 id
----
  1
(1 row)

ba_test=> BEGIN;
BEGIN
ba_test=*> SELECT * FROM t_data;
 id
----
  1
(1 row)
```

Schritt 10 (B):
```
ba_test=# REVOKE SELECT ON t_data FROM t_victim;
REVOKE
```

Schritt 11 (A, in der Transaktion):
```
ba_test=*> SELECT * FROM t_data;
ERROR:  42501: permission denied for table t_data
LOCATION:  aclcheck_error, aclchk.c:2843
```

Schritt 12 (A):
```
ba_test=!> COMMIT;
ROLLBACK
```

Schritt 13 (A):
```
ba_test=> SELECT * FROM t_data;
ERROR:  42501: permission denied for table t_data
LOCATION:  aclcheck_error, aclchk.c:2843
```

## Befund

| Schritt | Erwartung | Ergebnis |
|---|---|---|
| 5 | 42501 | bestätigt |
| 11 | 1 Zeile oder 42501 | 42501 |
| 12 | ROLLBACK, wenn 11 scheiterte | bestätigt |
| 13 | 42501 | bestätigt |

REVOKE wirkt sofort auf die laufende Sitzung, ohne neue Anmeldung.
Die Prüfung erfolgt je Anweisung, auch innerhalb einer bereits
begonnenen Transaktion; die Transaktion wird dadurch abgebrochen und
kann nur noch zurückgerollt werden.

## Folge für den Text

3.2.5: "Ob ein REVOKE in einer laufenden gewöhnlichen Sitzung sofort
wirkt, wird im praktischen Teil geprüft" wird zur Feststellung, mit
dem Zusatz "auch innerhalb einer offenen Transaktion". Der Unterschied
zur Replikation, deren Rechte nur beim Verbindungsaufbau geprüft
werden (Kap. 29.10), ist damit belegt. Keine Auswirkung auf Schicht 6.