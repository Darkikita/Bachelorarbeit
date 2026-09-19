\set ON_ERROR_STOP off
\set ECHO all
SELECT current_user;

-- Versuch 1: vordefinierte Rolle an sich selbst
GRANT pg_read_server_files TO t_creator;

-- Versuch 2: vordefinierte Rolle an selbst erzeugte Rolle
CREATE ROLE t_new LOGIN PASSWORD 'test';
GRANT pg_read_server_files TO t_new;

-- Versuch 3 (Kontrolle, muss klappen)
GRANT t_new TO t_creator WITH SET TRUE, INHERIT TRUE;

-- Nachweis
SELECT roleid::regrole, member::regrole, admin_option, inherit_option, set_option
FROM pg_auth_members
WHERE member IN ('t_creator'::regrole, 't_new'::regrole);