create schema sales;

alter schema sales  transfer dbo.olist_customers;
alter schema sales transfer dbo.olist_geolocation;
alter schema sales transfer dbo.olist_order_items;
alter schema sales transfer dbo.olist_order_payments;
alter schema sales transfer dbo.olist_order_reviews;
alter schema sales transfer dbo.olist_orders;
alter schema sales transfer dbo.olist_product_category_name_translation;
alter schema sales transfer dbo.olist_products;
alter schema sales transfer dbo.olist_sellers;

alter table sales.olist_order_items alter column order_item_id numeric NOT NULL;
alter table sales.olist_order_payments alter column payment_sequential tinyint NOT NULL;

-- PK
alter table sales.olist_orders         add constraint pk_olist_orders_order_id      primary key(order_id);
alter table sales.olist_sellers        add constraint pk_olist_sellers_seller_id    primary key(seller_id);
alter table sales.olist_products       add constraint pk_olist_products_product_id  primary key(product_id); 
alter table sales.olist_customers      add constraint pk_olist_customer_customer_id primary key(customer_id);
alter table sales.olist_order_reviews  add constraint pk_olist_reviews              primary key(review_id, order_id);
alter table sales.olist_order_items    add constraint pk_olist_order_items          primary key(order_id, order_item_id);
alter table sales.olist_order_payments add constraint pk_olist_order_payments       primary key(order_id, payment_sequential);
-- FK
alter table sales.olist_order_items    add constraint fk_orders        foreign key(order_id)    references sales.olist_orders(order_id) on delete cascade;
alter table sales.olist_order_items    add constraint fk_products      foreign key(product_id)  references sales.olist_products(product_id);
alter table sales.olist_order_items    add constraint fk_sellers       foreign key(seller_id)   references sales.olist_sellers(seller_id);
alter table sales.olist_orders         add constraint fk_customers     foreign key(customer_id) references sales.olist_customers(customer_id);
alter table sales.olist_order_payments add constraint fk_payments      foreign key(order_id)    references sales.olist_orders(order_id) on delete cascade;
alter table sales.olist_order_reviews  add constraint fk_orders_rewiew foreign key(order_id)    references sales.olist_orders(order_id) on delete cascade;
