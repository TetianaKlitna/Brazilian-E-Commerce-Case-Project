﻿-- Replaced Null values in review_comment_title and review_comment_message columns with empty string:
update sales.olist_order_reviews
set review_comment_title   = coalesce(review_comment_title, ''),
    review_comment_message = coalesce(review_comment_message, '')
where review_comment_title is null or review_comment_message is null;

-- Removed dublicates in olist_order_reviews table:
-- Removed 87 rows
begin transaction
delete res
from (
select * 
	from 
	 (
		 select r.*, rank() over(partition by order_id, review_score, review_creation_date, review_comment_title, review_comment_message order by review_answer_timestamp desc) rank
		 from sales.olist_order_reviews r
	 ) t
 where rank > 1
 ) res;

 commit transaction;

 -- Created view sales.v_last_order_reviews for getting last review for each order:
go
create or alter view sales.v_last_order_reviews
as
	select review_id, order_id, review_creation_date, review_score, review_comment_title, review_comment_message, review_answer_timestamp
	from (
		select review_id
		, order_id
		, review_creation_date
		, row_number()over(partition by order_id order by review_creation_date, review_answer_timestamp desc) num
		, review_score
		, review_comment_title
		, review_comment_message
		, review_answer_timestamp
		from sales.olist_order_reviews
		) r
	where r.num = 1;
go

-- Amount orders without review
-- 768 orders
select count(1) amount_orders_without_review
from sales.olist_orders o left join sales.v_last_order_reviews r on o.order_id = r.order_id 
where r.order_id is null;
-- 646 (0.65%) orders with status delivered without review
select  count(o.order_id) amount_orders_without_reviews,
        count(o.order_id)/cast( (select count(o.order_id) amount_orders 
	                             from sales.olist_orders o) as float) *100 percent_orders_without_reviews
from sales.olist_orders o left join sales.v_last_order_reviews r on o.order_id = r.order_id 
where r.order_id is null and order_status = 'delivered';

-- Amount orders with review
-- Result: 98673
select count(1)
from sales.v_last_order_reviews;

-- Updated completed orders with positive reviews lacking order_delivered_customer_date by assigning them the order_estimated_delivery_date.
-- It looks like system issue (8 rows is updated)
update sales.olist_orders
set order_delivered_customer_date = order_estimated_delivery_date
where order_delivered_customer_date is null and order_status = 'delivered';

--Orders without order list items
--775 orders without items in the olist_order_items (statuses: canceled, created, invoiced, shipped, unavailable)
-- It isn't data issue, because according to the reviews, products aren't available for order.
select *
from sales.olist_orders o full join sales.olist_order_items i on o.order_id = i.order_id
where i.order_id is null or o.order_id is null;

-- Corrected 611 rows with Null values in product table
select count(1) amount_products
from sales.olist_products p
where product_category_name is null
   or product_description_lenght is null 
   or product_name_lenght is null 
   or product_photos_qty is null
   or product_weight_g is null
   or product_length_cm is null
   or product_height_cm is null
   or product_width_cm is null;

begin transaction
update sales.olist_products 
set product_category_name      = coalesce(product_category_name, 'N/A'),
    product_description_lenght = coalesce(product_description_lenght, 0),
	product_name_lenght        = coalesce(product_name_lenght, 0),
	product_photos_qty         = coalesce(product_photos_qty, 0),
	product_weight_g           = coalesce(product_weight_g, 0),
	product_length_cm          = coalesce(product_length_cm, 0),
	product_height_cm          = coalesce(product_height_cm, 0),
	product_width_cm           = coalesce(product_width_cm, 0)
where product_category_name      is null
   or product_description_lenght is null 
   or product_name_lenght        is null 
   or product_photos_qty         is null
   or product_weight_g           is null
   or product_length_cm          is null
   or product_height_cm          is null
   or product_width_cm           is null;
commit transaction;

-- Product categories exist only in the Spanish language and are absent from the English translation table.
-- Result: 'pc_gamer' and 'portateis_cozinha_e_preparadores_de_alimentos'
select distinct p.product_category_name
from sales.olist_products p left join sales.olist_product_category_name_translation t on p.product_category_name = t.product_category_name
where t.product_category_name is null;

--Amount product without category name
-- 610 product without category
select  count(1) products_without_category_name
from sales.olist_products p left join sales.olist_product_category_name_translation t on p.product_category_name = t.product_category_name
where t.product_category_name is null;

--Insert translation for these categories
insert into sales.olist_product_category_name_translation(product_category_name, product_category_name_english)
values
('pc_gamer', 'pc_gamer'),
('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_processors'),
('N/A', 'N/A');

-- Founded dublicates in product_category_name: 
-- casa_conforto and casa_conforto_2; eletrodomesticos and eletrodomesticos_2
begin transaction;

update sales.olist_products
set product_category_name = 'casa_conforto'
where product_category_name = 'casa_conforto_2';
	
update sales.olist_products
set product_category_name = 'eletrodomesticos'
where product_category_name = 'eletrodomesticos_2';

delete  sales.olist_product_category_name_translation
where product_category_name in ('eletrodomesticos_2', 'casa_conforto_2');

commit transaction;

-- Checked dublicates in the olist_product_category_name_translation table
select product_category_name, product_category_name_english
from sales.olist_product_category_name_translation
group by product_category_name, product_category_name_english
having count(1) > 1

-- Added Primary key product_category_name in the sales.olist_product_category_name_translation table
alter table sales.olist_product_category_name_translation add constraint pk_olist_category_name primary key(product_category_name);

-- Added Foreign Key in sales.olist_products for column product_category_name
alter table sales.olist_products add constraint fk_product_categories foreign key(product_category_name) references sales.olist_product_category_name_translation(product_category_name);

-- There are 3 rows in the 'sales.olist_order_payments' table with a 'payment_value' of 0.
select order_id, sum(payment_value) payment
from sales.olist_order_payments
group by order_id
having sum(payment_value) = 0
-- Order status of these orders is canceled
select distinct order_status
from sales.olist_orders
where order_id in ('00b1cb0320190ca0daa2c88b35206009', '4637ca194b6387e2d538dc89b124b0ee', 'c8c528189310eaa44a745b8d9d26908b');

-- 1 order with status 'delivered' doesn't contain payment information
select *
from sales.olist_order_payments p full join sales.olist_orders o
on p.order_id = o.order_id
where p.order_id is null or o.order_id is null;
-- This order contain review score 1 and message "I did not receive the product, and I did not receive a response from the company."
select *
from sales.v_last_order_reviews
where order_id = 'bfbd0f9bdef84302105ad712db648a6c';

--Corrected city names in the sales.olist_geolocation table
begin transaction
update sales.olist_geolocation
set geolocation_city = translate(geolocation_city, 'ááãâçéêíóôõúü', 'aaaaceeiooouu');
commit transaction;

--Removed dublicates in the sales.olist_geolocation
begin transaction
delete res
	from (
	select * 
		from 
		 (
			 select r.*, row_number() over(partition by geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, geolocation_city, geolocation_state order by  geolocation_zip_code_prefix, geolocation_state, geolocation_city) rank
			 from sales.olist_geolocation r
		 ) t
	 where rank > 1
) res;
commit transaction; 

--Created Index on table sales.olist_geolocation
create index ind_zip_code_prefix on sales.olist_geolocation(geolocation_zip_code_prefix);

select *
from sales.olist_geolocation

--Added new column state_full_name
alter table  sales.olist_geolocation add full_name_state nvarchar(50);

update sales.olist_geolocation 
set full_name_state = case  when geolocation_state = 'AC' then 'Acre'
							when geolocation_state = 'AL' then 'Alagoas'
							when geolocation_state = 'AP' then 'Amapa'
							when geolocation_state = 'AM' then 'Amazonas'
							when geolocation_state = 'BA' then 'Bahia'
							when geolocation_state = 'CE' then 'Ceara'
							when geolocation_state = 'DF' then 'Distrito Federal'
							when geolocation_state = 'ES' then 'Espirito Santo'
							when geolocation_state = 'GO' then 'Goias'
							when geolocation_state = 'MA' then 'Maranhao'
							when geolocation_state = 'MT' then 'Mato Grosso'
							when geolocation_state = 'MS' then 'Mato Grosso do Sul'
							when geolocation_state = 'MG' then 'Minas Gerais'
							when geolocation_state = 'PA' then 'Para'
							when geolocation_state = 'PB' then 'Paraiba'
							when geolocation_state = 'PR' then 'Parana'
							when geolocation_state = 'PE' then 'Pernambuco'
							when geolocation_state = 'PI' then 'Piaui'
							when geolocation_state = 'RJ' then 'Rio de Janeiro'
							when geolocation_state = 'RN' then 'Rio Grande do Norte'
							when geolocation_state = 'RS' then 'Rio Grande do Sul'
							when geolocation_state = 'RO' then 'Rondonia'
							when geolocation_state = 'RR' then 'Roraima'
							when geolocation_state = 'SC' then 'Santa Catarina'
							when geolocation_state = 'SP' then 'Sao Paulo'
							when geolocation_state = 'SE' then 'Sergipe'
							when geolocation_state = 'TO' then 'Tocantins' end;

--Checked city name for correctness
--Quilômetro 14 do Mutum is the community in Brazil
select *
from sales.olist_geolocation
where geolocation_city like '%[0-9]%';
