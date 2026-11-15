CREATE TABLE litvinov_food.client (
    client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    login varchar(50) NOT NULL UNIQUE  CHECK (trim(login) <> ''),
    password char(32) NOT NULL CHECK (password ~ '^[0-9a-f]{32}$'),
    phone_number char(11) NOT NULL UNIQUE CHECK (phone_number ~ '^7[0-9]{10}$') 
);

CREATE TABLE litvinov_food.address (
    address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    street varchar(150) NOT NULL CHECK (trim(street) <> ''),
    house_number varchar(20) NOT NULL CHECK (trim(house_number) <> ''),
    apartment_office varchar(20) NULL CHECK (apartment_office IS NULL OR trim(apartment_office) <> '')
);

CREATE TABLE litvinov_food.client_address (
    client_id uuid NOT NULL REFERENCES litvinov_food.client(client_id),
    address_id uuid NOT NULL REFERENCES litvinov_food.address(address_id),
    PRIMARY KEY (client_id, address_id)
);

CREATE TABLE litvinov_food.restaurant (
    restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    restaurant_name varchar(100) NOT NULL CHECK (trim(restaurant_name) <> ''),
    address_id uuid NOT NULL UNIQUE REFERENCES litvinov_food.address(address_id),
    description text NOT NULL CHECK (trim(description) <> ''),
    work_start time NOT NULL,
    work_end time NOT NULL,
    company_details text NOT NULL CHECK (trim(company_details) <> ''),
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status litvinov_food.restaurant_status NOT NULL DEFAULT 'активен',
    
    CHECK (work_end > work_start)
);

CREATE TABLE litvinov_food.courier (
    courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    fio varchar(150) NOT NULL CHECK (trim(fio) <> ''),
    phone_number char(11) NOT NULL CHECK (phone_number ~ '^7[0-9]{10}$'),
    status litvinov_food.courier_status NOT NULL DEFAULT 'свободен',
    hire_date date NOT NULL DEFAULT CURRENT_DATE,
    dismissal_date date,
    coefficient numeric(2,1) NOT NULL DEFAULT 0.1 CHECK (coefficient BETWEEN 0.1 AND 0.5),
    
    CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date),
    CHECK (status <> 'уволен' OR dismissal_date IS NOT NULL)
);

CREATE TABLE litvinov_food.product_category (
    product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_category_name varchar(100) NOT NULL CHECK (trim(product_category_name) <> '')
); 

CREATE TABLE litvinov_food.product (
    product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    product_name varchar(100) NOT NULL CHECK (trim(product_name) <> ''),
    product_category_id uuid NOT NULL REFERENCES litvinov_food.product_category(product_category_id),
    price numeric(7,2) NOT NULL CHECK (price >= 0),
    restaurant_id uuid NOT NULL REFERENCES litvinov_food.restaurant(restaurant_id),
    photo_url text CHECK (photo_url IS NULL OR trim(photo_url) <> ''),
    rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
    status litvinov_food.product_status NOT NULL DEFAULT 'доступно',
    description text NOT NULL CHECK (trim(description) <> '')
);

CREATE TABLE litvinov_food.courier_pay (
    year integer NOT NULL CHECK (year BETWEEN 2026 AND 9999), -- вот уберу верхний предел и тут же порадую вас, хотя и так бизнес столько не живёт...
    month integer NOT NULL CHECK (month BETWEEN 1 AND 12),
    courier_id uuid NOT NULL REFERENCES litvinov_food.courier(courier_id),
    amount numeric(8,2) NOT NULL CHECK (amount >= 0),
    coefficient_used numeric(2,1) NOT NULL CHECK (coefficient_used BETWEEN 0.1 AND 0.5),
    
    PRIMARY KEY (year, month, courier_id)
);


CREATE TABLE litvinov_food."order" (
    order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    courier_id uuid NOT NULL REFERENCES litvinov_food.courier(courier_id),
    client_id uuid NOT NULL REFERENCES litvinov_food.client(client_id),
    address_id uuid NOT NULL REFERENCES litvinov_food.address(address_id),
    restaurant_id uuid NOT NULL REFERENCES litvinov_food.restaurant(restaurant_id),
    order_timestamp timestamp NOT NULL DEFAULT LOCALTIMESTAMP,
    delivery_timestamp timestamp,
    order_amount numeric(8,2) NOT NULL CHECK (order_amount >= 0),
    commission numeric(8,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,
    total_amount numeric(9,2) GENERATED ALWAYS AS (round(order_amount + round(order_amount * 0.10, 2), 2)) STORED CHECK (total_amount >= 1000),
    status litvinov_food.order_status NOT NULL DEFAULT 'создан',
    pay_status litvinov_food.order_pay_status NOT NULL DEFAULT 'ожидает',
    description text,
    
    CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
    CHECK ((status = 'доставлен') = (delivery_timestamp IS NOT NULL)),
    FOREIGN KEY (client_id, address_id) REFERENCES litvinov_food.client_address(client_id, address_id),
    UNIQUE (order_id, client_id)
);

CREATE TABLE litvinov_food.order_structure (
    order_id uuid NOT NULL REFERENCES litvinov_food."order"(order_id),
    product_id uuid NOT NULL REFERENCES litvinov_food.product(product_id),
    quantity numeric(6,3) NOT NULL CHECK (quantity > 0),
    price_fixed numeric(7,2) NOT NULL CHECK (price_fixed >= 0),
    PRIMARY KEY (order_id, product_id)
);

CREATE TABLE litvinov_food.review (
    review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    client_id uuid NOT NULL,
    review_timestamp timestamp NOT NULL DEFAULT LOCALTIMESTAMP,
    entity_id uuid NOT NULL,
    entity_type litvinov_food.review_entity_type NOT NULL,
    order_id uuid NOT NULL,
    description text NOT NULL CHECK (trim(description) <> ''),
    photo_url text CHECK (photo_url IS NULL OR trim(photo_url) <> ''),
    rating numeric(2,1) NOT NULL CHECK (rating BETWEEN 1 AND 5),
    FOREIGN KEY (order_id, client_id) REFERENCES litvinov_food."order"(order_id, client_id),
    UNIQUE (order_id, entity_type, entity_id)
);

CREATE TABLE litvinov_food.payment (
    payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
    order_id uuid NOT NULL REFERENCES litvinov_food."order"(order_id),
    type litvinov_food.payment_type NOT NULL,
    amount numeric(9,2) NOT NULL CHECK (amount >= 0),
    transaction_id varchar(100) NOT NULL UNIQUE CHECK (trim(transaction_id) <> ''),
    transaction_timestamp timestamp NOT NULL DEFAULT LOCALTIMESTAMP,
    status litvinov_food.payment_status NOT NULL
);
