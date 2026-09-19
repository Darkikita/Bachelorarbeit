\set ON_ERROR_STOP on
SELECT version();

-- T1 / T2
CREATE ROLE t_victim LOGIN PASSWORD 'alt';
CREATE TABLE t_data (id int);
INSERT INTO t_data VALUES (1);
GRANT USAGE ON SCHEMA public TO t_victim;
GRANT SELECT ON t_data TO t_victim;

-- T3
CREATE ROLE t_creator LOGIN PASSWORD 'test' CREATEROLE;
SELECT roleid::regrole, member::regrole, admin_option
FROM pg_auth_members WHERE member = 't_creator'::regrole;
SHOW createrole_self_grant;