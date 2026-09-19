-- ============================================================
-- Schicht 2  Autorisierung und Least Privilege  (gegen Weg 2)
-- Laeuft als ba_admin
-- ============================================================

-- kein Erzeugen von Rollen mehr durch die Anwendungsrolle
ALTER ROLE creator NOCREATEROLE;

-- Mitgliedschaft samt ADMIN-Option von der kompromittierbaren Rolle nehmen
REVOKE grp_priv FROM attacker;

-- flankierend: schliesst in echt Weg 1 mit ab, trifft hier aber nur public.
-- Das gemeinsame Schema shared bleibt beschreibbar, deshalb ueberlebt E1
-- diese Schicht. Erst der feste Suchpfad in Schicht 3 schliesst den Weg.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;