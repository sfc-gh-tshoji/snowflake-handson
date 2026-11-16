-- 【発展】Redshift のストアドプロシージャ（plpgsql）。時間があれば Snowflake Scripting へ変換する
CREATE OR REPLACE PROCEDURE kompas.sp_refresh_mart(p_from DATE)
AS $$
DECLARE
  v_cnt INTEGER;
BEGIN
  DELETE FROM kompas.mart_monthly_brand_sales WHERE sales_month >= DATE_TRUNC('month', p_from);

  INSERT INTO kompas.mart_monthly_brand_sales
  SELECT
    DATE_TRUNC('month', f.sale_date)::date, p.brand,
    DECODE(s.channel, 'EC', 'ECサイト', 'STORE', '店舗', 'その他'),
    COUNT(*), SUM(f.qty), SUM(f.sales_amount_tax_in),
    SUM(NVL(CASE WHEN f.return_flag = 0 THEN f.sales_amount_tax_in END, 0)),
    ROUND(SUM(NVL(CASE WHEN f.return_flag = 0 THEN f.sales_amount_tax_in END, 0)) / 1.10, 0),
    APPROXIMATE COUNT(DISTINCT f.product_id),
    LISTAGG(DISTINCT s.region, ',') WITHIN GROUP (ORDER BY s.region),
    DATEDIFF(day, MIN(f.sale_date), MAX(f.sale_date)),
    GETDATE()
  FROM kompas.fact_sales f
  JOIN kompas.dim_store   s ON s.store_id   = f.store_id
  JOIN kompas.dim_product p ON p.product_id = f.product_id
  WHERE f.sale_date >= DATE_TRUNC('month', p_from)
  GROUP BY 1, 2, 3;

  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  RAISE INFO 'refreshed % rows', v_cnt;
END;
$$ LANGUAGE plpgsql;
