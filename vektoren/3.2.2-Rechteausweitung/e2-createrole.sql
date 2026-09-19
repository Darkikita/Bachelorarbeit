\echo '## E2  CREATEROLE, Weg 2a  (als creator)'
-- Rolle anlegen und sich selbst gewaehren (automatische ADMIN-Option auf neu)
CREATE ROLE neu NOLOGIN;
GRANT neu TO creator WITH SET TRUE, INHERIT TRUE;
\echo '-- Grenze (vgl. T3): Serverrolle ohne ADMIN-Option nicht erreichbar'
GRANT pg_read_server_files TO creator;