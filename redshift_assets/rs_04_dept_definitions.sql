-- 第2幕の材料: 部門ごとに「売上」の定義が異なる（課題①：定義の散在・解釈揺れを模した架空例）
-- 営業部門: 税込金額をそのまま合計（返品も含む）
SELECT DATE_TRUNC('month', sale_date) AS sales_month, SUM(sales_amount_tax_in) AS uriage
FROM DWH.FACT_SALES GROUP BY 1 ORDER BY 1;

-- 経理部門: 返品を除き、税抜（税率10%）に換算して合計
SELECT DATE_TRUNC('month', sale_date) AS sales_month,
       ROUND(SUM(IFF(return_flag = 0, sales_amount_tax_in, 0)) / 1.10, 0) AS uriage
FROM DWH.FACT_SALES GROUP BY 1 ORDER BY 1;
