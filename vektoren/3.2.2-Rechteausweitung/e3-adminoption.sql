\echo '## E3  ADMIN-Option, Weg 2b  (als attacker)'
-- ein einziger GRANT verschafft die Rechte von grp_priv
GRANT grp_priv TO attacker WITH INHERIT TRUE;
-- nun sind grp_privs Rechte in der Sitzung nutzbar
SELECT count(*) AS geheim_zeilen FROM geheim;