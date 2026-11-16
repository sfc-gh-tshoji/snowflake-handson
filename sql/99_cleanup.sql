-- =============================================================
-- 99_cleanup.sql  ハンズオン終了後のクレジット消費停止・削除
-- =============================================================
USE ROLE ACCOUNTADMIN;
ALTER WAREHOUSE IF EXISTS HANDSON_WH SUSPEND;

-- 環境を残さない場合は以下も実行
-- DROP DATABASE IF EXISTS RETAIL_HANDSON;
-- DROP WAREHOUSE IF EXISTS HANDSON_WH;
-- DROP ROLE IF EXISTS HANDSON_ROLE;
