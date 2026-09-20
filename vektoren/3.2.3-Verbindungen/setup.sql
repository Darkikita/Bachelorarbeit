-- ============================================================
-- Vektor 3.2.3  Ausnutzung bestehender Verbindungen
-- Grundzustand (absichtlich unsicher). Laeuft als ba_admin.
-- Voraussetzung am Server: wal_level=logical (siehe README).
-- ============================================================

-- Extensions fuer die zwei Wege nach aussen
CREATE EXTENSION IF NOT EXISTS dblink;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- ---- Rollen ------------------------------------------------
CREATE ROLE attacker LOGIN PASSWORD 'attacker';
-- Replikationskonto, das die Subscription an der Gegenstelle nutzt
CREATE ROLE repl LOGIN REPLICATION PASSWORD 'repl';

-- ============================================================
-- E1  dblink: Selbst-Connect auf localhost
--     Fehlkonfiguration: dblink_connect_u fuer attacker freigegeben.
--     Damit umgeht attacker die Passwortpflicht und kommt ueber die
--     trust-Zeile fuer 127.0.0.1 als Superuser an.
-- ============================================================
GRANT EXECUTE ON FUNCTION dblink_connect_u(text, text) TO attacker;

-- ============================================================
-- E2  postgres_fdw: oeffentliches User Mapping
--     Fehlkonfiguration: USAGE fuer attacker, ein PUBLIC-Mapping auf
--     ba_admin mit password_required 'false'. Jede Rolle kommt darueber
--     als Superuser an der Gegenstelle an.
-- ============================================================
CREATE SERVER loop FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host '127.0.0.1', port '5432', dbname 'ba_test');
GRANT USAGE ON FOREIGN SERVER loop TO attacker;
CREATE USER MAPPING FOR PUBLIC SERVER loop
  OPTIONS (user 'ba_admin', password_required 'false');
CREATE FOREIGN TABLE ft_authid (rolname name)
  SERVER loop OPTIONS (schema_name 'pg_catalog', table_name 'pg_authid');
GRANT SELECT ON ft_authid TO attacker;

-- ============================================================
-- E3  Subscription: attacker als Empfaenger
--     Publisher-Seite hier in ba_test, Empfaenger in ba_sub.
--     Fehlkonfiguration: pg_create_subscription und CREATE auf ba_sub
--     fuer attacker.
-- ============================================================
CREATE TABLE oeffentlich (id int PRIMARY KEY, wert text);
INSERT INTO oeffentlich VALUES (1, 'eins'), (2, 'zwei');
CREATE PUBLICATION pub FOR TABLE oeffentlich;
GRANT SELECT ON oeffentlich TO repl;

GRANT pg_create_subscription TO attacker;

CREATE DATABASE ba_sub;
GRANT CREATE ON DATABASE ba_sub TO attacker;

-- Empfaengertabelle muss vorab bestehen (logische Replikation legt sie
-- nicht selbst an); attacker ist Eigentuemer, damit der Apply-Worker
-- (laeuft als Subscription-Eigentuemer) schreiben darf
\c ba_sub
CREATE TABLE oeffentlich (id int PRIMARY KEY, wert text);
ALTER TABLE oeffentlich OWNER TO attacker;