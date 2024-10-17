

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


CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."pricing_plan_interval" AS ENUM (
    'day',
    'week',
    'month',
    'year'
);


ALTER TYPE "public"."pricing_plan_interval" OWNER TO "postgres";


CREATE TYPE "public"."pricing_type" AS ENUM (
    'one_time',
    'recurring'
);


ALTER TYPE "public"."pricing_type" OWNER TO "postgres";


CREATE TYPE "public"."subscription_status" AS ENUM (
    'trialing',
    'active',
    'canceled',
    'incomplete',
    'incomplete_expired',
    'past_due',
    'unpaid',
    'paused'
);


ALTER TYPE "public"."subscription_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.users (id, full_name, avatar_url)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'avatar_url');
  insert into public.credits (id, user_credits) 
  values (new.id, 10);
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."CRM" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "email" "text",
    "phone" "text",
    "company" "uuid"
);


ALTER TABLE "public"."CRM" OWNER TO "postgres";


ALTER TABLE "public"."CRM" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."CRM_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Downloads" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "email" "text" NOT NULL,
    "name" "text" NOT NULL,
    "files" "text"[],
    "organization" "text"
);


ALTER TABLE "public"."Downloads" OWNER TO "postgres";


ALTER TABLE "public"."Downloads" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Downloads_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."credits" (
    "id" "uuid" NOT NULL,
    "user_credits" integer
);


ALTER TABLE "public"."credits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customers" (
    "id" "uuid" NOT NULL,
    "stripe_customer_id" "text"
);


ALTER TABLE "public"."customers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."newsletter" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "email" character varying
);


ALTER TABLE "public"."newsletter" OWNER TO "postgres";


ALTER TABLE "public"."newsletter" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."newsletter_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."posts" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" "text",
    "published" boolean,
    "markdown" "text" DEFAULT ''::"text",
    "title" "text",
    "tagline" "text",
    "slug" "text",
    "tags" "text",
    "version" "text",
    "user_id" "uuid" DEFAULT "auth"."uid"()
);


ALTER TABLE "public"."posts" OWNER TO "postgres";


ALTER TABLE "public"."posts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."posts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."prices" (
    "id" "text" NOT NULL,
    "product_id" "text",
    "active" boolean,
    "description" "text",
    "unit_amount" bigint,
    "currency" "text",
    "type" "public"."pricing_type",
    "interval" "public"."pricing_plan_interval",
    "interval_count" integer,
    "trial_period_days" integer,
    "metadata" "jsonb",
    CONSTRAINT "prices_currency_check" CHECK (("char_length"("currency") = 3))
);


ALTER TABLE "public"."prices" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "id" "text" NOT NULL,
    "active" boolean,
    "name" "text",
    "description" "text",
    "image" "text",
    "metadata" "jsonb"
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid",
    "avatar_url" "text"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."spec" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "extract" "json" DEFAULT '{}'::"json",
    "transform" "json" DEFAULT '{}'::"json",
    "load" "json" DEFAULT '{}'::"json"
);


ALTER TABLE "public"."spec" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subscriptions" (
    "id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "public"."subscription_status",
    "metadata" "jsonb",
    "price_id" "text",
    "quantity" integer,
    "cancel_at_period_end" boolean,
    "created" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "current_period_start" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "current_period_end" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "ended_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "cancel_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "canceled_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "trial_start" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "trial_end" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"())
);


ALTER TABLE "public"."subscriptions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_prompts" (
    "id" "uuid" NOT NULL,
    "url" "text" NOT NULL,
    "url_id" bigint NOT NULL
);


ALTER TABLE "public"."user_prompts" OWNER TO "postgres";


ALTER TABLE "public"."user_prompts" ALTER COLUMN "url_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_prompts_url_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."user_urls" (
    "id" "uuid" NOT NULL,
    "src" "text" NOT NULL,
    "url_id" bigint NOT NULL
);


ALTER TABLE "public"."user_urls" OWNER TO "postgres";


ALTER TABLE "public"."user_urls" ALTER COLUMN "url_id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_urls_url_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "avatar_url" "text",
    "billing_address" "jsonb",
    "payment_method" "jsonb"
);


ALTER TABLE "public"."users" OWNER TO "postgres";


ALTER TABLE ONLY "public"."CRM"
    ADD CONSTRAINT "CRM_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Downloads"
    ADD CONSTRAINT "Downloads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."credits"
    ADD CONSTRAINT "credits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."newsletter"
    ADD CONSTRAINT "newsletter_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."newsletter"
    ADD CONSTRAINT "newsletter_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prices"
    ADD CONSTRAINT "prices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."spec"
    ADD CONSTRAINT "spec_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_prompts"
    ADD CONSTRAINT "user_prompts_pkey" PRIMARY KEY ("url_id");



ALTER TABLE ONLY "public"."user_prompts"
    ADD CONSTRAINT "user_prompts_url_id_key" UNIQUE ("url_id");



ALTER TABLE ONLY "public"."user_prompts"
    ADD CONSTRAINT "user_prompts_url_key" UNIQUE ("url");



ALTER TABLE ONLY "public"."user_urls"
    ADD CONSTRAINT "user_urls_pkey" PRIMARY KEY ("url_id");



ALTER TABLE ONLY "public"."user_urls"
    ADD CONSTRAINT "user_urls_url_id_key" UNIQUE ("url_id");



ALTER TABLE ONLY "public"."user_urls"
    ADD CONSTRAINT "user_urls_url_key" UNIQUE ("src");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."credits"
    ADD CONSTRAINT "credits_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."prices"
    ADD CONSTRAINT "prices_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_price_id_fkey" FOREIGN KEY ("price_id") REFERENCES "public"."prices"("id");



ALTER TABLE ONLY "public"."subscriptions"
    ADD CONSTRAINT "subscriptions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_prompts"
    ADD CONSTRAINT "user_prompts_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_urls"
    ADD CONSTRAINT "user_urls_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



CREATE POLICY "All can read published" ON "public"."posts" FOR SELECT TO "anon" USING (("published" = true));



CREATE POLICY "Allow public read-only access." ON "public"."prices" FOR SELECT USING (true);



CREATE POLICY "Allow public read-only access." ON "public"."products" FOR SELECT USING (true);



CREATE POLICY "Auth powers" ON "public"."posts" TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id")) WITH CHECK ((( SELECT "auth"."uid"() AS "uid") = "user_id"));



ALTER TABLE "public"."CRM" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Can insert records" ON "public"."user_prompts" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Can only view own subs data." ON "public"."subscriptions" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Can select own prompts" ON "public"."user_prompts" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Can update (smart?)" ON "public"."credits" FOR UPDATE TO "authenticated" USING (("id" = "auth"."uid"()));



CREATE POLICY "Can update own image urls." ON "public"."user_urls" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Can update own records" ON "public"."user_prompts" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Can update own user data." ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Can view own credits." ON "public"."credits" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Can view own image urls." ON "public"."user_urls" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "Can view own user data." ON "public"."users" FOR SELECT USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."Downloads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Enable insert for all users (let's see...)" ON "public"."newsletter" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for anyone" ON "public"."Downloads" FOR INSERT WITH CHECK (true);



CREATE POLICY "Enable insert for authenticated users only" ON "public"."user_urls" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own profiles." ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."credits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."newsletter" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."prices" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."spec" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."subscriptions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_prompts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_urls" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."prices";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."products";






REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






































































































































































































GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";





















GRANT ALL ON TABLE "public"."CRM" TO "anon";
GRANT ALL ON TABLE "public"."CRM" TO "authenticated";
GRANT ALL ON TABLE "public"."CRM" TO "service_role";



GRANT ALL ON SEQUENCE "public"."CRM_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."CRM_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."CRM_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Downloads" TO "anon";
GRANT ALL ON TABLE "public"."Downloads" TO "authenticated";
GRANT ALL ON TABLE "public"."Downloads" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Downloads_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Downloads_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Downloads_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."credits" TO "anon";
GRANT ALL ON TABLE "public"."credits" TO "authenticated";
GRANT ALL ON TABLE "public"."credits" TO "service_role";



GRANT ALL ON TABLE "public"."customers" TO "anon";
GRANT ALL ON TABLE "public"."customers" TO "authenticated";
GRANT ALL ON TABLE "public"."customers" TO "service_role";



GRANT ALL ON TABLE "public"."newsletter" TO "anon";
GRANT ALL ON TABLE "public"."newsletter" TO "authenticated";
GRANT ALL ON TABLE "public"."newsletter" TO "service_role";



GRANT ALL ON SEQUENCE "public"."newsletter_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."newsletter_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."newsletter_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."posts" TO "anon";
GRANT ALL ON TABLE "public"."posts" TO "authenticated";
GRANT ALL ON TABLE "public"."posts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."posts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."posts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."posts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."prices" TO "anon";
GRANT ALL ON TABLE "public"."prices" TO "authenticated";
GRANT ALL ON TABLE "public"."prices" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."spec" TO "anon";
GRANT ALL ON TABLE "public"."spec" TO "authenticated";
GRANT ALL ON TABLE "public"."spec" TO "service_role";



GRANT ALL ON TABLE "public"."subscriptions" TO "anon";
GRANT ALL ON TABLE "public"."subscriptions" TO "authenticated";
GRANT ALL ON TABLE "public"."subscriptions" TO "service_role";



GRANT ALL ON TABLE "public"."user_prompts" TO "anon";
GRANT ALL ON TABLE "public"."user_prompts" TO "authenticated";
GRANT ALL ON TABLE "public"."user_prompts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_prompts_url_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_prompts_url_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_prompts_url_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."user_urls" TO "anon";
GRANT ALL ON TABLE "public"."user_urls" TO "authenticated";
GRANT ALL ON TABLE "public"."user_urls" TO "service_role";



GRANT ALL ON SEQUENCE "public"."user_urls_url_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."user_urls_url_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."user_urls_url_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



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
