-- Query 1: Impact of Delivery Delays on Customer Review Scores (CSAT)
SELECT 
    CASE 
        WHEN delivery_delay_days <= -5 THEN '1. Early (>5 days)'
        WHEN delivery_delay_days BETWEEN -5 AND 0 THEN '2. On Time (0-5 days early)'
        WHEN delivery_delay_days BETWEEN 0.01 AND 3 THEN '3. Minor Delay (1-3 days)'
        WHEN delivery_delay_days BETWEEN 3.01 AND 7 THEN '4. Moderate Delay (4-7 days)'
        ELSE '5. Severe Delay (>7 days)'
    END AS delay_bracket,
    COUNT(order_id) AS total_orders,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS detractor_rate_pct
FROM fact_orders
WHERE order_status = 'delivered' AND review_score IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- Query 2: Regional Logistics Bottlenecks & Freight Burden
SELECT 
    c.customer_state,
    COUNT(o.order_id) AS total_orders,
    ROUND(AVG(o.delivery_delay_days), 1) AS avg_delay_days,
    ROUND(AVG(o.total_freight), 2) AS avg_freight_cost,
    ROUND(AVG(o.total_freight * 100.0 / NULLIF(o.total_item_value, 0)), 2) AS freight_to_value_pct,
    ROUND(AVG(o.review_score), 2) AS avg_customer_rating
FROM fact_orders o
JOIN dim_customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY 1
HAVING COUNT(o.order_id) > 500
ORDER BY avg_delay_days DESC;

-- Query 3: Recency, Frequency, Monetary (RFM) Segmentation
WITH rfm_base AS (
    SELECT 
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp) AS last_order_date,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(o.total_payment) AS monetary_value
    FROM fact_orders o
    JOIN dim_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
rfm_ranked AS (
    SELECT 
        customer_unique_id,
        NTILE(5) OVER (ORDER BY last_order_date ASC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary_value ASC) AS m_score,
        monetary_value
    FROM rfm_base
)
SELECT 
    CASE 
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk / Churning'
        ELSE 'Casual / One-Time'
    END AS segment_name,
    COUNT(*) AS total_customers,
    ROUND(AVG(monetary_value), 2) AS avg_spend,
    ROUND(SUM(monetary_value), 2) AS total_revenue
FROM rfm_ranked
GROUP BY 1
ORDER BY total_revenue DESC;
