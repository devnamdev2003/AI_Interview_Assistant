--
-- PostgreSQL database dump
--

-- Dumped from database version 15.4
-- Dumped by pg_dump version 17.0

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', 'public, xata', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COMMENT ON SCHEMA public IS '';


--
-- Name: xata; Type: SCHEMA; Schema: -; Owner: xata
--

CREATE SCHEMA xata;


ALTER SCHEMA xata OWNER TO xata;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA xata;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA xata;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA xata;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat access method';


--
-- Name: xata_file; Type: DOMAIN; Schema: xata; Owner: xata
--

CREATE DOMAIN xata.xata_file AS jsonb DEFAULT jsonb_build_object('uploadKey', xata_private.xid(), 'signedUrlTimeout', 60, 'uploadUrlTimeout', 86400);


ALTER DOMAIN xata.xata_file OWNER TO xata;

--
-- Name: xata_file_array; Type: DOMAIN; Schema: xata; Owner: xata
--

CREATE DOMAIN xata.xata_file_array AS jsonb NOT NULL DEFAULT '[]'::jsonb;


ALTER DOMAIN xata.xata_file_array OWNER TO xata;

--
-- Name: bigint2bytea(bigint); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.bigint2bytea(bi bigint) RETURNS bytea
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $$
DECLARE
    result bytea := '\x';
    r      integer;
BEGIN
    FOR i IN 0 .. 7
        LOOP
            r := bi % 256;
            result := result || set_byte('\x00', 0, r);
            bi := (bi - r) / 256;
        END LOOP;
    RETURN result;
END;
$$;


ALTER FUNCTION xata.bigint2bytea(bi bigint) OWNER TO xata;

--
-- Name: generate_file_id_with_hmac(boolean, text, text, text); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.generate_file_id_with_hmac(isupload boolean, table_name text, recordid text, secret text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
    fileBytes     bytea;
    code          bytea;
    fileID        text;
    recordIDbytes bytea;
    table_id      text;
    table_oid     oid;
    workspaceID   text;
    branchID      text;
    secretBytes   bytea;
begin
    -- handle standard record id differently from custom record id.
    IF starts_with(recordID, 'rec_') AND char_length(recordID) = 24 THEN
        recordID := substr(recordID, 5);
        recordIDbytes := '\x00' || base32.decode_to_bytea(recordID);
    ELSE
        -- custom record ids adds the length first and then use escape decoding rather than base32
        recordIDbytes := set_byte('\x00', 0, char_length(recordID)) || decode(recordID, 'escape');
    END IF;

    secretBytes := base32.decode_to_bytea(secret);

    -- Version changes depending on upload or download
    IF isUpload THEN
        fileBytes := '\x03';
    ELSE
        IF length(secretBytes) = 16 THEN
            fileBytes := '\x02';
        ELSE
            fileBytes := '\x04';
        END IF;
    END IF;

    -- Get the oid for the table from its name so that we can look up the pgstream id
    table_oid := (select to_regclass(table_name)::oid);
    table_id := (select id from pgstream.table_ids where oid = table_oid);
    workspaceID := current_setting('xata.current_workspace');
    branchID := current_setting('xata.current_branch_id');
    -- drop the bb_ prefix
    IF starts_with(branchID, 'bb_') THEN
        branchID = substr(branchID, 4);
    END IF;

    fileBytes := fileBytes || decode(workspaceID, 'escape') || base32.decode_to_bytea(branchID) ||
                 base32.decode_to_bytea(table_id) || recordIDbytes ||
                 secretBytes;

    code := hmac(fileBytes, decode(current_setting('xata.file_secret_hmac'), 'hex'), 'sha256');
    fileID := base32.encode_bytea_no_padding(fileBytes || code);
    return fileID;
end;
$$;


ALTER FUNCTION xata.generate_file_id_with_hmac(isupload boolean, table_name text, recordid text, secret text) OWNER TO xata;

--
-- Name: generate_file_signature(boolean, bigint, text, text, bigint); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.generate_file_signature(isupload boolean, timeoutseconds bigint, signaturekey text, fileid text, now bigint DEFAULT floor(EXTRACT(epoch FROM now()))) RETURNS text
    LANGUAGE plpgsql
    AS $$
declare
    signature    text;
    signatureMac bytea;
    timestamp    bigint;
    dataToSign   bytea;
begin
    timestamp := now + timeoutSeconds;

    IF isUpload THEN
        -- data to sign is timestamp + '1' + fileID (string)
        dataToSign := xata.bigint2bytea(timestamp) || '\x01' || decode(fileID, 'escape');
    ELSE
        -- data to sign is timestamp + fileID (string)
        dataToSign := xata.bigint2bytea(timestamp) || decode(fileID, 'escape');
    END IF;

    -- mac is hmac(data to sign)
    signatureMac := hmac(dataToSign, decode(signaturekey, 'hex'), 'sha256');
    -- signature is timestamp + mac
    signature := base32.encode_bytea_no_padding(xata.bigint2bytea(timestamp) || signatureMac);

    return signature;
end;
$$;


ALTER FUNCTION xata.generate_file_signature(isupload boolean, timeoutseconds bigint, signaturekey text, fileid text, now bigint) OWNER TO xata;

--
-- Name: generate_file_signed_url(text, text, text, bigint, bigint); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.generate_file_signed_url(table_name text, recordid text, storagekey text, now bigint DEFAULT floor(EXTRACT(epoch FROM now())), signedurltimeout bigint DEFAULT 60) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
    domain        text;
    bucket        text;
    region        text;
    fileID        text;
    signature     text;
    signature_key text;
    branchID      text;
begin
    domain := (select value from xata_private.config where name = 'files.s3.domain');
    bucket := (select value from xata_private.config where name = 'files.s3.bucket');
    region := (select value from xata_private.config where name = 'files.s3.region');
    signature_key := current_setting('xata.file_secret_hmac');
    branchID := current_setting('xata.current_branch_id');
    -- drop the bb_ prefix
    IF starts_with(branchID, 'bb_') THEN
        branchID = substr(branchID, 4);
    END IF;

    fileID := xata.generate_file_id_with_hmac(false, table_name, recordID, storagekey);
    signature := xata.generate_file_signature(false, signedurltimeout, signature_key, fileID, now);

    return format('https://%s.%s/file/%s?verify=%s', region, domain, fileID, signature);
end;
$$;


ALTER FUNCTION xata.generate_file_signed_url(table_name text, recordid text, storagekey text, now bigint, signedurltimeout bigint) OWNER TO xata;

--
-- Name: generate_file_upload_url(text, text, text, bigint, bigint); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.generate_file_upload_url(table_name text, recordid text, uploadkey text, uploadurltimeout bigint DEFAULT 600, now bigint DEFAULT floor(EXTRACT(epoch FROM now()))) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
    domain          text;
    bucket          text;
    region          text;
    fileID          text;
    signature       text;
    signature_key   text;
    uploadsubdomain text;
    workspaceID     text;
    branchID        text;
begin
    domain := (select value from xata_private.config where name = 'files.s3.domain');
    bucket := (select value from xata_private.config where name = 'files.s3.bucket');
    region := (select value from xata_private.config where name = 'files.s3.region');
    uploadsubdomain := (select value
                        from xata_private.config
                        where name = 'files.s3.upload.subdomain');
    signature_key := current_setting('xata.file_secret_hmac');
    workspaceID := current_setting('xata.current_workspace');

    IF uploadURLTimeout < 0 THEN
        uploadURLTimeout = 0;
    END IF;

    branchID := current_setting('xata.current_branch_id');
    -- drop the bb_ prefix
    IF starts_with(branchID, 'bb_') THEN
        branchID = substr(branchID, 4);
    END IF;

    fileID := xata.generate_file_id_with_hmac(true, table_name, recordID, uploadkey);
    signature := xata.generate_file_signature(true, uploadUrlTimeout, signature_key, fileID, now);

    return format('https://%s.%s.%s.%s/file/%s?verify=%s', workspaceid, region, uploadsubdomain, domain, fileID,
                  signature);
end;
$$;


ALTER FUNCTION xata.generate_file_upload_url(table_name text, recordid text, uploadkey text, uploadurltimeout bigint, now bigint) OWNER TO xata;

--
-- Name: generate_file_url(text, text, boolean, text); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.generate_file_url(tablename text, recordid text, public boolean, storagekey text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
    domain  text;
    bucket  text;
    region  text;
    file_id text;
begin
    domain := (select value from xata_private.config where name = 'files.s3.domain');
    bucket := (select value from xata_private.config where name = 'files.s3.bucket');
    region := (select value from xata_private.config where name = 'files.s3.region');

    IF public THEN
        -- In production the bucket name includes the domain, for example eu-central-1.storage.xata.sh
        return format('https://%s/%s', bucket, storagekey);
    ELSE
        file_id := xata.generate_file_id_with_hmac(false, tablename, recordID, storagekey);
        return format('https://%s.%s/file/%s', region, domain, file_id);
    END IF;
end ;
$$;


ALTER FUNCTION xata.generate_file_url(tablename text, recordid text, public boolean, storagekey text) OWNER TO xata;

--
-- Name: set_search_path(text, text); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.set_search_path(systemsp text, usersp text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
     EXECUTE 'set search_path to ' || systemsp;
     EXECUTE 'set xata.user_search_path to ' || quote_ident(usersp);
END; $$;


ALTER FUNCTION xata.set_search_path(systemsp text, usersp text) OWNER TO xata;

--
-- Name: show_search_path(); Type: FUNCTION; Schema: xata; Owner: xata
--

CREATE FUNCTION xata.show_search_path() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    user_sp text;
BEGIN
    SELECT current_setting('xata.user_search_path') INTO user_sp;
    RETURN user_sp;
END; $$;


ALTER FUNCTION xata.show_search_path() OWNER TO xata;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts_users; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.accounts_users (
    id bigint NOT NULL,
    password character varying(128) NOT NULL,
    last_login timestamp with time zone,
    is_superuser boolean NOT NULL,
    username character varying(150) NOT NULL,
    first_name character varying(150) NOT NULL,
    last_name character varying(150) NOT NULL,
    email character varying(254) NOT NULL,
    is_staff boolean NOT NULL,
    is_active boolean NOT NULL,
    date_joined timestamp with time zone NOT NULL,
    phone_number character varying(15) NOT NULL,
    date_of_birth date,
    is_registered boolean NOT NULL,
    otp character varying(6),
    interview_limit integer,
    bio text NOT NULL,
    city character varying(100) NOT NULL,
    country character varying(100) NOT NULL,
    user_type character varying(100) NOT NULL
);


ALTER TABLE public.accounts_users OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: accounts_users_groups; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.accounts_users_groups (
    id bigint NOT NULL,
    users_id bigint NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.accounts_users_groups OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: accounts_users_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.accounts_users_groups ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.accounts_users_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: accounts_users_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.accounts_users ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.accounts_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: accounts_users_user_permissions; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.accounts_users_user_permissions (
    id bigint NOT NULL,
    users_id bigint NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.accounts_users_user_permissions OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: accounts_users_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.accounts_users_user_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.accounts_users_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


ALTER TABLE public.auth_group OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.auth_group ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.auth_group_permissions (
    id bigint NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_group_permissions OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.auth_group_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_group_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


ALTER TABLE public.auth_permission OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.auth_permission ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.auth_permission_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_admin_log; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.django_admin_log (
    id integer NOT NULL,
    action_time timestamp with time zone NOT NULL,
    object_id text,
    object_repr character varying(200) NOT NULL,
    action_flag smallint NOT NULL,
    change_message text NOT NULL,
    content_type_id integer,
    user_id bigint NOT NULL,
    CONSTRAINT django_admin_log_action_flag_check CHECK ((action_flag >= 0))
);


ALTER TABLE public.django_admin_log OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: django_admin_log_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.django_admin_log ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_admin_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


ALTER TABLE public.django_content_type OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.django_content_type ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_content_type_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.django_migrations (
    id bigint NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


ALTER TABLE public.django_migrations OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.django_migrations ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.django_migrations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: django_session; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


ALTER TABLE public.django_session OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: interview_interviewmodel; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.interview_interviewmodel (
    id bigint NOT NULL,
    email character varying(254) NOT NULL,
    "ScheduleID" character varying(255) NOT NULL,
    job_role character varying(500) NOT NULL,
    qa text NOT NULL,
    is_scheduled boolean NOT NULL,
    result text NOT NULL
);


ALTER TABLE public.interview_interviewmodel OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: interview_interviewmodel_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.interview_interviewmodel ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.interview_interviewmodel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: interview_scheduleinterview; Type: TABLE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE TABLE public.interview_scheduleinterview (
    id bigint NOT NULL,
    name character varying(255),
    email character varying(254) NOT NULL,
    unique_id uuid NOT NULL,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone NOT NULL,
    created_at timestamp with time zone NOT NULL,
    job_role character varying(255),
    experience character varying(100),
    interview_type character varying(100),
    interview_completed boolean NOT NULL,
    scheduled_by character varying(255) NOT NULL,
    interview_link character varying(200)
);


ALTER TABLE public.interview_scheduleinterview OWNER TO xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8;

--
-- Name: interview_scheduleinterview_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE public.interview_scheduleinterview ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.interview_scheduleinterview_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Data for Name: accounts_users; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.accounts_users (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined, phone_number, date_of_birth, is_registered, otp, interview_limit, bio, city, country, user_type) FROM stdin;
1	pbkdf2_sha256$870000$ZBWB9x8njdxpO48qxgY2fW$vCfcBpCmsaIBx4j0lR7GgpV3cixs+OxtB+lFnFKc9nI=	2024-10-16 10:55:09+00	t	dev	Dev	Namdev	devnamdevcse@gmail.com	t	t	2024-10-16 10:48:23+00	9926040407	\N	f	\N	\N				company
\.


--
-- Data for Name: accounts_users_groups; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.accounts_users_groups (id, users_id, group_id) FROM stdin;
\.


--
-- Data for Name: accounts_users_user_permissions; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.accounts_users_user_permissions (id, users_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.auth_group (id, name) FROM stdin;
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.auth_permission (id, name, content_type_id, codename) FROM stdin;
1	Can add log entry	1	add_logentry
2	Can change log entry	1	change_logentry
3	Can delete log entry	1	delete_logentry
4	Can view log entry	1	view_logentry
5	Can add permission	2	add_permission
6	Can change permission	2	change_permission
7	Can delete permission	2	delete_permission
8	Can view permission	2	view_permission
9	Can add group	3	add_group
10	Can change group	3	change_group
11	Can delete group	3	delete_group
12	Can view group	3	view_group
13	Can add content type	4	add_contenttype
14	Can change content type	4	change_contenttype
15	Can delete content type	4	delete_contenttype
16	Can view content type	4	view_contenttype
17	Can add session	5	add_session
18	Can change session	5	change_session
19	Can delete session	5	delete_session
20	Can view session	5	view_session
21	Can add interview model	6	add_interviewmodel
22	Can change interview model	6	change_interviewmodel
23	Can delete interview model	6	delete_interviewmodel
24	Can view interview model	6	view_interviewmodel
25	Can add schedule interview	7	add_scheduleinterview
26	Can change schedule interview	7	change_scheduleinterview
27	Can delete schedule interview	7	delete_scheduleinterview
28	Can view schedule interview	7	view_scheduleinterview
29	Can add user	8	add_users
30	Can change user	8	change_users
31	Can delete user	8	delete_users
32	Can view user	8	view_users
\.


--
-- Data for Name: django_admin_log; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.django_admin_log (id, action_time, object_id, object_repr, action_flag, change_message, content_type_id, user_id) FROM stdin;
1	2024-10-16 10:56:51.051543+00	1	dev	2	[{"changed": {"fields": ["User type"]}}]	8	1
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	admin	logentry
2	auth	permission
3	auth	group
4	contenttypes	contenttype
5	sessions	session
6	interview	interviewmodel
7	interview	scheduleinterview
8	accounts	users
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2024-10-16 10:44:57.342116+00
2	contenttypes	0002_remove_content_type_name	2024-10-16 10:44:59.235077+00
3	auth	0001_initial	2024-10-16 10:45:05.902213+00
4	auth	0002_alter_permission_name_max_length	2024-10-16 10:45:06.908011+00
5	auth	0003_alter_user_email_max_length	2024-10-16 10:45:07.424252+00
6	auth	0004_alter_user_username_opts	2024-10-16 10:45:08.160818+00
7	auth	0005_alter_user_last_login_null	2024-10-16 10:45:08.929898+00
8	auth	0006_require_contenttypes_0002	2024-10-16 10:45:09.668303+00
9	auth	0007_alter_validators_add_error_messages	2024-10-16 10:45:10.420596+00
10	auth	0008_alter_user_username_max_length	2024-10-16 10:45:11.158907+00
11	auth	0009_alter_user_last_name_max_length	2024-10-16 10:45:11.9126+00
12	auth	0010_alter_group_name_max_length	2024-10-16 10:45:13.405476+00
13	auth	0011_update_proxy_permissions	2024-10-16 10:45:13.907655+00
14	auth	0012_alter_user_first_name_max_length	2024-10-16 10:45:14.660175+00
15	accounts	0001_initial	2024-10-16 10:45:22.777129+00
16	admin	0001_initial	2024-10-16 10:45:25.80303+00
17	admin	0002_logentry_remove_auto_add	2024-10-16 10:45:26.054306+00
18	admin	0003_logentry_add_action_flag_choices	2024-10-16 10:45:26.811055+00
19	interview	0001_initial	2024-10-16 10:45:29.162603+00
20	sessions	0001_initial	2024-10-16 10:45:31.343837+00
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
tpbz3k1dof5353ld45su4szvnoecv13f	.eJxVjDsOwjAQRO_iGllO8G8p6TmDteu1cQA5UpxUiLvjSClA0817M28RcFtL2FpawsTiIgZx-u0I4zPVHfAD632Wca7rMpHcFXnQJm8zp9f1cP8OCrbS16CAXdKZtQKggQyRQ-PJOpfRe-1Gxk7OOgNba5QaVYqsrTFAPSw-X9zaN5c:1t11g0:LCjUgSGTPJoNCbhchk0446UDV0JlKdA1YvS8piw8otY	2024-10-30 10:54:48.642997+00
j8bixbxd6lq1rfbmrkm019c55i05jlvo	.eJxVjDsOwjAQRO_iGllO8G8p6TmDteu1cQA5UpxUiLvjSClA0817M28RcFtL2FpawsTiIgZx-u0I4zPVHfAD632Wca7rMpHcFXnQJm8zp9f1cP8OCrbS16CAXdKZtQKggQyRQ-PJOpfRe-1Gxk7OOgNba5QaVYqsrTFAPSw-X9zaN5c:1t11gL:jVvOSpdvEL93CnEJ6p70b67ol9CMong581pFGYtbJb4	2024-10-30 10:55:09.357491+00
\.


--
-- Data for Name: interview_interviewmodel; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.interview_interviewmodel (id, email, "ScheduleID", job_role, qa, is_scheduled, result) FROM stdin;
\.


--
-- Data for Name: interview_scheduleinterview; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

COPY public.interview_scheduleinterview (id, name, email, unique_id, start_time, end_time, created_at, job_role, experience, interview_type, interview_completed, scheduled_by, interview_link) FROM stdin;
\.


--
-- Name: accounts_users_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.accounts_users_groups_id_seq', 1, false);


--
-- Name: accounts_users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.accounts_users_id_seq', 1, true);


--
-- Name: accounts_users_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.accounts_users_user_permissions_id_seq', 1, false);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 1, false);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 1, false);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 32, true);


--
-- Name: django_admin_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.django_admin_log_id_seq', 1, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 8, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 20, true);


--
-- Name: interview_interviewmodel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.interview_interviewmodel_id_seq', 1, false);


--
-- Name: interview_scheduleinterview_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

SELECT pg_catalog.setval('public.interview_scheduleinterview_id_seq', 1, false);


--
-- Name: accounts_users_groups accounts_users_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_groups
    ADD CONSTRAINT accounts_users_groups_pkey PRIMARY KEY (id);


--
-- Name: accounts_users_groups accounts_users_groups_users_id_group_id_8dfb39d5_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_groups
    ADD CONSTRAINT accounts_users_groups_users_id_group_id_8dfb39d5_uniq UNIQUE (users_id, group_id);


--
-- Name: accounts_users accounts_users_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users
    ADD CONSTRAINT accounts_users_phone_number_key UNIQUE (phone_number);


--
-- Name: accounts_users accounts_users_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users
    ADD CONSTRAINT accounts_users_pkey PRIMARY KEY (id);


--
-- Name: accounts_users_user_permissions accounts_users_user_perm_users_id_permission_id_866b235f_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_user_permissions
    ADD CONSTRAINT accounts_users_user_perm_users_id_permission_id_866b235f_uniq UNIQUE (users_id, permission_id);


--
-- Name: accounts_users_user_permissions accounts_users_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_user_permissions
    ADD CONSTRAINT accounts_users_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: accounts_users accounts_users_username_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users
    ADD CONSTRAINT accounts_users_username_key UNIQUE (username);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: django_admin_log django_admin_log_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_pkey PRIMARY KEY (id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: interview_interviewmodel interview_interviewmodel_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.interview_interviewmodel
    ADD CONSTRAINT interview_interviewmodel_pkey PRIMARY KEY (id);


--
-- Name: interview_scheduleinterview interview_scheduleinterview_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.interview_scheduleinterview
    ADD CONSTRAINT interview_scheduleinterview_pkey PRIMARY KEY (id);


--
-- Name: interview_scheduleinterview interview_scheduleinterview_unique_id_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.interview_scheduleinterview
    ADD CONSTRAINT interview_scheduleinterview_unique_id_key UNIQUE (unique_id);


--
-- Name: accounts_users_groups_group_id_371be490; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX accounts_users_groups_group_id_371be490 ON public.accounts_users_groups USING btree (group_id);


--
-- Name: accounts_users_groups_users_id_c8303f87; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX accounts_users_groups_users_id_c8303f87 ON public.accounts_users_groups USING btree (users_id);


--
-- Name: accounts_users_phone_number_38bdfbe8_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX accounts_users_phone_number_38bdfbe8_like ON public.accounts_users USING btree (phone_number varchar_pattern_ops);


--
-- Name: accounts_users_user_permissions_permission_id_5f3d0fff; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX accounts_users_user_permissions_permission_id_5f3d0fff ON public.accounts_users_user_permissions USING btree (permission_id);


--
-- Name: accounts_users_user_permissions_users_id_62a47b5b; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX accounts_users_user_permissions_users_id_62a47b5b ON public.accounts_users_user_permissions USING btree (users_id);


--
-- Name: accounts_users_username_43ad8e69_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX accounts_users_username_43ad8e69_like ON public.accounts_users USING btree (username varchar_pattern_ops);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: django_admin_log_content_type_id_c4bce8eb; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX django_admin_log_content_type_id_c4bce8eb ON public.django_admin_log USING btree (content_type_id);


--
-- Name: django_admin_log_user_id_c564eba6; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX django_admin_log_user_id_c564eba6 ON public.django_admin_log USING btree (user_id);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: accounts_users_groups accounts_users_groups_group_id_371be490_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_groups
    ADD CONSTRAINT accounts_users_groups_group_id_371be490_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: accounts_users_groups accounts_users_groups_users_id_c8303f87_fk_accounts_users_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_groups
    ADD CONSTRAINT accounts_users_groups_users_id_c8303f87_fk_accounts_users_id FOREIGN KEY (users_id) REFERENCES public.accounts_users(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: accounts_users_user_permissions accounts_users_user__permission_id_5f3d0fff_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_user_permissions
    ADD CONSTRAINT accounts_users_user__permission_id_5f3d0fff_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: accounts_users_user_permissions accounts_users_user__users_id_62a47b5b_fk_accounts_; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.accounts_users_user_permissions
    ADD CONSTRAINT accounts_users_user__users_id_62a47b5b_fk_accounts_ FOREIGN KEY (users_id) REFERENCES public.accounts_users(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_content_type_id_c4bce8eb_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_content_type_id_c4bce8eb_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_user_id_c564eba6_fk_accounts_users_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_user_id_c564eba6_fk_accounts_users_id FOREIGN KEY (user_id) REFERENCES public.accounts_users(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: SCHEMA pg_catalog; Type: ACL; Schema: -; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT USAGE ON SCHEMA pg_catalog TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: xata_owner_bb_0tg5gab2ft5d19ffa3jpo2b8n8
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;


--
-- Name: SCHEMA xata; Type: ACL; Schema: -; Owner: xata
--

GRANT USAGE ON SCHEMA xata TO pgstreamrole;
GRANT USAGE ON SCHEMA xata TO xata_schema_access;
GRANT USAGE ON SCHEMA xata TO xata_metadata_update;


--
-- Name: TYPE xata_file; Type: ACL; Schema: xata; Owner: xata
--

GRANT ALL ON TYPE xata.xata_file TO xata_schema_access;


--
-- Name: TYPE xata_file_array; Type: ACL; Schema: xata; Owner: xata
--

GRANT ALL ON TYPE xata.xata_file_array TO xata_schema_access;


--
-- Name: FUNCTION lo_export(oid, text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.lo_export(oid, text) FROM PUBLIC;


--
-- Name: FUNCTION lo_import(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.lo_import(text) FROM PUBLIC;


--
-- Name: FUNCTION lo_import(text, oid); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.lo_import(text, oid) FROM PUBLIC;


--
-- Name: FUNCTION pg_backup_start(label text, fast boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_backup_start(label text, fast boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_backup_stop(wait_for_archive boolean, OUT lsn pg_lsn, OUT labelfile text, OUT spcmapfile text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_backup_stop(wait_for_archive boolean, OUT lsn pg_lsn, OUT labelfile text, OUT spcmapfile text) FROM PUBLIC;


--
-- Name: FUNCTION pg_config(OUT name text, OUT setting text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_config(OUT name text, OUT setting text) FROM PUBLIC;


--
-- Name: FUNCTION pg_create_restore_point(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_create_restore_point(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_current_logfile(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_current_logfile() FROM PUBLIC;


--
-- Name: FUNCTION pg_current_logfile(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_current_logfile(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_get_backend_memory_contexts(OUT name text, OUT ident text, OUT parent text, OUT level integer, OUT total_bytes bigint, OUT total_nblocks bigint, OUT free_bytes bigint, OUT free_chunks bigint, OUT used_bytes bigint); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_get_backend_memory_contexts(OUT name text, OUT ident text, OUT parent text, OUT level integer, OUT total_bytes bigint, OUT total_nblocks bigint, OUT free_bytes bigint, OUT free_chunks bigint, OUT used_bytes bigint) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_get_backend_memory_contexts(OUT name text, OUT ident text, OUT parent text, OUT level integer, OUT total_bytes bigint, OUT total_nblocks bigint, OUT free_bytes bigint, OUT free_chunks bigint, OUT used_bytes bigint) TO pg_read_all_stats;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_get_shmem_allocations(OUT name text, OUT off bigint, OUT size bigint, OUT allocated_size bigint); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_get_shmem_allocations(OUT name text, OUT off bigint, OUT size bigint, OUT allocated_size bigint) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_get_shmem_allocations(OUT name text, OUT off bigint, OUT size bigint, OUT allocated_size bigint) TO pg_read_all_stats;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_hba_file_rules(OUT line_number integer, OUT type text, OUT database text[], OUT user_name text[], OUT address text, OUT netmask text, OUT auth_method text, OUT options text[], OUT error text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_hba_file_rules(OUT line_number integer, OUT type text, OUT database text[], OUT user_name text[], OUT address text, OUT netmask text, OUT auth_method text, OUT options text[], OUT error text) FROM PUBLIC;


--
-- Name: FUNCTION pg_ident_file_mappings(OUT line_number integer, OUT map_name text, OUT sys_name text, OUT pg_username text, OUT error text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ident_file_mappings(OUT line_number integer, OUT map_name text, OUT sys_name text, OUT pg_username text, OUT error text) FROM PUBLIC;


--
-- Name: FUNCTION pg_log_backend_memory_contexts(integer); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_log_backend_memory_contexts(integer) FROM PUBLIC;


--
-- Name: FUNCTION pg_ls_archive_statusdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_archive_statusdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_archive_statusdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_dir(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_dir(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_ls_dir(text, boolean, boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_dir(text, boolean, boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_ls_logdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_logdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_logdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_logicalmapdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_logicalmapdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_logicalmapdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_logicalsnapdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_logicalsnapdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_logicalsnapdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_replslotdir(slot_name text, OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_replslotdir(slot_name text, OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_replslotdir(slot_name text, OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_tmpdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_tmpdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_tmpdir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_tmpdir(tablespace oid, OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_tmpdir(tablespace oid, OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_tmpdir(tablespace oid, OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_ls_waldir(OUT name text, OUT size bigint, OUT modification timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_ls_waldir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) FROM PUBLIC;
SET SESSION AUTHORIZATION rdsadmin;
GRANT ALL ON FUNCTION pg_catalog.pg_ls_waldir(OUT name text, OUT size bigint, OUT modification timestamp with time zone) TO pg_monitor;
RESET SESSION AUTHORIZATION;


--
-- Name: FUNCTION pg_promote(wait boolean, wait_seconds integer); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_promote(wait boolean, wait_seconds integer) FROM PUBLIC;


--
-- Name: FUNCTION pg_read_binary_file(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_read_binary_file(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_read_binary_file(text, bigint, bigint); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_read_binary_file(text, bigint, bigint) FROM PUBLIC;


--
-- Name: FUNCTION pg_read_binary_file(text, bigint, bigint, boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_read_binary_file(text, bigint, bigint, boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_read_file(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_read_file(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_read_file(text, bigint, bigint); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_read_file(text, bigint, bigint) FROM PUBLIC;


--
-- Name: FUNCTION pg_read_file(text, bigint, bigint, boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_read_file(text, bigint, bigint, boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_reload_conf(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_reload_conf() FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_advance(text, pg_lsn); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_advance(text, pg_lsn) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_create(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_create(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_drop(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_drop(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_oid(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_oid(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_progress(text, boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_progress(text, boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_session_is_setup(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_session_is_setup() FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_session_progress(boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_session_progress(boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_session_reset(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_session_reset() FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_session_setup(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_session_setup(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_xact_reset(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_xact_reset() FROM PUBLIC;


--
-- Name: FUNCTION pg_replication_origin_xact_setup(pg_lsn, timestamp with time zone); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_replication_origin_xact_setup(pg_lsn, timestamp with time zone) FROM PUBLIC;


--
-- Name: FUNCTION pg_rotate_logfile(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_rotate_logfile() FROM PUBLIC;


--
-- Name: FUNCTION pg_show_all_file_settings(OUT sourcefile text, OUT sourceline integer, OUT seqno integer, OUT name text, OUT setting text, OUT applied boolean, OUT error text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_show_all_file_settings(OUT sourcefile text, OUT sourceline integer, OUT seqno integer, OUT name text, OUT setting text, OUT applied boolean, OUT error text) FROM PUBLIC;


--
-- Name: FUNCTION pg_show_replication_origin_status(OUT local_id oid, OUT external_id text, OUT remote_lsn pg_lsn, OUT local_lsn pg_lsn); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_show_replication_origin_status(OUT local_id oid, OUT external_id text, OUT remote_lsn pg_lsn, OUT local_lsn pg_lsn) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_file(filename text, OUT size bigint, OUT access timestamp with time zone, OUT modification timestamp with time zone, OUT change timestamp with time zone, OUT creation timestamp with time zone, OUT isdir boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_file(filename text, OUT size bigint, OUT access timestamp with time zone, OUT modification timestamp with time zone, OUT change timestamp with time zone, OUT creation timestamp with time zone, OUT isdir boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_file(filename text, missing_ok boolean, OUT size bigint, OUT access timestamp with time zone, OUT modification timestamp with time zone, OUT change timestamp with time zone, OUT creation timestamp with time zone, OUT isdir boolean); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_file(filename text, missing_ok boolean, OUT size bigint, OUT access timestamp with time zone, OUT modification timestamp with time zone, OUT change timestamp with time zone, OUT creation timestamp with time zone, OUT isdir boolean) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_have_stats(text, oid, oid); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_have_stats(text, oid, oid) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset() FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset_replication_slot(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset_replication_slot(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset_shared(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset_shared(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset_single_function_counters(oid); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset_single_function_counters(oid) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset_single_table_counters(oid); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset_single_table_counters(oid) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset_slru(text); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset_slru(text) FROM PUBLIC;


--
-- Name: FUNCTION pg_stat_reset_subscription_stats(oid); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_stat_reset_subscription_stats(oid) FROM PUBLIC;


--
-- Name: FUNCTION pg_switch_wal(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_switch_wal() FROM PUBLIC;


--
-- Name: FUNCTION pg_wal_replay_pause(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_wal_replay_pause() FROM PUBLIC;


--
-- Name: FUNCTION pg_wal_replay_resume(); Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

REVOKE ALL ON FUNCTION pg_catalog.pg_wal_replay_resume() FROM PUBLIC;


--
-- Name: TABLE pg_aggregate; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_aggregate TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_am; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_am TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_amop; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_amop TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_amproc; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_amproc TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_attrdef; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_attrdef TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_attribute; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_attribute TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_auth_members; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_auth_members TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_available_extension_versions; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_available_extension_versions TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_available_extensions; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_available_extensions TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_backend_memory_contexts; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_backend_memory_contexts TO pg_read_all_stats;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_cast; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_cast TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_class; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_class TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_collation; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_collation TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_constraint; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_constraint TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_conversion; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_conversion TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_cursors; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_cursors TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_database; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_database TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_db_role_setting; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_db_role_setting TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_default_acl; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_default_acl TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_depend; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_depend TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_description; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_description TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_enum; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_enum TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_event_trigger; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_event_trigger TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_extension; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_extension TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_foreign_data_wrapper; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_foreign_data_wrapper TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_foreign_server; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_foreign_server TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_foreign_table; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_foreign_table TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_group; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_group TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_index; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_index TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_inherits; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_inherits TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_init_privs; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_init_privs TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_language; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_language TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_largeobject_metadata; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_largeobject_metadata TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_locks; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_locks TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_matviews; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_matviews TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_namespace; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_namespace TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_opclass; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_opclass TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_operator; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_operator TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_opfamily; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_opfamily TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_parameter_acl; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_parameter_acl TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_partitioned_table; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_partitioned_table TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_policies; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_policies TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_policy; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_policy TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_prepared_statements; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_prepared_statements TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_prepared_xacts; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_prepared_xacts TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_proc; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_proc TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_publication; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_publication TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_publication_namespace; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_publication_namespace TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_publication_rel; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_publication_rel TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_publication_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_publication_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_range; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_range TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_replication_origin; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_replication_origin TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_replication_slots; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_replication_slots TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_rewrite; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_rewrite TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_roles; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_roles TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_rules; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_rules TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_seclabel; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_seclabel TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_seclabels; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_seclabels TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_sequence; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_sequence TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_sequences; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_sequences TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_settings; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT,UPDATE ON TABLE pg_catalog.pg_settings TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_shdepend; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_shdepend TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_shdescription; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_shdescription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_shmem_allocations; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_shmem_allocations TO pg_read_all_stats;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_shseclabel; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_shseclabel TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_activity; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_activity TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_all_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_all_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_all_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_all_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_archiver; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_archiver TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_bgwriter; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_bgwriter TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_database; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_database TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_database_conflicts; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_database_conflicts TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_gssapi; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_gssapi TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_progress_analyze; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_progress_analyze TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_progress_basebackup; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_progress_basebackup TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_progress_cluster; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_progress_cluster TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_progress_copy; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_progress_copy TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_progress_create_index; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_progress_create_index TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_progress_vacuum; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_progress_vacuum TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_recovery_prefetch; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_recovery_prefetch TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_replication; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_replication TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_replication_slots; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_replication_slots TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_slru; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_slru TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_ssl; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_ssl TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_subscription; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_subscription_stats; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_subscription_stats TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_sys_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_sys_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_sys_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_sys_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_user_functions; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_user_functions TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_user_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_user_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_user_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_user_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_wal; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_wal TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_wal_receiver; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_wal_receiver TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_xact_all_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_xact_all_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_xact_sys_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_xact_sys_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_xact_user_functions; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_xact_user_functions TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stat_xact_user_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stat_xact_user_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_all_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_all_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_all_sequences; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_all_sequences TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_all_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_all_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_sys_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_sys_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_sys_sequences; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_sys_sequences TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_sys_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_sys_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_user_indexes; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_user_indexes TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_user_sequences; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_user_sequences TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statio_user_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statio_user_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_statistic_ext; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_statistic_ext TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stats; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stats TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stats_ext; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stats_ext TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_stats_ext_exprs; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_stats_ext_exprs TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.oid; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(oid) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subdbid; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subdbid) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subskiplsn; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subskiplsn) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subname; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subname) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subowner; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subowner) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subenabled; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subenabled) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subbinary; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subbinary) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.substream; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(substream) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subtwophasestate; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subtwophasestate) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subdisableonerr; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subdisableonerr) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subslotname; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subslotname) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subsynccommit; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subsynccommit) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: COLUMN pg_subscription.subpublications; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT(subpublications) ON TABLE pg_catalog.pg_subscription TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_subscription_rel; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_subscription_rel TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_tables; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_tables TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_tablespace; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_tablespace TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_timezone_abbrevs; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_timezone_abbrevs TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_timezone_names; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_timezone_names TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_transform; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_transform TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_trigger; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_trigger TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_ts_config; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_ts_config TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_ts_config_map; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_ts_config_map TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_ts_dict; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_ts_dict TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_ts_parser; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_ts_parser TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_ts_template; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_ts_template TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_type; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_type TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_user; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_user TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_user_mappings; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_user_mappings TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: TABLE pg_views; Type: ACL; Schema: pg_catalog; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT SELECT ON TABLE pg_catalog.pg_views TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- PostgreSQL database dump complete
--

