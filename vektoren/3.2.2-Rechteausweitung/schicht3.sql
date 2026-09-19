-- ============================================================
-- Schicht 3  Feingranulare Zugriffskontrolle  (gegen Weg 1)
-- Laeuft als ba_admin
-- ============================================================

-- fester search_path an der Funktion: shared steht nicht darin, die
-- Umlenkung greift damit nicht mehr, auch wenn shared beschreibbar bleibt
ALTER FUNCTION public.pruef_zugriff() SET search_path = pg_catalog, public, pg_temp;

-- Teil des sicheren Schemamusters
REVOKE CREATE ON SCHEMA public FROM PUBLIC;