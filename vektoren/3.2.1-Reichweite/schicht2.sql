-- Vier Absätze aus 4.2, je ein Block. Als ba_admin.

-- Eine Rolle je Zweck: Eigentum weg von der Anwendungsrolle
REASSIGN OWNED BY app_over TO app_owner;

-- Objektrechte nach Bedarf: je Operation statt ALL
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_over;
GRANT SELECT, INSERT ON kunden TO app_over;

-- PUBLIC-Voreinstellung zurücknehmen
REVOKE EXECUTE ON FUNCTION f() FROM PUBLIC;

-- Mitgliedschaften ohne Ketten: flach und INHERIT FALSE
REVOKE grp_read FROM grp_mid;
REVOKE grp_mid  FROM attacker;
GRANT grp_read TO attacker WITH INHERIT FALSE;