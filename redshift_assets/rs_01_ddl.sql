-- Redshift（KOMPAS を模した架空の DDL）。第1幕で CoCo に Snowflake 向けへ変換させる
CREATE SCHEMA IF NOT EXISTS kompas;

CREATE TABLE kompas.dim_store (
  store_id    INTEGER      ENCODE az64  NOT NULL,
  store_name  VARCHAR(100) ENCODE lzo,
  channel     VARCHAR(10)  ENCODE lzo,
  region      VARCHAR(20)  ENCODE lzo,
  PRIMARY KEY (store_id)
)
DISTSTYLE ALL
SORTKEY (store_id);

CREATE TABLE kompas.dim_product (
  product_id    INTEGER      ENCODE az64  NOT NULL,
  product_name  VARCHAR(100) ENCODE lzo,
  brand         VARCHAR(20)  ENCODE lzo,
  category      VARCHAR(20)  ENCODE lzo,
  list_price    INTEGER      ENCODE az64,
  PRIMARY KEY (product_id)
)
DISTSTYLE ALL
SORTKEY (product_id);

CREATE TABLE kompas.fact_sales (
  sale_id              BIGINT        ENCODE az64  NOT NULL,
  sale_date            DATE          ENCODE az64  NOT NULL,
  store_id             INTEGER       ENCODE az64  NOT NULL,
  product_id           INTEGER       ENCODE az64  NOT NULL,
  qty                  SMALLINT      ENCODE az64,
  discount_rate        DECIMAL(4,2)  ENCODE az64,
  return_flag          SMALLINT      ENCODE az64,
  sales_amount_tax_in  DECIMAL(12,0) ENCODE az64,
  loaded_at            TIMESTAMP     DEFAULT GETDATE(),
  PRIMARY KEY (sale_id)
)
DISTKEY (store_id)
COMPOUND SORTKEY (sale_date, store_id);
