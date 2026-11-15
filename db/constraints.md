# Обоснование ограничений

Все идентификаторы в таблицах имеют тип uuid и генерируются автоматически с промощью функции exts.uuid_generate_v4() (BR-11.1, BR-13.3).
Схема exts не пересоздается.
Таблица заказов названа order и в скриптах пишется в кавычках, чтобы не менять название из erd.md (BR-13.1).

---

## Enum-типы

| Тип | Значения | BR |
|---|---|---|
| restaurant_status | активен, неактивен | BR-4.3 |
| product_status | доступно, нет_в_наличии, архив | BR-5.5 |
| courier_status | свободен, занят, на_доставке, уволен | BR-6.2 |
| order_status | создан, готовится, в_доставке, доставлен, отменён | BR-7.7 |
| order_pay_status | ожидает, оплачен, ошибка | BR-7.9 |
| payment_status | успех, ошибка, в_обработке | BR-8.2 |
| payment_type | карта, наличные, безнал | BR-8.2 |
| review_entity_type | блюдо, ресторан, заказ | BR-9.1 |

---

## Ловушки

### Ловушка 1: `payment` - неполная сущность

**Какие атрибуты добавил в `payment` и почему** (BR-8.2):
В erd.md у сущности payment были указаны только payment_id и order_id.
Для выполнения (BR-8.1–BR-8.7) в таблицу payment добавлены следующие атрибуты:
payment_type - для фиксации способа оплаты (карта/наличные/безнал), amount - сумма платежа, transaction_id -  внешний идентификатор финансовой транзакции от провайдера(BR-1.7, BR-8.2, BR-8.3), payment_timestamp - дата и время и status - статус попытки.
Так же был добавлен триггер check_payment_amount, который проверяет, что сумма равна order.total_amount (BR-8.4).

**Где хранится тип оплаты - `payment` или `order`** (BR-8.6):
Хранится в payment, т.к. в соотвествии с BR-8.6 тип относится к попытке оплаты, а не к заказу.

### Ловушка 2: `order.address_id` - принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**
Был добавлен составной внешний ключ в таблице order - `FOREIGN KEY (client_id, address_id) REFERENCES client_address(client_id, address_id)`.
Данный ключ гарантирует, что заказ оформляется только на адрес данного клиента (BR-7.4)

### Ловушка 3: `order_structure` - один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**
Был добавлен триггер order_product_restaurant_check, срабатывающий на вставку или обновление таблицы order_structure.
В нём проверяется соответствие restaurant_id у блюда и заказа.

### Ловушка 4: `review` - полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**
Реализовано следующим образом:  полиморфная связь (entity_type, entity_id) из docs/erd.md + составной FK для проверки автора заказа + триггер для проверки (rating_change).
FK тут не подходит, т.к. entity_id ссылается на три разные таблицы (product, restaurant и order).
Был создан составной внешний ключ `FOREIGN KEY (order_id, client_id) REFERENCES "order"(order_id, client_id)`, это гарантирует, что отзыв может оставить только тот клиент, который оформил заказ(BR-9.2).
Был добавлен уникальный ключ `UNIQUE (order_id, entity_type, entity_id)` для того, чтобы в одном заказе нельзя было добавть несколько отзывов на одну сущность (BR-9.5).

---

## CHECK-ограничения

Для текстовых полей, значения которых которые не должны быть null, были добавлены проверки вида CHECK (trim("имя_поля") <> ''), чтобы не дать возможности оставить эти поля фактически пустыми (BR-11.6) 

| Таблица | Столбец | Условие | BR | Обоснование |
| --- | --- | --- | --- | --- |
| `address` | `street` | `trim(street) <> ''` | BR-3.1, BR-11.6 | Непустая строка |
| `address` | `house_number` | `trim(house_number) <> ''` | BR-3.1, BR-11.6 | Непустая строка |
| `address` | `apartment_office` | `apartment_office IS NULL OR trim(apartment_office) <> ''` | BR-3.1, BR-11.6 | не может быть пустой строкой |
| `client` | `login` | `trim(login) <> ''` | BR-2.1, BR-2.6, BR-11.6 | Непустая строка |
| `client` | `password` | `password ~ '^[0-9a-f]{32}$'` | BR-2.3, BR-11.6 | MD5 |
| `client` | `phone_number` | `phone_number ~ '^7[0-9]{10}$'` | BR-2.1, BR-2.2, BR-11.6 | Телефон в формате `7XXXXXXXXXX` |
| `courier` | `fio` | `trim(fio) <> ''` | BR-6.1, BR-11.6 | Непустая строка |
| `courier` | `phone_number` | `phone_number ~ '^7[0-9]{10}$'` | BR-6.1, BR-11.6 | Телефон в формате `7XXXXXXXXXX` |
| `courier` | `coefficient` | `coefficient BETWEEN 0.1 AND 0.5` | BR-6.4 | Коэффициент в диапазоне `0.1`–`0.5`|
| `courier` | `dismissal_date`, `hire_date` | `dismissal_date IS NULL OR dismissal_date >= hire_date` | BR-6.1, BR-6.3, BR-11.6 | Нельзя уволить раньше найма |
| `courier` | `status`, `dismissal_date` | `(status = 'уволен' AND dismissal_date IS NOT NULL) OR (status <> 'уволен' AND dismissal_date IS NULL)` | BR-6.2, BR-6.3, BR-11.3, BR-11.6 | Обязательноя дата у уволенного курьера , у работающего должна отсутствовать |
| `courier_pay` | `month` | `month BETWEEN 1 AND 12` | BR-10.1, BR-10.2 | Месяц от `1` до `12` |
| `courier_pay` | `amount` | `amount >= 0` | BR-10.4 | Сумма выплаты курьеру неотрицательна  |
| `courier_pay` | `coefficient_used` | `coefficient_used BETWEEN 0.1 AND 0.5` | BR-6.4, BR-10.2 | Коэффициент в диапазоне `0.1`–`0.5` |
| `"order"` | `description` | `trim(description) <> ''` | BR-11.3, BR-11.6 | Непустая строка |
| `"order"` | `order_amount` | `order_amount > 0` | BR-1.8, BR-7.10, BR-7.11 | Сумма стоимости блюд положительна. Исторический снимок суммы, не пересчитывается при смене цен блюд |
| `"order"` | `commission`, `order_amount` | `commission = ROUND(order_amount * 0.10, 2)` | BR-1.4, BR-7.10 | Комиссия - 10% от стоимости блюд |
| `"order"` | `total_amount`, `order_amount`, `commission` | `total_amount = order_amount + commission` | BR-1.5, BR-7.10 | Полная сумма |
| `"order"` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | Минимальная сумма заказа 1000 |
| `"order"` | `delivery_timestamp`, `order_timestamp` | `delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp` | BR-7.13 | Доставка не раньше создания заказа |
| `"order"` | `status`, `delivery_timestamp` | `(status = 'доставлен' AND delivery_timestamp IS NOT NULL) OR (status <> 'доставлен' AND delivery_timestamp IS NULL)` | BR-7.12, BR-11.3, BR-11.6 | Время доставки заполнено только тогда, когда статус `'доставлен'`.  |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | Положительное количество |
| `payment` | `amount` | `amount >= 1000` | BR-1.8, BR-7.11, BR-8.4 | Сумма оплаты равна общей сумме заказа,  не менее 1000 |
| `payment` | `transaction_id` | `trim(transaction_id) <> ''` | BR-8.2, BR-8.3, BR-11.6 | Непустая строка |
| `product` | `product_name` | `trim(product_name) <> ''` | BR-5.2, BR-11.6 | Непустая строка |
| `product` | `description` | `trim(description) <> ''` | BR-5.2, BR-11.6 | Непустая строка |
| `product` | `photo_url` | `photo_url IS NULL OR trim(photo_url) <> ''` | BR-5.2, BR-5.6, BR-11.6 | Непустая ссылка есть есть |
| `product` | `price` | `price >= 0` | BR-5.3 | Цена неотрицательна по BR-5.3. |
| `product` | `rating` | `rating BETWEEN 0 AND 5` | BR-5.4 | Рейтинг от `0` до `5` по BR-5.4. |
| `product_category` | `product_category_name` | `trim(product_category_name) <> ''` | BR-5.7, BR-11.6 | Непустая строка |
| `restaurant` | `restaurant_name` | `trim(restaurant_name) <> ''` | BR-4.1, BR-11.6 | Непустая строка |
| `restaurant` | `description` | `trim(description) <> ''` | BR-4.1, BR-11.6 | Непустая строка |
| `restaurant` | `company_details` | `trim(company_details) <> ''` | BR-4.1, BR-11.6 | Непустая строка |
| `restaurant` | `work_start`, `work_end` | `work_end > work_start` | BR-4.4 | Закрытие позже открытия |
| `restaurant` | `rating` | `rating BETWEEN 0 AND 5` | BR-4.2 | Рейтинг от `0` до `5`|
| `review` | `description` | `trim(description) <> ''` | BR-9.3, BR-11.6 | Непустая строка |
| `review` | `photo_url` | `photo_url IS NULL OR trim(photo_url) <> ''` | BR-9.3, BR-11.6 | Непустая ссылка на фото, если есть |
| `review` | `rating` | `rating BETWEEN 1 AND 5` | BR-9.4 | Оценка от 1 до 5 |




---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | Логин клиента уникален |
| `client` | `phone_number` | BR-2.2 | Телефон клиента уникален |
| `client_address` | `(client_id, address_id)` (PK) | BR-2.5 | У клиента не может быть один и тот же адрес дважны |
| `courier_pay` | `(year, month, courier_id)` (PK) | BR-10.3 | Одна зп в месяц |
| `"order"` | `(order_id, client_id)` | BR-9.2 | Отзыв может оставить только тот, кто заказал |
| `order_structure` | `(order_id, product_id)` (PK) | BR-7.16 | Блюдо в заказе не повторяется |
| `payment` | `transaction_id` | BR-8.3 | Внешний ID транзакции уникален |
| `payment` | `order_id WHERE status = 'успех'` | BR-8.1 | Всегда лишь одна успешная попытка оплаты заказа |
| `restaurant` | `address_id` | BR-3.3 | Два ресторана не могут иметь один адрес |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | Не более одного отзыва на сущность за заказ |

---

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` | `client(client_id)` | BR-2.4 | Связь с клиентом |
| `client_address` | `address_id` | `address(address_id)` | BR-2.4 | Связь с адресом |
| `restaurant` | `address_id` | `address(address_id)` | BR-3.3 | У ресторана должен быть адрес |
| `product` | `restaurant_id` | `restaurant(restaurant_id)` | BR-5.1 | Блюдо принадлежит ресторану |
| `product` | `product_category_id` | `product_category(product_category_id)` | BR-5.1 | Блюдо входит в категорию |
| `courier_pay` | `courier_id` | `courier(courier_id)` | BR-10.2 | Выплата относится к курьеру |
| `"order"` | `client_id` | `client(client_id)` | BR-7.1, BR-7.2 | Заказ оформляет клиент |
| `"order"` | `restaurant_id` | `restaurant(restaurant_id)` | BR-7.2 | Заказ привязан к ресторану |
| `"order"` | `courier_id` | `courier(courier_id)` | BR-7.5 | Доставку выполняет курьер |
| `"order"` | `address_id` | `address(address_id)` | BR-7.4 | Заказ доставляется по адресу |
| `"order"` | `(client_id, address_id)` | `client_address(client_id, address_id)` | BR-7.4 | Адрес доставки соответсвтует адресу клиента |
| `order_structure` | `order_id` | `"order"(order_id)` | BR-7.14 | Позиция относится к заказу |
| `order_structure` | `product_id` | `product(product_id)` | BR-7.14 | Позиция ссылается на блюдо |
| `payment` | `order_id` | `"order"(order_id)` | BR-8.1 | Попытка оплаты привязана к заказу |
| `review` | `client_id` | `client(client_id)` | BR-9.1 | Отзыв оставляет клиент |
| `review` | `order_id` | `"order"(order_id)` | BR-9.2 | Отзыв привязан к заказу |
| `review` | `(order_id, client_id)` | `"order"(order_id, client_id)` | BR-9.2 | Нельзя оставить отзыв на чужой заказ |

---

## NOT NULL (только бизнес-обязательные)

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `"order"` | `courier_id` | BR-1.3, BR-7.5 | Курьер обязателен |
| `"order"` | `address_id` | BR-1.3, BR-7.4 | Адрес доставки обязателен |
| `order_structure` | `restaurant_id` | BR-7.3 | Ресторан позиции обязателен |
| `payment` | `payment_type`, `amount`, `transaction_id`, `payment_timestamp`, `status` | BR-8.2, BR-8.3, BR-8.6 | Все атрибуты попытки оплаты (способ, сумма, идентификатор транзакции, время, статус) обязательны |
| `product`, `review` | `description` | BR-4.1, BR-4.5, BR-5.2, BR-9.3, BR-11.3 | В соотвествии с BR-11.3 всё, кроме разрешённых исключений, обязательно |
| `restaurant` | `company_details` | BR-4.1, BR-4.5 | У ресторана должны быть указаны реквизиты |


---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2 | Может быть частный дом |
| `courier` | `dismissal_date` | BR-6.3 | У работающего курьера не может быть даты увольнения. |
| `"order"` | `delivery_timestamp` | BR-7.12 | Пока не доставлен - время доставки пустое |
| `"order"` | `description` | BR-11.6 | Хоть и сказано косвенно, что обязально, но логически может быть пустым |
| `restaurant` | `rating` | BR-9.6, BR-9.7 | Если нет отзывывов, то нет и рейтинга |
| `review` | `photo_url` | BR-9.3 | Фотография в отзыве необязательна. |
| `product` | `photo_url` | BR-5.6 | Фотография блюда необязательна |
| `product` | `rating` | BR-9.6, BR-9.7 | Если нет отзывывов, то нет и рейтинга |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| Таблицы с UUID PK | `*_id` | `DEFAULT exts.uuid_generate_v4()` | Генерация UUID на сервере (BR-11.1). |
| `courier` | `coefficient` | `DEFAULT 0.1` | Начальный коэффициент 0.1 (BR-6.5). |
| `courier` | `status` | `DEFAULT 'свободен'` | Новый курьер по дефолту свободен |
| `"order"` | `order_timestamp` | `localtimestamp` | фиксируем время создания заказа |
| `"order"` | `status` | `DEFAULT 'создан'` | Начальное состояние заказа |
| `"order"` | `pay_status` | `DEFAULT 'ожидает'` | Начальное состояние платежа |
| `"order"` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | Комиссия всегда 10% от суммы (BR-1.4, BR-7.10) |
| `"order"` | `total_amount` | `GENERATED ALWAYS AS (round(order_amount + round(order_amount * 0.10, 2), 2)) STORED` | Общая сумма равна сумме блюд + комиссия (BR-7.10) |
| `payment` | `payment_timestamp` | `localtimestamp` | Фиксация времени транзакции (BR-8.2, BR-9.3, BR-11.2) |
| `product` | `status` | `DEFAULT 'доступно'` | Новое блюдо доступно для заказа |
| `restaurant` | `status` | `DEFAULT 'активен'` | Новый ресторан по дефолту доступен |
| `review` | `review_timestamp` | `localtimestamp` | Фиксация времени отзыва (BR-8.2, BR-9.3, BR-11.2) |

---

## Нормализация (3НФ)

База данных соответствует требованиям третьей нормальной формы (3НФ). Все атрибуты атомарны. В таблицах с составными первичными ключами (client_address, order_structure, courier_pay) неключевые атрибуты зависят от полного ключа, частичные и транзитивные зависимости отсутствуют.
Поля order.commission и order.total_amount реализованы как вычисляемые (GENERATED ALWAYS AS ... STORED), что исключает возможность несоответствия значений.
Поля product.rating и restaurant.rating сохранены в соответствующих таблицах согласно структуре ERD. Их значения автоматически обновляются триггером rating_change (BR-9.6, BR-9.7).
Связь в таблице review через поля entity_id и entity_type реализована как полиморфная в соответствии с требованиями.