\echo '## E2  postgres_fdw oeffentliches Mapping  (als attacker, in ba_test)'
-- Zugriff ueber die Fremdtabelle: die Verbindung kommt ueber das
-- PUBLIC-Mapping als ba_admin an und liest pg_authid, das attacker
-- selbst nicht lesen darf
SELECT count(*) AS authid_zeilen FROM ft_authid;