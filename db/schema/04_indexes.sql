CREATE UNIQUE INDEX payment_only_one_success_per_order
ON litvinov_food.payment(order_id) WHERE status = 'успех';

CREATE INDEX idx_order_structure_product
ON litvinov_food.order_structure(product_id);

CREATE INDEX idx_payment_order
ON litvinov_food.payment(order_id);

CREATE INDEX idx_review_entity
ON litvinov_food.review(entity_type, entity_id);

CREATE INDEX idx_client_address_address
ON litvinov_food.client_address(address_id);

CREATE INDEX idx_order_courier
ON litvinov_food."order"(courier_id);

CREATE INDEX idx_order_restaurant
ON litvinov_food."order"(restaurant_id);

CREATE INDEX idx_order_client
ON litvinov_food."order"(client_id);

CREATE INDEX idx_order_address
ON litvinov_food."order"(address_id);

CREATE INDEX idx_product_restaurant
ON litvinov_food.product(restaurant_id);

CREATE INDEX idx_product_category
ON litvinov_food.product(product_category_id);

CREATE INDEX idx_courier_pay_courier
ON litvinov_food.courier_pay(courier_id);
