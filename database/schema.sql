-- DealScout: kernetabeller, indeks og views til tilbuds-API'et.

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

CREATE TABLE public.canonical_products (
    id bigint NOT NULL,
    canonical_name text NOT NULL,
    brand text,
    product_type text NOT NULL,
    category text,
    subcategory text,
    standard_quantity numeric(12,3),
    standard_unit text,
    comparison_group text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE public.canonical_products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.canonical_products_id_seq OWNED BY public.canonical_products.id;

CREATE TABLE public.grocery_offers (
    id bigint NOT NULL,
    external_offer_id text NOT NULL,
    chain_id text NOT NULL,
    chain_name text NOT NULL,
    product_name text NOT NULL,
    description text,
    price_dkk numeric(10,2),
    advertised_before_price_dkk numeric(10,2),
    quantity_from numeric(12,3),
    quantity_to numeric(12,3),
    original_unit text,
    pieces_from numeric(12,3),
    pieces_to numeric(12,3),
    unit_price_worst_case numeric(12,4),
    unit_price_best_case numeric(12,4),
    normalized_unit text,
    valid_from timestamp with time zone,
    valid_until timestamp with time zone,
    image_url text,
    has_quantity_range boolean DEFAULT false NOT NULL,
    raw_payload jsonb NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE public.grocery_offers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.grocery_offers_id_seq OWNED BY public.grocery_offers.id;

CREATE TABLE public.offer_product_matches (
    offer_id bigint NOT NULL,
    alias_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.product_aliases (
    id bigint NOT NULL,
    chain_id text NOT NULL,
    source_name text NOT NULL,
    source_description text,
    alias_signature text GENERATED ALWAYS AS (md5(((((chain_id || '|'::text) || lower(TRIM(BOTH FROM source_name))) || '|'::text) || lower(TRIM(BOTH FROM COALESCE(source_description, ''::text)))))) STORED,
    canonical_product_id bigint,
    normalization_status text DEFAULT 'pending'::text NOT NULL,
    match_confidence numeric(5,4),
    extracted_brand text,
    extracted_type text,
    extracted_category text,
    extracted_quantity numeric(12,3),
    extracted_unit text,
    comparison_group text,
    agent_result jsonb,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT product_aliases_normalization_status_check CHECK ((normalization_status = ANY (ARRAY['pending'::text, 'matched'::text, 'review'::text, 'multi_product'::text, 'ignored'::text])))
);

CREATE SEQUENCE public.product_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.product_aliases_id_seq OWNED BY public.product_aliases.id;

CREATE VIEW public.v_comparable_offers AS
 SELECT go.id AS offer_id,
    go.external_offer_id,
    go.chain_id,
    go.chain_name,
    go.product_name,
    go.description,
    pa.id AS alias_id,
    pa.extracted_brand,
    pa.extracted_type,
    pa.extracted_category,
    pa.comparison_group,
    pa.match_confidence,
    go.price_dkk,
    go.advertised_before_price_dkk,
    go.quantity_from,
    go.quantity_to,
    go.original_unit,
    go.pieces_from,
    go.pieces_to,
    go.unit_price_best_case,
    go.unit_price_worst_case,
    go.normalized_unit,
        CASE
            WHEN (go.unit_price_worst_case IS NOT NULL) THEN go.unit_price_worst_case
            WHEN (go.unit_price_best_case IS NOT NULL) THEN go.unit_price_best_case
            ELSE NULL::numeric
        END AS comparison_unit_price,
        CASE
            WHEN ((go.advertised_before_price_dkk IS NOT NULL) AND (go.advertised_before_price_dkk > go.price_dkk) AND (go.advertised_before_price_dkk > (0)::numeric)) THEN round((((go.advertised_before_price_dkk - go.price_dkk) / go.advertised_before_price_dkk) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS advertised_discount_percent,
    go.has_quantity_range,
    go.valid_from,
    go.valid_until,
    go.first_seen_at,
    go.last_seen_at,
    go.image_url
   FROM ((public.grocery_offers go
     JOIN public.offer_product_matches opm ON ((opm.offer_id = go.id)))
     JOIN public.product_aliases pa ON ((pa.id = opm.alias_id)))
  WHERE ((pa.normalization_status = 'matched'::text) AND (pa.comparison_group IS NOT NULL) AND (go.price_dkk IS NOT NULL) AND (go.price_dkk > (0)::numeric));

CREATE VIEW public.v_comparable_offers_deduplicated AS
 SELECT DISTINCT ON (chain_id, (lower(TRIM(BOTH FROM product_name))), price_dkk, comparison_unit_price, normalized_unit, valid_from, valid_until) offer_id,
    external_offer_id,
    chain_id,
    chain_name,
    product_name,
    description,
    alias_id,
    extracted_brand,
    extracted_type,
    extracted_category,
    comparison_group,
    match_confidence,
    price_dkk,
    advertised_before_price_dkk,
    quantity_from,
    quantity_to,
    original_unit,
    pieces_from,
    pieces_to,
    unit_price_best_case,
    unit_price_worst_case,
    normalized_unit,
    comparison_unit_price,
    advertised_discount_percent,
    has_quantity_range,
    valid_from,
    valid_until,
    first_seen_at,
    last_seen_at,
    image_url
   FROM public.v_comparable_offers
  ORDER BY chain_id, (lower(TRIM(BOTH FROM product_name))), price_dkk, comparison_unit_price, normalized_unit, valid_from, valid_until, offer_id;

CREATE VIEW public.v_current_offer_assessments AS
 SELECT current_offer.offer_id,
    current_offer.external_offer_id,
    current_offer.chain_id,
    current_offer.chain_name,
    current_offer.product_name,
    current_offer.description,
    current_offer.alias_id,
    current_offer.extracted_brand,
    current_offer.extracted_type,
    current_offer.extracted_category,
    current_offer.comparison_group,
    current_offer.match_confidence,
    current_offer.price_dkk,
    current_offer.advertised_before_price_dkk,
    current_offer.quantity_from,
    current_offer.quantity_to,
    current_offer.original_unit,
    current_offer.pieces_from,
    current_offer.pieces_to,
    current_offer.unit_price_best_case,
    current_offer.unit_price_worst_case,
    current_offer.normalized_unit,
    current_offer.comparison_unit_price,
    current_offer.advertised_discount_percent,
    current_offer.has_quantity_range,
    current_offer.valid_from,
    current_offer.valid_until,
    current_offer.first_seen_at,
    current_offer.last_seen_at,
    current_offer.image_url,
    history.prior_offer_period_count,
    history.prior_distinct_price_count,
    history.prior_min_unit_price,
    history.prior_median_unit_price,
    history.prior_average_unit_price,
    history.prior_max_unit_price,
    round(((((history.prior_median_unit_price - (current_offer.comparison_unit_price)::double precision) / NULLIF(history.prior_median_unit_price, (0)::double precision)) * (100)::double precision))::numeric, 2) AS verified_discount_vs_history_percent,
        CASE
            WHEN ((history.prior_offer_period_count < 3) OR (history.prior_distinct_price_count < 2)) THEN 'insufficient_history'::text
            WHEN ((current_offer.comparison_unit_price)::double precision <= (history.prior_median_unit_price * (0.75)::double precision)) THEN 'exceptional'::text
            WHEN ((current_offer.comparison_unit_price)::double precision <= (history.prior_median_unit_price * (0.90)::double precision)) THEN 'good'::text
            WHEN ((current_offer.comparison_unit_price)::double precision <= (history.prior_median_unit_price * (1.05)::double precision)) THEN 'normal'::text
            ELSE 'expensive'::text
        END AS historical_price_assessment,
        CASE
            WHEN ((history.prior_offer_period_count >= 8) AND (history.prior_distinct_price_count >= 3)) THEN 'strong'::text
            WHEN ((history.prior_offer_period_count >= 3) AND (history.prior_distinct_price_count >= 2)) THEN 'usable'::text
            WHEN (history.prior_offer_period_count >= 1) THEN 'early'::text
            ELSE 'none'::text
        END AS assessment_confidence
   FROM (public.v_comparable_offers_deduplicated current_offer
     LEFT JOIN LATERAL ( SELECT count(DISTINCT ROW(previous_offer.valid_from, previous_offer.valid_until)) AS prior_offer_period_count,
            count(DISTINCT previous_offer.comparison_unit_price) AS prior_distinct_price_count,
            min(previous_offer.comparison_unit_price) AS prior_min_unit_price,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((previous_offer.comparison_unit_price)::double precision)) AS prior_median_unit_price,
            round(avg(previous_offer.comparison_unit_price), 4) AS prior_average_unit_price,
            max(previous_offer.comparison_unit_price) AS prior_max_unit_price
           FROM public.v_comparable_offers_deduplicated previous_offer
          WHERE ((previous_offer.alias_id = current_offer.alias_id) AND (previous_offer.normalized_unit = current_offer.normalized_unit) AND (previous_offer.valid_from < current_offer.valid_from) AND (previous_offer.comparison_unit_price IS NOT NULL) AND (previous_offer.comparison_unit_price > (0)::numeric))) history ON (true))
  WHERE ((current_offer.valid_from <= CURRENT_TIMESTAMP) AND (current_offer.valid_until >= CURRENT_TIMESTAMP) AND (current_offer.comparison_unit_price IS NOT NULL));

CREATE VIEW public.v_current_price_comparisons AS
 WITH active_offers AS (
         SELECT v_comparable_offers_deduplicated.offer_id,
            v_comparable_offers_deduplicated.external_offer_id,
            v_comparable_offers_deduplicated.chain_id,
            v_comparable_offers_deduplicated.chain_name,
            v_comparable_offers_deduplicated.product_name,
            v_comparable_offers_deduplicated.description,
            v_comparable_offers_deduplicated.alias_id,
            v_comparable_offers_deduplicated.extracted_brand,
            v_comparable_offers_deduplicated.extracted_type,
            v_comparable_offers_deduplicated.extracted_category,
            v_comparable_offers_deduplicated.comparison_group,
            v_comparable_offers_deduplicated.match_confidence,
            v_comparable_offers_deduplicated.price_dkk,
            v_comparable_offers_deduplicated.advertised_before_price_dkk,
            v_comparable_offers_deduplicated.quantity_from,
            v_comparable_offers_deduplicated.quantity_to,
            v_comparable_offers_deduplicated.original_unit,
            v_comparable_offers_deduplicated.pieces_from,
            v_comparable_offers_deduplicated.pieces_to,
            v_comparable_offers_deduplicated.unit_price_best_case,
            v_comparable_offers_deduplicated.unit_price_worst_case,
            v_comparable_offers_deduplicated.normalized_unit,
            v_comparable_offers_deduplicated.comparison_unit_price,
            v_comparable_offers_deduplicated.advertised_discount_percent,
            v_comparable_offers_deduplicated.has_quantity_range,
            v_comparable_offers_deduplicated.valid_from,
            v_comparable_offers_deduplicated.valid_until,
            v_comparable_offers_deduplicated.first_seen_at,
            v_comparable_offers_deduplicated.last_seen_at,
            v_comparable_offers_deduplicated.image_url
           FROM public.v_comparable_offers_deduplicated
          WHERE ((v_comparable_offers_deduplicated.valid_from <= CURRENT_TIMESTAMP) AND (v_comparable_offers_deduplicated.valid_until >= CURRENT_TIMESTAMP) AND (v_comparable_offers_deduplicated.comparison_unit_price IS NOT NULL))
        ), eligible_groups AS (
         SELECT active_offers.comparison_group,
            active_offers.normalized_unit
           FROM active_offers
          GROUP BY active_offers.comparison_group, active_offers.normalized_unit
         HAVING (count(DISTINCT active_offers.chain_id) >= 2)
        ), group_statistics AS (
         SELECT active_1.comparison_group,
            active_1.normalized_unit,
            count(*) AS group_offer_count,
            count(DISTINCT active_1.chain_id) AS group_chain_count,
            min(active_1.comparison_unit_price) AS group_min_unit_price,
            percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((active_1.comparison_unit_price)::double precision)) AS group_median_unit_price,
            max(active_1.comparison_unit_price) AS group_max_unit_price
           FROM (active_offers active_1
             JOIN eligible_groups eligible ON (((eligible.comparison_group = active_1.comparison_group) AND (eligible.normalized_unit = active_1.normalized_unit))))
          GROUP BY active_1.comparison_group, active_1.normalized_unit
        )
 SELECT active.offer_id,
    active.external_offer_id,
    active.chain_id,
    active.chain_name,
    active.product_name,
    active.description,
    active.alias_id,
    active.extracted_brand,
    active.extracted_type,
    active.extracted_category,
    active.comparison_group,
    active.match_confidence,
    active.price_dkk,
    active.advertised_before_price_dkk,
    active.quantity_from,
    active.quantity_to,
    active.original_unit,
    active.pieces_from,
    active.pieces_to,
    active.unit_price_best_case,
    active.unit_price_worst_case,
    active.normalized_unit,
    active.comparison_unit_price,
    active.advertised_discount_percent,
    active.has_quantity_range,
    active.valid_from,
    active.valid_until,
    active.first_seen_at,
    active.last_seen_at,
    active.image_url,
    statistics.group_offer_count,
    statistics.group_chain_count,
    statistics.group_min_unit_price,
    statistics.group_median_unit_price,
    statistics.group_max_unit_price,
    dense_rank() OVER (PARTITION BY active.comparison_group, active.normalized_unit ORDER BY active.comparison_unit_price) AS price_rank,
    round((((((active.comparison_unit_price)::double precision - statistics.group_median_unit_price) / NULLIF(statistics.group_median_unit_price, (0)::double precision)) * (100)::double precision))::numeric, 2) AS percent_vs_group_median,
    round((((statistics.group_max_unit_price - active.comparison_unit_price) / NULLIF(statistics.group_max_unit_price, (0)::numeric)) * (100)::numeric), 2) AS percent_below_group_max
   FROM (active_offers active
     JOIN group_statistics statistics ON (((statistics.comparison_group = active.comparison_group) AND (statistics.normalized_unit = active.normalized_unit))));

CREATE VIEW public.v_offer_intelligence AS
 SELECT assessment.offer_id,
    assessment.external_offer_id,
    assessment.chain_id,
    assessment.chain_name,
    assessment.alias_id,
    assessment.product_name,
    assessment.description,
    assessment.extracted_brand,
    assessment.extracted_type,
    assessment.extracted_category,
    assessment.comparison_group,
    assessment.price_dkk,
    assessment.advertised_before_price_dkk,
    assessment.advertised_discount_percent,
    assessment.quantity_from,
    assessment.quantity_to,
    assessment.original_unit,
    assessment.normalized_unit,
    assessment.comparison_unit_price,
    assessment.valid_from,
    assessment.valid_until,
    assessment.image_url,
    comparison.group_offer_count,
    comparison.group_chain_count,
    comparison.group_min_unit_price,
    comparison.group_median_unit_price,
    comparison.group_max_unit_price,
    comparison.price_rank,
    comparison.percent_vs_group_median,
    assessment.prior_offer_period_count,
    assessment.prior_distinct_price_count,
    assessment.prior_min_unit_price,
    assessment.prior_median_unit_price,
    assessment.prior_average_unit_price,
    assessment.prior_max_unit_price,
    assessment.verified_discount_vs_history_percent,
    assessment.historical_price_assessment,
    assessment.assessment_confidence,
        CASE
            WHEN (assessment.assessment_confidence = ANY (ARRAY['usable'::text, 'strong'::text])) THEN assessment.historical_price_assessment
            WHEN ((comparison.price_rank = 1) AND (comparison.group_chain_count >= 2)) THEN 'current_cheapest'::text
            WHEN (comparison.group_chain_count >= 2) THEN 'currently_comparable'::text
            ELSE 'unverified'::text
        END AS display_status,
        CASE
            WHEN (assessment.assessment_confidence = ANY (ARRAY['usable'::text, 'strong'::text])) THEN 'historical_price'::text
            WHEN (comparison.group_chain_count >= 2) THEN 'current_market_comparison'::text
            ELSE 'insufficient_data'::text
        END AS status_basis
   FROM (public.v_current_offer_assessments assessment
     LEFT JOIN public.v_current_price_comparisons comparison ON ((comparison.offer_id = assessment.offer_id)));

ALTER TABLE ONLY public.canonical_products ALTER COLUMN id SET DEFAULT nextval('public.canonical_products_id_seq'::regclass);

ALTER TABLE ONLY public.grocery_offers ALTER COLUMN id SET DEFAULT nextval('public.grocery_offers_id_seq'::regclass);

ALTER TABLE ONLY public.product_aliases ALTER COLUMN id SET DEFAULT nextval('public.product_aliases_id_seq'::regclass);

ALTER TABLE ONLY public.canonical_products
    ADD CONSTRAINT canonical_products_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.grocery_offers
    ADD CONSTRAINT grocery_offers_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.offer_product_matches
    ADD CONSTRAINT offer_product_matches_pkey PRIMARY KEY (offer_id);

ALTER TABLE ONLY public.product_aliases
    ADD CONSTRAINT product_aliases_alias_signature_key UNIQUE (alias_signature);

ALTER TABLE ONLY public.product_aliases
    ADD CONSTRAINT product_aliases_pkey PRIMARY KEY (id);

ALTER TABLE ONLY public.grocery_offers
    ADD CONSTRAINT uq_grocery_offer UNIQUE (chain_id, external_offer_id);

CREATE INDEX idx_aliases_comparison_group ON public.product_aliases USING btree (comparison_group);

CREATE INDEX idx_aliases_name_trgm ON public.product_aliases USING gin (source_name public.gin_trgm_ops);

CREATE INDEX idx_aliases_product ON public.product_aliases USING btree (canonical_product_id);

CREATE INDEX idx_aliases_status ON public.product_aliases USING btree (normalization_status);

CREATE INDEX idx_canonical_name_trgm ON public.canonical_products USING gin (canonical_name public.gin_trgm_ops);

CREATE INDEX idx_grocery_offers_chain ON public.grocery_offers USING btree (chain_id);

CREATE INDEX idx_grocery_offers_product_name ON public.grocery_offers USING btree (lower(product_name));

CREATE INDEX idx_grocery_offers_raw_payload ON public.grocery_offers USING gin (raw_payload);

CREATE INDEX idx_grocery_offers_unit_price ON public.grocery_offers USING btree (normalized_unit, unit_price_worst_case);

CREATE INDEX idx_grocery_offers_validity ON public.grocery_offers USING btree (valid_from, valid_until);

ALTER TABLE ONLY public.offer_product_matches
    ADD CONSTRAINT offer_product_matches_alias_id_fkey FOREIGN KEY (alias_id) REFERENCES public.product_aliases(id);

ALTER TABLE ONLY public.offer_product_matches
    ADD CONSTRAINT offer_product_matches_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES public.grocery_offers(id) ON DELETE CASCADE;

ALTER TABLE ONLY public.product_aliases
    ADD CONSTRAINT product_aliases_canonical_product_id_fkey FOREIGN KEY (canonical_product_id) REFERENCES public.canonical_products(id);
