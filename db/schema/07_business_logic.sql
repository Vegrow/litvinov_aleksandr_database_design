CREATE OR REPLACE PROCEDURE litvinov_food.add_product(
    p_restaurant_id uuid,
    p_product_category_id uuid,
    p_name varchar,
    p_price numeric,
    p_rating numeric,
    p_status litvinov_food.product_status,
    p_description text,
    p_photo_url text DEFAULT NULL
)
LANGUAGE plpgsql
SET search_path = litvinov_food, exts, pg_temp
AS $$
BEGIN
    INSERT INTO litvinov_food.product
        (product_id, product_name, product_category_id, price, restaurant_id, photo_url, rating, status, description)
    VALUES
        (exts.uuid_generate_v4(), p_name, p_product_category_id, p_price, p_restaurant_id, p_photo_url, p_rating, p_status, p_description);
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'Ресторан или категория блюда не существует';
    WHEN check_violation OR not_null_violation THEN
        RAISE EXCEPTION 'Нарушение ограничений таблицы product';
END;
$$;


CREATE OR REPLACE FUNCTION litvinov_food.get_statistic()
RETURNS TABLE (
    restaurant_name varchar,
    best_product_name varchar,
    total_amount numeric,
    avg_amount numeric,
    best_user varchar
)
LANGUAGE sql
STABLE
SET search_path = litvinov_food, pg_temp
AS $$
    WITH delivered_orders AS (
        SELECT order_id, restaurant_id, client_id, total_amount
        FROM litvinov_food."order"
        WHERE status = 'доставлен'
    ),

    order_totals AS (
        SELECT restaurant_id, sum(total_amount) AS total_amount, avg(total_amount) AS avg_amount
        FROM delivered_orders
        GROUP BY restaurant_id
    ),

    product_sales AS (
        SELECT d.restaurant_id, p.product_id, p.product_name, sum(os.quantity) AS quantity_sold
        FROM delivered_orders d
        JOIN litvinov_food.order_structure os USING (order_id)
        JOIN litvinov_food.product p USING (product_id)
        GROUP BY d.restaurant_id, p.product_id, p.product_name
    ),

    best_products AS (
        SELECT DISTINCT ON (restaurant_id) restaurant_id, product_name
        FROM product_sales
        ORDER BY restaurant_id, quantity_sold DESC, product_id
    ),

    client_orders AS (
        SELECT d.restaurant_id, c.client_id, c.login, count(*) AS order_count
        FROM delivered_orders d
        JOIN litvinov_food.client c USING (client_id)
        GROUP BY d.restaurant_id, c.client_id, c.login
    ),

    best_clients AS (
        SELECT DISTINCT ON (restaurant_id) restaurant_id, login
        FROM client_orders
        ORDER BY restaurant_id, order_count DESC, client_id
    )

    SELECT r.restaurant_name, bp.product_name, ot.total_amount, ot.avg_amount, bc.login
    FROM litvinov_food.restaurant r
    LEFT JOIN order_totals ot USING (restaurant_id)
    LEFT JOIN best_products bp USING (restaurant_id)
    LEFT JOIN best_clients bc USING (restaurant_id)
    ORDER BY r.restaurant_name;
$$;

CREATE OR REPLACE PROCEDURE litvinov_food.courier_salary()
LANGUAGE plpgsql
SET search_path = litvinov_food, pg_temp
AS $$
DECLARE
    v_month_start timestamp := date_trunc('month', localtimestamp);
BEGIN

    INSERT INTO litvinov_food.courier_pay (
        year,
        month,
        courier_id,
        amount,
        coefficient_used
    )
    SELECT
        extract(year FROM v_month_start)::integer,
        extract(month FROM v_month_start)::integer,
        c.courier_id,
        round( coalesce(s.total_commission, 0) * c.coefficient, 2),
        c.coefficient
    FROM litvinov_food.courier c
    LEFT JOIN (
        SELECT courier_id, sum(commission) AS total_commission
        FROM litvinov_food."order"
        WHERE status = 'доставлен'
			AND order_timestamp >= v_month_start
          	AND order_timestamp < v_month_start + interval '1 month'
        GROUP BY courier_id
    ) s USING (courier_id)

    ON CONFLICT (year, month, courier_id)
    DO NOTHING;

    WITH delivery_counts AS (
        SELECT c.courier_id, count(o.order_id) AS deliveries
        FROM litvinov_food.courier c
        LEFT JOIN litvinov_food."order" o ON o.courier_id = c.courier_id
        	AND o.status = 'доставлен'
           	AND o.order_timestamp >= v_month_start
           	AND o.order_timestamp < v_month_start + interval '1 month'
        WHERE c.status IS DISTINCT FROM 'уволен'
        GROUP BY c.courier_id
    )
    UPDATE litvinov_food.courier c
    SET coefficient = CASE
        WHEN dc.deliveries <= 150 THEN 0.1
        WHEN dc.deliveries <= 250 THEN 0.2
        WHEN dc.deliveries <= 500 THEN 0.3
        ELSE 0.5
    END
    FROM delivery_counts dc
    WHERE c.courier_id = dc.courier_id;

END;
$$;

CREATE OR REPLACE VIEW litvinov_food.how_much_money AS
WITH bounds AS (
    SELECT
        date_trunc('month', min(order_timestamp)) AS first_month,
        date_trunc('month', max(order_timestamp)) AS last_month
    FROM litvinov_food."order"
    WHERE status = 'доставлен'
),

months AS (
    SELECT generate_series(first_month, last_month, interval '1 month') AS month_start
    FROM bounds
    WHERE first_month IS NOT NULL
),

order_totals AS (
    SELECT
        date_trunc('month', order_timestamp) AS month_start,
        sum(order_amount) AS sum_no_commission,
        sum(total_amount) AS sum_with_commission
    FROM litvinov_food."order"
    WHERE status = 'доставлен'
    GROUP BY date_trunc('month', order_timestamp)
),

pay_totals AS (
    SELECT
        make_date(year, month, 1)::timestamp AS month_start,
        sum(amount) AS courier_pay
    FROM litvinov_food.courier_pay
    GROUP BY year, month
),

month_values AS (
    SELECT
        m.month_start,
        coalesce(ot.sum_no_commission, 0) AS sum_no_commission,
        coalesce(ot.sum_with_commission, 0) AS sum_with_commission,
        coalesce(ot.sum_with_commission, 0) - coalesce(ot.sum_no_commission, 0) AS commission,
        coalesce(pt.courier_pay, 0) AS courier_pay
    FROM months m
    LEFT JOIN order_totals ot USING (month_start)
    LEFT JOIN pay_totals pt USING (month_start)
),

lagged AS (
    SELECT *,  coalesce(lag(commission) OVER (ORDER BY month_start),0) AS prev_commission
    FROM month_values
)

SELECT
    to_char(month_start, 'YYYY-MM') AS year_month,
    sum_no_commission,
    sum_with_commission,
    commission,
    prev_commission,
    commission - prev_commission AS commission_diff,
    courier_pay,
    commission - courier_pay AS net_profit
FROM lagged;