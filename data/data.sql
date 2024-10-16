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
-- Name: public; Type: SCHEMA; Schema: -; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

-- *not* creating schema, since initdb creates it


ALTER SCHEMA public OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: api_contact; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.api_contact (
    id bigint NOT NULL,
    name character varying(20) NOT NULL,
    email character varying(50) NOT NULL,
    message text NOT NULL
);


ALTER TABLE public.api_contact OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: api_contact_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE public.api_contact ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.api_contact_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: auth_group; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.auth_group (
    id integer NOT NULL,
    name character varying(150) NOT NULL
);


ALTER TABLE public.auth_group OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: auth_group_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: auth_group_permissions; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.auth_group_permissions (
    id bigint NOT NULL,
    group_id integer NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.auth_group_permissions OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: auth_permission; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.auth_permission (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    content_type_id integer NOT NULL,
    codename character varying(100) NOT NULL
);


ALTER TABLE public.auth_permission OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: auth_permission_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: django_admin_log; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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


ALTER TABLE public.django_admin_log OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: django_admin_log_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: django_content_type; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.django_content_type (
    id integer NOT NULL,
    app_label character varying(100) NOT NULL,
    model character varying(100) NOT NULL
);


ALTER TABLE public.django_content_type OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: django_content_type_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: django_migrations; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.django_migrations (
    id bigint NOT NULL,
    app character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    applied timestamp with time zone NOT NULL
);


ALTER TABLE public.django_migrations OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: django_migrations_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: django_session; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.django_session (
    session_key character varying(40) NOT NULL,
    session_data text NOT NULL,
    expire_date timestamp with time zone NOT NULL
);


ALTER TABLE public.django_session OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: home_customuser; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.home_customuser (
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
    user_type character varying(100) NOT NULL,
    xata_version integer DEFAULT 0 NOT NULL,
    xata_createdat timestamp with time zone DEFAULT now() NOT NULL,
    xata_updatedat timestamp with time zone DEFAULT now() NOT NULL,
    xata_id text DEFAULT ('rec_'::text || (xata_private.xid())::text) NOT NULL,
    CONSTRAINT home_customuser_xata_id_length_xata_id CHECK ((length(xata_id) < 256))
);

ALTER TABLE ONLY public.home_customuser REPLICA IDENTITY FULL;


ALTER TABLE public.home_customuser OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: home_customuser_groups; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.home_customuser_groups (
    id bigint NOT NULL,
    customuser_id bigint NOT NULL,
    group_id integer NOT NULL
);


ALTER TABLE public.home_customuser_groups OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: home_customuser_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE public.home_customuser_groups ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.home_customuser_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: home_customuser_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE public.home_customuser ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.home_customuser_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: home_customuser_user_permissions; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.home_customuser_user_permissions (
    id bigint NOT NULL,
    customuser_id bigint NOT NULL,
    permission_id integer NOT NULL
);


ALTER TABLE public.home_customuser_user_permissions OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: home_customuser_user_permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE public.home_customuser_user_permissions ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.home_customuser_user_permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: interview_interviewmodel; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE TABLE public.interview_interviewmodel (
    id bigint NOT NULL,
    email character varying(254) NOT NULL,
    job_role character varying(500) NOT NULL,
    qa text NOT NULL,
    is_scheduled boolean NOT NULL,
    result text NOT NULL,
    "ScheduleID" character varying(255) NOT NULL,
    xata_id text DEFAULT ('rec_'::text || (xata_private.xid())::text) NOT NULL,
    xata_version integer DEFAULT 0 NOT NULL,
    xata_createdat timestamp with time zone DEFAULT now() NOT NULL,
    xata_updatedat timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT interview_interviewmodel_xata_id_length_xata_id CHECK ((length(xata_id) < 256))
);

ALTER TABLE ONLY public.interview_interviewmodel REPLICA IDENTITY FULL;


ALTER TABLE public.interview_interviewmodel OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: interview_interviewmodel_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Name: interview_scheduleinterview; Type: TABLE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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


ALTER TABLE public.interview_scheduleinterview OWNER TO xata_owner_bb_q787r2egrt10deud8nc50k7ems;

--
-- Name: interview_scheduleinterview_id_seq; Type: SEQUENCE; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
-- Data for Name: api_contact; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.api_contact (id, name, email, message) FROM stdin;
\.


--
-- Data for Name: auth_group; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.auth_group (id, name) FROM stdin;
1	interview
\.


--
-- Data for Name: auth_group_permissions; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.auth_group_permissions (id, group_id, permission_id) FROM stdin;
1	1	21
2	1	22
3	1	23
4	1	24
5	1	25
6	1	26
7	1	27
8	1	28
\.


--
-- Data for Name: auth_permission; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
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
29	Can add user	8	add_customuser
30	Can change user	8	change_customuser
31	Can delete user	8	delete_customuser
32	Can view user	8	view_customuser
33	Can add user	9	add_user
34	Can change user	9	change_user
35	Can delete user	9	delete_user
36	Can view user	9	view_user
37	Can add contact	10	add_contact
38	Can change contact	10	change_contact
39	Can delete contact	10	delete_contact
40	Can view contact	10	view_contact
\.


--
-- Data for Name: django_admin_log; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.django_admin_log (id, action_time, object_id, object_repr, action_flag, change_message, content_type_id, user_id) FROM stdin;
1	2024-04-17 06:51:12.394317+00	1	devnamdevcse@gmail.com	2	[{"changed": {"fields": ["Job role", "Interview link"]}}]	7	1
2	2024-04-17 06:51:46.995448+00	1	devnamdevcse@gmail.com	2	[{"changed": {"fields": ["Interview completed"]}}]	7	1
3	2024-04-17 06:53:23.798636+00	1	devnamdevcse@gmail.com	2	[{"changed": {"fields": ["Interview completed"]}}]	7	1
36	2024-07-30 13:52:22.640927+00	367	sanketb	3		8	1
69	2024-09-07 12:25:42.189272+00	1	interview	1	[{"added": {}}]	3	1
70	2024-09-07 12:26:20.514366+00	37	codersdev	2	[{"changed": {"fields": ["Groups"]}}]	8	1
\.


--
-- Data for Name: django_content_type; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.django_content_type (id, app_label, model) FROM stdin;
1	admin	logentry
2	auth	permission
3	auth	group
4	contenttypes	contenttype
5	sessions	session
6	interview	interviewmodel
7	interview	scheduleinterview
8	home	customuser
9	auth	user
10	api	contact
\.


--
-- Data for Name: django_migrations; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.django_migrations (id, app, name, applied) FROM stdin;
1	contenttypes	0001_initial	2024-04-17 05:13:43.298948+00
2	contenttypes	0002_remove_content_type_name	2024-04-17 05:13:44.680122+00
3	auth	0001_initial	2024-04-17 05:13:49.465346+00
4	auth	0002_alter_permission_name_max_length	2024-04-17 05:13:50.279314+00
5	auth	0003_alter_user_email_max_length	2024-04-17 05:13:50.775197+00
6	auth	0004_alter_user_username_opts	2024-04-17 05:13:51.510309+00
7	auth	0005_alter_user_last_login_null	2024-04-17 05:13:52.245237+00
8	auth	0006_require_contenttypes_0002	2024-04-17 05:13:52.974924+00
9	auth	0007_alter_validators_add_error_messages	2024-04-17 05:13:53.718646+00
10	auth	0008_alter_user_username_max_length	2024-04-17 05:13:54.465258+00
11	auth	0009_alter_user_last_name_max_length	2024-04-17 05:13:55.195654+00
12	auth	0010_alter_group_name_max_length	2024-04-17 05:13:56.515865+00
13	auth	0011_update_proxy_permissions	2024-04-17 05:13:57.007492+00
14	auth	0012_alter_user_first_name_max_length	2024-04-17 05:13:57.750541+00
15	home	0001_initial	2024-04-17 05:14:04.035595+00
16	admin	0001_initial	2024-04-17 05:14:06.385268+00
17	admin	0002_logentry_remove_auto_add	2024-04-17 05:14:06.644794+00
18	admin	0003_logentry_add_action_flag_choices	2024-04-17 05:14:07.412749+00
19	interview	0001_initial	2024-04-17 05:14:09.200526+00
20	interview	0002_interviewmodel_scheduleid	2024-04-17 05:14:10.615004+00
21	sessions	0001_initial	2024-04-17 05:14:12.551633+00
22	api	0001_initial	2024-04-17 05:47:49.073915+00
\.


--
-- Data for Name: django_session; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.django_session (session_key, session_data, expire_date) FROM stdin;
6i8q6qepgevzc44g17su7lbo06daqx4r	eyJfcGFzc3dvcmRfcmVzZXRfdG9rZW4iOiJjNmdja2ctODBhODU5NzVjODBkNDVjZTNkOWVkY2UyZjM0NjUyMTgifQ:1s2nWl:r4N8T1FGrf8xyA5rGtdtPaejsFvRIZk4pHySWrenzU0	2024-05-17 07:40:19.838844+00
qgwpu7j1lokxcz2st8plqhq3a70t6z3u	.eJxVkEFv2zAMhf8KoUuBIDAcJ7Dn3DoMA3oYsG67rUNAm3SsVpY8SY5nBPnvo7oE7Y7i-_T4-M7qgFPsD1Ngf9Ck9qpQ6_ezBtsXtkmgZ7RHl7XORq-bLCHZVQ3ZF0dsPl7Z_wx6DL38xq740OZttcGcsNjmVZUXFe64orIhrLclVmXV5eW25LqjmtqiK3c10S6v6s2GWEwJI6r9WVkcWByTu0yfXfPNmTT47ro4o2f4xCc2bhzYRhBC28j-pHn-sYyJ--y1pDQLPNwEgfjPyGneJiKH6GADC6NXl7V6vFf7n2f1e-IQtbMCrFaP18d-tXqyT_Y-AILnNq08eqQJI8OsYw9GDzoywduCNUQ2BgYGbNwUYXGThxFDEDvonIdwO4TeHYKWoHdzomE0aFNEI7rHI_-zEKqfgsYwgBa51wG8NJPJdWjDLG2ljrxfYMA7HNbwAOTsXYQXK76xlzyvWAZfDWNgOOoTv8YE0l3HPsW4lZCpy6_LXzkAxYg:1rwy5b:_7fEWGa0TSVJawFsAaVZDWyy43hu0alJ3TaUgrot1og	2024-05-01 05:44:11.317619+00
da4o0w5qj9yyk3m1qlfrp98svnfbnzs8	.eJxVjDsOgzAQRO_iOrJsrz84ZXrOYK3ZJSaJjIShinL3gESRlDPvzbxFwm0taWu8pInEVWhx-e0yDk-uB6AH1vssh7muy5TlociTNtnPxK_b6f4dFGxlX3fonFMAkcGC7gIE7Q3bPXgbwWMejVEhkqasonaOGNRoOCKxD-Ss-HwBmNc2hw:1rwz3e:6vi6x-kyz4sr1mQUPiJfE4mUaJ-6SJuoZMls5ML7SWs	2024-05-01 06:46:14.654071+00
ceo8j8clpyc6l3uho3cida0a2owofvjb	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1smW0T:ZBmDXHEVUx6Z9-VE-jzPcHXZxI7awI_42B9eEXr0dvQ	2024-09-20 10:15:57.756225+00
m0732gabztdp42bi8gk2eai3k3e3rj9f	.eJxVkMlu2zAQhl9lwEsvhqDFli1fii4IkgIFkrS3ojCG4thkxJAKSVkRDL97ScsG0iP_5ZvhnNgOhyB3gye3U4JtWZFXbPFR5dh2ZJIlXtAcbNZaE5ziWYpkV9dnP60g_fWa_Q8g0cvYrvKKl5u8pPVaYLnkm1VdVBteVkKsl_tmv6qXRSN4U1W8WYmi3JeYr_JaVJuybIq6jlCBAdn2xAy-UiQ-OjWh8XKI1ovlz1YntZ-CtAYEHUnbnlw0lQnkjorG31OfIvfP8HCTok3vMabItMm7c-RlbJ0X7OkL2_45sbeBfFDWfJy4AGVgsoMD7HutWkyBRVLglUx6kJj9jsjAZYFISa0feMTbdimbwTe8sCCQ1rEOo8QA9N6qQH5G2lhFbocAo3WdMgcYVZAzCo0AacdLkJNWkTxP9p3S2gNqdTBzPkgCR2-DcpQme7D7qCk_g77fLgYuXvJzPEz86hhPsWW_rHMTeOXgAYQ1nwJ0Jo5MvGvm_Pf8DyHdyxk:1s2nrb:7uHuF4rZnuPtzgDhjCSjjeyfOrhcj1Oxx8g9FkCphwo	2024-05-17 08:01:51.792592+00
w4xtajml31zcazh49ja7fpcdnjv7b64f	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1s2ntX:vJGb54BotZYBYmH1tnR2wVctATaK0j_pAZU5Dqap0dA	2024-05-17 08:03:51.57501+00
xtpvcxjhrg06vrxkks6onz7b4so558r6	.eJxVUc1O4zAQfpWRL1yqKgFSml4QCCE4rLQgboCqiT2pTdNxsZ2Gquq773gbJDjO9ztjH9QS-2SXfaSwdEYtVKkmP7EG9Zo4E-YDeeWn2nMKrplmyXRk4_SPN9TdjtpfARajFXeBdVWZtmy0qdHMZ2VrSJ_TrKrNVVHMiou6qYp6XmFdUFmXSPN23lyaqxnqi0tzThJqMKFaHBTjhvI-tBPwwzfPvsvzdp-sZxCYOr-lIKTjRGHnaHjZb7Pk4RkevyGh6Utkjlhn7j5QtOI6TtTTjVq8HtRnTzE5z0K-qZsICG3WwCqg6TERRKK145UQf0_dd9_dEGSnCQwWE2Ag2Ps-wMYnt8OcGKH1AbZ9iP3Jr0UkLscQfZuGbBnv2BCnCSAbsH4A43MUEO9clBzoRBRwlUP-VyTSlp3GDuLadV2E5GH8sF4Wlumkws31m5IXQI6D3LxQ0Yewh0cp4LMEa5auZAlG_vh-_AeVZb_u:1s2nue:wDi6S9I-H2ltP3yPtAuxpMexZiVW8o0pQa97sgUVUz0	2024-05-17 08:05:00.411464+00
ffu6utjy2jyfw8u2u10srwq584240n15	.eJxVjMFOwzAQBX-l8hlFMY0T0iMSSBy4QO_Rer2OnYZ1ZbsUVPXfsaUiwfXNvLmICU7ZTadEcfJG7ITsR3H3d9WAB-KKzAI8hwYD5-h1U5XmRlPzGgytjzf3X8BBcvXddVb1crCdgkHdI8KWtrLXo2qpw5a0tEOvlZF2tCRBWVRaPmjTDjBi8UvUQAaxuwiGDyrFA0TgxefkeXYFL0G_hbWS92DzGSJtnnj2TBQL9Zwpfno677-P1dkTOvYI6-bllxSLvo4UPTFW5TlScuV8vf4A0V1kEg:1s7YWH:YXyTNcB3KHIyETXxzc34Z5rUnJ84fTDME-bjokCf_gQ	2024-05-30 10:39:29.581103+00
z9ii9enuv5ea5bqur4gfq2r08gkd9t1p	.eJxVjDsOwyAQRO9CHSE-i2FTpvcZEJ8lOImwZOwqyt1jSy6SaqR5b-bNfNjW6rdOi58yuzJgl98uhvSkdoD8CO0-8zS3dZkiPxR-0s7HOdPrdrp_BzX0uq9dsgiQrZYoUO8BYpBKxGgBi5DSBjFQKSQdasgSFRGWYI3JTmlDhn2-pXw2lw:1rxRP9:TP8McHZqMoYkfkOMiTJgnyYNxtdioweRdxHoGHkMKpU	2024-05-02 13:02:19.626461+00
tm4hta4g42a43kqd4fiulabob6fvuf6r	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1sDObK:98NR5dishGp2-xfm-kGdCvTgLpJaJ1_sjyJaBZrwbR8	2024-06-15 13:16:50.456013+00
92ovm3faws9sh3atq8wt46qsfxchln1n	e30:1sEjKY:gn7H1vmMtkJlRNFt8mvCwvOLdNUMUiuWNfCrwtyxIq4	2024-06-19 05:37:02.615576+00
m31bmxrs79uzpqby5nw64a4pnqgjz76m	.eJxVjMFuAiEURX_FsG4m4FgQl12YdNGkadxP3oM3BTuCAUZrjP8uJJq023vOPVc2wFzcMGdKg7dswwTv2cvfFcH8UGjI7iF8x87EUJLHrindg-buI1qa3h7uv4CD7OqbwCDxUSyXQmm5WnFJWggk1GQV8rEXiEJLJQGl1K-Ia7U23PamQlB6rFELBdjmygIcqBY_k79AyG6uaB_xK05tzXEsZ0i0sHSiKR4pVexDoXTydN5djk3akXHBG5gW709SLfqttqdgmrJNlF093253dBVivA:1sEjOh:SBl3CY7vygF9bv9RstoHmPuAFK0YxrYaQrmy3txD0HE	2024-06-19 05:41:19.76008+00
to4tltpbotzoqhcu2a7jiv3p4egufaub	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1ryMvL:3iRVcAbKX6jCvgTd9EeGzc4AXzV5hwRzpxw34jMPRPQ	2024-05-05 02:27:23.223804+00
7txcmu64ppyu97n9q1t3mnop79b2yb90	.eJxVjLsOwjAMAP8lM4pSN4_CyM43RHZsSAElUtNOiH-HSB1gvTvdS0Xc1hy3JkucWZ3UGNThFxKmh5Ru-I7lVnWqZV1m0j3Ru236Ulme5739G2RsuX8HIJswGLADSAAeURw6jyTHQMLI9pqYiRI6tuTABOO_ygeBCaak3h8m0jjo:1s0dTY:f4MfHmKCMv81IIOU9p_wub45TVK_1K5y1crYOnt1hbw	2024-05-11 08:32:04.970879+00
w6q3oubn121jdarz6gqjnahchkqgc5ki	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1s0dZD:rH48-SEtgGXAV0BXkHeRkh2VLJLfLSZP1zuPbdKawzo	2024-05-11 08:37:55.731618+00
sygvfntly7o32wr76sr5z3vpgsplyud3	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1s0dZF:NDtcC-xKIatHnL6cs4MZxhsMqjwGoTthrndsHcQyDNQ	2024-05-11 08:37:57.529181+00
6ek5tmng8hoxeg82owsql4ufqvlodok0	.eJyVVt9z2zYM_ldwflmbUxU7bdLYL72u8Zb2miWttfV26y5HSZDFhCI1krKj5fq_D6Ak_0pe9hCfCALghw8fyDyObkXjy9vGob2V-Wg2moyiXVsqsnvUvJHfCb00cWa0tzKN2SXud118ZXJUP_e-ewlK4UqKHovp6WleTNIsn4r8_GxS5Jid4NnpNH87Hp-NX0_T0_H0_FRMxziZTgSeF-fpm_ztmchev8lPkJLmwovR7HGkRYWMB1dkvDPpV6N4vTCFXwuLcIErVKauUHuY66XUiBZeLC7mMHkJr-Cm9aXRxxehHHgxfnUCrXUvKZfUHu1K4jppa86YYFZqmQkFH4cd8sKHGq1EnbHLGLyBCbQo7OhHNPryfjT763H0T4POS6PJYf5QKyE1-BKhtiZD58AUkFkUXuolCPg6XyRFo-D9zUdoHNs6aBFInakmZ0spdK744zJJbqBCqiB3ERC_Uij5r-DDIiAnYOKpcELNtpjwCu3WaANB1rYRIyGSpKOjC0tUro2952Vt0TFl61JmJRsYcs8SY9x6x_BN-jLsl6hqrseXFLBNt0bIhAYUTqq2Kxa5VKKlL9UFtL1fjgV1KSS89L6eHR_3JYKS9wi_zpMIbq4X_Pt7EgIv5p_nyTx87pEAKR1JHaNTSX05d4cEu0LrKbvwwBoiFwwfvMtndooATRlWCIoqbsSycyGOzXO8_omihNY03R79FcYe-MCnQF0pKKfUaSOVP_RwrfNYxbAwzERu9E8eSK0Btqsxk0UbAJrGglnrw3AmJyZtbni9a_RS4U4ftr1-GgmfviWHdqokTgwN8UBnRzAh4Ez970FM6D4O8olpDPYG4OjoS7-YHR1919_1pVlTqR15NY2EILU5o1Ys78xUtcIHWveznO_MMvmmCitHbPYti6AWloA0Sljq-JpgAdfNqdYsUbL3jXTo3bv9aej9SZh00BDGNe-EUfG-Y4t08GHxR2dkVvAhQxWWQ_-Gzu0M2AZpDMnWqmRqBV0hvbxrSidomnVT1TSflfC1Mp4G1co6xJFctyEM9kDkrL0el1Ctk91sBctKumYzHDFcdbkp23M5LA53ADd0U2mHL3wSxJQU8HTI6EqkDFWnVlp0510HvQw8djwR59RTy4QFiQaRtZvO902OeP-ucX7_LCKvRxPIiq_QW1MbJT3dIp8Hjp5o8Dd88DCsZ7CjQNSuIUIzer7IgZjybSi0ojvb059IZbA9lRbdHigqVn-vUbTuHdwo5NuFqlhJStkNscxILYLrC3d_SjjIQ2SkXLIwjMIoRaC2ctlTqpCB4x4rU_z_8Jru-TlYDiPUD8AzZLOXMsslB3VXVViijSC8JbCQdmMppMJ-0WklSCEIgB4HvezFzv8TxB9MxRPt4l9IdVw_VdfonCL97n26T1QEHwdU8XV6h5mHa36HPSmQ-F7SpVcx0v42D6dlStB7yxd-DibEkDb-_vEfYMIzGA:1s0kkc:hyV7goyU3EktrL09QRQi5eS0M1tVTuLEwIQ9vfc05Uk	2024-05-11 16:18:10.094819+00
zkjrfxm31kvt5r24oyex5aot263b5c3f	.eJxVjsFKxDAQhl8l5CwlabpN3JseBA-CiPcy04w2a02WpFXLsu_uBFbR0zDzffPzn-QA6zINa6E8BC_30ip59feIML5RrMQfIL6mZkxxyQGbqjQXWpqH5Gm-vbj_AiYoE3-r3nhUpNFB651tHZGH6-6FXI-7nUdslXV21Fah68h02iuwGvvWGMNcc6iHBeT-JCO8EyfebGuZdGuYHBI-pbke7zLX4w4i8MgfgT4F89_leTtW65FySRFmcf8DWKKvI-VAcayGEksSWmwEWZ7P36shYRg:1s1TkG:Jnbk1e5orT3m2tRJd44coe9r-7SJt5Y6lEeLT9OHGcY	2024-05-13 16:20:48.12483+00
ze34mu3eq88vdl4ky50tqryg5fdl2kgh	.eJxlkU1v2zAMhv8KoUsvQZA4n81l6A7bethhxW7rEFAWHSuRRU-S4wVB_vsoJ-tS7CKAfPnx8tFZbbFL9baLFLbWqI2azpZqdJ_VWB7IZ8ns0e94XLJPwepxLhnf1Dj-yobcx1vtuwE1xlq6i6UucDFf6tljoWmyWC9W69W6KouielxqUyxRntnULCZ6OlstJ6Zaz_VsvaiKYj6f6IkMNZhQbc7KY0MysZHUnvULuxxFrlKPgcDQ0XFLQVTrE4Wjpf77qc01X17g-W9KZPotZZZ8mbVPgWItXZeR-vakNj_O6ldHMVn2Ir6qpwgI9ztoWAK9TTV4hjZYDvBv4ghq7sEwnLgD8kcbZRI46Qu4s36X8wGwREONLUXA4CUtW7yBRGXtbYkO4sE6FyEx3LB3iXKUmxNh8xCB5VPywDbwnsoUP7wquQ197OWajcr7s-XIDaU6Fz6LLf-Q4ODFYYMnTYPJEr0sMTQ4oIwJ4ikmauTwJPyuInt3koegJucYeg7OAB8E2ztgn-2R_PVGZxubyPzHpudOWgd7rXjHsn6jMFhAg23KgZybaoLOV9hYZzFc-bDjnaUrsGxNY5SIq4HNG4x7FOry8_IHeW8HgA:1s3fSo:fwvyNY2YZ1nd6u28sKn0WZEYA5qdyHwmZdVjx6bQHRY	2024-05-19 17:15:50.493871+00
2u32jk9vrv6xm1yzupvvs0ntuhvzfkf1	.eJxVkEFP4zAQhf_KyJe9oCgBUpreQAKJwx52xW1B1cSe1G4dT9Z2GlDV_77jCqTl6Pe-9_TGJ7XFOdvtnChunVEb1air_7Ue9YFCMcwew44rzSFH11cFqT7dVP1kQ_7hk_1WYDFZSdfYta0Zml6bDs161QyG9DWt2s7c1fWqvun6tu7WLXY1NV2DtB7W_a25W6G-uTXXJKUGM6rNSQUcqeyho4h77n-zL-_EQ14wEohBnieKYruQKR4dLS8fU4FeSNvgNHp4_nKEonehHQVdkKdIyUr4fKV-3avNn5P6O1PKjoOYr9LgPYwE2POcAWGKvCedYZEMwQfPYNFAZnDj5GmkUKA0kXaD01BugJTjrPMsOEdAv-Posh0reHyfPLoA2RJoi95T2FG6dA6oyQAGA5aXi8JHilp-otBj9arkDAxpkeEbdeFkJ8MzGA4_MhyCxFJmfVDnt_M_L1OsRA:1sbOQa:Zd4KiO1jPMkUg3mk9NYOlXBOyU0reLRUkhG5S0tHgKo	2024-08-20 17:56:56.229323+00
rjr1pmlgpfa3veg3rh85upzcalfg7wsz	.eJxVjMtOwzAURH-l8hpF8SOO02WRkFiwQd2wiq7t69ol2JWTAFHVf8eWigTLmXNmrmSEdfHjOmMegyV7IlpKHv62Gsw7xorsGeIpNSbFJQfdVKW507l5SRanw939d-Bh9mXNKEJHBeWDk4x3VIOTopdKtB1jaBnjnMne6cGB4wP0SpheatV2upVKuXpqYQGyv5IIH1ge37atlOekX9NU8-OUVrvDeAoRMRcU4oL5M-DXcbtU4YjGx2Bg2j3_kmLh9wVzwGiq8pRx9mV8u_0AoptdEQ:1sbcJi:zGjSj2cMxYFhNcTJdrqaO5SLpwHNPUc4t44C4R7iJSY	2024-08-21 08:46:46.799024+00
voalqz99ffwlrqxk5dzjmunbshyyva4i	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1smuYA:uvhCOlABYO6bxPoQ8bHsejBj81NJIhj3K-W6rKDk5fA	2024-09-21 12:28:22.110978+00
0ykx1ceh2gxij00ke25vfgu194knm141	.eJxVkU9v2zAMxb8KoXNg2Gmdxrl1p_XQAut6G4qAluhYqSxm-lPXCPLdSw0Z0N70-H56Iqmz2mNO4z5HCntr1E41avW11qN-I18Mc0R_4EqzT8H2VUGqqxurRzbkflzZbwEjxlFu19i1rRmaXpsOzXbTDIb0mjZtZ-7qelPfdH1bd9sWu5qarkHaDtv-1txtUN_cmjVJqMGEandWHicq_dC7FI_cP7Mr-jcPacZAIAY5PlEQ2_pE4d3S_LKcCvTzGR7-l8SmD8EseV28BhLDGhbCENVlpX7dq92fs_qbKSbLXogXcg4mAuw5J0BIVsQ8koeFM8SsNcU4ZOcW0OycYAETGZhtGgtOOAF7OWmeTo4-4BT4SDqtII48a4zWH0pUkBess2kpHdEwCGJlppI6TdlbLamA3sD1M7JIIVFiZAEGDoyukvHQx1nWsFNPnMaSLVDERa4u_3SlLq-XT387sY8:1sp4I7:nsSA3Efxgc_iur7D56SohpWcldIEsUrUepr-dALeZyA	2024-09-27 11:16:43.647547+00
035tp35h6r76r95nuzdxvfu2kfhdxer2	.eJxVjsFuwjAQRH8F-VxFDuAQc-yhgkMvqPdo7Z00pqmNbAOtEP9eW6JSe9x5b0Z7EwOd8zScE-LgWGxFK57-ZobsB3wFfCT_HhobfI7ONFVpHjQ1r4ExPz_cfwMTpam0JWmleGyNZU3cd-3IsEt0SvNGyk6utFFS94q0RKtbQj_2Zs2bjuxqzUuUUaZMYnsTnj5R_8GlhMdgDmGudwpjpitFLArBHE6IhTufES8O17fvU7V2h8X-NyoYX0Vz8Layl4g0ldb9_gNUMl1Q:1sFSL0:_f4A0WaeAN9j8tym7mF8Wb6bz5LKcMZ_1L_K-BlBTws	2024-06-21 05:40:30.711621+00
etuqzo0xi875raz0z20cthgzc0cn2a9a	.eJxdkMFu2zAQRH9lwUsBwxCkJHIsXYr20CKHFkgRoIemMFbi2qJNL1WSkmIY_vcuUxt1ciNnh8M3e1QrHGK3GgL5ldGqVoWaX2sNtjviNNBb5I3LWsfRmyZLluw8Ddk3p8l-PnvfBHQYOnmdY1WWel00ra5QLxfFWlN7Q4uy0vd5vshvq6bMq2WJVU5FVSAt18vmTt8vsL290zckoRojqvqoGPeUeGgUceuaH86m-1eRQUSyrt8TxwAyNhzJj4amp0OfTF-8EUJ7gIfLQEz00lPS238OCh15dZqrx0-q_nVUfwYK0TiW4RNZC_INNm6IcHCDh4E1-RCRteENuDXEjmDzjgV671oKYQ49-mjawaIXCMMgFPtweealSTojbAc2zl8iyCcrAm6MGCLhHohH4x2n8EwqIIdJoGv1ANrxhwg7dpN0eEM_m32nlwiPZ6WezZ75mX92KVS6wB4PwC5ChyMJcQL4v5pE8L7WHKYOI0Qv36_JYyNBYWesDULxGtm7EKS3tBPf5AaroSEY0Q6v5tSKr2sFilH2-PG6UidLd-r0-_QXjkLu9A:1sFSr5:x95LxzzSHUb5NPJaH41VWUEZorcGJfnJdk35-lSbYk4	2024-06-21 06:13:39.104639+00
ozqzqamklkc74cigx3ynfc824pyigf69	.eJxdj09PAjEQxb_KpBcvuNk_sCg3PRg5eJBwM4bMtlO2UDpr2wUJ4bvbNWjE6_u99-bNSaywj-2qD-RXRomZKPNSjP6qDcotuQGpDbo1Z5Jd9KbJBkt2oSF7YUX28eK9KmgxtCkt63pS5Xld3U3KqiQ1KXWNsmrqqiiw1rWWdzk2pZpSXeQqn1b3YxqrYiKJUEuNqVRhRDE7CYc7So07dmY76BtuFmwHKbCOB_QEivZkuSOfsHGR_N7QYXnsBtPzAuY_UsL0mWyGnBzYk6fQptR5JF4fxOztJD56CtGwS3BJ1kIfABvuIxy597B1fLCk1gSs4f_1HbkIO4otK7a8NpSiTkGTCqHzKKORSdLsAdfGXseMAwSNId52KEkBub3x7AaWpdHowiHNnIk5KHY38XsIBOOhs4SBAMM2nQZltCY_FP7-cX4_fwG4wa46:1sFTHw:M0_Q12H88UwPwNBcsX3lwugZOP-eKuIIp85vmBaoZIY	2024-06-21 06:41:24.645076+00
zisy8qlqwd1yaa9xzfvccm2ecwfndxg8	.eJyNU8Fu2zAM_RXClwFBYCRtk8a5FO22Qw8b1jXADstQ0BJdK1UkT5LrGUX_fZTsdCmQww5BbPKR7_GRfskesA31Q-vJPSiZrbN5Nj2OlSieyMSE3KF5tLmwJjhV5hGSj1mff7GS9M2IfdegRl9z9QyLxUJW81LIAuVqOa8kiTNaLgp5OZstZ-dFuZgVqwUWM5oXc6RVtSov5OUSxfmFPCNuKjFgtn7JDO4p6qFnDu5s-d3q-H59_y3_-nkDHCdtG3LAaWUCuWdF3aZvImhDojZKoIbbQ4ZR9IfhioyIkDMIFs6hJ3Q-e51md9fZ-udL9rslH5Q1jLhvHU2hJkegPCAcUhBqDNDbFgQaQP_EAYrPUrF2Wm_N1kwmdyN6PZnEwDb7yOBYxCo0KjMUWRbTBLAVfKKGTWVxPWvekUhMDBvnnQL3h9p2oELiLQnYeBmnUPvG2WdKHQOzYqm0Cn2q2DNV4N8hxkyCl3i1zdgQNL4jx6Mekas38hJ9tFD3kSjyoKgVjTzaWk-cErZtNMuQ5NVjEtzVStTQJUdAOGJL2Ly0oQoFQWUdELeCdGJWa3I5_EjwDyE9GRrm6pwKA1u8hSg9eabR-xzuLc9megiKU75tGtaT_O3QhFjtKFWdLB9sONDHuImKd61nBbcJOGx93-qgeMAjtH-DH3SKmj8ZGs4i8AEOVMo85hsm9IMKfo3uIEhVVdydRR4bcNMGdq6HzrZaJqHy1E7iSk8nGr4BdvVqtBKkjaQeyh48HwiPMP5pZehwBjm7-G_NR4197wPt35-A_L8byLPXX69_AQZnj8c:1sIlEZ:hWglw7nUXjqz9ub5_U1cqUxvcnII_lbt76duQUjOk6U	2024-06-30 08:27:31.742324+00
g0xfgfnwim4y6eo5qmd6hl45vqiifom4	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1sKgJ9:S8mFMSF83rICZ-SEQhZZz100PoGgB1NSJsCCMq-D3-k	2024-07-05 15:36:11.201938+00
pm4z65sis9rn2a34gkoslnxma45zrf17	.eJxVjDsOwjAQBe_iGllrx19Kes5gedcbHECOFCcV4u4QKQW0b2beS6S8rTVtnZc0FXEWerDi9Ltipge3HZV7brdZ0tzWZUK5K_KgXV7nws_L4f4d1Nzrt3bBUIFsfADU4DBrX0hb9tHFMEIYUSlDDOTjYJX2gYO3xTnjMDIgivcHGYI3uw:1sKgPX:Xvn_GHDX0xWrbD4KuVZZ6ZkbLMK1qiR65BsLpnvoTKY	2024-07-05 15:42:47.299313+00
oo6s0ii93dg2wfzg17abqiyjb6lwgj8k	.eJxVjLFuwyAURX8lYq4sjAmYjBkqdehSZbeeH6-FxAELSNsoyr8XpFRq13vOPTc2waW46ZIpTd6yHRt4z57-rjPgiUJD9gjhI3YYQ0l-7prSPWjuXqOlZf9w_wUcZFffRnNUvSTiOMhRaCu2SkmrzVbwUSqtSIsRtSBDHN45H2Qv1YjWGiM0ClOjFgqw3Y0FOFMtnuMpuxVS7UOq-Bjnt7g0srpr9pg3hQAdNeZDofTp6etwXZtxIHTBIyybl19SLfpeKXkK2JTnRLmd7_cfyPhhWQ:1sTaJD:BwNwXdDFfGtsISx1ttNpeBwMFsHjvGS9Tq9XdPV-EsQ	2024-07-30 05:01:03.18275+00
1f8ecbt47amj0rgm5fwxnunwufyylhz2	.eJxVjEFvAiEQRv-K4Ww2sMCW9eihSQ9ejPfNAEMXXcEA2hrjfy8kNmmPM-9970EmuJZ5umZMk7dkQzgXZP33q8GcMDRkjxA-Y2diKMnrrindi-ZuFy0u25f7LzBDnut6cAZFj2qk1LwxafmoNFDpNOMCkKnBjkwL47AHpH3PpB4cCu4kCkmtUjVqoQDZPEiAM9biLp5qeU2OUe_j0j5mxrPPJd1XBaEeqVIfCqabx6_D_dKcA5o5eAPL6uOXVAu_L5g8BtOU94S5jZ_PH0vHYFA:1sV7pg:8lehJFi37WiZ7Aj3D5pjDEfi7jdCQmeB3mdjNJegYe8	2024-08-03 11:00:56.29071+00
kas12j0t6rsrj0odeqjc68qdqvd9ydc3	.eJydU8FS20AM_RWNL70ETwIkJLm1Q6fNoR1guJUOI-_K8cJ6ZXbXCSnTf6-UhEJoD50evXqS3nt6fipusc_NbZ8o3jpbzItRMXj9VqG5p6AFe4dhyaXhkKOrSoWU-2oqv7Al_2GPPRjQYGqke4iz8djWo8rYGdrpZFRbMsc0Gc_s2XA4GZ7MqvFwNh3jbEij2QhpWk-rU3s2QXNyao9JhlrMWMyfioAtKR9ayeMdV1fs9TtxndcYCaRAnjuKUnYhU1w5Wl9vOgVdk2mCM-hh8VwRFD0K2lEwChlBZjiGDWFMxc9Bcfm-mH97Kh56StlxEMRN8cmtKEBuCFwwkTC5sAS03CkCuAbjubeQdRt7XjpKA7AumT4laHgNG-5hzb23wja5ZQCEJKyw8jSAGnufj7LIihgytM5ETkrWUAKMpnEyOPciNTeYwWCABoP1BI1bNpAj1rUzsGLft5TKm0IkYkhrcWReLKSBQ3Ipp_Izec8DaDegnoJLcI4rApkFC7Ac3mW4D8J2rWtU7bMJKlG_E4XEUQaqkn-2AioyKOH4w4naBXrlxM4IODQC_tuJwYGoUm57cNWv9Jjhcv89h5vinJKRpL-liV0XGU0DkpmaY4sSG1C5rfuBW9HyKio8ZknU5kg9clkCA2uqtNtL_hT35jAXXswT-eke2q0Lru38i-WpXAC2EFgNYWh7YfCSW1tekS60Gt6LTW5k_F8FPvwW-PGx8-h2KZZEGOqynqtjv2k5do1LrZx0P2ybCdG9clbzIZtR2ZUHArSTItTOt1BJEOSMfgN6aCG1d0uI--xUmP6hO78qtw2GSbKv6zPUfTC7gnZrnjjIIJZwPJdE3PefvwAaobFp:1sVp0E:dURHl546lSISPGsPzH8cVTXszV4liW8WCL9kpjaDm9k	2024-08-05 09:06:42.495468+00
jweap4r1xlsflhvse2uphvtt6ah890t4	.eJxVjsFuwjAQRH8F-VxFNuAQc-yhUg9cEPdo7Z00htRGjoFWiH-vLVGpPe68N6O9i54ueewvM1LvWWyFEi9_M0vuhFABHyl8xMbFkJO3TVWaJ52bXWRMr0_338BI81jakozWPCjr2BB3rRoYbolWG95I2cqVsVqaTpORUEYRuqGza9605FZrXqKMMmUS27sI9In6D64lPEa7j1O95zjkGyUsCsAUz0gF-5CRrh63w_e5Sge4MXhH0-L9lxQLX8X2CK4qbwnzWMqPxw-cOF_g:1sayFJ:GAsgm9CYzWb9iWb3dwt4P6ZYKsXba8dyuUnUz04-8qA	2024-08-19 13:59:33.011968+00
ow97milmpmpv6fvtphqc4wrs0c322mii	.eJxVjk1PwzAQRP8K8hlFdluncW9wQHDgUvUerb2TxiXYlZP0Q1X_O7ZUJDjuezOjvYmW5qlv5xGp9Sw2Qonnv8yS-0Iogg8U9rFyMUzJ26pEqocdq8_IGF4f2X8DPY19bksyWnOnrGND3NSqY7gFam14LWUtl8ZqaRpNRkIZRWi6xq54XZNbrniBPMo0kdjcRKBvlH9wyvAQ7TYO5X4J-3mglJkPE9LJ47y7Hot53z59_KKscTkieQRX3FvC2COJ-_0H5StYaA:1sXizy:NmFj8ZWbxFB_DTNPQNe7j5RUVuDI8b4uadrX-ODd3DY	2024-08-10 15:06:18.992119+00
yyb7uxng516fuas9vh1z3u724rfj3j6q	.eJxVjDsOwjAQBe_iGln-7DqEkj5nsNbeDQ4gR4qTCnF3iJQC2jcz76UibWuJW5MlTqwuyqnT75YoP6TugO9Ub7POc12XKeld0QdtephZntfD_Tso1Mq3Dp1YFvaZEZ0EhnPCnkYC8YkRpEPr0ZgEZHsIicVm5wM6g-AgjKjeH_SON5g:1sqrI6:bKEIqVN4IBctFqKNQMiLct6HD5d5gdQGnfltGDc6wuU	2024-10-02 09:48:06.020573+00
jy1ynarki6dh2l7wxeod4yw63vmc2qif	.eJxVj0FvwjAMhf-KlQsXVLVAgXKZ2KRpHHYY2m1MyG1cGihJ5yQwhPjvS2CT2NHv83t-Pos1etesvSVeKylmIhP9e63Eakc6ArlFvTFJZbRjVSZxJfmlNnk1ktrH391_AQ3aJrhTLPJc1llZyQLldJzVkqoBjfNCTtJ0nA6LMk-LaY5FSlmRIU3raTmSkzFWw5EcUAiV6FDMzkLjnmIfOgRxa8qlaeMc2vkWOWhKO-KDouP7qYvkZQmLPylg-u6IFekqsmcm2xCLS1-8zcXs4yy-PFmnjA5wJeYWUMN9AHEfFr09EG6IwRloCVnD3jABlsY7OBnPYXbqgDEHasPQebZe6Q24RlmY36pCZ6yKKwk8hSvBB9SGDEZHEIzHBh1IpuMVhVNXs-k6w85r5U59KCmGItS3Nx5WIjyI2oaaof8CpNE9BzttjuLyefkBkoioZQ:1sXj8C:b-nWCNco6N5WXtpgZI_iBmLNtYVllQnRGMGD55QFZ8w	2024-08-10 15:14:48.353853+00
fxvprn2inbaqx2zzax5pcbxz2so70173	.eJxlUsFu2zAM_RVCl10yw06bNPZtwwashwHr1ttSBLRER2pkyZPluEaQfx-VpGuDwT5I4nvk4yMPYoND1Juhp7AxSlSiELP3bzXKHbkUUM_otj6T3sVg6ixBsku0z757RfbzBXuVQGOvmZ1juViopqilKlGtlkWjSM5puSjVXZ4v85uyXuTlaoFlTkVZIK2aVX2r7pYob27VnDipwoiiOgiHLSU9tOfHZ1__9Dbdf_kmjhgIvtCerO8ocNi4SGFvaHycugR6JKmdkWjh_jXCKHphtCEnEySH6KGAiTCI40w8fBLV74P4M1AfjXep0BBoBvcg0YEm28HkBxhN1BA1xgy-UaD1MM-LsgcE7wheySdkomG_4xCflOGu6MzOP56rgm_gTRGM2oPhTF1nJ-O20PjA3P-7hcA-VGvHn_j60lk0jrkYofN2an3otOlbzjQDLgvaj2fdfrAKTNtZaslFMPyfdAboAjUUAik--W3Atk3lLW_BgFvK4Efwe6OIxdQsNWnGlCZbC7YUXT_yBCqBewoMZyuvTHy4HCtuoJe8UClPNG3ql85GMZ-gQckCTv6wYRqtJbdNOuK_SbK6mtVfteW5quQ94X6y92p4Xtbz7JR3HyLsHMOj5tKnOKCMA1eYGIAttBM0gXqdApz6bXViYG9PXpgdnYYujk_Hv2PBJQA:1sZnMO:ERM8Yjk70xmNKvpIumhpBjH8h00Nv4MYKRdhaxzBRR8	2024-08-16 08:10:00.824215+00
xg9cvheaxb5qadyefjstfw4v3neyxs69	.eJxVjEEOwiAQRe_C2pChLZRx6d4zkIEZpGpoUtqV8e7apAvd_vfef6lA21rC1mQJE6uzMur0u0VKD6k74DvV26zTXNdlinpX9EGbvs4sz8vh_h0UauVbA6G1nE1MjMTemcySOnEWeQRw0GO0gN4Sghg0JD77OPDoKPUDd6LeH_RkODw:1sayE0:A_dyCDjl_2TX2Z7ZSqviYj7TehkuGCGBLt7YGqTWy2M	2024-08-19 13:58:12.246416+00
\.


--
-- Data for Name: home_customuser; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.home_customuser (id, password, last_login, is_superuser, username, first_name, last_name, email, is_staff, is_active, date_joined, phone_number, date_of_birth, is_registered, otp, interview_limit, bio, city, country, user_type, xata_version, xata_createdat, xata_updatedat, xata_id) FROM stdin;
103	pbkdf2_sha256$720000$x2KZDV0WaWPlF7Vo43cnPe$LyWzpQINZMPfKTQZ3ql/7fzWe7ECCU0f777HD3wpjNA=	2024-06-05 05:37:56.789064+00	f	Priyanshu	Priyanshu	Tedia	priyanshu16aug@gmail.com	f	t	2024-05-03 07:36:28.426851+00	1234567891	\N	t	\N	\N				company	5	2024-05-03 07:36:29.576252+00	2024-06-05 05:37:56.822417+00	rec_coq97vdqrj67mrqomaeg
368	pbkdf2_sha256$720000$lefb0OKTM3JkRg1gD5wOxy$IU/cs/xZUmV5QhmQXlrICkVpytA/bPVI8NPvDuFn0a0=	2024-07-30 13:52:58.629151+00	f	sanketb	sanket	bhandare	sanket.s.bhandare@gmail.com	f	t	2024-07-30 13:52:56.643828+00	9766991349	\N	t	\N	\N				normal	2	2024-07-30 13:52:58.294376+00	2024-07-30 13:53:07.10733+00	rec_cqkf0elqrj64net4pos0
1	pbkdf2_sha256$870000$ZMWHoNxyuyfjM4u7BIN6KB$hy22e/7AINGNmv6QPzegoPQOnYeu8hx+krkDGpnN83A=	2024-10-15 06:08:32.14052+00	t	dev	Dev	Namdev	devnamdevcse@gmail.com	t	t	2024-04-17 05:15:34.695+00	9926040407	\N	t	\N	\N				company	44	2024-04-17 05:31:05.599589+00	2024-10-15 06:08:32.116738+00	rec_coflt6dqrj6631bvhjig
202	pbkdf2_sha256$720000$akyaMFgLZl3oMnVHw9upw0$6by6jEZnUZ4xjA5mr1hWVHDZNBUqEOR+EPaNKcUAkZw=	2024-06-07 05:50:40.447843+00	f	monika	Monika	Namdev	ishusharma52064@gmail.com	f	t	2024-06-07 05:50:38.751215+00	1234567779	\N	t	\N	\N				company	1	2024-06-07 05:50:40.060387+00	2024-06-07 05:50:40.475684+00	rec_cph9vc5qrj60a94pfvhg
70	pbkdf2_sha256$720000$0qJ1mHOnreQ12AiBf7vqhj$7UU25+QVzbql4DhqVG0IpPHSR+nAOJDJDPQJPTB3Dhg=	2024-04-29 16:19:35.139701+00	f	Ayush123	Ayush	Khan	ayushkhana230@gmail.com	f	t	2024-04-29 16:19:33.605352+00	8839858154	\N	t	\N	\N				normal	2	2024-04-29 16:19:34.705696+00	2024-04-29 16:20:03.951912+00	rec_consh5lqrj64kp14hkhg
4	pbkdf2_sha256$720000$vsYA3MzjGLMJptLhijQc1S$JwXbL6ET+v3avzNwbbP5Uwape7yH9OIJypZ2BMq7A8Y=	2024-04-18 13:02:19.553689+00	f	petarivanov	Petar	Ivanov	petyr.iv@gmail.com	f	t	2024-04-18 13:02:17.743339+00	0788382993	\N	t	\N	\N				normal	1	2024-04-18 13:02:19.236486+00	2024-04-18 13:02:19.588853+00	rec_coghjmtqrj6525koqf1g
3	pbkdf2_sha256$720000$iFvujt351Mpz7IdGOQcSdU$7TKzflkOYBpVxZKOxysOxtnhdZ7bKQ57WC+nVyo75og=	2024-04-18 10:10:08.766436+00	f	user1	user	1	user1@gmail.com	f	t	2024-04-18 10:10:07.26293+00	1234567890	\N	t	\N	\N				normal	2	2024-04-18 10:10:08.457488+00	2024-04-19 03:59:28.72851+00	rec_cogf305qrj626fko5n5g
235	pbkdf2_sha256$720000$bKrdzV7ej60DsJGCNlQHKg$u4tI/yDjl05J8IqB/9WoaYXN7gT42CQCPPyHrS2iCzc=	2024-06-21 15:42:47.05153+00	f	qaz	qaz	qaz	qaz@gmail.com	f	t	2024-06-21 15:42:42.913435+00	1598746320	\N	t	\N	\N				normal	1	2024-06-21 15:42:46.056856+00	2024-06-21 15:42:47.304459+00	rec_cpqputlqrj66cd83tj1g
136	pbkdf2_sha256$720000$FGaLyXOviC5TKkdgqHzpxg$BBJ0EdlwgwpP/1GZRHOflA+Ml+oUOqtl+3EeLBezrW4=	2024-05-05 17:13:37.502177+00	f	m	Mohd	Farhan	gfdsdfghj@gmail.com	f	t	2024-05-05 17:13:35.717726+00	1886959099	\N	t	\N	\N				normal	1	2024-05-05 17:13:37.18167+00	2024-05-05 17:13:37.537238+00	rec_corrsgdqrj620jbd8ib0
268	pbkdf2_sha256$720000$OaxXH2Y9Dtft4elrWX16vW$lT5IaR1x9uY/2G8hyb2b4g5P2kafUDRjHYhTUwwUJL0=	2024-07-14 04:46:34.286355+00	f	Arnab	Arnab	Manna	arnabmanna203@gmail.com	f	t	2024-07-14 04:46:32.474986+00	9733193689	\N	t	\N	\N				normal	1	2024-07-14 04:46:33.963096+00	2024-07-14 04:46:34.315767+00	rec_cq9lgadqrj64fjsrpq40
169	pbkdf2_sha256$720000$Tv2i5VxLdmTHT0GMrAHKsb$iJZWL/24zliqmaohj81fYLJPEVzsW1P9PrGvIgC17tQ=	2024-05-16 10:39:12.734591+00	f	karanjitsingh	Karanjit	Singh Randhawa	karanjitrandhawa2000@gmail.com	f	t	2024-05-16 10:39:11.053024+00	8399913392	\N	t	\N	\N				normal	1	2024-05-16 10:39:12.411787+00	2024-05-16 10:39:12.76826+00	rec_cp2u4k5qrj625j74nus0
401	pbkdf2_sha256$720000$vqVQZ1451Sqxg6Pf89wKIC$eZ/2kfhLcPMC9ZshomXuOyHYAQXH1ftb921G0G4coYU=	2024-08-07 08:46:13.63224+00	f	Yyy	emmanuel	lekwa	emmanuellekwa@gmail.com	f	t	2024-08-07 08:46:11.987615+00	0813331003	\N	t	\N	\N				normal	1	2024-08-07 08:46:13.311468+00	2024-08-07 08:46:13.662499+00	rec_cqpj8ldqrj65cu9krleg
301	pbkdf2_sha256$720000$Mo6YOZKIXrB5r2yk0sx0W2$UoLnvrRKkw37R7N4eNKIla/noWDZe4UcfAUD+Ef5Xak=	2024-07-16 05:00:26.139033+00	f	mokshparashar	Moksh 	parashar	parasharm239@gmail.com	f	t	2024-07-16 05:00:24.180413+00	9425790135	\N	t	\N	\N				normal	1	2024-07-16 05:00:25.793979+00	2024-07-16 05:00:26.173196+00	rec_cqavsqdqrj60fjmb3ri0
334	pbkdf2_sha256$720000$KDh7QEfffd8JHvLPwl4LXW$/9j0/OYPD+slyOmhGEzuLQ03DQMcbGlDnMjlD9f1E6U=	2024-07-18 10:59:14.876036+00	f	Moksh	moksh	parashar	ashutoshsvp123@gmail.com	f	t	2024-07-18 10:59:13.028334+00	8969856868	\N	t	\N	\N				normal	1	2024-07-18 10:59:14.473068+00	2024-07-18 10:59:14.918924+00	rec_cqcfb0lqrj614of0pb6g
37	pbkdf2_sha256$720000$ANuuzlS3EwkdqseWT1a1qL$JxQhBB/HMycG3nrq29hX4x5nPEyfv4DSlpE8UN49qfQ=	2024-09-07 12:27:54.631829+00	f	codersdev	dev	dev	useer1@gmail.com	f	t	2024-04-24 06:42:50+00	9923040407	\N	t	\N	\N				normal	5	2024-04-24 06:42:51.755307+00	2024-09-07 12:27:54.663006+00	rec_cokajqtqrj65gk5me2v0
2	pbkdf2_sha256$720000$w0GFULtrWuOmVuL4JtCzST$HL+V8K4LYwTXj+462L+tl4rGy3ZnU0r7ghc1KyfR0S8=	2024-09-16 06:18:32.540483+00	f	user	Dev	namdev	codersdev2@gmail.com	f	t	2024-04-17 05:38:58.383591+00	1234567989	\N	t	\N	\N				company	8	2024-04-17 05:39:00.371337+00	2024-09-18 09:48:05.98271+00	rec_cofm0t5qrj666krvj2n0
\.


--
-- Data for Name: home_customuser_groups; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.home_customuser_groups (id, customuser_id, group_id) FROM stdin;
1	37	1
\.


--
-- Data for Name: home_customuser_user_permissions; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.home_customuser_user_permissions (id, customuser_id, permission_id) FROM stdin;
\.


--
-- Data for Name: interview_interviewmodel; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.interview_interviewmodel (id, email, job_role, qa, is_scheduled, result, "ScheduleID", xata_id, xata_version, xata_createdat, xata_updatedat) FROM stdin;
1	devnamdevcse@gmail.com	Software Development 	[{"question":"**Interviewer:**\\n\\nDev, as a fresh software developer, tell me about your understanding of agile development methodologies and how they can benefit a software development team.","answer":"My mother fresher in software developer.I don't know about the Agile development, but I know about the DevOps engineering. So because Agile is a theoretical implementation and the DevOps is a practical implementation."}]	t	"**Answer 1:**\\n\\n**Question:**\\n\\n**Interviewer:**\\n\\nDev, as a fresh software developer, tell me about your understanding of agile development methodologies and how they can benefit a software development team.\\n\\n**Answer:**\\n\\n\\"My mother fresher in software developer.I don't know about the Agile development, but I know about the DevOps engineering. So because Agile is a theoretical implementation and the DevOps is a practical implementation.\\"\\n\\n**Score:** 0 out of 100\\n\\n**Feedback:**\\n\\nThe candidate's response is not relevant to the question and demonstrates a lack of understanding of agile development methodologies. The candidate mentions DevOps engineering but does not provide any information about agile development. Additionally, the statement \\"Agile is a theoretical implementation and DevOps is a practical implementation\\" is not accurate.\\n\\n**Areas for Improvement:**\\n\\n* The candidate should gain a basic understanding of agile development methodologies, such as Scrum and Kanban.\\n* The candidate should be able to explain the benefits of agile development for a software development team, such as increased flexibility, faster time to market, and improved quality.\\n* The candidate should be able to discuss the differences between agile development and traditional development methodologies."	e2b8b4d9-1646-492c-a1ee-87f91db702a9	rec_coflvn5qrj665ervhjmg	0	2024-04-17 05:36:28.703763+00	2024-04-17 05:36:28.828479+00
34	devn@omnixm.com	Software Developer	[{"question":"Tell me about your understanding of software development life cycles and which one you are most familiar with, and why?","answer":"Sorry I don't know the answer. Please tell me a different question."},{"question":"\\"Since you're a fresher, let's explore some basic software development concepts. Can you explain what a variable is in programming?\\"","answer":"where you will basically used to define the value like if you want to define the integer value in a programming then you define with the help of int variable and we want to define a clicker variable then you define a variable so basically variable is basically used to do a mathematic and write a logic in programming languages"},{"question":"**Interviewer:**\\n\\n\\"That's a good understanding of variables. Can you describe the difference between a local variable and a global variable?\\"","answer":"Local value will basically access inside the.Brackets.Like which is accessible only inside the locally, but the global variable can be access.All over the programming.All over the code, any function, any class.So there's a major difference between global and.Local variables."}]	t	"**Answer 1:**\\n\\n* **Score:** 0/100\\n* **Feedback:** The candidate did not demonstrate any understanding of software development life cycles. Instead, they indicated that they did not know the answer. This is a crucial concept for a software developer, and it is essential to have a good understanding of the different stages involved in developing software.\\n\\n**Answer 2:**\\n\\n* **Score:** 25/100\\n* **Feedback:** The candidate provided a basic and somewhat incomplete explanation of what a variable is in programming. They did not mention the different types of variables or the scope of variables. It would be beneficial for the candidate to have a more thorough understanding of this concept.\\n\\n**Answer 3:**\\n\\n* **Score:** 50/100\\n* **Feedback:** The candidate provided a good explanation of the difference between local and global variables. They correctly identified that local variables are accessible only within a specific scope, while global variables can be accessed anywhere in the code. However, they could improve their explanation by providing more specific examples.\\n\\n**Overall Impression:**\\n\\nThe candidate has some basic knowledge of software development concepts, but they need to develop a stronger understanding of software development life cycles and variables. With additional study and practice, they could improve their overall performance in a software developer interview."	962a3f2d-7234-45fe-be02-eb002ffc44ab	rec_cqjkeq5qrj6757sqbeng	0	2024-07-29 07:40:24.220535+00	2024-07-29 07:40:24.220535+00
67	sanket.s.bhandare@gmail.com	front end	[{"question":"\\"Sanket, as a front-end developer with over five years of experience, tell me about a complex UI challenge you faced and how you overcame it to deliver a seamless user experience.\\"","answer":"hello I don't know the answer"},{"question":"\\"Sanket, given your extensive experience in front-end development, how do you approach optimizing web performance for different devices and screen sizes to ensure a consistent user experience?\\"","answer":"hello"}]	t	"**Question 1:**\\n\\n**Question:** \\"Sanket, as a front-end developer with over five years of experience, tell me about a complex UI challenge you faced and how you overcame it to deliver a seamless user experience.\\"\\n\\n**Answer:** \\"hello I don't know the answer\\"\\n\\n**Score:** 0/100\\n\\n**Feedback:** Your answer is not responsive to the question. It does not provide any information about a complex UI challenge you faced or how you overcame it.\\n\\n**Question 2:**\\n\\n**Question:** \\"Sanket, given your extensive experience in front-end development, how do you approach optimizing web performance for different devices and screen sizes to ensure a consistent user experience?\\"\\n\\n**Answer:** \\"hello\\"\\n\\n**Score:** 0/100\\n\\n**Feedback:** Your answer is not responsive to the question. It does not provide any information about how you approach optimizing web performance for different devices and screen sizes.\\n\\n**Overall Feedback:**\\n\\nYour answers to both questions were not satisfactory. They did not demonstrate the skills and experience that are expected of a front-end developer with over five years of experience. You need to be able to provide detailed and specific examples of your work to demonstrate your abilities. I would recommend that you prepare more thoroughly for future interviews."	40c13373-51dd-4595-b59d-8ec97dcc0572	rec_cqkesadqrj64gnt4pkag	0	2024-07-30 13:44:09.693778+00	2024-07-30 13:44:09.693778+00
100	devnamdevcse@gmail.com	ASP.NET developer 	[{"question":"How would you implement cross-origin resource sharing (CORS) in an ASP.NET Core web application to handle requests from external domains?","answer":"I don't know how to handle this."},{"question":"Next Question:\\n\\nHow would you handle HTTP POST requests with large payloads in an ASP.NET Core application to avoid performance issues?","answer":"I'm sorry, I don't know."}]	t	"**Question 1:** How would you implement cross-origin resource sharing (CORS) in an ASP.NET Core web application to handle requests from external domains?\\n\\n**Answer:** \\"I don't know how to handle this.\\"\\n\\n**Score:** 0 out of 100\\n\\n**Feedback:** This is a fundamental skill for an ASP.NET Core developer. The candidate should be able to explain how to implement CORS to allow requests from external domains.\\n\\n**Question 2:** How would you handle HTTP POST requests with large payloads in an ASP.NET Core application to avoid performance issues?\\n\\n**Answer:** \\"I'm sorry, I don't know.\\"\\n\\n**Score:** 0 out of 100\\n\\n**Feedback:** This is another basic skill for an ASP.NET Core developer. The candidate should be able to explain how to handle large payloads in order to avoid performance issues.\\n\\n**Overall:** The candidate's answers were not satisfactory. They were unable to answer either of the two questions that were asked. I would recommend that the candidate review these topics and practice answering questions about them before their next interview."	b2c9654e-c038-4a24-80e5-a3d4f522a721	rec_cre4ft5qrj67qh0duthg	0	2024-09-07 12:32:52.358307+00	2024-09-07 12:32:52.358307+00
\.


--
-- Data for Name: interview_scheduleinterview; Type: TABLE DATA; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

COPY public.interview_scheduleinterview (id, name, email, unique_id, start_time, end_time, created_at, job_role, experience, interview_type, interview_completed, scheduled_by, interview_link) FROM stdin;
1	Dev namdev	devnamdevcse@gmail.com	e2b8b4d9-1646-492c-a1ee-87f91db702a9	2024-04-17 05:33:00+00	2024-04-25 05:33:00+00	2024-04-17 05:33:24.749592+00	Software Development	Fresher	Personal Interview	t	dev	https://ai-interview-assistant.onrender.com/interview/e2b8b4d9-1646-492c-a1ee-87f91db702a9/
34	princy goyal	princygoyal1148@gmail.com	5ce42aba-e9f5-4028-b648-e2b7d71d184e	2024-05-10 07:45:00+00	2024-05-14 07:45:00+00	2024-05-03 07:46:20.384373+00	business development	Fresher	HR Interview	f	Priyanshu	https://ai-interview-assistant.onrender.com/interview/5ce42aba-e9f5-4028-b648-e2b7d71d184e/
67	dev namdev	devnamdevcse@gmail.com	3fcf540c-3fba-4541-99a5-889a5001f26c	2024-06-05 06:32:00+00	2024-06-06 06:32:00+00	2024-06-05 06:33:03.532278+00	Software developer	0 to 1 year	Technical Interview	f	Priyanshu	https://ai-interview-assistant.onrender.com/interview/3fcf540c-3fba-4541-99a5-889a5001f26c/
100	Pawan Verma	pawanv@omnixm.com	c306d6fc-c941-4f54-b50d-eecefd7b5814	2024-07-29 06:57:00+00	2024-07-30 06:57:00+00	2024-07-29 06:58:19.798687+00	Quality Assurence	Fresher	Technical Interview	f	dev	https://ai-interview-assistant.onrender.com/interview/c306d6fc-c941-4f54-b50d-eecefd7b5814/
101	Dev namdev	devn@omnixm.com	962a3f2d-7234-45fe-be02-eb002ffc44ab	2024-07-29 06:59:00+00	2024-07-30 06:59:00+00	2024-07-29 06:59:27.501472+00	Software Developer	Fresher	Technical Interview	t	dev	https://ai-interview-assistant.onrender.com/interview/962a3f2d-7234-45fe-be02-eb002ffc44ab/
134	Sanket	sanket.s.bhandare@gmail.com	40c13373-51dd-4595-b59d-8ec97dcc0572	2024-07-30 02:39:00+00	2024-07-30 15:40:00+00	2024-07-30 13:39:41.516551+00	front end	More than 5 years	Personal Interview	t	dev	https://ai-interview-assistant.onrender.com/interview/40c13373-51dd-4595-b59d-8ec97dcc0572/
167	Shubham Athawane	shubhamathawane02@gmail.com	3e284283-2f07-4dda-9076-6c408f9cd950	2024-08-06 17:58:00+00	2024-08-07 17:58:00+00	2024-08-06 17:58:34.753849+00	software developer	Fresher	HR Interview	f	dev	https://ai-interview-assistant.onrender.com/interview/3e284283-2f07-4dda-9076-6c408f9cd950/
200	dev	devnamdevcse@gmail.com	b2c9654e-c038-4a24-80e5-a3d4f522a721	2024-09-07 12:29:00+00	2024-09-08 12:30:00+00	2024-09-07 12:30:16.400686+00	ASP.NET developer 	More than 5 years	Technical Interview	t	dev	https://ai-interview-assistant.onrender.com/interview/b2c9654e-c038-4a24-80e5-a3d4f522a721/
\.


--
-- Name: api_contact_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.api_contact_id_seq', 1, false);


--
-- Name: auth_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.auth_group_id_seq', 33, true);


--
-- Name: auth_group_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.auth_group_permissions_id_seq', 40, true);


--
-- Name: auth_permission_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.auth_permission_id_seq', 72, true);


--
-- Name: django_admin_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.django_admin_log_id_seq', 102, true);


--
-- Name: django_content_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.django_content_type_id_seq', 42, true);


--
-- Name: django_migrations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.django_migrations_id_seq', 54, true);


--
-- Name: home_customuser_groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.home_customuser_groups_id_seq', 33, true);


--
-- Name: home_customuser_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.home_customuser_id_seq', 433, true);


--
-- Name: home_customuser_user_permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.home_customuser_user_permissions_id_seq', 1, false);


--
-- Name: interview_interviewmodel_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.interview_interviewmodel_id_seq', 132, true);


--
-- Name: interview_scheduleinterview_id_seq; Type: SEQUENCE SET; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

SELECT pg_catalog.setval('public.interview_scheduleinterview_id_seq', 232, true);


--
-- Name: api_contact api_contact_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.api_contact
    ADD CONSTRAINT api_contact_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_name_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_name_key UNIQUE (name);


--
-- Name: auth_group_permissions auth_group_permissions_group_id_permission_id_0cd325b0_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_permission_id_0cd325b0_uniq UNIQUE (group_id, permission_id);


--
-- Name: auth_group_permissions auth_group_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_pkey PRIMARY KEY (id);


--
-- Name: auth_group auth_group_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_group
    ADD CONSTRAINT auth_group_pkey PRIMARY KEY (id);


--
-- Name: auth_permission auth_permission_content_type_id_codename_01ab375a_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_codename_01ab375a_uniq UNIQUE (content_type_id, codename);


--
-- Name: auth_permission auth_permission_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_pkey PRIMARY KEY (id);


--
-- Name: django_admin_log django_admin_log_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_pkey PRIMARY KEY (id);


--
-- Name: django_content_type django_content_type_app_label_model_76bd3d3b_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_app_label_model_76bd3d3b_uniq UNIQUE (app_label, model);


--
-- Name: django_content_type django_content_type_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_content_type
    ADD CONSTRAINT django_content_type_pkey PRIMARY KEY (id);


--
-- Name: django_migrations django_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_migrations
    ADD CONSTRAINT django_migrations_pkey PRIMARY KEY (id);


--
-- Name: django_session django_session_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_session
    ADD CONSTRAINT django_session_pkey PRIMARY KEY (session_key);


--
-- Name: home_customuser home_customuser__pgroll_new_xata_id_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser
    ADD CONSTRAINT home_customuser__pgroll_new_xata_id_key UNIQUE (xata_id);


--
-- Name: home_customuser_groups home_customuser_groups_customuser_id_group_id_b342dd9a_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_groups
    ADD CONSTRAINT home_customuser_groups_customuser_id_group_id_b342dd9a_uniq UNIQUE (customuser_id, group_id);


--
-- Name: home_customuser_groups home_customuser_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_groups
    ADD CONSTRAINT home_customuser_groups_pkey PRIMARY KEY (id);


--
-- Name: home_customuser home_customuser_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser
    ADD CONSTRAINT home_customuser_phone_number_key UNIQUE (phone_number);


--
-- Name: home_customuser home_customuser_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser
    ADD CONSTRAINT home_customuser_pkey PRIMARY KEY (id);


--
-- Name: home_customuser_user_permissions home_customuser_user_per_customuser_id_permission_a032181a_uniq; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_user_permissions
    ADD CONSTRAINT home_customuser_user_per_customuser_id_permission_a032181a_uniq UNIQUE (customuser_id, permission_id);


--
-- Name: home_customuser_user_permissions home_customuser_user_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_user_permissions
    ADD CONSTRAINT home_customuser_user_permissions_pkey PRIMARY KEY (id);


--
-- Name: home_customuser home_customuser_username_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser
    ADD CONSTRAINT home_customuser_username_key UNIQUE (username);


--
-- Name: interview_interviewmodel interview_interviewmodel__pgroll_new_xata_id_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.interview_interviewmodel
    ADD CONSTRAINT interview_interviewmodel__pgroll_new_xata_id_key UNIQUE (xata_id);


--
-- Name: interview_interviewmodel interview_interviewmodel_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.interview_interviewmodel
    ADD CONSTRAINT interview_interviewmodel_pkey PRIMARY KEY (id);


--
-- Name: interview_scheduleinterview interview_scheduleinterview_pkey; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.interview_scheduleinterview
    ADD CONSTRAINT interview_scheduleinterview_pkey PRIMARY KEY (id);


--
-- Name: interview_scheduleinterview interview_scheduleinterview_unique_id_key; Type: CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.interview_scheduleinterview
    ADD CONSTRAINT interview_scheduleinterview_unique_id_key UNIQUE (unique_id);


--
-- Name: auth_group_name_a6ea08ec_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX auth_group_name_a6ea08ec_like ON public.auth_group USING btree (name varchar_pattern_ops);


--
-- Name: auth_group_permissions_group_id_b120cbf9; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX auth_group_permissions_group_id_b120cbf9 ON public.auth_group_permissions USING btree (group_id);


--
-- Name: auth_group_permissions_permission_id_84c5c92e; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX auth_group_permissions_permission_id_84c5c92e ON public.auth_group_permissions USING btree (permission_id);


--
-- Name: auth_permission_content_type_id_2f476e4b; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX auth_permission_content_type_id_2f476e4b ON public.auth_permission USING btree (content_type_id);


--
-- Name: django_admin_log_content_type_id_c4bce8eb; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX django_admin_log_content_type_id_c4bce8eb ON public.django_admin_log USING btree (content_type_id);


--
-- Name: django_admin_log_user_id_c564eba6; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX django_admin_log_user_id_c564eba6 ON public.django_admin_log USING btree (user_id);


--
-- Name: django_session_expire_date_a5c62663; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX django_session_expire_date_a5c62663 ON public.django_session USING btree (expire_date);


--
-- Name: django_session_session_key_c0390e0f_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX django_session_session_key_c0390e0f_like ON public.django_session USING btree (session_key varchar_pattern_ops);


--
-- Name: home_customuser_groups_customuser_id_34f18930; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX home_customuser_groups_customuser_id_34f18930 ON public.home_customuser_groups USING btree (customuser_id);


--
-- Name: home_customuser_groups_group_id_d4a55f72; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX home_customuser_groups_group_id_d4a55f72 ON public.home_customuser_groups USING btree (group_id);


--
-- Name: home_customuser_phone_number_a0d3dc1a_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX home_customuser_phone_number_a0d3dc1a_like ON public.home_customuser USING btree (phone_number varchar_pattern_ops);


--
-- Name: home_customuser_user_permissions_customuser_id_8a95c1d3; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX home_customuser_user_permissions_customuser_id_8a95c1d3 ON public.home_customuser_user_permissions USING btree (customuser_id);


--
-- Name: home_customuser_user_permissions_permission_id_d445b84f; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX home_customuser_user_permissions_permission_id_d445b84f ON public.home_customuser_user_permissions USING btree (permission_id);


--
-- Name: home_customuser_username_617277eb_like; Type: INDEX; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

CREATE INDEX home_customuser_username_617277eb_like ON public.home_customuser USING btree (username varchar_pattern_ops);


--
-- Name: auth_group_permissions auth_group_permissio_permission_id_84c5c92e_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissio_permission_id_84c5c92e_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_group_permissions auth_group_permissions_group_id_b120cbf9_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_group_permissions
    ADD CONSTRAINT auth_group_permissions_group_id_b120cbf9_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: auth_permission auth_permission_content_type_id_2f476e4b_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.auth_permission
    ADD CONSTRAINT auth_permission_content_type_id_2f476e4b_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_content_type_id_c4bce8eb_fk_django_co; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_content_type_id_c4bce8eb_fk_django_co FOREIGN KEY (content_type_id) REFERENCES public.django_content_type(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: django_admin_log django_admin_log_user_id_c564eba6_fk_home_customuser_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.django_admin_log
    ADD CONSTRAINT django_admin_log_user_id_c564eba6_fk_home_customuser_id FOREIGN KEY (user_id) REFERENCES public.home_customuser(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: home_customuser_groups home_customuser_grou_customuser_id_34f18930_fk_home_cust; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_groups
    ADD CONSTRAINT home_customuser_grou_customuser_id_34f18930_fk_home_cust FOREIGN KEY (customuser_id) REFERENCES public.home_customuser(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: home_customuser_groups home_customuser_groups_group_id_d4a55f72_fk_auth_group_id; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_groups
    ADD CONSTRAINT home_customuser_groups_group_id_d4a55f72_fk_auth_group_id FOREIGN KEY (group_id) REFERENCES public.auth_group(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: home_customuser_user_permissions home_customuser_user_customuser_id_8a95c1d3_fk_home_cust; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_user_permissions
    ADD CONSTRAINT home_customuser_user_customuser_id_8a95c1d3_fk_home_cust FOREIGN KEY (customuser_id) REFERENCES public.home_customuser(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: home_customuser_user_permissions home_customuser_user_permission_id_d445b84f_fk_auth_perm; Type: FK CONSTRAINT; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

ALTER TABLE ONLY public.home_customuser_user_permissions
    ADD CONSTRAINT home_customuser_user_permission_id_d445b84f_fk_auth_perm FOREIGN KEY (permission_id) REFERENCES public.auth_permission(id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: SCHEMA pg_catalog; Type: ACL; Schema: -; Owner: xataadmin
--

SET SESSION AUTHORIZATION rdsadmin;
GRANT USAGE ON SCHEMA pg_catalog TO PUBLIC;
RESET SESSION AUTHORIZATION;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


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
-- Name: TABLE api_contact; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.api_contact TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE auth_group; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.auth_group TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE auth_group_permissions; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.auth_group_permissions TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE auth_permission; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.auth_permission TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE django_admin_log; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.django_admin_log TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE django_content_type; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.django_content_type TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE django_migrations; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.django_migrations TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE django_session; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.django_session TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE home_customuser; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.home_customuser TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE home_customuser_groups; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.home_customuser_groups TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE home_customuser_user_permissions; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.home_customuser_user_permissions TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE interview_interviewmodel; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.interview_interviewmodel TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- Name: TABLE interview_scheduleinterview; Type: ACL; Schema: public; Owner: xata_owner_bb_q787r2egrt10deud8nc50k7ems
--

GRANT SELECT ON TABLE public.interview_scheduleinterview TO xata_ro_group_bb_q787r2egrt10deud8nc50k7ems;


--
-- PostgreSQL database dump complete
--

