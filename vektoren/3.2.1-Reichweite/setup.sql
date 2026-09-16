-- Grundfall aus 3.2.1, absichtlich unsicher. Als ba_admin.

-- Rollen
CREATE ROLE app_over  LOGIN PASSWORD 'app_over';
CREATE ROLE app_owner NOLOGIN;
CREATE ROLE attacker  LOGIN PASSWORD 'attacker';
CREATE ROLE admin_cr  LOGIN PASSWORD 'admin_cr' CREATEROLE;
CREATE ROLE grp_read  NOLOGIN;
CREATE ROLE grp_mid   NOLOGIN;

-- Voreinstellung bis PG 14 nachstellen, Vorher-Zustand für 3.2.2
GRANT CREATE ON SCHEMA public TO PUBLIC;

-- Anwendungsrolle legt das Schema selbst an und besitzt alles
SET ROLE app_over;
CREATE TABLE kunden (id int PRIMARY KEY, name text, iban text);
CREATE TABLE intern (id int PRIMARY KEY, notiz text);
INSERT INTO kunden
  SELECT g, 'Kunde ' || g, 'DE' || lpad(g::text, 20, '0') FROM generate_series(1, 20) g;
INSERT INTO intern
  SELECT g, 'Notiz ' || g FROM generate_series(1, 10) g;
CREATE FUNCTION f() RETURNS text LANGUAGE sql AS $$ SELECT 'aufgerufen'::text $$;
RESET ROLE;

-- Kette von Mitgliedschaften, INHERIT ist Voreinstellung
GRANT SELECT ON intern TO grp_read;
GRANT grp_read TO grp_mid;
GRANT grp_mid  TO attacker;