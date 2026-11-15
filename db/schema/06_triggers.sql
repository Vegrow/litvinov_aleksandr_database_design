SET search_path = litvinov_food, pg_temp;

CREATE OR REPLACE FUNCTION litvinov_food.validate_review()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = litvinov_food, pg_temp
AS $$
DECLARE
    v_order_restaurant uuid;
BEGIN
    SELECT restaurant_id INTO v_order_restaurant
    FROM litvinov_food."order" WHERE order_id = NEW.order_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Заказ не существует';
    END IF;

    CASE NEW.entity_type
        WHEN 'блюдо' THEN
            IF NOT EXISTS (
                SELECT 1 FROM litvinov_food.order_structure os
                WHERE os.order_id = NEW.order_id AND os.product_id = NEW.entity_id
            ) THEN
                RAISE EXCEPTION 'Блюдо должно входить в заказ клиента';
            END IF;
        WHEN 'ресторан' THEN
            IF NEW.entity_id <> v_order_restaurant THEN
                RAISE EXCEPTION 'Ресторан должен совпадать с рестораном заказа';
            END IF;
        WHEN 'заказ' THEN
            IF NEW.entity_id <> NEW.order_id THEN
                RAISE EXCEPTION 'Для отзыва на заказ entity_id должен совпадать с order_id';
            END IF;
    END CASE;
    RETURN NEW;
END;
$$;

CREATE TRIGGER review_target_check
BEFORE INSERT OR UPDATE OF client_id, order_id, entity_id, entity_type ON litvinov_food.review
FOR EACH ROW EXECUTE FUNCTION litvinov_food.validate_review();


CREATE OR REPLACE FUNCTION litvinov_food.refresh_review_rating(
    p_entity_type litvinov_food.review_entity_type,
    p_entity_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_rating numeric(3,2);
BEGIN
    IF p_entity_type NOT IN ('блюдо', 'ресторан') THEN
        RETURN;
    END IF;

    SELECT round(avg(rating), 2)
    INTO v_rating
    FROM litvinov_food.review
    WHERE entity_type = p_entity_type
      	AND entity_id = p_entity_id;

    IF p_entity_type = 'блюдо' THEN
        UPDATE litvinov_food.product
        SET rating = v_rating
        WHERE product_id = p_entity_id
  			AND rating IS DISTINCT FROM v_rating;
    ELSE
        UPDATE litvinov_food.restaurant
        SET rating = v_rating
        WHERE restaurant_id = p_entity_id
          	AND rating IS DISTINCT FROM v_rating;

    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION litvinov_food.rating_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM litvinov_food.refresh_review_rating(
            NEW.entity_type,
            NEW.entity_id
        );
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM litvinov_food.refresh_review_rating(
            OLD.entity_type,
            OLD.entity_id
        );
    ELSE
        IF (OLD.entity_type, OLD.entity_id)
           IS DISTINCT FROM
           (NEW.entity_type, NEW.entity_id) THEN
            PERFORM litvinov_food.refresh_review_rating(
                OLD.entity_type,
                OLD.entity_id
            );
        END IF;
        PERFORM litvinov_food.refresh_review_rating(
            NEW.entity_type,
            NEW.entity_id
        );
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS review_rating_change ON litvinov_food.review;
CREATE TRIGGER review_rating_change
AFTER INSERT OR DELETE OR UPDATE OF rating, entity_type, entity_id
ON litvinov_food.review
FOR EACH ROW
EXECUTE FUNCTION litvinov_food.rating_change();

CREATE OR REPLACE FUNCTION litvinov_food.validate_product_in_order()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM litvinov_food."order" o
        JOIN litvinov_food.product p ON p.product_id = NEW.product_id
     	AND p.restaurant_id = o.restaurant_id
        WHERE o.order_id = NEW.order_id
    ) THEN
        RAISE EXCEPTION 'Блюдо должно принадлежать ресторану заказа';
    END IF;

    RETURN NEW;
END;
$$;


DROP TRIGGER IF EXISTS order_product_restaurant_check ON litvinov_food.order_structure;
CREATE TRIGGER order_product_restaurant_check
BEFORE INSERT OR UPDATE OF order_id, product_id ON litvinov_food.order_structure
FOR EACH ROW EXECUTE FUNCTION litvinov_food.validate_product_in_order();

CREATE OR REPLACE FUNCTION litvinov_food.prevent_restaurant_change_with_orders()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.restaurant_id IS NOT DISTINCT FROM OLD.restaurant_id THEN
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'product' THEN
        IF EXISTS (
            SELECT 1
            FROM litvinov_food.order_structure os
            JOIN litvinov_food."order" o ON o.order_id = os.order_id
            WHERE os.product_id = OLD.product_id
              	AND o.restaurant_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION 'Попытка перенести блюда, входящее в заказы другого ресторана';
        END IF;

    ELSIF TG_TABLE_NAME = 'order' THEN
        IF EXISTS (
            SELECT 1
            FROM litvinov_food.order_structure os
            JOIN litvinov_food.product p ON p.product_id = os.product_id
            WHERE os.order_id = OLD.order_id 
				AND p.restaurant_id <> NEW.restaurant_id
        ) THEN
            RAISE EXCEPTION 'Ресторан заказа не совпадает с ресторанами всех блюд';
        END IF;

    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS product_restaurant_change_check ON litvinov_food.product;
CREATE TRIGGER product_restaurant_change_check
BEFORE UPDATE OF restaurant_id ON litvinov_food.product
FOR EACH ROW EXECUTE FUNCTION litvinov_food.prevent_restaurant_change_with_orders();

DROP TRIGGER IF EXISTS order_restaurant_change_check ON litvinov_food."order";
CREATE TRIGGER order_restaurant_change_check
BEFORE UPDATE OF restaurant_id ON litvinov_food."order"
FOR EACH ROW EXECUTE FUNCTION litvinov_food.prevent_restaurant_change_with_orders();

CREATE OR REPLACE FUNCTION litvinov_food.assert_order_amount()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'order_structure'
       AND TG_OP = 'UPDATE'
       AND OLD.order_id IS DISTINCT FROM NEW.order_id THEN

        PERFORM litvinov_food.assert_order_amount_for(OLD.order_id);
    END IF;

    IF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    PERFORM litvinov_food.assert_order_amount_for(v_order_id);

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION litvinov_food.assert_order_amount_for(
    p_order_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_expected numeric(10,2);
    v_actual numeric(10,2);
    v_count bigint;
BEGIN
    SELECT order_amount
    INTO v_actual
    FROM litvinov_food."order"
    WHERE order_id = p_order_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT
        count(*),
        round(coalesce(sum(quantity * price_fixed), 0), 2)
    INTO v_count, v_expected
    FROM litvinov_food.order_structure
    WHERE order_id = p_order_id;

    IF v_count = 0 OR v_expected <> v_actual THEN
        RAISE EXCEPTION 'Сумма позиций заказа (%) должна совпадать с order_amount (%)',  v_expected, v_actual;
    END IF;
END;
$$;

CREATE CONSTRAINT TRIGGER order_amount_check_order
AFTER INSERT OR UPDATE ON litvinov_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION litvinov_food.assert_order_amount();
CREATE CONSTRAINT TRIGGER order_amount_check_lines
AFTER INSERT OR UPDATE OR DELETE ON litvinov_food.order_structure
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION litvinov_food.assert_order_amount();

CREATE OR REPLACE FUNCTION litvinov_food.assert_payment_amounts()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = litvinov_food, pg_temp
AS $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM litvinov_food.payment p
        JOIN litvinov_food."order" o USING (order_id)
        WHERE o.order_id = NEW.order_id AND p.amount <> o.total_amount
    ) THEN
        RAISE EXCEPTION 'Сумма каждой попытки оплаты должна совпадать с итогом заказа';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER order_payment_amount_check
AFTER UPDATE ON litvinov_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION litvinov_food.assert_payment_amounts();

CREATE OR REPLACE FUNCTION litvinov_food.validate_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = litvinov_food, pg_temp
AS $$
DECLARE
    v_total numeric(14,2);
BEGIN
    SELECT total_amount INTO v_total FROM litvinov_food."order" WHERE order_id = NEW.order_id;
    IF v_total IS NULL OR NEW.amount <> v_total THEN
        RAISE EXCEPTION 'Сумма платежа должна совпадать с общей суммой заказа';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER payment_amount_check
BEFORE INSERT OR UPDATE OF order_id, amount ON litvinov_food.payment
FOR EACH ROW EXECUTE FUNCTION litvinov_food.validate_payment();

CREATE OR REPLACE FUNCTION litvinov_food.validate_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = litvinov_food, pg_temp
AS $$
DECLARE
    v_expected litvinov_food.order_pay_status;
BEGIN
    SELECT CASE
        WHEN bool_or(status = 'успех') THEN 'оплачен'::litvinov_food.order_pay_status
        WHEN bool_or(status = 'в_обработке') THEN 'ожидает'::litvinov_food.order_pay_status
        WHEN count(*) > 0 THEN 'ошибка'::litvinov_food.order_pay_status
        ELSE 'ожидает'::litvinov_food.order_pay_status
    END INTO v_expected
    FROM litvinov_food.payment WHERE order_id = NEW.order_id;
    IF NEW.pay_status IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'pay_status вычисляется по попыткам оплаты';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_pay_status_check
BEFORE UPDATE OF pay_status ON litvinov_food."order"
FOR EACH ROW EXECUTE FUNCTION litvinov_food.validate_order_pay_status();

CREATE OR REPLACE FUNCTION litvinov_food.sync_order_pay_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id uuid;
    v_old_order_id uuid;
    v_status litvinov_food.order_pay_status;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    IF TG_OP = 'UPDATE'
       AND OLD.order_id IS DISTINCT FROM NEW.order_id THEN
        v_old_order_id := OLD.order_id;
    END IF;

    SELECT CASE
        WHEN bool_or(status = 'успех') THEN 'оплачен'::litvinov_food.order_pay_status
        WHEN bool_or(status = 'в_обработке') THEN 'ожидает'::litvinov_food.order_pay_status
        WHEN count(*) > 0 THEN 'ошибка'::litvinov_food.order_pay_status
        ELSE 'ожидает'::litvinov_food.order_pay_status
    END
    INTO v_status
    FROM litvinov_food.payment
    WHERE order_id = v_order_id;

    UPDATE litvinov_food."order"
    SET pay_status = v_status
    WHERE order_id = v_order_id AND pay_status IS DISTINCT FROM v_status;

    IF v_old_order_id IS NOT NULL THEN

        SELECT CASE
            WHEN bool_or(status = 'успех') THEN 'оплачен'::litvinov_food.order_pay_status
            WHEN bool_or(status = 'в_обработке') THEN 'ожидает'::litvinov_food.order_pay_status
            WHEN count(*) > 0 THEN 'ошибка'::litvinov_food.order_pay_status
            ELSE 'ожидает'::litvinov_food.order_pay_status
        END
        INTO v_status
        FROM litvinov_food.payment
        WHERE order_id = v_old_order_id;

        UPDATE litvinov_food."order"
        SET pay_status = v_status
        WHERE order_id = v_old_order_id
          	AND pay_status IS DISTINCT FROM v_status;

    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER payment_order_status
AFTER INSERT OR UPDATE OR DELETE ON litvinov_food.payment
FOR EACH ROW EXECUTE FUNCTION litvinov_food.sync_order_pay_status();

CREATE OR REPLACE FUNCTION litvinov_food.assert_only_one_successful_payment()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = litvinov_food, pg_temp
AS $$
DECLARE
    v_order_id uuid := CASE WHEN TG_TABLE_NAME = 'order' THEN NEW.order_id
                            WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    v_success_count bigint;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM litvinov_food."order" WHERE order_id = v_order_id) THEN
        RETURN NULL;
    END IF;
    SELECT count(*) INTO v_success_count FROM litvinov_food.payment
    WHERE order_id = v_order_id AND status = 'успех';
    IF v_success_count <> 1 THEN
        RAISE EXCEPTION 'У заказа должна быть ровно одна успешная попытка оплаты';
    END IF;
    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER order_payment_success_check
AFTER INSERT OR UPDATE ON litvinov_food."order"
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION litvinov_food.assert_only_one_successful_payment();

CREATE CONSTRAINT TRIGGER payment_success_check
AFTER INSERT OR UPDATE OR DELETE ON litvinov_food.payment
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION litvinov_food.assert_only_one_successful_payment();