INSERT INTO ac_roles (name, description, is_active, created_at, updated_at)
VALUES 
    ('admin', 'Administrator role with full permissions', true, NOW(), NOW()),
    ('user', 'Standard user role with limited permissions', true, NOW(), NOW()),
    ('interviewer', 'Interviewer role with permissions to access interview-related features', true, NOW(), NOW()),
    ('candidate', 'Candidate role for those applying to job listings', true, NOW(), NOW());


INSERT INTO ac_token_details (type, description, validity_duration, created_at, updated_at, is_active)
VALUES ('verification_token', 'Email Verification Token for user@example.com', 
        '1 hour'::interval, NOW(), NOW(), TRUE);

INSERT INTO ac_token_details (type, description, validity_duration, created_at, updated_at, is_active)
VALUES ('password_reset_token', 'Password Reset Token for user@example.com', 
        '2 hours'::interval, NOW(), NOW(), TRUE);

INSERT INTO ac_token_details (type, description, validity_duration, created_at, updated_at, is_active)
VALUES ('access_token', 'JWT Access Token for user@example.com', 
        '15 minutes'::interval, NOW(), NOW(), TRUE);

INSERT INTO ac_token_details (type, description, validity_duration, created_at, updated_at, is_active)
VALUES ('refresh_token', 'JWT Refresh Token for user@example.com', 
        '30 days'::interval, NOW(), NOW(), TRUE);

