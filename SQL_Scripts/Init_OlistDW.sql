/*==============================================================================
  OlistDW - Kho dữ liệu Olist E-commerce (Nhóm 06 - DAWH430784)
  Kiến trúc: Source (CSV) -> Staging (schema staging) -> Data Mart (schema dwh, Galaxy Schema)
  Chuẩn Kimball: 10 Dimension + 5 Fact, Surrogate Key, Unknown Member = -1

  Cách dùng:
    1. Mở file trong SSMS, bấm Execute (chạy lại được nhiều lần, sẽ DROP & tạo lại).
    2. Chạy các package SSIS: PKG_01_Staging -> PKG_02 ... -> Master.dtsx
==============================================================================*/

USE master;
GO
IF DB_ID(N'OlistDW') IS NULL
    CREATE DATABASE OlistDW;
GO
USE OlistDW;
GO
SET LANGUAGE us_english;
GO
IF SCHEMA_ID(N'staging') IS NULL EXEC (N'CREATE SCHEMA staging');
IF SCHEMA_ID(N'dwh')     IS NULL EXEC (N'CREATE SCHEMA dwh');
GO

/*------------------------------------------------------------------------------
  2. DROP IF EXISTS  (Proc/Function -> Facts -> Dimensions -> Staging)
------------------------------------------------------------------------------*/
DROP PROCEDURE IF EXISTS dbo.sp_Run_ETL_OlistDW;
GO

-- Facts
DROP TABLE IF EXISTS dwh.fact_customer_segment_monthly;
DROP TABLE IF EXISTS dwh.fact_seller_route_monthly;
DROP TABLE IF EXISTS dwh.fact_order_fulfillment;
DROP TABLE IF EXISTS dwh.fact_review;
DROP TABLE IF EXISTS dwh.fact_order_item;
GO

-- Dimensions (bảng con trước, bảng cha sau)
DROP TABLE IF EXISTS dwh.dim_product;
DROP TABLE IF EXISTS dwh.dim_product_category;
DROP TABLE IF EXISTS dwh.dim_customer;
DROP TABLE IF EXISTS dwh.dim_seller;
DROP TABLE IF EXISTS dwh.dim_geolocation;
DROP TABLE IF EXISTS dwh.dim_route;
DROP TABLE IF EXISTS dwh.dim_payment_method;
DROP TABLE IF EXISTS dwh.dim_review_category;
DROP TABLE IF EXISTS dwh.dim_order_status;
DROP TABLE IF EXISTS dwh.dim_date;
GO

-- Staging
DROP TABLE IF EXISTS staging.stg_product_category_name_translation;
DROP TABLE IF EXISTS staging.stg_geolocation;
DROP TABLE IF EXISTS staging.stg_order_reviews;
DROP TABLE IF EXISTS staging.stg_order_payments;
DROP TABLE IF EXISTS staging.stg_products;
DROP TABLE IF EXISTS staging.stg_sellers;
DROP TABLE IF EXISTS staging.stg_customers;
DROP TABLE IF EXISTS staging.stg_order_items;
DROP TABLE IF EXISTS staging.stg_orders;
GO

DROP FUNCTION IF EXISTS dbo.fn_date_key;
DROP FUNCTION IF EXISTS dbo.fn_state_region;
GO

/*------------------------------------------------------------------------------
  Hàm tiện ích
------------------------------------------------------------------------------*/
-- Vùng của Brazil suy ra từ bang
CREATE FUNCTION dbo.fn_state_region (@state NVARCHAR(10))
RETURNS NVARCHAR(20)
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
        WHEN UPPER(LTRIM(RTRIM(@state))) IN (N'AC',N'AP',N'AM',N'PA',N'RO',N'RR',N'TO')                 THEN N'North'
        WHEN UPPER(LTRIM(RTRIM(@state))) IN (N'AL',N'BA',N'CE',N'MA',N'PB',N'PE',N'PI',N'RN',N'SE')     THEN N'Northeast'
        WHEN UPPER(LTRIM(RTRIM(@state))) IN (N'DF',N'GO',N'MT',N'MS')                                   THEN N'Central-West'
        WHEN UPPER(LTRIM(RTRIM(@state))) IN (N'ES',N'MG',N'RJ',N'SP')                                   THEN N'Southeast'
        WHEN UPPER(LTRIM(RTRIM(@state))) IN (N'PR',N'RS',N'SC')                                         THEN N'South'
        ELSE N'Unknown'
    END;
END;
GO

-- Timestamp -> date_key (YYYYMMDD); NULL hoặc ngoài phạm vi dim_date -> -1 (Unknown)
CREATE FUNCTION dbo.fn_date_key (@d DATETIME2(0))
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CASE
        WHEN @d IS NULL OR @d < '2016-01-01' OR @d >= '2019-01-01' THEN -1
        ELSE CONVERT(INT, CONVERT(CHAR(8), @d, 112))
    END;
END;
GO

/*------------------------------------------------------------------------------
  3. TẦNG STAGING AREA (schema staging) - NVARCHAR thô, không PK/FK/ràng buộc
------------------------------------------------------------------------------*/
CREATE TABLE staging.stg_orders (
    order_id                        NVARCHAR(50),
    customer_id                     NVARCHAR(50),
    order_status                    NVARCHAR(20),
    order_purchase_timestamp        NVARCHAR(50),
    order_approved_at               NVARCHAR(50),
    order_delivered_carrier_date    NVARCHAR(50),
    order_delivered_customer_date   NVARCHAR(50),
    order_estimated_delivery_date   NVARCHAR(50)
);

CREATE TABLE staging.stg_order_items (
    order_id            NVARCHAR(50),
    order_item_id       NVARCHAR(10),
    product_id          NVARCHAR(50),
    seller_id           NVARCHAR(50),
    shipping_limit_date NVARCHAR(50),
    price               NVARCHAR(20),
    freight_value       NVARCHAR(20)
);

CREATE TABLE staging.stg_customers (
    customer_id              NVARCHAR(50),
    customer_unique_id       NVARCHAR(50),
    customer_zip_code_prefix NVARCHAR(10),
    customer_city            NVARCHAR(100),
    customer_state           NVARCHAR(10)
);

CREATE TABLE staging.stg_sellers (
    seller_id              NVARCHAR(50),
    seller_zip_code_prefix NVARCHAR(10),
    seller_city            NVARCHAR(100),
    seller_state           NVARCHAR(10)
);

CREATE TABLE staging.stg_products (
    product_id                 NVARCHAR(50),
    product_category_name      NVARCHAR(100),
    product_name_lenght        NVARCHAR(10),
    product_description_lenght NVARCHAR(10),
    product_photos_qty         NVARCHAR(10),
    product_weight_g           NVARCHAR(20),
    product_length_cm          NVARCHAR(20),
    product_height_cm          NVARCHAR(20),
    product_width_cm           NVARCHAR(20)
);

CREATE TABLE staging.stg_order_payments (
    order_id             NVARCHAR(50),
    payment_sequential   NVARCHAR(10),
    payment_type         NVARCHAR(30),
    payment_installments NVARCHAR(10),
    payment_value        NVARCHAR(20)
);

CREATE TABLE staging.stg_order_reviews (
    review_id               NVARCHAR(50),
    order_id                NVARCHAR(50),
    review_score            NVARCHAR(10),
    review_comment_title    NVARCHAR(255),
    review_comment_message  NVARCHAR(MAX),
    review_creation_date    NVARCHAR(50),
    review_answer_timestamp NVARCHAR(50)
);

CREATE TABLE staging.stg_geolocation (
    geolocation_zip_code_prefix NVARCHAR(10),
    geolocation_lat             NVARCHAR(30),
    geolocation_lng             NVARCHAR(30),
    geolocation_city            NVARCHAR(100),
    geolocation_state           NVARCHAR(10)
);

CREATE TABLE staging.stg_product_category_name_translation (
    product_category_name         NVARCHAR(100),
    product_category_name_english NVARCHAR(100)
);
GO

/*------------------------------------------------------------------------------
  4. TẦNG DATA MART (schema dwh - Galaxy Schema)
  4.1 DIMENSIONS
------------------------------------------------------------------------------*/

-- 1) dim_date: khóa cố định YYYYMMDD
CREATE TABLE dwh.dim_date (
    date_key          INT           NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,
    full_date         DATE          NULL,
    [year]            SMALLINT      NULL,
    [quarter]         TINYINT       NULL,
    [month]           TINYINT       NULL,
    month_name        NVARCHAR(20)  NOT NULL,
    day_of_week       NVARCHAR(20)  NOT NULL,
    is_weekend        BIT           NOT NULL,
    is_holiday_brazil BIT           NOT NULL
);

-- 2) dim_geolocation (SCD1): 1 dòng / zip_code_prefix
CREATE TABLE dwh.dim_geolocation (
    geo_key         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_geolocation PRIMARY KEY,
    zip_code_prefix NVARCHAR(10)  NOT NULL CONSTRAINT UQ_dim_geolocation_zip UNIQUE,
    city            NVARCHAR(100) NULL,
    state           NVARCHAR(10)  NULL,
    region          NVARCHAR(20)  NULL,
    latitude        DECIMAL(9,6)  NULL,
    longitude       DECIMAL(9,6)  NULL
);

-- 3) dim_customer (SCD2): BK = customer_unique_id
CREATE TABLE dwh.dim_customer (
    customer_key       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_customer PRIMARY KEY,
    customer_unique_id NVARCHAR(50)  NOT NULL,
    city               NVARCHAR(100) NULL,
    state              NVARCHAR(10)  NULL,
    customer_region    NVARCHAR(20)  NULL,
    geo_key            INT           NOT NULL CONSTRAINT FK_dim_customer_geo REFERENCES dwh.dim_geolocation(geo_key),
    effective_from     DATETIME2(0)  NOT NULL,
    effective_to       DATETIME2(0)  NOT NULL CONSTRAINT DF_dim_customer_to DEFAULT ('9999-12-31'),
    is_current         BIT           NOT NULL CONSTRAINT DF_dim_customer_cur DEFAULT (1)
);
CREATE UNIQUE INDEX UX_dim_customer_bk_from
    ON dwh.dim_customer (customer_unique_id, effective_from) INCLUDE (effective_to, customer_key);

-- 4) dim_seller (SCD1)
CREATE TABLE dwh.dim_seller (
    seller_key    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_seller PRIMARY KEY,
    seller_id     NVARCHAR(50)  NOT NULL CONSTRAINT UQ_dim_seller_id UNIQUE,
    city          NVARCHAR(100) NULL,
    state         NVARCHAR(10)  NULL,
    geo_key       INT           NOT NULL CONSTRAINT FK_dim_seller_geo REFERENCES dwh.dim_geolocation(geo_key),
    seller_region NVARCHAR(20)  NULL
);

-- 5) dim_product_category (SCD1)
CREATE TABLE dwh.dim_product_category (
    category_key             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_product_category PRIMARY KEY,
    category_name_portuguese NVARCHAR(100) NOT NULL CONSTRAINT UQ_dim_product_category_pt UNIQUE,
    category_name_english    NVARCHAR(100) NULL
);

-- 6) dim_product (SCD1)
CREATE TABLE dwh.dim_product (
    product_key        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_product PRIMARY KEY,
    product_id         NVARCHAR(50)  NOT NULL CONSTRAINT UQ_dim_product_id UNIQUE,
    category_key       INT           NOT NULL CONSTRAINT FK_dim_product_category REFERENCES dwh.dim_product_category(category_key),
    product_weight_g   DECIMAL(10,2) NULL,
    product_length_cm  DECIMAL(10,2) NULL,
    product_width_cm   DECIMAL(10,2) NULL,
    product_height_cm  DECIMAL(10,2) NULL
);

-- 7) dim_order_status (Static, khóa cố định)
CREATE TABLE dwh.dim_order_status (
    order_status_key INT           NOT NULL CONSTRAINT PK_dim_order_status PRIMARY KEY,
    order_status     NVARCHAR(20)  NOT NULL CONSTRAINT UQ_dim_order_status UNIQUE,
    [description]    NVARCHAR(200) NULL
);

-- 8) dim_review_category (Static)
CREATE TABLE dwh.dim_review_category (
    review_category_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_review_category PRIMARY KEY,
    score_bucket        NVARCHAR(20) NOT NULL,
    has_comment         BIT          NOT NULL,
    CONSTRAINT UQ_dim_review_category UNIQUE (score_bucket, has_comment)
);

-- 9) dim_payment_method (Static)
CREATE TABLE dwh.dim_payment_method (
    payment_method_key INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_payment_method PRIMARY KEY,
    payment_type       NVARCHAR(30)  NOT NULL CONSTRAINT UQ_dim_payment_method UNIQUE,
    [description]      NVARCHAR(200) NULL
);

-- 10) dim_route (Static): bang người bán -> bang khách hàng
CREATE TABLE dwh.dim_route (
    route_key       INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_route PRIMARY KEY,
    seller_state    NVARCHAR(10) NOT NULL,
    seller_region   NVARCHAR(20) NULL,
    customer_state  NVARCHAR(10) NOT NULL,
    customer_region NVARCHAR(20) NULL,
    is_same_region  BIT          NOT NULL,
    CONSTRAINT UQ_dim_route UNIQUE (seller_state, customer_state)
);
GO

/*------------------------------------------------------------------------------
  4.2 FACTS
------------------------------------------------------------------------------*/

-- 1) fact_order_item - Transaction Fact (grain: 1 sản phẩm / đơn)
CREATE TABLE dwh.fact_order_item (
    fact_order_item_id          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_fact_order_item PRIMARY KEY,
    order_id                    NVARCHAR(50)  NOT NULL,   -- degenerate dimension
    order_item_id               INT           NOT NULL,   -- degenerate dimension
    customer_key                INT NOT NULL CONSTRAINT FK_foi_customer REFERENCES dwh.dim_customer(customer_key),
    seller_key                  INT NOT NULL CONSTRAINT FK_foi_seller   REFERENCES dwh.dim_seller(seller_key),
    product_key                 INT NOT NULL CONSTRAINT FK_foi_product  REFERENCES dwh.dim_product(product_key),
    route_key                   INT NOT NULL CONSTRAINT FK_foi_route    REFERENCES dwh.dim_route(route_key),
    order_date_key              INT NOT NULL CONSTRAINT FK_foi_odate    REFERENCES dwh.dim_date(date_key),
    approved_date_key           INT NOT NULL CONSTRAINT FK_foi_adate    REFERENCES dwh.dim_date(date_key),
    delivered_date_key          INT NOT NULL CONSTRAINT FK_foi_ddate    REFERENCES dwh.dim_date(date_key),
    estimated_delivery_date_key INT NOT NULL CONSTRAINT FK_foi_edate    REFERENCES dwh.dim_date(date_key),
    order_status_key            INT NOT NULL CONSTRAINT FK_foi_status   REFERENCES dwh.dim_order_status(order_status_key),
    primary_payment_method_key  INT NOT NULL CONSTRAINT FK_foi_payment  REFERENCES dwh.dim_payment_method(payment_method_key),
    price                       DECIMAL(12,2) NOT NULL,
    freight_value               DECIMAL(12,2) NOT NULL,
    quantity                    INT           NOT NULL CONSTRAINT DF_foi_qty DEFAULT (1),
    CONSTRAINT UQ_fact_order_item UNIQUE (order_id, order_item_id)
);
CREATE INDEX IX_foi_order_date ON dwh.fact_order_item (order_date_key);
CREATE INDEX IX_foi_seller_route ON dwh.fact_order_item (seller_key, route_key, order_date_key);

-- 2) fact_review - Transaction Fact (grain: 1 review / đơn, giữ review mới nhất)
CREATE TABLE dwh.fact_review (
    order_id            NVARCHAR(50) NOT NULL CONSTRAINT PK_fact_review PRIMARY KEY,
    review_id           NVARCHAR(50) NULL,   -- không duy nhất trên nguồn nên không làm khóa
    customer_key        INT NOT NULL CONSTRAINT FK_fr_customer REFERENCES dwh.dim_customer(customer_key),
    review_date_key     INT NOT NULL CONSTRAINT FK_fr_date     REFERENCES dwh.dim_date(date_key),
    review_category_key INT NOT NULL CONSTRAINT FK_fr_category REFERENCES dwh.dim_review_category(review_category_key),
    review_score        TINYINT NOT NULL CONSTRAINT CK_fr_score CHECK (review_score BETWEEN 1 AND 5)
);

-- 3) fact_order_fulfillment - Accumulating Snapshot (grain: 1 đơn hàng)
CREATE TABLE dwh.fact_order_fulfillment (
    order_id                    NVARCHAR(50) NOT NULL CONSTRAINT PK_fact_order_fulfillment PRIMARY KEY,
    customer_key                INT NOT NULL CONSTRAINT FK_fof_customer REFERENCES dwh.dim_customer(customer_key),
    primary_seller_key          INT NOT NULL CONSTRAINT FK_fof_seller   REFERENCES dwh.dim_seller(seller_key),
    order_date_key              INT NOT NULL CONSTRAINT FK_fof_odate    REFERENCES dwh.dim_date(date_key),
    approved_date_key           INT NOT NULL CONSTRAINT FK_fof_adate    REFERENCES dwh.dim_date(date_key),
    shipped_date_key            INT NOT NULL CONSTRAINT FK_fof_sdate    REFERENCES dwh.dim_date(date_key),
    delivered_date_key          INT NOT NULL CONSTRAINT FK_fof_ddate    REFERENCES dwh.dim_date(date_key),
    estimated_delivery_date_key INT NOT NULL CONSTRAINT FK_fof_edate    REFERENCES dwh.dim_date(date_key),
    days_to_approve             INT NULL,
    days_to_ship                INT NULL,
    days_to_deliver             INT NULL,
    total_days                  INT NULL,
    is_delayed                  BIT NULL,   -- NULL nếu đơn chưa hợp lệ
    order_status_key            INT NOT NULL CONSTRAINT FK_fof_status   REFERENCES dwh.dim_order_status(order_status_key)
);

-- 4) fact_seller_route_monthly - Periodic Snapshot (seller x route x tháng)
CREATE TABLE dwh.fact_seller_route_monthly (
    seller_key              INT NOT NULL CONSTRAINT FK_fsr_seller REFERENCES dwh.dim_seller(seller_key),
    route_key               INT NOT NULL CONSTRAINT FK_fsr_route  REFERENCES dwh.dim_route(route_key),
    month_key               INT NOT NULL CONSTRAINT FK_fsr_month  REFERENCES dwh.dim_date(date_key),  -- YYYYMM01
    total_orders            INT NOT NULL DEFAULT (0),
    total_items             INT NOT NULL DEFAULT (0),
    total_revenue           DECIMAL(14,2) NOT NULL DEFAULT (0),
    total_freight_value     DECIMAL(14,2) NOT NULL DEFAULT (0),
    total_orders_delivered  INT NOT NULL DEFAULT (0),
    on_time_orders          INT NOT NULL DEFAULT (0),
    total_delivery_days     INT NOT NULL DEFAULT (0),
    total_reviewed_orders   INT NOT NULL DEFAULT (0),
    total_review_score      INT NOT NULL DEFAULT (0),
    -- Calculated measures: tổng / mẫu số tương ứng
    avg_freight_value AS CAST(total_freight_value / NULLIF(total_orders_delivered, 0) AS DECIMAL(12,2)) PERSISTED,
    avg_delivery_days AS CAST(total_delivery_days * 1.0 / NULLIF(total_orders_delivered, 0) AS DECIMAL(10,2)) PERSISTED,
    avg_review_score  AS CAST(total_review_score * 1.0 / NULLIF(total_reviewed_orders, 0) AS DECIMAL(4,2)) PERSISTED,
    on_time_rate      AS CAST(on_time_orders * 1.0 / NULLIF(total_orders_delivered, 0) AS DECIMAL(5,4)) PERSISTED,
    CONSTRAINT PK_fact_seller_route_monthly PRIMARY KEY (seller_key, route_key, month_key)
);

-- 5) fact_customer_segment_monthly - Periodic Snapshot (customer_unique_id x tháng, RFM)
CREATE TABLE dwh.fact_customer_segment_monthly (
    customer_key       INT NOT NULL CONSTRAINT FK_fcs_customer REFERENCES dwh.dim_customer(customer_key),
    month_key          INT NOT NULL CONSTRAINT FK_fcs_month    REFERENCES dwh.dim_date(date_key),  -- YYYYMM01
    customer_unique_id NVARCHAR(50)  NOT NULL,
    monthly_orders     INT           NOT NULL DEFAULT (0),   -- phát sinh trong tháng
    monthly_items      INT           NOT NULL DEFAULT (0),
    monthly_spent      DECIMAL(14,2) NOT NULL DEFAULT (0),
    avg_review_score   DECIMAL(4,2)  NULL,
    recency_days       INT           NULL,                   -- R
    frequency_count    INT           NOT NULL DEFAULT (0),   -- F tích lũy
    monetary_value     DECIMAL(14,2) NOT NULL DEFAULT (0),   -- M tích lũy
    rfm_segment        NVARCHAR(20)  NULL,                   -- VIP / Regular / At-risk / Churned
    CONSTRAINT PK_fact_customer_segment_monthly PRIMARY KEY (customer_key, month_key)
);
CREATE INDEX IX_fcs_unique_id ON dwh.fact_customer_segment_monthly (customer_unique_id, month_key);
GO

/*------------------------------------------------------------------------------
  5. NẠP DỮ LIỆU TĨNH VÀ UNKNOWN MEMBER (-1)
------------------------------------------------------------------------------*/

-- 1) Unknown Members (-1) cho các Dimension có Surrogate Key tự tăng
SET IDENTITY_INSERT dwh.dim_geolocation ON;
INSERT INTO dwh.dim_geolocation (geo_key, zip_code_prefix, city, state, region, latitude, longitude)
VALUES (-1, N'00000', N'Unknown', N'NA', N'Unknown', 0, 0);
SET IDENTITY_INSERT dwh.dim_geolocation OFF;

SET IDENTITY_INSERT dwh.dim_customer ON;
INSERT INTO dwh.dim_customer (customer_key, customer_unique_id, city, state, customer_region, geo_key, effective_from, effective_to, is_current)
VALUES (-1, N'UNKNOWN', N'Unknown', N'NA', N'Unknown', -1, '1900-01-01', '9999-12-31', 1);
SET IDENTITY_INSERT dwh.dim_customer OFF;

SET IDENTITY_INSERT dwh.dim_seller ON;
INSERT INTO dwh.dim_seller (seller_key, seller_id, city, state, geo_key, seller_region)
VALUES (-1, N'UNKNOWN', N'Unknown', N'NA', -1, N'Unknown');
SET IDENTITY_INSERT dwh.dim_seller OFF;

SET IDENTITY_INSERT dwh.dim_product_category ON;
INSERT INTO dwh.dim_product_category (category_key, category_name_portuguese, category_name_english)
VALUES (-1, N'nao_definido', N'Unknown');
SET IDENTITY_INSERT dwh.dim_product_category OFF;

SET IDENTITY_INSERT dwh.dim_product ON;
INSERT INTO dwh.dim_product (product_key, product_id, category_key, product_weight_g, product_length_cm, product_width_cm, product_height_cm)
VALUES (-1, N'UNKNOWN', -1, 0, 0, 0, 0);
SET IDENTITY_INSERT dwh.dim_product OFF;

-- 2) dim_date: Bản ghi Unknown (-1) + Sinh chuỗi ngày từ 2016-01-01 đến 2018-12-31
INSERT INTO dwh.dim_date (date_key, full_date, [year], [quarter], [month], month_name, day_of_week, is_weekend, is_holiday_brazil)
VALUES (-1, '1900-01-01', 1900, 0, 0, N'Unknown', N'Unknown', 0, 0);

DECLARE @CurDate DATE = '2016-01-01', @EndDate DATE = '2018-12-31';
WHILE @CurDate <= @EndDate
BEGIN
    INSERT INTO dwh.dim_date (date_key, full_date, [year], [quarter], [month], month_name, day_of_week, is_weekend, is_holiday_brazil)
    VALUES (
        CONVERT(INT, CONVERT(CHAR(8), @CurDate, 112)),
        @CurDate,
        YEAR(@CurDate),
        DATEPART(QUARTER, @CurDate),
        MONTH(@CurDate),
        DATENAME(MONTH, @CurDate),
        DATENAME(WEEKDAY, @CurDate),
        CASE WHEN DATEPART(WEEKDAY, @CurDate) IN (1, 7) THEN 1 ELSE 0 END,
        0
    );
    SET @CurDate = DATEADD(DAY, 1, @CurDate);
END;

-- 3) dim_order_status (Static)
INSERT INTO dwh.dim_order_status (order_status_key, order_status, [description]) VALUES
(-1, N'unknown', N'Không xác định'),
(1, N'delivered', N'Đã giao hàng'),
(2, N'shipped', N'Đã gửi hàng'),
(3, N'canceled', N'Đã hủy đơn'),
(4, N'invoiced', N'Đã xuất hóa đơn'),
(5, N'processing', N'Đang xử lý'),
(6, N'approved', N'Đã phê duyệt'),
(7, N'unavailable', N'Không có hàng'),
(8, N'created', N'Mới khởi tạo');

-- 4) dim_review_category (Static - Unknown -1)
SET IDENTITY_INSERT dwh.dim_review_category ON;
INSERT INTO dwh.dim_review_category (review_category_key, score_bucket, has_comment)
VALUES (-1, N'Unknown', 0);
SET IDENTITY_INSERT dwh.dim_review_category OFF;

INSERT INTO dwh.dim_review_category (score_bucket, has_comment) VALUES
(N'1-2 sao', 0), (N'1-2 sao', 1),
(N'3 sao', 0),   (N'3 sao', 1),
(N'4-5 sao', 0), (N'4-5 sao', 1);

-- 5) dim_payment_method (Static - Unknown -1)
SET IDENTITY_INSERT dwh.dim_payment_method ON;
INSERT INTO dwh.dim_payment_method (payment_method_key, payment_type, [description])
VALUES (-1, N'not_defined', N'Không xác định');
SET IDENTITY_INSERT dwh.dim_payment_method OFF;

INSERT INTO dwh.dim_payment_method (payment_type, [description]) VALUES
(N'credit_card', N'Thẻ tín dụng'),
(N'boleto', N'Phiếu thanh toán Boleto'),
(N'voucher', N'Voucher giảm giá'),
(N'debit_card', N'Thẻ ghi nợ');

-- 6) dim_route (Static - Unknown -1 + 27x27 tổ hợp bang)
SET IDENTITY_INSERT dwh.dim_route ON;
INSERT INTO dwh.dim_route (route_key, seller_state, seller_region, customer_state, customer_region, is_same_region)
VALUES (-1, N'NA', N'Unknown', N'NA', N'Unknown', 0);
SET IDENTITY_INSERT dwh.dim_route OFF;

WITH States AS (
    SELECT state_code FROM (VALUES 
        (N'AC'),(N'AL'),(N'AM'),(N'AP'),(N'BA'),(N'CE'),(N'DF'),(N'ES'),(N'GO'),
        (N'MA'),(N'MG'),(N'MS'),(N'MT'),(N'PA'),(N'PB'),(N'PE'),(N'PI'),(N'PR'),
        (N'RJ'),(N'RN'),(N'RO'),(N'RR'),(N'RS'),(N'SC'),(N'SE'),(N'SP'),(N'TO')
    ) AS T(state_code)
)
INSERT INTO dwh.dim_route (seller_state, seller_region, customer_state, customer_region, is_same_region)
SELECT 
    s.state_code AS seller_state,
    dbo.fn_state_region(s.state_code) AS seller_region,
    c.state_code AS customer_state,
    dbo.fn_state_region(c.state_code) AS customer_region,
    CASE WHEN dbo.fn_state_region(s.state_code) = dbo.fn_state_region(c.state_code) THEN 1 ELSE 0 END AS is_same_region
FROM States s CROSS JOIN States c;
GO