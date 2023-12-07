alter table sales.olist_orders         add constraint pk_olist_orders_order_id      primary key(order_id);
alter table sales.olist_sellers        add constraint pk_olist_sellers_seller_id    primary key(seller_id);
alter table sales.olist_products       add constraint pk_olist_products_product_id  primary key(product_id); 
alter table sales.olist_customers      add constraint pk_olist_customer_customer_id primary key(customer_id);
alter table sales.olist_order_reviews  add constraint pk_olist_reviews              primary key(review_id, order_id);
alter table sales.olist_order_items    add constraint pk_olist_order_items          primary key(order_id, order_item_id);
alter table sales.olist_order_payments add constraint pk_olist_order_payments       primary key(order_id, payment_sequential);

alter table sales.olist_order_items    add constraint fk_orders        foreign key(order_id)    references sales.olist_orders(order_id) on delete cascade;
alter table sales.olist_order_items    add constraint fk_products      foreign key(product_id)  references sales.olist_products(product_id);
alter table sales.olist_order_items    add constraint fk_sellers       foreign key(seller_id)   references sales.olist_sellers(seller_id);
alter table sales.olist_orders         add constraint fk_customers     foreign key(customer_id) references sales.olist_customers(customer_id);
alter table sales.olist_order_payments add constraint fk_payments      foreign key(order_id)    references sales.olist_orders(order_id) on delete cascade;
alter table sales.olist_order_reviews  add constraint fk_orders_rewiew foreign key(order_id)    references sales.olist_orders(order_id) on delete cascade;
alter table sales.olist_order_reviews_insatisfaction add constraint fk_orders_rewiew_insatisfaction foreign key(order_id) references sales.olist_orders(order_id);	