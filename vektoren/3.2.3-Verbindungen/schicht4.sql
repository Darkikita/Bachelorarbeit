-- ============================================================
-- Schicht 4  Systemgrenze  (Praevention aller drei Wege)
-- Laeuft als ba_admin in ba_test
-- ============================================================

-- E1: dblink_connect_u zurueck auf Superuser-only. Nicht-Superuser
-- koennen dann nur passwort- oder GSSAPI-authentifiziert verbinden.
REVOKE EXECUTE ON FUNCTION dblink_connect_u(text, text) FROM attacker;

-- E2: kein oeffentliches Mapping, USAGE nur an die Rolle, die es braucht
DROP USER MAPPING FOR PUBLIC SERVER loop;
REVOKE USAGE ON FOREIGN SERVER loop FROM attacker;

-- E3: Subscriptions nur durch dafuer vorgesehene Konten
REVOKE pg_create_subscription FROM attacker;
REVOKE CREATE ON DATABASE ba_sub FROM attacker;