-- Redshift（KOMPAS を模した架空のマート作成クエリ）。第1幕で変換し、結果を突合する
CREATE TABLE kompas.mart_monthly_brand_sales
DISTKEY (brand)
SORTKEY (sales_month)
AS
SELECT
  DATE_TRUNC('month', f.sale_date)::date                                    AS sales_month,
  p.brand,
  DECODE(s.channel, 'EC', 'ECサイト', 'STORE', '店舗', 'その他')            AS channel_name,
  COUNT(*)                                                                  AS txn_count,
  SUM(f.qty)                                                                AS qty_total,
  SUM(f.sales_amount_tax_in)                                                AS gross_tax_in,
  SUM(NVL(CASE WHEN f.return_flag = 0 THEN f.sales_amount_tax_in END, 0))   AS net_tax_in,
  ROUND(SUM(NVL(CASE WHEN f.return_flag = 0 THEN f.sales_amount_tax_in END, 0)) / 1.10, 0) AS net_tax_ex,
  APPROXIMATE COUNT(DISTINCT f.product_id)                                  AS product_cnt,
  LISTAGG(DISTINCT s.region, ',') WITHIN GROUP (ORDER BY s.region)          AS regions,
  DATEDIFF(day, MIN(f.sale_date), MAX(f.sale_date))                         AS span_days,
  GETDATE()                                                                 AS loaded_at
FROM kompas.fact_sales f
JOIN kompas.dim_store   s ON s.store_id   = f.store_id
JOIN kompas.dim_product p ON p.product_id = f.product_id
GROUP BY 1, 2, 3;
