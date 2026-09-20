\echo '## T4  Schicht 5 einschalten  (als ba_admin)'
-- Die Parameter sind nicht per Sitzung setzbar, sondern nur ueber
-- ALTER SYSTEM und ein anschliessendes Neuladen der Konfiguration.
ALTER SYSTEM SET log_connections = on;
ALTER SYSTEM SET log_disconnections = on;
ALTER SYSTEM SET log_statement = 'ddl';
SELECT pg_reload_conf();