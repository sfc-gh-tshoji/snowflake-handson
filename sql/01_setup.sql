-- =============================================================
-- ハンズオン: Redshift 資産の変換から Agent / CoWork まで
-- 01_setup.sql  （参加者が自分のトライアルアカウントで ACCOUNTADMIN として実行）
-- 前提: Snowflake が事前に作成したトライアルアカウント（AI 機能が有効）
-- 実データは使わず、化粧品小売を模した架空データを決定論的に生成する（RANDOM 不使用、HASH で固定）
-- =============================================================
USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

CREATE ROLE IF NOT EXISTS HANDSON_ROLE;
GRANT ROLE HANDSON_ROLE TO ROLE SYSADMIN;
SET my_user = CURRENT_USER();
GRANT ROLE HANDSON_ROLE TO USER IDENTIFIER($my_user);
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE HANDSON_ROLE;

CREATE WAREHOUSE IF NOT EXISTS HANDSON_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
GRANT USAGE, OPERATE ON WAREHOUSE HANDSON_WH TO ROLE HANDSON_ROLE;

CREATE DATABASE IF NOT EXISTS RETAIL_HANDSON;
GRANT OWNERSHIP ON DATABASE RETAIL_HANDSON TO ROLE HANDSON_ROLE COPY CURRENT GRANTS;

USE ROLE HANDSON_ROLE;
USE WAREHOUSE HANDSON_WH;
USE DATABASE RETAIL_HANDSON;
CREATE SCHEMA IF NOT EXISTS RS_EXPORT;  -- Redshift から UNLOAD した想定のデータ（変換元）
CREATE SCHEMA IF NOT EXISTS DWH;        -- 演習で Snowflake 向けに作り直す先
USE SCHEMA RS_EXPORT;

-- ---------- 店舗マスタ（20件: 店舗16 + EC4） ----------
CREATE OR REPLACE TABLE STORE_MASTER AS
WITH n AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS RN FROM TABLE(GENERATOR(ROWCOUNT => 20)))
SELECT
  RN                                                                      AS STORE_ID,
  IFF(RN <= 16, 'STORE_' || LPAD(RN, 2, '0'), 'EC_' || LPAD(RN - 16, 2, '0')) AS STORE_NAME,
  IFF(RN <= 16, 'STORE', 'EC')                                            AS CHANNEL,
  ARRAY_CONSTRUCT('KANTO','KANSAI','CHUBU','KYUSHU')[MOD(RN - 1, 4)]::STRING AS REGION
FROM n;

-- ---------- 商品マスタ（60件: 5ブランド × 4カテゴリ） ----------
CREATE OR REPLACE TABLE PRODUCT_MASTER AS
WITH n AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS RN FROM TABLE(GENERATOR(ROWCOUNT => 60)))
SELECT
  RN                                                                      AS PRODUCT_ID,
  'ITEM_' || LPAD(RN, 3, '0')                                             AS PRODUCT_NAME,
  ARRAY_CONSTRUCT('BRAND_A','BRAND_B','BRAND_C','BRAND_D','BRAND_E')[MOD(RN - 1, 5)]::STRING AS BRAND,
  ARRAY_CONSTRUCT('SKINCARE','MAKEUP','HAIRCARE','FRAGRANCE')[MOD(RN - 1, 4)]::STRING        AS CATEGORY,
  1000 + MOD(RN * 7, 10) * 500                                            AS LIST_PRICE
FROM n;

-- ---------- 売上明細（3,000,000件, 2026-01-01〜2026-09-27） ----------
-- 乱数ではなく HASH(連番, 種) で値を決める（毎回同じ結果になり、期待値を固定できる）
-- 店舗・商品・日付は独立に散らし、返品率だけ「EC」「MAKEUP」「KANSAI」で高くなるようにしてある（第4幕の質問用）
CREATE OR REPLACE TABLE SALES_DETAIL AS
WITH n AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS RN FROM TABLE(GENERATOR(ROWCOUNT => 3000000))),
b AS (
  SELECT
    RN                                                           AS SALE_ID,
    DATEADD(day, MOD(ABS(HASH(RN, 1)), 270), '2026-01-01'::DATE) AS SALE_DATE,
    MOD(ABS(HASH(RN, 2)), 20) + 1                                AS STORE_ID,
    MOD(ABS(HASH(RN, 3)), 60) + 1                                AS PRODUCT_ID,
    MOD(ABS(HASH(RN, 4)), 3) + 1                                 AS QTY,
    ARRAY_CONSTRUCT(0, 0.05, 0.10)[MOD(ABS(HASH(RN, 5)), 3)]::NUMBER(4,2) AS DISCOUNT_RATE,
    MOD(ABS(HASH(RN, 6)), 1000)                                  AS RET_DICE
  FROM n
)
SELECT
  b.SALE_ID, b.SALE_DATE, b.STORE_ID, b.PRODUCT_ID, b.QTY, b.DISCOUNT_RATE,
  IFF(b.RET_DICE < 30 + IFF(s.CHANNEL = 'EC', 40, 0) + IFF(p.CATEGORY = 'MAKEUP', 30, 0) + IFF(s.REGION = 'KANSAI', 20, 0), 1, 0) AS RETURN_FLAG,
  ROUND(b.QTY * p.LIST_PRICE * (1 - b.DISCOUNT_RATE), 0)::NUMBER(12,0) AS SALES_AMOUNT_TAX_IN
FROM b
JOIN PRODUCT_MASTER p ON p.PRODUCT_ID = b.PRODUCT_ID
JOIN STORE_MASTER   s ON s.STORE_ID   = b.STORE_ID;

-- ---------- 確認 ----------
SELECT 'STORE_MASTER' AS T, COUNT(*) AS N FROM STORE_MASTER
UNION ALL SELECT 'PRODUCT_MASTER', COUNT(*) FROM PRODUCT_MASTER
UNION ALL SELECT 'SALES_DETAIL', COUNT(*) FROM SALES_DETAIL;
