\echo '## hinterlegter Code anlegen  (als attacker)'
-- eine SECURITY-DEFINER-Funktion im eigenen Schema. Sie ist der Zustand,
-- der die Sperrung ueberdauert: sie gehoert attacker, nicht der Sitzung,
-- und traegt beim Aufruf die Rechte ihres Eigentuemers.
CREATE OR REPLACE FUNCTION attacker.hintertuer() RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $$ SELECT 'code des angreifers'::text $$;