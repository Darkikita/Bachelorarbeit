-- ============================================================
-- Vektor 3.2.2  Rechteausweitung  Grundzustand (absichtlich unsicher)
-- Laeuft als ba_admin in ba_test
-- ============================================================

-- PUBLIC darf im Schema public Objekte anlegen
-- (Vorher-Zustand, wie voreingestellt bis PostgreSQL 14;
--  Schicht 2 nimmt das flankierend zurueck)
GRANT CREATE ON SCHEMA public TO PUBLIC;

-- ---- Rollen ------------------------------------------------
CREATE ROLE victim_owner NOLOGIN;                          -- privilegierter Eigentuemer
CREATE ROLE attacker  LOGIN PASSWORD 'attacker';           -- Weg 1 und Weg 2b
CREATE ROLE creator   LOGIN PASSWORD 'creator' CREATEROLE; -- Weg 2a
CREATE ROLE grp_priv  NOLOGIN;                             -- privilegierte Gruppe
CREATE ROLE app       LOGIN PASSWORD 'app';                -- regulaerer Aufrufer (Nutzfall)

-- Gemeinsames Schema, fuer jede Rolle beschreibbar, und im Suchpfad
-- der Datenbank noch vor public. Das ist die erste Voraussetzung des
-- Angriffs: ein beschreibbares Schema, das vor dem Ziel durchsucht wird.
-- Anders als "$user" gilt es unabhaengig davon, welche Rolle die
-- Funktion gerade ausfuehrt, also auch fuer die SECURITY-DEFINER-Sitzung.
CREATE SCHEMA shared;
GRANT USAGE, CREATE ON SCHEMA shared TO PUBLIC;
ALTER DATABASE ba_test SET search_path = shared, public;

-- ---- Geheime Daten -----------------------------------------
CREATE TABLE geheim (id int, wert text);
INSERT INTO geheim VALUES (1, 'streng geheim');
ALTER TABLE geheim OWNER TO victim_owner;

-- grp_priv darf lesen; attacker ist Mitglied mit ADMIN, aber ohne
-- INHERIT und ohne SET, kann die Rechte also noch nicht nutzen
GRANT SELECT ON geheim TO grp_priv;
GRANT grp_priv TO attacker WITH ADMIN TRUE, INHERIT FALSE, SET FALSE;

-- ---- Umgelenkte Funktion (Weg 1) ---------------------------
-- legitime Funktion in public, ueber den Suchpfad auffindbar
CREATE FUNCTION public.protokoll() RETURNS text
  LANGUAGE sql AS $$ SELECT 'ok'::text $$;
ALTER FUNCTION public.protokoll() OWNER TO victim_owner;

-- SECURITY DEFINER, KEIN fester search_path, ruft protokoll()
-- unqualifiziert auf: der search_path der Sitzung (shared, public)
-- entscheidet, welche protokoll() sie erreicht
CREATE FUNCTION public.pruef_zugriff() RETURNS text
  LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN protokoll();
END;
$$;
ALTER FUNCTION public.pruef_zugriff() OWNER TO victim_owner;
GRANT EXECUTE ON FUNCTION public.pruef_zugriff() TO app;  -- Nutzfall gesichert