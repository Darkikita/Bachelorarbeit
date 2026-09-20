# Befund: Passwortpflicht bei Subscriptions von Nicht-Superusern

## Einleitung

Beim ersten Durchlauf von Vektor 3.2.3 scheiterte E3, während E1 und E2
gelangen. Ursache ist ein Standardschutz von PostgreSQL, der im
Vektortext bis dahin nur für `dblink` und `postgres_fdw` benannt war:
Eine Subscription, die eine Nicht-Superuser-Rolle anlegt, verlangt eine
passwortauthentifizierte Verbindung zur Gegenstelle. Die
Verbindungszeichenkette muss ein Passwort enthalten, und die Anmeldung
muss es tatsächlich verwenden. Eine `trust`-Zeile, wie sie für
`127.0.0.1` gilt, reicht deshalb nicht. Der Testaufbau nutzte zunächst
genau diese trust-Verbindung und wurde abgewiesen.

## Befehl

```bash
docker compose exec -T pg-service psql -U attacker -d ba_sub -f - < $V/e3-subscription.sql
```

Verbindung im Skript zu diesem Zeitpunkt:

```
CONNECTION 'host=127.0.0.1 port=5432 dbname=ba_test user=repl'
```

## Ausgabe

```
## E3  Subscription als Empfaenger  (als attacker, in ba_sub)
psql:<stdin>:6: ERROR:  password is required
DETAIL:  Non-superusers must provide a password in the connection string.
 pg_sleep
----------

(1 row)

 id | wert
----+------
(0 rows)
```

## Ursache

Referenz `CREATE SUBSCRIPTION`, Parameter `password_required` (Default
`true`): Verbindungen der Subscription müssen Passwortauthentifizierung
verwenden und das Passwort in der Verbindungszeichenkette führen. Die
Prüfung wird nur übergangen, wenn die Subscription einem Superuser
gehört; nur ein Superuser kann sie mit `password_required = false`
abschalten (PostgreSQL 17, Referenzseite CREATE SUBSCRIPTION).

## Änderung

Die Verbindung wurde von der trust-Loopback-Adresse auf den Hostnamen
`ba-test-pg` umgestellt, der die `scram`-Zeile trifft, und um das
Passwort des Replikationskontos ergänzt:

```
CONNECTION 'host=ba-test-pg port=5432 dbname=ba_test user=repl password=repl'
```

Danach läuft E3 wie erwartet: `CREATE SUBSCRIPTION`, Erstkopie, und die
publizierten Zeilen erscheinen in `ba_sub`. Der Befund selbst bleibt
erhalten und ist als Absatz in 3.2.3 eingearbeitet: der Standardschutz
gegen die Verbindung zurück auf einen trust-erreichbaren Server gilt auch
für die Subscription, nicht nur für `dblink` und `postgres_fdw`.