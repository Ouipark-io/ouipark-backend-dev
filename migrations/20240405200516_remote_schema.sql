
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";

CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "postgis" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE TYPE "public"."account_type" AS ENUM (
    'occupier',
    'owner',
    'both'
);

ALTER TYPE "public"."account_type" OWNER TO "postgres";

CREATE TYPE "public"."booking_inventory_status" AS ENUM (
    'started',
    'ended',
    'owner_started',
    'occupier_started',
    'owner_ended',
    'occupier_ended',
    'start_inventory_done',
    'end_inventory_done'
);

ALTER TYPE "public"."booking_inventory_status" OWNER TO "postgres";

COMMENT ON TYPE "public"."booking_inventory_status" IS 'If is start or end';

CREATE TYPE "public"."booking_status" AS ENUM (
    'pending',
    'canceled',
    'rejected',
    'payment_pending',
    'start_of_inventory',
    'location_ongoing',
    'end_of_inventory',
    'location_ended',
    'expired',
    'request_interruption_by_owner',
    'request_interruption_by_occupier',
    'interrupted'
);

ALTER TYPE "public"."booking_status" OWNER TO "postgres";

CREATE TYPE "public"."continents" AS ENUM (
    'Africa',
    'Antarctica',
    'Asia',
    'Europe',
    'Oceania',
    'North America',
    'South America'
);

ALTER TYPE "public"."continents" OWNER TO "postgres";

CREATE TYPE "public"."gender" AS ENUM (
    'male',
    'female'
);

ALTER TYPE "public"."gender" OWNER TO "postgres";

CREATE TYPE "public"."parking_alert_status" AS ENUM (
    'pending',
    'done',
    'active',
    'canceled',
    'persist',
    'deleted'
);

ALTER TYPE "public"."parking_alert_status" OWNER TO "postgres";

COMMENT ON TYPE "public"."parking_alert_status" IS 'All status of alert notification';

CREATE TYPE "public"."payment_method" AS ENUM (
    'paypal',
    'credit_card',
    'bank_account',
    'sepa'
);

ALTER TYPE "public"."payment_method" OWNER TO "postgres";

COMMENT ON TYPE "public"."payment_method" IS 'All payment methods';

CREATE TYPE "public"."report_target" AS ENUM (
    'profile',
    'parking',
    'location_owner',
    'location_occupier'
);

ALTER TYPE "public"."report_target" OWNER TO "postgres";

CREATE TYPE "public"."transaction_status" AS ENUM (
    'paid',
    'unpaid',
    'refunded',
    'pending'
);

ALTER TYPE "public"."transaction_status" OWNER TO "postgres";

COMMENT ON TYPE "public"."transaction_status" IS 'All status of payment transaction';

CREATE OR REPLACE FUNCTION "public"."create_new_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$begin
  IF NEW.raw_user_meta_data ->> 'account_type' IS NULL THEN
    NEW.raw_user_meta_data := NEW.raw_user_meta_data || '{"account_type": "occupier"}';
  END IF;

  insert into public.profiles (user_id, email, first_name, last_name, provider, account_type)
  values (
    new.id, 
    new.email,
    new.raw_user_meta_data ->> 'first_name', 
    new.raw_user_meta_data ->> 'last_name',
    new.raw_app_meta_data ->> 'provider',
    (new.raw_user_meta_data ->> 'account_type')::account_type);
    -- new.raw_user_meta_data['account_type']::account_type);
  return new;
end;
$$;

ALTER FUNCTION "public"."create_new_user_profile"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."create_transaction_after_location_accepted"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$BEGIN

END$$;

ALTER FUNCTION "public"."create_transaction_after_location_accepted"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_booking_by_id"("p_booking_id" "uuid") RETURNS TABLE("id" "uuid", "start_date" timestamp with time zone, "end_date" timestamp with time zone, "status" "public"."booking_status"[], "created_at" timestamp with time zone, "transaction_id" "uuid", "parking" "jsonb", "owner" "jsonb", "booking_inventories" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Sélectionnez les "bookings" liés aux "parkings" dont la valeur de "owner_id" correspond à owner_id_variable
    RETURN QUERY
        SELECT
            b.id,
            b.start_date,
            b.end_date,
            b.status,
            b.created_at,
            b.transaction_id,
            jsonb_build_object(
                    'id', p.id,
                    'title', p.title,
                    'images_url', p.images_url,
                    'price_per_day', p.price_per_day,
                    'price_per_week', p.price_per_week,
                    'price_per_month', p.price_per_month,
                    'caution', p.caution,
                    'owner', jsonb_build_object(
                            'user_id', parking_owner.user_id,
                            'first_name', parking_owner.first_name,
                            'last_name', parking_owner.last_name,
                            'avatar', parking_owner.avatar,
                            'evaluations', (
                                SELECT json_agg(
                                       json_build_object(
                                               'id', e.id,
                                               'note', e.note,
                                               'comment', e.comment,
                                               'created_at', e.created_at
                                       )
                               )
                                FROM public.evaluations e
                                WHERE e.parking_id = p.id
                            )
                    ),
                    'address', jsonb_build_object(
                        'id'  , a.id,
                        'street', a.street,
                        'city', a.city,
                        'full_address', a.full_address,
                        'postal_code', a.postal_code
                    )
            ) AS parking,
            jsonb_build_object(
                    'user_id', booking_owner.user_id,
                    'first_name', booking_owner.first_name,
                    'last_name', booking_owner.last_name,
                    'avatar', booking_owner.avatar
            ) AS owner,
            CASE
                WHEN bi.id IS NOT NULL
                THEN jsonb_build_object(
                    'id', bi.id,
                    'status', bi.status,
                    'start_inventory_contract_url', bi.start_inventory_contract_url,
                    'end_inventory_contract_url', bi.end_inventory_contract_url
                )
            END AS booking_inventories
        FROM public.bookings b
                 JOIN
             public.parkings p ON b.parking_id = p.id
                 JOIN
             public.profiles parking_owner ON p.owner_id = parking_owner.user_id
                 JOIN
             public.profiles booking_owner ON b.owner_id = booking_owner.user_id
                LEFT JOIN
            public.booking_inventories bi ON bi.booking_id = b.id
                 JOIN
            public.addresses a ON p.id = a.parking_id
        WHERE b.id = p_booking_id AND p.is_archived = false
        GROUP BY b.id, p.id, parking_owner.user_id, booking_owner.user_id, bi.id, a.id;
END;
$$;

ALTER FUNCTION "public"."get_booking_by_id"("p_booking_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_bookings_by_occupier_id"("occupier_id" "uuid", "p_booking_status" "public"."booking_status"[]) RETURNS TABLE("id" "uuid", "start_date" timestamp with time zone, "end_date" timestamp with time zone, "status" "public"."booking_status"[], "created_at" timestamp with time zone, "transaction_id" "uuid", "parking" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Sélectionnez les "bookings" liés aux "parkings" dont la valeur de "owner_id" correspond à owner_id_variable
    RETURN QUERY
        WITH LatestStatus AS (
            SELECT
                b.id AS booking_id,
                b.status[array_length(b.status, 1)] AS latest_status
            FROM
                public.bookings b
            WHERE
                array_length(b.status, 1) > 0
        )
        SELECT
            b.id,
            b.start_date,
            b.end_date,
            b.status,
            b.created_at,
            b.transaction_id,
            jsonb_build_object(
                'id', p.id,
                'title', p.title,
                'images_url', p.images_url,
                'price_per_day', p.price_per_day,
                'price_per_week', p.price_per_week,
                'price_per_month', p.price_per_month,
                'caution', p.caution,
                'owner', jsonb_build_object(
                        'user_id', p.owner_id,
                        'first_name', profile.first_name,
                        'last_name', profile.last_name,
                        'avatar', profile.avatar
                         )
            ) AS parking
        FROM public.bookings b
                 JOIN
             public.parkings p ON b.parking_id = p.id
                 JOIN
             public.profiles profile ON p.owner_id = profile.user_id
                 JOIN
             LatestStatus ls ON b.id = ls.booking_id
        WHERE
            b.owner_id = occupier_id
        AND ls.latest_status = ANY(p_booking_status)
        AND p.is_archived = false
        GROUP BY b.id, p.id, profile.user_id;
END;
$$;

ALTER FUNCTION "public"."get_bookings_by_occupier_id"("occupier_id" "uuid", "p_booking_status" "public"."booking_status"[]) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_bookings_by_owner_id"("parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) RETURNS TABLE("id" "uuid", "start_date" timestamp with time zone, "end_date" timestamp with time zone, "status" "public"."booking_status"[], "created_at" timestamp with time zone, "owner_id" "uuid", "transaction_id" "uuid", "parking" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Sélectionnez les "bookings" liés aux "parkings" dont la valeur de "owner_id" correspond à owner_id_variable
    RETURN QUERY
        WITH LatestStatus AS (
            SELECT
                b.id AS booking_id,
                b.status[array_length(b.status, 1)] AS latest_status
            FROM
                public.bookings b
            WHERE
                array_length(b.status, 1) > 0
        )
        SELECT
            b.id,
            b.start_date,
            b.end_date,
            b.status,
            b.created_at,
            b.owner_id,
            b.transaction_id,
            jsonb_build_object(
                'id', p.id,
                'title', p.title,
                'images_url', p.images_url,
                'price_per_day', p.price_per_day,
                'price_per_week', p.price_per_week,
                'price_per_month', p.price_per_month,
                'owner', jsonb_build_object(
                    'user_id', p.owner_id,
                    'first_name', profile.first_name,
                    'last_name', profile.last_name,
                    'avatar', profile.avatar
                )
            ) AS parking
        FROM public.bookings b
                 JOIN
             public.parkings p ON b.parking_id = p.id
                 JOIN
             public.profiles profile ON p.owner_id = profile.user_id
                 JOIN
             LatestStatus ls ON b.id = ls.booking_id
        WHERE
            p.owner_id = parking_owner_id
          AND
            ls.latest_status = ANY(p_booking_status)
          AND
            p.is_archived = false
        GROUP BY b.id, p.id, profile.user_id;
END;
$$;

ALTER FUNCTION "public"."get_bookings_by_owner_id"("parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_bookings_by_parking_id"("p_parking_id" "uuid", "parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) RETURNS TABLE("id" "uuid", "start_date" timestamp with time zone, "end_date" timestamp with time zone, "status" "public"."booking_status"[], "created_at" timestamp with time zone, "owner_id" "uuid", "transaction_id" "uuid", "parking" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Sélectionnez les "bookings" liés aux "parkings" dont la valeur de "owner_id" correspond à owner_id_variable
    RETURN QUERY
        WITH LatestStatus AS (
            SELECT
                b.id AS booking_id,
                b.status[array_length(b.status, 1)] AS latest_status
            FROM
                public.bookings b
            WHERE
                array_length(b.status, 1) > 0
        )
        SELECT
            b.id,
            b.start_date,
            b.end_date,
            b.status,
            b.created_at,
            b.owner_id,
            b.transaction_id,
            jsonb_build_object(
                    'id', p.id,
                    'title', p.title,
                    'images_url', p.images_url,
                    'price_per_day', p.price_per_day,
                    'price_per_week', p.price_per_week,
                    'price_per_month', p.price_per_month,
                    'owner', jsonb_build_object(
                            'user_id', p.owner_id,
                            'first_name', profile.first_name,
                            'last_name', profile.last_name,
                            'avatar', profile.avatar
                             )
            ) AS parking
        FROM public.bookings b
                 JOIN
             public.parkings p ON b.parking_id = p.id
                 JOIN
             public.profiles profile ON p.owner_id = profile.user_id
                 JOIN
             LatestStatus ls ON b.id = ls.booking_id
        WHERE p.owner_id = parking_owner_id
          and ls.latest_status = ANY(p_booking_status)
          and p.id = p_parking_id
          AND p.is_archived = false
        GROUP BY b.id, p.id, profile.user_id;
END;
$$;

ALTER FUNCTION "public"."get_bookings_by_parking_id"("p_parking_id" "uuid", "parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_chat_messages"("p_sender_id" "uuid", "p_recipient_id" "uuid") RETURNS TABLE("id" "uuid", "sender_id" "uuid", "recipient_id" "uuid", "messages" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
        SELECT
            c.id AS id,
            c.sender_id,
            c.recipient_id,
            jsonb_agg(
                jsonb_build_object(
                    'id', m.id,
                    'content', m.content,
                    'created_at', m.created_at,
                    'author', jsonb_build_object(
                        'user_id', m.author_id,
                        'first_name', p.first_name,
                        'last_name', p.last_name
                          )
                )
            ) AS messages
        FROM
            chats c
                JOIN
            messages m ON c.id = m.chat_id
                JOIN
            profiles p ON m.author_id = p.user_id
        WHERE
            (c.sender_id = p_sender_id AND c.recipient_id = p_recipient_id)
           OR (c.sender_id = p_recipient_id AND c.recipient_id = p_sender_id)
        GROUP BY
            c.id, c.sender_id, c.recipient_id
        ORDER BY
            MIN(m.created_at) DESC;
END;
$$;

ALTER FUNCTION "public"."get_chat_messages"("p_sender_id" "uuid", "p_recipient_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_owner_profile_by_id"("p_owner_id" "uuid") RETURNS TABLE("user_id" "uuid", "first_name" "text", "last_name" "text", "avatar" "text", "created_at" timestamp with time zone, "parkings" "jsonb", "profile_evaluations" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Sélectionnez les "bookings" liés aux "parkings" dont la valeur de "owner_id" correspond à owner_id_variable
    RETURN QUERY
        SELECT
            -- Sélectionnez les informations de profil de l'utilisateur propriétaire
            profile.user_id,
            profile.first_name,
            profile.last_name,
            profile.avatar,
            profile.created_at,
            -- Sélectionnez les informations sur les parkings du propriétaire
            jsonb_agg(
                jsonb_build_object(
                    'id', p.id,
                    'title', p.title,
                    'images_url', p.images_url,
                    'price_per_day', p.price_per_day,
                    'price_per_week', p.price_per_week,
                    'price_per_month', p.price_per_month,
                    'caution', p.caution,
                    'address', jsonb_build_object(
                        'id'  , a.id,
                        'street', a.street,
                        'city', a.city,
                        'full_address', a.full_address,
                        'postal_code', a.postal_code
                    ),
                    'evaluations', evaluations
                )
            ) AS parking,
            -- Sélectionnez les évaluations de profil
            CASE
                WHEN COUNT(profile_eval) > 0 THEN
                    jsonb_agg(
                        jsonb_build_object(
                            'id', profile_eval.id,
                            'note', profile_eval.note,
                            'comment', profile_eval.comment,
                            'author', jsonb_build_object(
                                'user_id', profile_eval_author.user_id,
                                'first_name', profile_eval_author.first_name,
                                'last_name', profile_eval_author.last_name,
                                'avatar', profile_eval_author.avatar,
                                'created_at', profile_eval_author.created_at
                            )
                        )
                    )
                ELSE
                    '[]'::jsonb
                END AS profile_evaluations
        FROM
            public.profiles profile
        JOIN public.parkings p ON p.owner_id = p_owner_id
        JOIN public.addresses a ON a.parking_id = p.id
        LEFT JOIN public.profile_evaluations profile_eval ON profile_eval.profile_id = profile.user_id
        LEFT JOIN public.profiles profile_eval_author ON profile_eval_author.user_id = profile_eval.author_id
        LEFT JOIN (
            SELECT
                ev.parking_id,
                json_agg(
                    jsonb_build_object(
                        'id', ev.id,
                        'note', ev.note,
                        'comment', ev.comment,
                        'created_at', ev.created_at,
                        'author', jsonb_build_object(
                            'user_id', ep.user_id,
                            'first_name', ep.first_name,
                            'last_name', ep.last_name,
                            'avatar', ep.avatar,
                            'created_at', ep.created_at
                        )
                    )
                ) AS evaluations
            FROM
                public.evaluations ev
                    LEFT JOIN public.profiles ep ON ev.author_id = ep.user_id
            GROUP BY
                ev.parking_id
        ) evaluations ON evaluations.parking_id = p.id
        WHERE
            profile.user_id = p_owner_id AND p.is_archived = false
        GROUP BY
            profile.user_id, a.id, p.id, profile_eval.id;
END;
$$;

ALTER FUNCTION "public"."get_owner_profile_by_id"("p_owner_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_parkings_by_filters"("features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real, "lat" double precision, "long" double precision, "max_distance_meters" double precision) RETURNS TABLE("data" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    parking_record jsonb;
    parkings_json jsonb[];
BEGIN
    FOR parking_record IN
        SELECT row_to_json(p)::jsonb
        FROM (
            SELECT
                p.id,
                p.title,
                p.description,
                p.price_per_day,
                p.price_per_month,
                p.price_per_week,
                p.start_date,
                p.end_date,
                p.is_booked,
                p.created_at,
                p.is_archived,
                p.images_url,
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'id', e.id,
                            'comment', e.comment,
                            'note', e.note,
                            'createdAt', e.created_at
                        )
                    )
                    FROM evaluations e
                    WHERE e.parking_id = p.id
                ) AS evaluations,
                jsonb_build_object(
                    'id', a.id,
                    'city', a.city,
                    'country', a.country,
                    'street', a.street,
                    'postal_code', a.postal_code,
                    'created_at', a.created_at,
                    'placeId', a.place_id,
                    'location', a.location,
                    'full_address', a.full_address
                ) AS address,
                ST_Distance(a.location, ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography) AS distanceMeters
            FROM public.parkings p
            LEFT JOIN parking_images ON parking_images.parking_id = p.id
            LEFT JOIN evaluations ON evaluations.parking_id = p.id
            LEFT JOIN addresses a ON a.parking_id = p.id
            WHERE ST_DWithin(a.location, ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography, max_distance_meters)
                AND p.is_archived = false
                AND p.is_booked = false
                AND p.price_per_day >= min_price::float4
                AND (
                    p.price_per_day <= max_price::float4
                    OR p.price_per_week <= max_price::float4
                    OR p.price_per_month <= max_price::float4
                )
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.parking_features f
                    WHERE f.parking_id = p.id
                        AND f.feature_id = ANY(features)
                        AND features IS NOT NULL
                )
                AND NOT EXISTS (
                    SELECT 1
                    FROM public.parking_car_types ct
                    WHERE ct.parking_id = p.id
                        AND ct.car_type_id = ANY(car_types)
                        AND car_types IS NOT NULL
                )
            GROUP BY p.id, p.title, p.description, p.price_per_day, p.price_per_month, p.price_per_week, p.start_date, p.end_date, p.is_booked, p.created_at, p.is_archived, a.id, a.city, a.country, a.street, a.postal_code, a.created_at, a.place_id, a.full_address
        ) p
    LOOP
        parkings_json := parkings_json || parking_record;
    END LOOP;

    RETURN QUERY SELECT jsonb_agg(value) FROM UNNEST(parkings_json) AS t(value);
END;
$$;

ALTER FUNCTION "public"."get_parkings_by_filters"("features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real, "lat" double precision, "long" double precision, "max_distance_meters" double precision) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."get_parkings_by_owner_id"("p_owner_id" "uuid") RETURNS TABLE("id" "uuid", "title" "text", "description" "text", "price_per_day" real, "created_at" timestamp with time zone, "price_per_month" real, "price_per_week" real, "start_date" timestamp with time zone, "end_date" timestamp with time zone, "is_booked" boolean, "is_archived" boolean, "owner_id" "uuid", "images_url" "text"[], "proof_identity_file" "text", "evaluations" "jsonb", "address" "jsonb")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    RETURN QUERY
        SELECT
            parking.id,
            parking.title,
            parking.description,
            parking.price_per_day,
            parking.created_at,
            parking.price_per_month,
            parking.price_per_week,
            parking.start_date,
            parking.end_date,
            parking.is_booked,
            parking.is_archived,
            parking.owner_id,
            parking.images_url,
            parking.proof_identity_file,
            CASE
                WHEN bool_or(e.id IS NOT NULL) THEN
                    jsonb_agg(
                            jsonb_build_object(
                                    'id', e.id,
                                    'note', e.note
                            )
                    )
                ELSE
                    '[]'::JSONB
                END AS evaluations,
            CASE
                WHEN bool_or(a.id IS NOT NULL) THEN
                    jsonb_build_object(
                            'id', a.id,
                            'full_address', a.full_address
                    )
                END AS address
        FROM
            public.parkings as parking
                LEFT JOIN
            public.evaluations e on parking.id = e.parking_id
                LEFT JOIN
            public.addresses a on parking.id = a.parking_id
        WHERE parking.owner_id = p_owner_id and parking.is_archived = false
        GROUP BY parking.id, a.id;
END;
$$;

ALTER FUNCTION "public"."get_parkings_by_owner_id"("p_owner_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."is_chat_exist"("p_sender_id" "uuid", "p_recipient_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    chat_id uuid;
BEGIN
    SELECT
        c.id AS id
    INTO chat_id
    FROM
        chats c
    WHERE
        (c.sender_id = p_sender_id AND c.recipient_id = p_recipient_id)
       OR (c.sender_id = p_recipient_id AND c.recipient_id = p_sender_id);

    RETURN json_build_object(
        'id', chat_id
    );
END;
$$;

ALTER FUNCTION "public"."is_chat_exist"("p_sender_id" "uuid", "p_recipient_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."nearby_parkings_filter_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision, "features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real) RETURNS TABLE("data" "json")
    LANGUAGE "sql"
    AS $$
SELECT json_build_object(
    'id', p.id,
    'title', p.title,
    'description', p.description,
    'price_per_day', p.price_per_day,
    'price_per_month', p.price_per_month,
    'price_per_week', p.price_per_week,
    'start_date', p.start_date,
    'end_date', p.end_date,
    'is_booked', p.is_booked,
    'created_at', p.created_at,
    'is_archived', p.is_archived,
    'images_url', p.images_url,
    'evaluations', (
        SELECT json_agg(
            json_build_object(
                'id', e.id,
                'comment', e.comment,
                'note', e.note,
                'createdAt', e.created_at
            )
        )
        FROM evaluations e
        WHERE e.parking_id = p.id
    ),
    'address', json_build_object(
        'id', a.id,
        'city', a.city,
        'country', a.country,
        'street', a.street,
        'postal_code', a.postal_code,
        'created_at', a.created_at,
        'placeId', a.place_id,
        'location', a.location,
        'full_address', a.full_address
    ),
    'distanceMeters', ST_Distance(a.location, ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography)
)
FROM public.parkings p
LEFT JOIN parking_images ON parking_images.parking_id = p.id
LEFT JOIN evaluations ON evaluations.parking_id = p.id
LEFT JOIN addresses a ON a.parking_id = p.id
WHERE ST_DWithin(a.location, ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography, max_distance_meters)
    AND p.is_archived = false
    AND p.price_per_day >= min_price
    AND (
        p.price_per_day <= max_price
        OR p.price_per_week <= max_price
        OR p.price_per_month <= max_price
    )
    AND NOT EXISTS (
        SELECT 1
        FROM unnest(car_types) ct_id
        WHERE ct_id = ANY(SELECT DISTINCT pct.car_type_id FROM public.parking_car_types pct WHERE pct.parking_id = p.id)
    )
    AND NOT EXISTS (
        SELECT 1
        FROM unnest(features) feature_id
        WHERE feature_id = ANY(SELECT DISTINCT pf.feature_id FROM public.parking_features pf WHERE pf.parking_id = p.id)
    )
GROUP BY p.id, p.title, p.description, p.price_per_day, p.price_per_month, p.price_per_week, p.start_date, p.end_date, p.is_booked, p.created_at, p.is_archived, a.id, a.city, a.country, a.street, a.postal_code, a.created_at, a.place_id, a.full_address;
$$;

ALTER FUNCTION "public"."nearby_parkings_filter_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision, "features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."nearby_parkings_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision) RETURNS TABLE("data" "json")
    LANGUAGE "sql"
    AS $$
    SELECT json_build_object(
                'id', p.id,
                'title', p.title,
                'description', p.description,
                'price_per_day', p.price_per_day,
                'price_per_month', p.price_per_month,
                'price_per_week', p.price_per_week,
                'start_date', p.start_date,
                'end_date', p.end_date,
                'is_booked', p.is_booked,
                'created_at', p.created_at,
                'is_archived', p.is_archived,
                'images_url', p.images_url,
                'evaluations', (
                    SELECT json_agg(
                        json_build_object(
                            'id', e.id,
                            'comment', e.comment,
                            'note', e.note,
                            'createdAt', e.created_at
                        )
                    )
                    FROM evaluations e
                    WHERE e.parking_id = p.id
                ),
                'address', json_build_object(
                    'id', a.id,
                    'city', a.city,
                    'country', a.country,
                    'street', a.street,
                    'postal_code', a.postal_code,
                    'created_at', a.created_at,
                    'placeId', a.place_id,
                    'location', a.location,
                    'full_address', a.full_address
                ),
                'distanceMeters', ST_Distance(a.location, ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography)
            )
    FROM public.parkings p
    LEFT JOIN parking_images ON parking_images.parking_id = p.id
    LEFT JOIN evaluations ON evaluations.parking_id = p.id
    LEFT JOIN addresses a ON a.parking_id = p.id
    WHERE ST_DWithin(a.location, ST_SetSRID(ST_MakePoint(long, lat), 4326)::geography, max_distance_meters) AND p.is_archived = false
    GROUP BY p.id, p.title, p.description, p.price_per_day, p.price_per_month, p.price_per_week, p.start_date, p.end_date, p.is_booked, p.created_at, p.is_archived, a.id, a.city, a.country, a.street, a.postal_code, a.created_at, a.place_id, a.full_address;
$$;

ALTER FUNCTION "public"."nearby_parkings_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."schedule_unpaid_booking_removing"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
BEGIN
    -- Nommer le cron job avec l'id de l'enregistrement
    PERFORM cron.schedule(
            NEW.id::text,  -- Utiliser l'id de l'enregistrement comme nom du cron job
            TO_CHAR((NEW.created_at AT TIME ZONE 'Europe/Paris')  + INTERVAL '1 day', 'MI HH24 DD Mon *'),  -- Formatage de la date pour la planification
            format(
                $dyn$
                UPDATE bookings
                    SET status = ARRAY[
                        'pending'::booking_status,
                        'expired'::booking_status
                    ]
                    WHERE id = %L;
                SELECT cron.unschedule(%L);
            $dyn$, NEW.id::text, NEW.id::text
                       )
            );
    RETURN NEW;
END;
$_$;

ALTER FUNCTION "public"."schedule_unpaid_booking_removing"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."unschedule_cronjob"("job_id" "text") RETURNS TABLE("unschedule" boolean)
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    return query SELECT cron.unschedule(job_id);
END
$$;

ALTER FUNCTION "public"."unschedule_cronjob"("job_id" "text") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_booking_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
    last_status TEXT;
    booking_record RECORD;
BEGIN
    last_status := NEW.status[array_length(NEW.status, 1)];
    IF last_status = 'start_inventory_done'
        THEN
            -- Mettre à jour le statut de la réservation
            UPDATE bookings
            SET status = array_append(bookings.status, 'location_ongoing')
            WHERE id = NEW.booking_id;

            -- Récupérer l'enregistrement complet du booking
            SELECT * INTO booking_record FROM bookings WHERE id = NEW.booking_id;

            -- Schedule booking ending cron job
            PERFORM cron.schedule(
                NEW.booking_id::text,  -- Utiliser l'id de l'enregistrement comme nom du cron job
                TO_CHAR(booking_record.end_date AT TIME ZONE 'Europe/Paris', 'MI HH24 DD Mon *'),  -- Formatage de la date pour la planification
                format(
                    $dyn$
                    UPDATE bookings
                        SET status = ARRAY[
                            'pending'::booking_status,
                            'payment_pending'::booking_status,
                            'start_of_inventory'::booking_status,
                            'location_ongoing'::booking_status,
                            'end_of_inventory'::booking_status
                        ]
                    WHERE id = %L;
                    SELECT cron.unschedule(%L);
                    $dyn$, NEW.booking_id::text, NEW.booking_id::text
                )
            );
    ELSEIF last_status = 'end_inventory_done'
        THEN
            UPDATE bookings
            SET status = array_append(bookings.status, 'location_ended')
            WHERE id = NEW.booking_id;
    END IF;
    RETURN NEW;
END;
$_$;

ALTER FUNCTION "public"."update_booking_status"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."update_parking_status"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    last_status TEXT;
BEGIN
    last_status := NEW.status[array_length(NEW.status, 1)];
    IF last_status = ANY(ARRAY['pending', 'canceled', 'rejected', 'payment_pending', 'location_ended']) THEN
        UPDATE parkings
        SET is_booked = false
        WHERE id = NEW.parking_id;
    ELSE
        UPDATE parkings
        SET is_booked = true
        WHERE id = NEW.parking_id;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."update_parking_status"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "postal_code" bigint,
    "country" "text" NOT NULL,
    "city" "text" NOT NULL,
    "street" "text" NOT NULL,
    "full_address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "owner_id" "uuid",
    "location" "extensions"."geometry" NOT NULL,
    "coordinates" "jsonb",
    "parking_id" "uuid" NOT NULL,
    "place_id" "text"
);

ALTER TABLE "public"."addresses" OWNER TO "postgres";

COMMENT ON TABLE "public"."addresses" IS 'All parkings addresses';

COMMENT ON COLUMN "public"."addresses"."parking_id" IS 'ID du parking';

CREATE TABLE IF NOT EXISTS "public"."booking_inventories" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "owner_proof_images_start" "text"[],
    "owner_signature_start" "text",
    "occupier_signature_end" "text",
    "owner_proof_images_end" "text"[],
    "status" "public"."booking_inventory_status"[] DEFAULT ARRAY['started'::"public"."booking_inventory_status"],
    "occupier_signature_start" "text",
    "owner_signature_end" "text",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "occupier_proof_images_start" "text"[],
    "occupier_proof_images_end" "text"[],
    "start_inventory_contract_url" "text",
    "end_inventory_contract_url" "text"
);

ALTER TABLE "public"."booking_inventories" OWNER TO "postgres";

COMMENT ON TABLE "public"."booking_inventories" IS 'The both signed documents contract (without duplicated)';

CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "start_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "end_date" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "parking_id" "uuid" NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "transaction_id" "uuid",
    "status" "public"."booking_status"[] DEFAULT ARRAY['pending'::"public"."booking_status"] NOT NULL
);

ALTER TABLE "public"."bookings" OWNER TO "postgres";

COMMENT ON TABLE "public"."bookings" IS 'all bookings';

CREATE TABLE IF NOT EXISTS "public"."canceled_bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "booking_id" "uuid" NOT NULL,
    "reasons" "text"[] NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."canceled_bookings" OWNER TO "postgres";

COMMENT ON TABLE "public"."canceled_bookings" IS 'Contient les bookings refusés par les propriétaires et les raisons de ces refus';

CREATE TABLE IF NOT EXISTS "public"."car_types" (
    "title" "text" NOT NULL,
    "slug" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "display_position" integer DEFAULT 0 NOT NULL,
    "image_url" "text"
);

ALTER TABLE "public"."car_types" OWNER TO "postgres";

COMMENT ON TABLE "public"."car_types" IS 'Informations about the type of cars';

CREATE TABLE IF NOT EXISTS "public"."chats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "recipient_id" "uuid" NOT NULL
);

ALTER TABLE "public"."chats" OWNER TO "postgres";

COMMENT ON COLUMN "public"."chats"."recipient_id" IS 'Id de la personne à qui est destiné le message';

CREATE TABLE IF NOT EXISTS "public"."chats_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "owner_id" "uuid"
);

ALTER TABLE "public"."chats_users" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."countries" (
    "id" bigint NOT NULL,
    "name" "text",
    "iso2" "text" NOT NULL,
    "iso3" "text",
    "local_name" "text",
    "continent" "public"."continents"
);

ALTER TABLE "public"."countries" OWNER TO "postgres";

COMMENT ON TABLE "public"."countries" IS 'Full list of countries.';

COMMENT ON COLUMN "public"."countries"."name" IS 'Full country name.';

COMMENT ON COLUMN "public"."countries"."iso2" IS 'ISO 3166-1 alpha-2 code.';

COMMENT ON COLUMN "public"."countries"."iso3" IS 'ISO 3166-1 alpha-3 code.';

COMMENT ON COLUMN "public"."countries"."local_name" IS 'Local variation of the name.';

ALTER TABLE "public"."countries" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."countries_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "public"."evaluations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "comment" "text" NOT NULL,
    "note" smallint DEFAULT '1'::smallint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "author_id" "uuid" NOT NULL,
    "parking_id" "uuid" NOT NULL
);

ALTER TABLE "public"."evaluations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."features" (
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "title" "text",
    "slug" "text",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "image_url" "text"
);

ALTER TABLE "public"."features" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "author_id" "uuid" NOT NULL,
    "content" "text" NOT NULL
);

ALTER TABLE "public"."messages" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text",
    "content" "json",
    "image_url" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user" "uuid"
);

ALTER TABLE "public"."notifications" OWNER TO "postgres";

COMMENT ON TABLE "public"."notifications" IS 'All notifications users or services';

CREATE TABLE IF NOT EXISTS "public"."parking_alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "public"."parking_alert_status" DEFAULT 'pending'::"public"."parking_alert_status",
    "parking_id" "uuid",
    "user_id" "uuid"
);

ALTER TABLE "public"."parking_alerts" OWNER TO "postgres";

COMMENT ON TABLE "public"."parking_alerts" IS 'All alert when parking is not available';

CREATE TABLE IF NOT EXISTS "public"."parking_car_types" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "parking_id" "uuid",
    "car_type_id" "uuid"
);

ALTER TABLE "public"."parking_car_types" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."parking_features" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "parking_id" "uuid",
    "feature_id" "uuid"
);

ALTER TABLE "public"."parking_features" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."parking_images" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "parking_id" "uuid" NOT NULL,
    "image_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."parking_images" OWNER TO "postgres";

COMMENT ON TABLE "public"."parking_images" IS 'All parkings images table';

CREATE TABLE IF NOT EXISTS "public"."parking_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "report_label_id" "uuid" NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "parking_id" "uuid" NOT NULL,
    "message" "text",
    "report_file_path" "text"
);

ALTER TABLE "public"."parking_reports" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."parkings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "price_per_day" real NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "price_per_month" real NOT NULL,
    "price_per_week" real DEFAULT '0'::real,
    "start_date" timestamp with time zone NOT NULL,
    "end_date" timestamp with time zone,
    "is_booked" boolean DEFAULT false NOT NULL,
    "is_archived" boolean DEFAULT false NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "images_url" "text"[],
    "proof_identity_file" "text",
    "caution" real
);

ALTER TABLE "public"."parkings" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profile_cars" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "car_name" "text",
    "car_brand" "text",
    "plate_id" "text" NOT NULL,
    "car_birth" timestamp without time zone,
    "car_features" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" DEFAULT "gen_random_uuid"()
);

ALTER TABLE "public"."profile_cars" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profile_evaluations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "note" integer NOT NULL,
    "comment" "text",
    "profile_id" "uuid" NOT NULL,
    "author_id" "uuid" NOT NULL,
    "created_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "profile_evaluations_rate_check" CHECK ((("note" >= 1) AND ("note" <= 5)))
);

ALTER TABLE "public"."profile_evaluations" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profile_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "report_label_id" "uuid" NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "message" "text",
    "report_file_path" "text"
);

ALTER TABLE "public"."profile_reports" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."profile_views" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" DEFAULT "auth"."uid"() NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."profile_views" OWNER TO "postgres";

COMMENT ON TABLE "public"."profile_views" IS 'Table that stores views on profiles.';

CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "first_name" "text" DEFAULT ''::"text",
    "last_name" "text" DEFAULT ''::"text",
    "anniversary" "date",
    "gender" "public"."gender" DEFAULT 'male'::"public"."gender" NOT NULL,
    "has_kyc_stripe" boolean DEFAULT false NOT NULL,
    "has_kyc_identity" boolean DEFAULT false NOT NULL,
    "avatar" "text" DEFAULT 'https://fxkgsfrercahckxykmtd.supabase.co/storage/v1/object/public/ouipark-bucket/op-logo-square.png'::"text",
    "is_owner_active" boolean DEFAULT false NOT NULL,
    "account_type" "public"."account_type" DEFAULT 'occupier'::"public"."account_type" NOT NULL,
    "email" character varying,
    "stripe_account_id" "text",
    "provider" character varying(30) DEFAULT 'email'::character varying,
    "plate_id" "text",
    "identity_client_id" "text",
    "favorite_payment_method" "public"."payment_method" DEFAULT 'credit_card'::"public"."payment_method" NOT NULL,
    "is_blocked" boolean DEFAULT false NOT NULL,
    "count_password_attempts" smallint DEFAULT '0'::smallint NOT NULL
);

ALTER TABLE "public"."profiles" OWNER TO "postgres";

COMMENT ON TABLE "public"."profiles" IS 'User profile ';

COMMENT ON COLUMN "public"."profiles"."plate_id" IS 'ID plate of vehicle required (if user profile is occupier or both)';

COMMENT ON COLUMN "public"."profiles"."is_blocked" IS 'block use access after many attempts user';

COMMENT ON COLUMN "public"."profiles"."count_password_attempts" IS 'Count user attempts password ';

CREATE TABLE IF NOT EXISTS "public"."report_labels" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "label" "text" NOT NULL,
    "description" "text",
    "draft" boolean DEFAULT false NOT NULL,
    "target" "public"."report_target"[] DEFAULT ARRAY['profile'::"public"."report_target", 'parking'::"public"."report_target"] NOT NULL
);

ALTER TABLE "public"."report_labels" OWNER TO "postgres";

COMMENT ON TABLE "public"."report_labels" IS 'Note: Autres ou Other data should be added first.';

CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "subscription_id" "text" NOT NULL,
    "booking_id" "uuid" DEFAULT "gen_random_uuid"(),
    "user_id" "uuid" DEFAULT "gen_random_uuid"(),
    "customer_id" "text",
    "status" "text"
);

ALTER TABLE "public"."subscriptions" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."transactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "method" "public"."payment_method" DEFAULT 'credit_card'::"public"."payment_method" NOT NULL,
    "payload" "json",
    "amount" integer NOT NULL,
    "fees" smallint DEFAULT '0'::smallint,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "public"."transaction_status" DEFAULT 'unpaid'::"public"."transaction_status" NOT NULL,
    "reference" "text"
);

ALTER TABLE "public"."transactions" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."views" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "owner_id" "uuid" NOT NULL,
    "parking_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."views" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."webhooks" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "payload" "json",
    "body" "json"
);

ALTER TABLE "public"."webhooks" OWNER TO "postgres";

ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "address_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_parking_id_key" UNIQUE ("parking_id");

ALTER TABLE ONLY "public"."booking_inventories"
    ADD CONSTRAINT "booking_inventories_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey1" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_transaction_id_key" UNIQUE ("transaction_id");

ALTER TABLE ONLY "public"."canceled_bookings"
    ADD CONSTRAINT "canceled_bookings_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chats_users"
    ADD CONSTRAINT "chats_users_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."countries"
    ADD CONSTRAINT "countries_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."evaluations"
    ADD CONSTRAINT "evaluations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."parking_alerts"
    ADD CONSTRAINT "parking_alert_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."car_types"
    ADD CONSTRAINT "parking_car_types_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."parking_car_types"
    ADD CONSTRAINT "parking_car_types_pkey1" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."car_types"
    ADD CONSTRAINT "parking_car_types_slug_key" UNIQUE ("slug");

ALTER TABLE ONLY "public"."features"
    ADD CONSTRAINT "parking_features_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."parking_features"
    ADD CONSTRAINT "parking_features_pkey1" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."parking_images"
    ADD CONSTRAINT "parking_images_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."parking_reports"
    ADD CONSTRAINT "parking_reports_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."parkings"
    ADD CONSTRAINT "parkings_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profile_cars"
    ADD CONSTRAINT "profile_cars_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profile_cars"
    ADD CONSTRAINT "profile_cars_plate_id_key" UNIQUE ("plate_id");

ALTER TABLE ONLY "public"."profile_evaluations"
    ADD CONSTRAINT "profile_evaluations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_email_key" UNIQUE ("email");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_plate_key" UNIQUE ("plate_id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_identity_client_id_key" UNIQUE ("identity_client_id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_stripe_account_id_key" UNIQUE ("stripe_account_id");

ALTER TABLE ONLY "public"."profile_views"
    ADD CONSTRAINT "provile_views_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."report_labels"
    ADD CONSTRAINT "report_labels_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_booking_id_key" UNIQUE ("booking_id");

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_subscription_id_key" UNIQUE ("subscription_id");

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "unique_sender_recipient_id" UNIQUE ("sender_id", "recipient_id");

ALTER TABLE ONLY "public"."views"
    ADD CONSTRAINT "views_pkey" PRIMARY KEY ("owner_id", "parking_id");

ALTER TABLE ONLY "public"."webhooks"
    ADD CONSTRAINT "webhooks_pkey" PRIMARY KEY ("id");

CREATE OR REPLACE TRIGGER "schedule_unpaid_booking_removing" AFTER INSERT ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."schedule_unpaid_booking_removing"();

CREATE OR REPLACE TRIGGER "update_booking_status_on_start_trigger" AFTER UPDATE ON "public"."booking_inventories" FOR EACH ROW EXECUTE FUNCTION "public"."update_booking_status"();

CREATE OR REPLACE TRIGGER "update_parking_trigger" AFTER UPDATE ON "public"."bookings" FOR EACH ROW EXECUTE FUNCTION "public"."update_parking_status"();

ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."addresses"
    ADD CONSTRAINT "addresses_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."booking_inventories"
    ADD CONSTRAINT "booking_inventories_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id");

ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_transaction_id_fkey" FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id");

ALTER TABLE ONLY "public"."canceled_bookings"
    ADD CONSTRAINT "canceled_bookings_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chats"
    ADD CONSTRAINT "chats_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chats_users"
    ADD CONSTRAINT "chats_users_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chats_users"
    ADD CONSTRAINT "chats_users_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE ONLY "public"."evaluations"
    ADD CONSTRAINT "evaluations_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."evaluations"
    ADD CONSTRAINT "evaluations_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id");

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."chats"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_fkey" FOREIGN KEY ("user") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_alerts"
    ADD CONSTRAINT "parking_alerts_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_alerts"
    ADD CONSTRAINT "parking_alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_car_types"
    ADD CONSTRAINT "parking_car_types_car_type_id_fkey" FOREIGN KEY ("car_type_id") REFERENCES "public"."car_types"("id") ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE ONLY "public"."parking_car_types"
    ADD CONSTRAINT "parking_car_types_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_features"
    ADD CONSTRAINT "parking_features_feature_id_fkey" FOREIGN KEY ("feature_id") REFERENCES "public"."features"("id") ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE ONLY "public"."parking_features"
    ADD CONSTRAINT "parking_features_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_images"
    ADD CONSTRAINT "parking_images_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_reports"
    ADD CONSTRAINT "parking_reports_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_reports"
    ADD CONSTRAINT "parking_reports_report_label_id_fkey" FOREIGN KEY ("report_label_id") REFERENCES "public"."report_labels"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parking_reports"
    ADD CONSTRAINT "parking_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."parkings"
    ADD CONSTRAINT "parkings_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("user_id");

ALTER TABLE ONLY "public"."profile_evaluations"
    ADD CONSTRAINT "profile_evaluations_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "public"."profiles"("user_id");

ALTER TABLE ONLY "public"."profile_evaluations"
    ADD CONSTRAINT "profile_evaluations_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("user_id");

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_report_label_id_fkey" FOREIGN KEY ("report_label_id") REFERENCES "public"."report_labels"("id");

ALTER TABLE ONLY "public"."profile_reports"
    ADD CONSTRAINT "profile_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("user_id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_cars"
    ADD CONSTRAINT "public_profile_cars_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_views"
    ADD CONSTRAINT "public_profile_views_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_views"
    ADD CONSTRAINT "public_profile_views_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "public_subscriptions_booking_id_fkey" FOREIGN KEY ("booking_id") REFERENCES "public"."bookings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "public_subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."views"
    ADD CONSTRAINT "views_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "public"."profiles"("user_id") ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY "public"."views"
    ADD CONSTRAINT "views_parking_id_fkey" FOREIGN KEY ("parking_id") REFERENCES "public"."parkings"("id") ON UPDATE CASCADE ON DELETE CASCADE;

CREATE POLICY "Enable delete for authenticated users only" ON "public"."parking_car_types" FOR DELETE TO "authenticated" USING (true);

CREATE POLICY "Enable delete for authenticated users only" ON "public"."parking_features" FOR DELETE TO "authenticated" USING (true);

CREATE POLICY "Enable delete for users based on user_id" ON "public"."notifications" FOR DELETE TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable delete for users based on user_id" ON "public"."parkings" FOR DELETE TO "authenticated" USING (("auth"."uid"() = "owner_id"));

CREATE POLICY "Enable enable users to update their own parking" ON "public"."parkings" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "owner_id"));

CREATE POLICY "Enable insert access for anon & authentificated users" ON "public"."parking_reports" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);

CREATE POLICY "Enable insert for all users" ON "public"."profile_evaluations" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);

CREATE POLICY "Enable insert for anon & authentificated  users" ON "public"."profile_reports" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."addresses" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."booking_inventories" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."bookings" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."canceled_bookings" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."chats" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "sender_id"));

CREATE POLICY "Enable insert for authenticated users only" ON "public"."messages" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "author_id"));

CREATE POLICY "Enable insert for authenticated users only" ON "public"."notifications" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."parking_alerts" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."parking_car_types" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."parking_features" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."parkings" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."profile_views" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."transactions" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."views" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for for all users" ON "public"."evaluations" FOR INSERT TO "authenticated", "anon" WITH CHECK (true);

CREATE POLICY "Enable insert for users" ON "public"."profiles" FOR INSERT WITH CHECK (true);

CREATE POLICY "Enable read access for all chat participants" ON "public"."messages" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."addresses" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."booking_inventories" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."bookings" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."canceled_bookings" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."car_types" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."chats" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."countries" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."evaluations" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."features" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."notifications" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."parking_alerts" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."parking_car_types" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."parking_features" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."parking_images" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."parking_reports" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."parkings" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."profile_evaluations" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."profile_reports" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."profile_views" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."profiles" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."report_labels" FOR SELECT USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."transactions" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for all users" ON "public"."views" FOR SELECT TO "authenticated", "anon" USING (true);

CREATE POLICY "Enable read access for annon users" ON "public"."profile_reports" FOR INSERT TO "anon" WITH CHECK (true);

CREATE POLICY "Enable read access for annon users" ON "public"."report_labels" FOR SELECT TO "anon" USING (true);

CREATE POLICY "Enable read access for authenticated users" ON "public"."profile_views" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "Enable update for authenticated users only" ON "public"."addresses" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users only" ON "public"."booking_inventories" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users only" ON "public"."bookings" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable update for users based on email" ON "public"."notifications" FOR UPDATE TO "authenticated", "anon" USING (true) WITH CHECK (true);

CREATE POLICY "Enable update for users based on email" ON "public"."profiles" FOR UPDATE USING ((("auth"."jwt"() ->> 'email'::"text") = ("email")::"text")) WITH CHECK ((("auth"."jwt"() ->> 'email'::"text") = ("email")::"text"));

CREATE POLICY "Update by auth users" ON "public"."profiles" FOR UPDATE TO "authenticated", "anon" USING (true) WITH CHECK (true);

CREATE POLICY "Users can profile." ON "public"."profiles" FOR INSERT TO "anon" WITH CHECK (true);

ALTER TABLE "public"."addresses" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."booking_inventories" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."canceled_bookings" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."car_types" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."chats" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."chats_users" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."countries" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."evaluations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."features" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."parking_alerts" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."parking_car_types" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."parking_features" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."parking_images" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."parking_reports" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."parkings" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_cars" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_evaluations" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_reports" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_views" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."report_labels" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."transactions" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."views" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."webhooks" ENABLE ROW LEVEL SECURITY;

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."booking_inventories";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."bookings";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."canceled_bookings";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chats";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."messages";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."notifications";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."parkings";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profile_cars";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profile_views";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."profiles";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."transactions";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."views";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."webhooks";

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."create_new_user_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_new_user_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_new_user_profile"() TO "service_role";

GRANT ALL ON FUNCTION "public"."create_transaction_after_location_accepted"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_transaction_after_location_accepted"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_transaction_after_location_accepted"() TO "service_role";

GRANT ALL ON FUNCTION "public"."get_booking_by_id"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_booking_by_id"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_booking_by_id"("p_booking_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."get_bookings_by_occupier_id"("occupier_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_bookings_by_occupier_id"("occupier_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_bookings_by_occupier_id"("occupier_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_bookings_by_owner_id"("parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_bookings_by_owner_id"("parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_bookings_by_owner_id"("parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_bookings_by_parking_id"("p_parking_id" "uuid", "parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."get_bookings_by_parking_id"("p_parking_id" "uuid", "parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_bookings_by_parking_id"("p_parking_id" "uuid", "parking_owner_id" "uuid", "p_booking_status" "public"."booking_status"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_chat_messages"("p_sender_id" "uuid", "p_recipient_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_chat_messages"("p_sender_id" "uuid", "p_recipient_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_chat_messages"("p_sender_id" "uuid", "p_recipient_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."get_owner_profile_by_id"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_owner_profile_by_id"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_owner_profile_by_id"("p_owner_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."get_parkings_by_filters"("features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real, "lat" double precision, "long" double precision, "max_distance_meters" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."get_parkings_by_filters"("features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real, "lat" double precision, "long" double precision, "max_distance_meters" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_parkings_by_filters"("features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real, "lat" double precision, "long" double precision, "max_distance_meters" double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."get_parkings_by_owner_id"("p_owner_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_parkings_by_owner_id"("p_owner_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_parkings_by_owner_id"("p_owner_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."is_chat_exist"("p_sender_id" "uuid", "p_recipient_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_chat_exist"("p_sender_id" "uuid", "p_recipient_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_chat_exist"("p_sender_id" "uuid", "p_recipient_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."nearby_parkings_filter_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision, "features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real) TO "anon";
GRANT ALL ON FUNCTION "public"."nearby_parkings_filter_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision, "features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real) TO "authenticated";
GRANT ALL ON FUNCTION "public"."nearby_parkings_filter_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision, "features" "uuid"[], "car_types" "uuid"[], "min_price" real, "max_price" real) TO "service_role";

GRANT ALL ON FUNCTION "public"."nearby_parkings_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."nearby_parkings_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."nearby_parkings_with_distance"("lat" double precision, "long" double precision, "max_distance_meters" double precision) TO "service_role";

GRANT ALL ON FUNCTION "public"."schedule_unpaid_booking_removing"() TO "anon";
GRANT ALL ON FUNCTION "public"."schedule_unpaid_booking_removing"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."schedule_unpaid_booking_removing"() TO "service_role";

GRANT ALL ON FUNCTION "public"."unschedule_cronjob"("job_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."unschedule_cronjob"("job_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."unschedule_cronjob"("job_id" "text") TO "service_role";

GRANT ALL ON FUNCTION "public"."update_booking_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_booking_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_booking_status"() TO "service_role";

GRANT ALL ON FUNCTION "public"."update_parking_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_parking_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_parking_status"() TO "service_role";

GRANT ALL ON TABLE "public"."addresses" TO "anon";
GRANT ALL ON TABLE "public"."addresses" TO "authenticated";
GRANT ALL ON TABLE "public"."addresses" TO "service_role";

GRANT ALL ON TABLE "public"."booking_inventories" TO "anon";
GRANT ALL ON TABLE "public"."booking_inventories" TO "authenticated";
GRANT ALL ON TABLE "public"."booking_inventories" TO "service_role";

GRANT ALL ON TABLE "public"."bookings" TO "anon";
GRANT ALL ON TABLE "public"."bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."bookings" TO "service_role";

GRANT ALL ON TABLE "public"."canceled_bookings" TO "anon";
GRANT ALL ON TABLE "public"."canceled_bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."canceled_bookings" TO "service_role";

GRANT ALL ON TABLE "public"."car_types" TO "anon";
GRANT ALL ON TABLE "public"."car_types" TO "authenticated";
GRANT ALL ON TABLE "public"."car_types" TO "service_role";

GRANT ALL ON TABLE "public"."chats" TO "anon";
GRANT ALL ON TABLE "public"."chats" TO "authenticated";
GRANT ALL ON TABLE "public"."chats" TO "service_role";

GRANT ALL ON TABLE "public"."chats_users" TO "anon";
GRANT ALL ON TABLE "public"."chats_users" TO "authenticated";
GRANT ALL ON TABLE "public"."chats_users" TO "service_role";

GRANT ALL ON TABLE "public"."countries" TO "anon";
GRANT ALL ON TABLE "public"."countries" TO "authenticated";
GRANT ALL ON TABLE "public"."countries" TO "service_role";

GRANT ALL ON SEQUENCE "public"."countries_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."countries_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."countries_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."evaluations" TO "anon";
GRANT ALL ON TABLE "public"."evaluations" TO "authenticated";
GRANT ALL ON TABLE "public"."evaluations" TO "service_role";

GRANT ALL ON TABLE "public"."features" TO "anon";
GRANT ALL ON TABLE "public"."features" TO "authenticated";
GRANT ALL ON TABLE "public"."features" TO "service_role";

GRANT ALL ON TABLE "public"."messages" TO "anon";
GRANT ALL ON TABLE "public"."messages" TO "authenticated";
GRANT ALL ON TABLE "public"."messages" TO "service_role";

GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";

GRANT ALL ON TABLE "public"."parking_alerts" TO "anon";
GRANT ALL ON TABLE "public"."parking_alerts" TO "authenticated";
GRANT ALL ON TABLE "public"."parking_alerts" TO "service_role";

GRANT ALL ON TABLE "public"."parking_car_types" TO "anon";
GRANT ALL ON TABLE "public"."parking_car_types" TO "authenticated";
GRANT ALL ON TABLE "public"."parking_car_types" TO "service_role";

GRANT ALL ON TABLE "public"."parking_features" TO "anon";
GRANT ALL ON TABLE "public"."parking_features" TO "authenticated";
GRANT ALL ON TABLE "public"."parking_features" TO "service_role";

GRANT ALL ON TABLE "public"."parking_images" TO "anon";
GRANT ALL ON TABLE "public"."parking_images" TO "authenticated";
GRANT ALL ON TABLE "public"."parking_images" TO "service_role";

GRANT ALL ON TABLE "public"."parking_reports" TO "anon";
GRANT ALL ON TABLE "public"."parking_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."parking_reports" TO "service_role";

GRANT ALL ON TABLE "public"."parkings" TO "anon";
GRANT ALL ON TABLE "public"."parkings" TO "authenticated";
GRANT ALL ON TABLE "public"."parkings" TO "service_role";

GRANT ALL ON TABLE "public"."profile_cars" TO "anon";
GRANT ALL ON TABLE "public"."profile_cars" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_cars" TO "service_role";

GRANT ALL ON TABLE "public"."profile_evaluations" TO "anon";
GRANT ALL ON TABLE "public"."profile_evaluations" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_evaluations" TO "service_role";

GRANT ALL ON TABLE "public"."profile_reports" TO "anon";
GRANT ALL ON TABLE "public"."profile_reports" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_reports" TO "service_role";

GRANT ALL ON TABLE "public"."profile_views" TO "anon";
GRANT ALL ON TABLE "public"."profile_views" TO "authenticated";
GRANT ALL ON TABLE "public"."profile_views" TO "service_role";

GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";
GRANT ALL ON TABLE "public"."profiles" TO PUBLIC;

GRANT ALL ON TABLE "public"."report_labels" TO "anon";
GRANT ALL ON TABLE "public"."report_labels" TO "authenticated";
GRANT ALL ON TABLE "public"."report_labels" TO "service_role";

GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";

GRANT ALL ON TABLE "public"."transactions" TO "anon";
GRANT ALL ON TABLE "public"."transactions" TO "authenticated";
GRANT ALL ON TABLE "public"."transactions" TO "service_role";

GRANT ALL ON TABLE "public"."views" TO "anon";
GRANT ALL ON TABLE "public"."views" TO "authenticated";
GRANT ALL ON TABLE "public"."views" TO "service_role";

GRANT ALL ON TABLE "public"."webhooks" TO "anon";
GRANT ALL ON TABLE "public"."webhooks" TO "authenticated";
GRANT ALL ON TABLE "public"."webhooks" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;
