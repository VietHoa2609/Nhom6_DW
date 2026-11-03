USE OlistDW;
GO

SELECT d.[year], d.[month],
       SUM(f.price)                                             AS gmv,
       SUM(CASE WHEN s.order_status = N'delivered' AND f.delivered_date_key > 0 THEN f.price END) AS doanh_thu_thuc_thu,
       COUNT(DISTINCT f.order_id)                               AS so_don,
       SUM(f.quantity)                                          AS so_san_pham
FROM dwh.fact_order_item f
JOIN dwh.dim_date d         ON d.date_key = f.order_date_key
JOIN dwh.dim_order_status s ON s.order_status_key = f.order_status_key
GROUP BY d.[year], d.[month]
ORDER BY d.[year], d.[month];

WITH c AS (
    SELECT pc.category_name_english AS danh_muc, SUM(f.price) AS doanh_thu, COUNT(DISTINCT f.order_id) AS so_don
    FROM dwh.fact_order_item f
    JOIN dwh.dim_product p           ON p.product_key = f.product_key
    JOIN dwh.dim_product_category pc ON pc.category_key = p.category_key
    JOIN dwh.dim_order_status s      ON s.order_status_key = f.order_status_key
    WHERE s.order_status = N'delivered' AND f.delivered_date_key > 0
    GROUP BY pc.category_name_english
)
SELECT TOP 10 danh_muc, doanh_thu, so_don,
       CAST(100.0 * doanh_thu / SUM(doanh_thu) OVER () AS DECIMAL(5,2))                       AS ty_trong_pct,
       CAST(100.0 * SUM(doanh_thu) OVER (ORDER BY doanh_thu DESC ROWS UNBOUNDED PRECEDING)
            / SUM(doanh_thu) OVER () AS DECIMAL(5,2))                                          AS ty_trong_luy_ke_pct
FROM c ORDER BY doanh_thu DESC;

SELECT pm.payment_type, COUNT(DISTINCT f.order_id) AS so_don, SUM(f.price) AS doanh_thu,
       CAST(100.0 * SUM(f.price) / SUM(SUM(f.price)) OVER () AS DECIMAL(5,2)) AS ty_trong_pct
FROM dwh.fact_order_item f
JOIN dwh.dim_payment_method pm ON pm.payment_method_key = f.primary_payment_method_key
JOIN dwh.dim_order_status s    ON s.order_status_key = f.order_status_key
WHERE s.order_status = N'delivered' AND f.delivered_date_key > 0
GROUP BY pm.payment_type ORDER BY doanh_thu DESC;

SELECT TOP 15 s.seller_id, s.state,
       SUM(m.total_revenue)                                                           AS doanh_thu,
       SUM(m.total_orders_delivered)                                                  AS don_da_giao,
       CAST(100.0 * SUM(m.on_time_orders) / NULLIF(SUM(m.total_orders_delivered),0) AS DECIMAL(5,2)) AS dung_han_pct,
       CAST(1.0 * SUM(m.total_review_score) / NULLIF(SUM(m.total_reviewed_orders),0)  AS DECIMAL(4,2)) AS diem_tb
FROM dwh.fact_seller_route_monthly m
JOIN dwh.dim_seller s ON s.seller_key = m.seller_key
WHERE m.seller_key <> -1
GROUP BY s.seller_id, s.state
ORDER BY doanh_thu DESC;

WITH sp AS (
    SELECT m.seller_key,
           SUM(m.total_revenue) AS doanh_thu,
           SUM(m.total_orders_delivered) AS don_da_giao,
           100.0 * SUM(m.on_time_orders) / NULLIF(SUM(m.total_orders_delivered),0) AS dung_han_pct,
           1.0 * SUM(m.total_review_score) / NULLIF(SUM(m.total_reviewed_orders),0) AS diem_tb
    FROM dwh.fact_seller_route_monthly m WHERE m.seller_key <> -1 GROUP BY m.seller_key
)
SELECT s.seller_id, s.state, sp.doanh_thu, sp.don_da_giao,
       CAST(sp.dung_han_pct AS DECIMAL(5,2)) AS dung_han_pct, CAST(sp.diem_tb AS DECIMAL(4,2)) AS diem_tb,
       CASE WHEN sp.dung_han_pct < 85 AND sp.diem_tb < 3.5 THEN N'Rui ro cao'
            WHEN sp.dung_han_pct < 85 OR  sp.diem_tb < 3.5 THEN N'Can theo doi' END AS muc_rui_ro
FROM sp JOIN dwh.dim_seller s ON s.seller_key = sp.seller_key
WHERE sp.doanh_thu >= 10000 AND (sp.dung_han_pct < 85 OR sp.diem_tb < 3.5)
ORDER BY sp.doanh_thu DESC;

SELECT TOP 15 r.seller_state, r.customer_state, r.is_same_region,
       SUM(m.total_orders_delivered)                                                              AS don_da_giao,
       CAST(1.0 * SUM(m.total_delivery_days) / NULLIF(SUM(m.total_orders_delivered),0) AS DECIMAL(6,2)) AS ngay_giao_tb,
       CAST(SUM(m.total_freight_value) / NULLIF(SUM(m.total_orders_delivered),0)       AS DECIMAL(8,2)) AS cuoc_van_chuyen_tb,
       CAST(100.0 * (SUM(m.total_orders_delivered) - SUM(m.on_time_orders))
            / NULLIF(SUM(m.total_orders_delivered),0) AS DECIMAL(5,2))                            AS ty_le_tre_pct
FROM dwh.fact_seller_route_monthly m
JOIN dwh.dim_route r ON r.route_key = m.route_key
GROUP BY r.seller_state, r.customer_state, r.is_same_region
HAVING SUM(m.total_orders_delivered) >= 100
ORDER BY ngay_giao_tb DESC;

SELECT CASE r.is_same_region WHEN 1 THEN N'Noi vung' ELSE N'Lien vung' END AS loai_tuyen,
       SUM(m.total_orders_delivered)                                                                  AS don_da_giao,
       CAST(100.0 * SUM(m.total_orders_delivered) / SUM(SUM(m.total_orders_delivered)) OVER () AS DECIMAL(5,2)) AS ty_trong_pct,
       CAST(1.0 * SUM(m.total_delivery_days) / NULLIF(SUM(m.total_orders_delivered),0) AS DECIMAL(6,2))     AS ngay_giao_tb,
       CAST(SUM(m.total_freight_value) / NULLIF(SUM(m.total_orders_delivered),0)       AS DECIMAL(8,2))     AS cuoc_tb,
       CAST(100.0 * (SUM(m.total_orders_delivered) - SUM(m.on_time_orders))
            / NULLIF(SUM(m.total_orders_delivered),0) AS DECIMAL(5,2))                                      AS ty_le_tre_pct
FROM dwh.fact_seller_route_monthly m
JOIN dwh.dim_route r ON r.route_key = m.route_key
WHERE r.route_key <> -1
GROUP BY r.is_same_region;

SELECT d.[year], d.[month],
       COUNT(*)                                              AS don_hop_le,
       CAST(AVG(1.0 * f.days_to_approve) AS DECIMAL(6,2))    AS ngay_duyet_don,
       CAST(AVG(1.0 * f.days_to_ship)    AS DECIMAL(6,2))    AS ngay_giao_van,
       CAST(AVG(1.0 * f.days_to_deliver) AS DECIMAL(6,2))    AS ngay_van_chuyen,
       CAST(AVG(1.0 * f.total_days)      AS DECIMAL(6,2))    AS tong_ngay,
       CAST(100.0 * SUM(CAST(f.is_delayed AS INT)) / COUNT(*) AS DECIMAL(5,2)) AS ty_le_tre_pct
FROM dwh.fact_order_fulfillment f
JOIN dwh.dim_date d ON d.date_key = f.order_date_key
WHERE f.is_delayed IS NOT NULL
GROUP BY d.[year], d.[month] ORDER BY d.[year], d.[month];

SELECT CASE f.is_delayed WHEN 1 THEN N'Giao tre' ELSE N'Dung han / som' END AS nhom_don,
       COUNT(*)                                              AS so_don,
       CAST(AVG(1.0 * r.review_score) AS DECIMAL(4,2))       AS diem_tb,
       CAST(100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,2)) AS danh_gia_tieu_cuc_pct
FROM dwh.fact_order_fulfillment f
JOIN dwh.fact_review r ON r.order_id = f.order_id
WHERE f.is_delayed IS NOT NULL
GROUP BY f.is_delayed;

SELECT rfm_segment, COUNT(DISTINCT customer_unique_id) AS so_khach,
       CAST(100.0 * COUNT(DISTINCT customer_unique_id)
            / SUM(COUNT(DISTINCT customer_unique_id)) OVER () AS DECIMAL(5,2)) AS ty_le_pct,
       CAST(AVG(monetary_value) AS DECIMAL(10,2)) AS monetary_tb,
       CAST(AVG(1.0 * recency_days) AS DECIMAL(8,1)) AS recency_tb
FROM dwh.fact_customer_segment_monthly
WHERE month_key = 20180801
GROUP BY rfm_segment ORDER BY so_khach DESC;

SELECT CASE WHEN frequency_count >= 2 THEN N'Quay lai (F>=2)' ELSE N'Mua 1 lan (F=1)' END AS nhom,
       COUNT(DISTINCT customer_unique_id) AS so_khach,
       CAST(100.0 * COUNT(DISTINCT customer_unique_id)
            / SUM(COUNT(DISTINCT customer_unique_id)) OVER () AS DECIMAL(5,2)) AS ty_le_khach_pct,
       SUM(monetary_value) AS doanh_thu,
       CAST(100.0 * SUM(monetary_value) / SUM(SUM(monetary_value)) OVER () AS DECIMAL(5,2)) AS ty_le_doanh_thu_pct
FROM dwh.fact_customer_segment_monthly
WHERE month_key = 20180801 AND frequency_count >= 1
GROUP BY CASE WHEN frequency_count >= 2 THEN N'Quay lai (F>=2)' ELSE N'Mua 1 lan (F=1)' END;

















