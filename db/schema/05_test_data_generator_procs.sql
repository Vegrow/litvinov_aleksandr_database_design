CREATE OR REPLACE PROCEDURE litvinov_food.erase_test_data() LANGUAGE PLPGSQL
SET search_path = litvinov_food, pg_temp AS
$$
BEGIN
    DELETE FROM litvinov_food.review;
	DELETE FROM litvinov_food.payment;
	DELETE FROM litvinov_food.order_structure;
	DELETE FROM litvinov_food."order";
	DELETE FROM litvinov_food.courier_pay;
	DELETE FROM litvinov_food.client_address;
	DELETE FROM litvinov_food.product;
	DELETE FROM litvinov_food.restaurant;
	DELETE FROM litvinov_food.client;
	DELETE FROM litvinov_food.courier;
	DELETE FROM litvinov_food.product_category;
	DELETE FROM litvinov_food.address;
END;
$$;


CREATE OR REPLACE PROCEDURE litvinov_food.insert_test_data(value integer) LANGUAGE PLPGSQL
SET search_path = litvinov_food, pg_temp AS
$$
DECLARE
    i integer;
    j integer;
    v_total bigint;

    v_uuid uuid;
    v_client_num integer;
    v_restaurant_num integer;
    v_product_num integer;
    v_offset integer;
    v_day_num integer;
    v_month_date timestamp;
    v_order_date timestamp;
    v_current_coef numeric(2,1);
    v_next_coef numeric(2,1);
    v_delivery_count integer;
    v_total_commission numeric(8,2);
    v_phone_start bigint := (extract(epoch FROM clock_timestamp()) * 1000000)::bigint % 10000000000;

    v_client_ids uuid[] := ARRAY[]::uuid[];
    v_courier_ids uuid[] := ARRAY[]::uuid[];
    v_restaurant_ids uuid[] := ARRAY[]::uuid[];
    v_category_ids uuid[] := ARRAY[]::uuid[];
    v_address_ids uuid[] := ARRAY[]::uuid[];
    v_product_ids uuid[] := ARRAY[]::uuid[];

    v_rest_status litvinov_food.restaurant_status[] := enum_range(NULL::litvinov_food.restaurant_status);
    v_prod_status litvinov_food.product_status[] := enum_range(NULL::litvinov_food.product_status);
    v_cour_status litvinov_food.courier_status[] := enum_range(NULL::litvinov_food.courier_status);
    v_ord_status litvinov_food.order_status[] := enum_range(NULL::litvinov_food.order_status);
    v_ord_pay_status litvinov_food.order_pay_status[] := enum_range(NULL::litvinov_food.order_pay_status);
    v_pay_status litvinov_food.payment_status[] := enum_range(NULL::litvinov_food.payment_status);
    v_pay_types litvinov_food.payment_type[] := enum_range(NULL::litvinov_food.payment_type);
    v_review_entities litvinov_food.review_entity_type[] := enum_range(NULL::litvinov_food.review_entity_type);

BEGIN
    IF value < 1 OR value IS NULL THEN
        RAISE EXCEPTION 'Введите value больше нуля';
    END IF;

    v_total := value * 5;

    FOR i IN 1..v_total LOOP
        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food.address
            (address_id, street, house_number, apartment_office)
        VALUES (
            v_uuid,
            'Улица ' || v_uuid::text,
            (i % 300 + 1)::text,
            CASE WHEN i % 4 = 0 THEN NULL ELSE (i % 200 + 1)::text END
        );

        v_address_ids := array_append(v_address_ids, v_uuid);
    END LOOP;

    FOR i IN 1..value LOOP
        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food.restaurant
            (restaurant_id, restaurant_name, address_id, description,
             work_start, work_end, company_details, rating, status)
        VALUES (
            v_uuid,
            'Ресторан ' || v_uuid::text,
            v_address_ids[i],
            'Тестовое описание ресторана ' || i,
            time '09:00',
            time '22:00',
            'Тестовые реквизиты ' || v_uuid::text,
            NULL,
            v_rest_status[1]
        );

        v_restaurant_ids := array_append(v_restaurant_ids, v_uuid);
    END LOOP;

    FOR i IN 1..value LOOP
        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food.client
            (client_id, login, password, phone_number)
        VALUES (
            v_uuid,
            'client_' || v_uuid::text,
            md5(random()::text),
            lpad((70000000000::bigint + (v_phone_start + i) % 10000000000)::text, 11, '0')
        );

        v_client_ids := array_append(v_client_ids, v_uuid);
        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food.courier
            (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
        VALUES (
            v_uuid,
            'Курьер ' || v_uuid::text,
            lpad((70000000000::bigint + (v_phone_start + 100000 + i) % 10000000000)::text, 11, '0'),
            CASE
                WHEN value > 1 AND i = value THEN v_cour_status[4]
                ELSE v_cour_status[1]
            END,
            current_date - 180,
            CASE
                WHEN value > 1 AND i = value THEN current_date - 1
                ELSE NULL
            END,
            0.1
        );

        v_courier_ids := array_append(v_courier_ids, v_uuid);
        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food.product_category
            (product_category_id, product_category_name)
        VALUES (
            v_uuid,
            'Категория ' || v_uuid::text
        );

        v_category_ids := array_append(v_category_ids, v_uuid);
    END LOOP;


    FOR i IN 1..(value * 4) LOOP
        v_client_num := (i - 1) % value + 1;

        INSERT INTO litvinov_food.client_address(client_id, address_id)
        VALUES (
            v_client_ids[v_client_num],
            v_address_ids[value + i]
        );
    END LOOP;

    FOR i IN 1..v_total LOOP
        v_restaurant_num := (i - 1) / 5 + 1;
        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food.product
            (product_id, product_name, product_category_id, price,
             restaurant_id, photo_url, rating, status, description)
        VALUES (
            v_uuid,
            'Блюдо ' || v_uuid::text,
            v_category_ids[(i - 1) % value + 1],
            1000 + (i % 10) * 100,
            v_restaurant_ids[v_restaurant_num],
            CASE
                WHEN i % 3 = 0 THEN NULL
                ELSE 'https://foodexpress.ru/img/' || v_uuid::text || '.jpg'
            END,
            NULL,
            v_prod_status[1],
            'Тестовое описание блюда ' || i
        );

        v_product_ids := array_append(v_product_ids, v_uuid);
    END LOOP;

    FOR i IN 1..v_total LOOP
        v_client_num := (i - 1) % value + 1;
        v_restaurant_num := ((i - 1) / 5) % value + 1;
        v_product_num := (v_restaurant_num - 1) * 5 + (i - 1) % 5 + 1;

        v_offset := (i - 1) % 6;
        v_month_date := date_trunc('month', localtimestamp)
                        - (5 - v_offset) * interval '1 month';

        IF v_offset = 5 THEN
            v_day_num := least(1 + i % 20, extract(day FROM current_date)::integer);
        ELSE
            v_day_num := 1 + i % 20;
        END IF;

        v_order_date := v_month_date
                        + (v_day_num - 1) * interval '1 day'
                        + interval '10 hours';

        IF v_offset = 5 THEN
            v_order_date := greatest(
                v_month_date,
                least(v_order_date, localtimestamp - interval '1 hour')
            );
        END IF;

        v_order_date := greatest(
            v_order_date,
            localtimestamp - interval '180 days'
        );

        v_uuid := exts.uuid_generate_v4();

        INSERT INTO litvinov_food."order"
            (order_id, courier_id, client_id, address_id, restaurant_id,
             order_timestamp, delivery_timestamp, order_amount,
             status, pay_status, description)
        VALUES (
            v_uuid,
            v_courier_ids[v_client_num],
            v_client_ids[v_client_num],
            v_address_ids[value + v_client_num],
            v_restaurant_ids[v_restaurant_num],
            v_order_date,
            v_order_date + interval '30 minutes',
            (
			 SELECT price
             FROM litvinov_food.product
             WHERE product_id = v_product_ids[v_product_num]
			),
            v_ord_status[array_position(v_ord_status, 'доставлен'::litvinov_food.order_status)],
            v_ord_pay_status[array_position(v_ord_pay_status, 'ожидает'::litvinov_food.order_pay_status)],
            'Тестовый заказ ' || i
        );

        INSERT INTO litvinov_food.order_structure
            (order_id, product_id, quantity, price_fixed)
        SELECT
            v_uuid,
            p.product_id,
            1,
            p.price
        FROM litvinov_food.product p
        WHERE p.product_id = v_product_ids[v_product_num];

        INSERT INTO litvinov_food.payment
            (payment_id, order_id, type, amount, transaction_id, transaction_timestamp, status)
        SELECT
            exts.uuid_generate_v4(),
            v_uuid,
            v_pay_types[1],
            o.total_amount,
            'test-' || exts.uuid_generate_v4()::text,
            v_order_date,
            v_pay_status[array_position(v_pay_status, 'успех'::litvinov_food.payment_status)]
        FROM litvinov_food."order" o
        WHERE o.order_id = v_uuid;

        INSERT INTO litvinov_food.review
            (review_id, client_id, review_timestamp, entity_id, entity_type,
             order_id, description, photo_url, rating)
        VALUES (
            exts.uuid_generate_v4(),
            v_client_ids[v_client_num],
            v_order_date + interval '1 hour',
            CASE v_review_entities[(i - 1) % 3 + 1]
                WHEN 'блюдо' THEN v_product_ids[v_product_num]
                WHEN 'ресторан' THEN v_restaurant_ids[v_restaurant_num]
                ELSE v_uuid
            END,
            v_review_entities[(i - 1) % 3 + 1],
            v_uuid,
            'Тестовый отзыв ' || i,
            CASE
                WHEN i % 4 = 0 THEN NULL
                ELSE 'https://foodexpress.ru/review/' || v_uuid::text || '.jpg'
            END,
            (i % 5) + 1
        );
    END LOOP;

    FOR i IN 1..value LOOP
        v_current_coef := 0.1;

        FOR j IN REVERSE 5..0 LOOP
            v_month_date := date_trunc('month', localtimestamp) - j * interval '1 month';

            SELECT
                count(*)::integer,
                coalesce(sum(commission), 0)
            INTO
                v_delivery_count,
                v_total_commission
            FROM litvinov_food."order"
            WHERE courier_id = v_courier_ids[i]
              AND status = 'доставлен'
              AND date_trunc('month', order_timestamp) = v_month_date;

            INSERT INTO litvinov_food.courier_pay
                (year, month, courier_id, amount, coefficient_used)
            VALUES (
                extract(year FROM v_month_date)::integer,
                extract(month FROM v_month_date)::integer,
                v_courier_ids[i],
                round(v_total_commission * v_current_coef, 2),
                v_current_coef
            )
            ON CONFLICT (year, month, courier_id)
            DO UPDATE SET
                amount = EXCLUDED.amount,
                coefficient_used = EXCLUDED.coefficient_used;

            v_next_coef := CASE
                WHEN v_delivery_count <= 150 THEN 0.1
                WHEN v_delivery_count <= 250 THEN 0.2
                WHEN v_delivery_count <= 500 THEN 0.3
                ELSE 0.5
            END;

            v_current_coef := v_next_coef;
        END LOOP;

        UPDATE litvinov_food.courier
        SET coefficient = v_current_coef
        WHERE courier_id = v_courier_ids[i]
          AND status <> 'уволен';
    END LOOP;
END;
$$;