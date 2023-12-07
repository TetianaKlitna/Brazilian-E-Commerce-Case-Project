-- Replaced Null values in review_comment_title and review_comment_message columns with empty string:
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

-- Corrected the name of a city in the table sales.olist_customers table by capitalizing the first letter.
begin transaction
update e
set e.customer_city = a.new_customer_city
from  sales.olist_customers  e
	inner join (
		select  customer_id, customer_unique_id, customer_state, customer_zip_code_prefix, customer_city, STRING_AGG(value, ' ') new_customer_city
		from (
			select customer_id, customer_unique_id,customer_state, customer_zip_code_prefix , 
			       case when value in ('de', 'do', 'dos', 'da') then value
			            else upper(left(value, 1)) + substring(value, 2, len(value)) end  value,
					customer_city
			from sales.olist_customers cross apply string_split(customer_city, ' ')
			) res
		group by customer_id, customer_unique_id, customer_state, customer_zip_code_prefix, customer_city
		) a
on e.customer_city = a.customer_city;
commit transaction;

-- Created new table sales.olist_locations 
-- with columns: zip_code prefix int not null; city nvarchar(50) not null, state nvarchar(50) not null
drop table if exists sales.olist_locations;

select zip_code_prefix, city, state
into sales.olist_locations
from (
	select  customer_zip_code_prefix as zip_code_prefix, customer_city as city, customer_state as state
	from sales.olist_customers
	union
	select  seller_zip_code_prefix, seller_city, seller_state
	from sales.olist_sellers) res;

--Generated scripts to correct values in the sales.olist_locations
select ' update sales.olist_locations set city = ''' + d.geolocation_city +  '''' + 
	   ' where city = ''' + t.city + ''' and zip_code_prefix = ' + cast(t.zip_code_prefix as nvarchar) + ' and state = ''' + t.state + ''';' script
from 
(
	select r.*, row_number() over(partition by zip_code_prefix order by (select null)) rank
	from sales.olist_locations r
) t left join 
(
    select distinct g.geolocation_zip_code_prefix, g.geolocation_state, g.geolocation_city
	from sales.olist_geolocation g ) d on t.zip_code_prefix = d.geolocation_zip_code_prefix and t.state = d.geolocation_state
where rank > 1 and t.city <> d.geolocation_city;

begin transaction
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paulo Sp' and zip_code_prefix = 1207 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Pauo' and zip_code_prefix = 2051 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = N'São Paulo' and zip_code_prefix = 4557 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sp / Sp' and zip_code_prefix = 3363 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paulo - Sp' and zip_code_prefix = 4130 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paulo / Sao Paulo' and zip_code_prefix = 3407 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paulo - Sp' and zip_code_prefix = 4007 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao  Paulo' and zip_code_prefix = 5303 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paulo - Sp' and zip_code_prefix = 5353 and state = 'SP';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paulop' and zip_code_prefix = 3581 and state = 'SP';
  update sales.olist_locations set city = 'Sao Paulo' where city = 'Sao Paluo' and zip_code_prefix = 8050 and state = 'SP';
 update sales.olist_locations set city = 'Guarulhos' where city = 'Garulhos' and zip_code_prefix = 7077 and state = 'SP';
 update sales.olist_locations set city = 'Santo Andre' where city = 'Santo Andre/sao Paulo' and zip_code_prefix = 9230 and state = 'SP';
 update sales.olist_locations set city = 'Sao Bernardo do Campo' where city = 'Ao Bernardo do Campo' and zip_code_prefix = 9687 and state = 'SP';
 update sales.olist_locations set city = 'Sao Bernardo do Campo' where city = 'Sao Bernardo do Capo' and zip_code_prefix = 9721 and state = 'SP';
 update sales.olist_locations set city = 'Sao Bernardo do Campo' where city = 'Sbc/sp' and zip_code_prefix = 9726 and state = 'SP';
  update sales.olist_locations set city = 'Sao Bernardo do Campo' where city = 'Sbc' and zip_code_prefix = 9861 and state = 'SP';
 update sales.olist_locations set city = 'Santa Barbara d''Oeste' where city = 'Santa Barbara D´oeste' and zip_code_prefix = 13450 and state = 'SP';
 update sales.olist_locations set city = 'Porto Ferreira' where city = 'Portoferreira' and zip_code_prefix = 13660 and state = 'SP';
 update sales.olist_locations set city = 'Ribeirao Preto' where city = 'Sao Paulo' and zip_code_prefix = 14015 and state = 'SP';
 update sales.olist_locations set city = 'Ribeirao Preto' where city = 'Ribeirao Preto / Sao Paulo' and zip_code_prefix = 14079 and state = 'SP';
 update sales.olist_locations set city = 'Ribeirao Preto' where city = 'Riberao Preto' and zip_code_prefix = 14085 and state = 'SP';
 update sales.olist_locations set city = 'Ribeirao Preto' where city = 'Bonfim Paulista' and zip_code_prefix = 14110 and state = 'SP';
 update sales.olist_locations set city = 'Sao Jose do Rio Pardo' where city = 'Scao Jose do Rio Pardo' and zip_code_prefix = 13720 and state = 'SP';
 update sales.olist_locations set city = 'Sao Jose do Rio Preto' where city = 'Sao Jose do Rio Pret' and zip_code_prefix = 15051 and state = 'SP';
 update sales.olist_locations set city = 'Sao Jose do Rio Preto' where city = 'S Jose do Rio Preto' and zip_code_prefix = 15014 and state = 'SP';
 update sales.olist_locations set city = 'Rio de Janeiro' where city = 'Rio de Janeiro / Rio de Janeiro' and zip_code_prefix = 20081 and state = 'RJ';
 update sales.olist_locations set city = 'Rio de Janeiro' where city = 'Rio de Janeiro \rio de Janeiro' and zip_code_prefix = 22050 and state = 'RJ';
 update sales.olist_locations set city = 'Angra dos Reis' where city = 'Angra dos Reis Rj' and zip_code_prefix = 23943 and state = 'RJ';
 update sales.olist_locations set city = 'Paraty' where city = 'Parati' and zip_code_prefix = 23970 and state = 'RJ';
 update sales.olist_locations set city = 'Cariacica' where city = 'Cariacica / Es' and zip_code_prefix = 29142 and state = 'ES';
 update sales.olist_locations set city = 'Barbacena' where city = 'Barbacena/ Minas Gerais' and zip_code_prefix = 36200 and state = 'MG';
 update sales.olist_locations set city = 'Brasilia' where city = 'Brasilia Df' and zip_code_prefix = 71906 and state = 'DF';
 update sales.olist_locations set city = 'Dias Davila' where city = 'Dias D Avila' and zip_code_prefix = 42850 and state = 'BA';
 update sales.olist_locations set city = 'Dias D''avila' where city = 'Dias D Avila' and zip_code_prefix = 42850 and state = 'BA';
 update sales.olist_locations set city = 'Arraial D Ajuda' where city = 'Porto Seguro' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Arraial D''ajuda' where city = 'Arraial D Ajuda' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Arraial D''ajuda' where city = 'Arraial D''ajuda (porto Seguro)' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Planaltina' where city = 'Planaltina de Goias' and zip_code_prefix = 73752 and state = 'GO';
 update sales.olist_locations set city = 'Ji-parana' where city = 'Ji Parana' and zip_code_prefix = 76900 and state = 'RO';
 update sales.olist_locations set city = 'Bataypora' where city = 'Bataipora' and zip_code_prefix = 79760 and state = 'MS';
 update sales.olist_locations set city = 'Porto Seguro' where city = 'Arraial D''ajuda (porto Seguro)' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Arraial D Ajuda' where city = 'Arraial D''ajuda (porto Seguro)' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Arraial D''ajuda' where city = 'Porto Seguro' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Porto Seguro' where city = 'Arraial D Ajuda' and zip_code_prefix = 45816 and state = 'BA';
 update sales.olist_locations set city = 'Camboriu' where city = 'Balneario Camboriu' and zip_code_prefix = 88330 and state = 'SC';
 update sales.olist_locations set city = 'Brasopolis' where city = 'Brazopolis' and zip_code_prefix = 37530 and state = 'MG';
 update sales.olist_locations set city = 'Piumhii' where city = 'Piumhi' and zip_code_prefix = 37925 and state = 'MG';
 update sales.olist_locations set city = 'Balneario Picarras' where city = 'Picarras' and zip_code_prefix = 88380 and state = 'SC';
 update sales.olist_locations set city = 'Juazeiro do Norte' where city = 'Juzeiro do Norte' and zip_code_prefix = 63020 and state = 'CE';
 update sales.olist_locations set city = 'Maringa' where city = 'Vendas@creditparts.com.br' and zip_code_prefix = 87025 and state = 'PR';
 update sales.olist_locations set city = 'Itapage' where city = 'Itapaje' and zip_code_prefix = 62600 and state = 'CE';
 update sales.olist_locations set city = 'Jacarei' where city = 'Jacarei / Sao Paulo' and zip_code_prefix = 12306 and state = 'SP';
 update sales.olist_locations set city = 'Carapicuiba' where city = 'Carapicuiba / Sao Paulo' and zip_code_prefix = 6311 and state = 'SP';
 update sales.olist_locations set city = 'Maua' where city = 'Maua/sao Paulo' and zip_code_prefix = 9380 and state = 'SP';
 update sales.olist_locations set city = 'Mogi Das Cruzes' where city = 'Mogi Das Cruses' and zip_code_prefix = 8710 and state = 'SP';
 update sales.olist_locations set city = 'Mogi Das Cruzes' where city = 'Mogi Das Cruzes / Sp' and zip_code_prefix = 8717 and state = 'SP';
 update sales.olist_locations set city = 'Novo Hamburgo' where city = 'Novo Hamburgo, Rio Grande do Sul, Brasil' and zip_code_prefix = 93310 and state = 'RS';
 update sales.olist_locations set city = 'Taboao da Serra' where city = 'Sao Paulo' and zip_code_prefix = 6760 and state = 'SP';
 update sales.olist_locations set city = 'Pinhais' where city = 'Pinhais/pr' and zip_code_prefix = 83327 and state = 'PR';
 update sales.olist_locations set city = 'Ribeirao Preto' where city = 'Ribeirao Pretp' and zip_code_prefix = 14027 and state = 'SP';
 update sales.olist_locations set city = 'Sao Jose dos Pinhais' where city = 'Sao Jose dos Pinhas' and zip_code_prefix = 83040 and state = 'PR';
 update sales.olist_locations set city = 'Sao Miguel do Oeste' where city = 'Sao Miguel D''oeste' and zip_code_prefix = 89900 and state = 'SC';
 update sales.olist_locations set city = 'Florianopolis' where city = 'Floranopolis' and zip_code_prefix = 88056 and state = 'SC';
 update sales.olist_locations set city = 'Sao Sebastiao da Grama' where city = 'Sao Sebastiao da Grama/sp' and zip_code_prefix = 13790 and state = 'SP';
 update sales.olist_locations set city = 'Belo Horizonte' where city = 'Belo Horizont' and zip_code_prefix = 31255 and state = 'MG';
 update sales.olist_locations set city = 'Taboao da Serra' where city = 'Tabao da Serra' and zip_code_prefix = 6764 and state = 'SP';
 update sales.olist_locations set city = 'Santo Andre' where city = 'Sando Andre' and zip_code_prefix = 9190 and state = 'SP';
 update sales.olist_locations set city = 'Ribeirao Preto' where city = 'Robeirao Preto' and zip_code_prefix = 14078 and state = 'SP';
 update sales.olist_locations set city = 'Auriflama' where city = 'Auriflama/sp' and zip_code_prefix = 15350 and state = 'SP';
 update sales.olist_locations set city = 'Lages' where city = 'Lages - Sc' and zip_code_prefix = 88501 and state = 'SC';
 update sales.olist_locations set city = 'Maringa' where city = 'Parana' and zip_code_prefix = 87083 and state = 'PR';
 update sales.olist_locations set city = 'Balneario Camboriu' where city = 'Balenario Camboriu' and zip_code_prefix = 88330 and state = 'SC';
 
 update sales.olist_locations set city = 'Ceilandia' where city = 'Brasilia' and zip_code_prefix = 72270 and state = 'DF';
 update sales.olist_locations set city = 'Sao Joao da Serra Negra' where city = 'Sao Benedito' and zip_code_prefix = 38749 and state = 'MG';
 update sales.olist_locations set city = 'Patrocinio' where city = 'Sao Benedito' and zip_code_prefix = 38749 and state = 'MG';
 update sales.olist_locations set city = 'Sao Caetano do Sul' where city = 'Sao Paulo' and zip_code_prefix = 9560 and state = 'SP';
 update sales.olist_locations set city = 'Guarapuava' where city = 'Colonia Vitoria' and zip_code_prefix = 85139 and state = 'PR';
 update sales.olist_locations set city = 'Ceilandia Norte' where city = 'Brasilia' and zip_code_prefix = 72270 and state = 'DF';
 update sales.olist_locations set city = 'Jaguariuna' where city = 'Monte Alegre do Sul' and zip_code_prefix = 13910 and state = 'SP';
 update sales.olist_locations set city = 'Camacari' where city = 'Abrantes' and zip_code_prefix = 42840 and state = 'BA';
 update sales.olist_locations set city = 'Presidente Venceslau' where city = 'Sao Paulo' and zip_code_prefix = 19400 and state = 'SP';
 update sales.olist_locations set city = 'Itaborai' where city = 'Rio de Janeiro' and zip_code_prefix = 24855 and state = 'RJ';
 update sales.olist_locations set city = 'Brasilia' where city = 'Guara' and zip_code_prefix = 71065 and state = 'DF';
 update sales.olist_locations set city = 'Fragosos' where city = 'Campo Alegre' and zip_code_prefix = 89294 and state = 'SC';
 update sales.olist_locations set city = 'Braganca Paulista' where city = 'Sao Paulo' and zip_code_prefix = 12903 and state = 'SP';
 update sales.olist_locations set city = 'Cachoeiras de Macacu' where city = 'Papucaia' and zip_code_prefix = 28695 and state = 'RJ';
 update sales.olist_locations set city = 'Camboriu' where city = 'Balenario Camboriu' and zip_code_prefix = 88330 and state = 'SC';
 update sales.olist_locations set city = 'Teofilo Otoni' where city = 'Castro Pires' and zip_code_prefix = 39801 and state = 'MG';
 update sales.olist_locations set city = 'Belo Horizonte' where city = 'Contagem' and zip_code_prefix = 31340 and state = 'MG';
 update sales.olist_locations set city = 'Aracatuba' where city = 'Sao Paulo' and zip_code_prefix = 16021 and state = 'SP';
 update sales.olist_locations set city = 'Mage' where city = 'Rio de Janeiro' and zip_code_prefix = 25900 and state = 'RJ';
 update sales.olist_locations set city = 'Dias D Avila' where city = 'Dias Davila' and zip_code_prefix = 42850 and state = 'BA';
 update sales.olist_locations set city = 'Vicosa' where city = 'Porto Firme' and zip_code_prefix = 36576 and state = 'MG';
 update sales.olist_locations set city = 'Para de Minas' where city = 'Centro' and zip_code_prefix = 35660 and state = 'MG';
 update sales.olist_locations set city = 'Florianopolis' where city = 'Sao Jose' and zip_code_prefix = 88075 and state = 'SC';
 update sales.olist_locations set city = 'Guaruja' where city = 'Vicente de Carvalho' and zip_code_prefix = 11450 and state = 'SP';
 update sales.olist_locations set city = 'Aruja' where city = 'Sao Paulo' and zip_code_prefix = 7411 and state = 'SP';
 update sales.olist_locations set city = 'Brasilia' where city = 'Taguatinga' and zip_code_prefix = 71939 and state = 'DF';
 update sales.olist_locations set city = 'Campo do Meio' where city = 'Minas Gerais' and zip_code_prefix = 37165 and state = 'MG';
 update sales.olist_locations set city = 'Tupa' where city = 'Sao Paulo' and zip_code_prefix = 17606 and state = 'SP';
 update sales.olist_locations set city = 'Palhoca' where city = 'Santa Catarina' and zip_code_prefix = 88135 and state = 'SC';
 update sales.olist_locations set city = 'Dias D''avila' where city = 'Dias Davila' and zip_code_prefix = 42850 and state = 'BA';
 update sales.olist_locations set city = 'Brasilia' where city = 'Taguatinga' and zip_code_prefix = 71937 and state = 'DF';
 update sales.olist_locations set city = 'Jaguariuna' where city = 'Monte Alegre do Sul' and zip_code_prefix = 13820 and state = 'SP';
 update sales.olist_locations set city = 'Nova Iguacu' where city = 'Rio de Janeiro' and zip_code_prefix = 26051 and state = 'RJ';
 update sales.olist_locations set city = 'Sobradinho' where city = 'Brasilia' and zip_code_prefix = 73060 and state = 'DF';
 update sales.olist_locations set city = 'Silvano' where city = 'Sao Benedito' and zip_code_prefix = 38749 and state = 'MG';
 update sales.olist_locations set city = 'Jurema' where city = 'Santo Antonio Das Queimadas' and zip_code_prefix = 55485 and state = 'PE';
 update sales.olist_locations set city = 'Itamira' where city = 'Apora' and zip_code_prefix = 48355 and state = 'BA';

  update sales.olist_locations set city = 'Osasco' where city = 'Sao Paulo' and zip_code_prefix = 6280 and state = 'SP';
 update sales.olist_locations set city = 'Paicandu' where city = 'Paincandu' and zip_code_prefix = 87140 and state = 'PR';
 update sales.olist_locations set city = 'Sao Joao da Serra Negra' where city = 'Silvano' and zip_code_prefix = 38749 and state = 'MG';
 update sales.olist_locations set city = 'Patrocinio' where city = 'Silvano' and zip_code_prefix = 38749 and state = 'MG';
 update sales.olist_locations set city = 'Pindamonhangaba' where city = 'Sao Paulo' and zip_code_prefix = 12401 and state = 'SP';
 update sales.olist_locations set city = 'Guarapuava' where city = 'Vitoria' and zip_code_prefix = 85139 and state = 'PR';
 update sales.olist_locations set city = 'Dias D''avila' where city = 'Dias D Avila' and zip_code_prefix = 42850 and state = 'BA';
 update sales.olist_locations set city = 'Dias Davila' where city = 'Dias D Avila' and zip_code_prefix = 42850 and state = 'BA';
 update sales.olist_locations set city = 'Colonia Vitoria' where city = 'Vitoria' and zip_code_prefix = 85139 and state = 'PR';
 update sales.olist_locations set city = 'Balneario Camboriu' where city = 'Camboriu' and zip_code_prefix = 88330 and state = 'SC';
 update sales.olist_locations set city = 'Brasilia' where city = 'Gama' and zip_code_prefix = 72460 and state = 'DF';
 update sales.olist_locations set city = 'Barra do Jacare' where city = 'Andira-pr' and zip_code_prefix = 86385 and state = 'PR';
 update sales.olist_locations set city = 'Piracicaba' where city = 'Sao Paulo' and zip_code_prefix = 13420 and state = 'SP';
 
 update sales.olist_locations set city = 'Cascavel' where city = 'Cascavael' and zip_code_prefix = 85802 and state = 'PR';
 update sales.olist_locations set city = 'Diadema' where city = 'Sao Paulo' and zip_code_prefix = 9911 and state = 'SP';
 update sales.olist_locations set city = 'Campos dos Goytacazes' where city = 'Rio de Janeiro' and zip_code_prefix = 28035 and state = 'RJ';
 update sales.olist_locations set city = 'Araras' where city = 'Sao Paulo' and zip_code_prefix = 13600 and state = 'SP';
 update sales.olist_locations set city = 'Paulo Afonso' where city = 'Bahia' and zip_code_prefix = 48602 and state = 'BA';
 update sales.olist_locations set city = 'Sao Paulo' where city = 'Pirituba' and zip_code_prefix = 5141 and state = 'SP';
 update sales.olist_locations set city = 'Laranjal Paulista' where city = 'Tatui' and zip_code_prefix = 18500 and state = 'SP';

 update  sales.olist_locations set city = 'Aguas Claras', state = 'DF' where city = 'Aguas Claras Df' and zip_code_prefix = 71900 and state = 'SP';
 update  sales.olist_locations set city = 'Aguas Claras' where city = 'Brasilia' and zip_code_prefix = 71900 and state = 'DF';
 update  sales.olist_locations set city = 'Santa Rita do Sapucai', state = 'MG' where city = 'Sao Paulo' and zip_code_prefix = 37540 and state = 'SP';
 update  sales.olist_locations set city = 'Rio Bonito'  where city = 'Boa Esperanca' and zip_code_prefix = 28810 and state = 'RJ';
 update  sales.olist_locations set city = 'Boa Esperanca'  where city = 'Rio Bonito' and zip_code_prefix = 28810 and state = 'RJ';
 update  sales.olist_locations set city = 'Brasilia'  where city = 'Aguas Claras' and zip_code_prefix = 71900 and state = 'DF';
 commit transaction;

 --Generated scripts to correct values in the sales.olist_locations
 select ' update sales.olist_locations set state = ''' + d.geolocation_state +  '''' + 
	    ' where city = ''' + t.city + ''' and zip_code_prefix = ' + cast(t.zip_code_prefix as nvarchar) + ' and state = ''' + t.state + ''';' script
 from 
 (
	select r.*, row_number() over(partition by zip_code_prefix order by (select null)) rank
	from sales.olist_locations r
  ) t left join 
 (
    select distinct g.geolocation_zip_code_prefix, g.geolocation_state, g.geolocation_city
	from sales.olist_geolocation g 
 )d on t.zip_code_prefix = d.geolocation_zip_code_prefix and  t.city = d.geolocation_city 
 where rank > 1 and t.state <> d.geolocation_state;

 begin transaction;
 update sales.olist_locations set state = 'PR' where city = 'Sao Jose dos Pinhais' and zip_code_prefix = 83020 and state = 'SP';
 update sales.olist_locations set state = 'SC' where city = 'Blumenau' and zip_code_prefix = 89052 and state = 'SP';
 update sales.olist_locations set state = 'RJ' where city = 'Volta Redonda' and zip_code_prefix = 27277 and state = 'SP';
 update sales.olist_locations set state = 'SC' where city = 'Laguna' and zip_code_prefix = 88790 and state = 'SP';
 update sales.olist_locations set state = 'SC' where city = 'Chapeco' and zip_code_prefix = 89803 and state = 'SP';
 update sales.olist_locations set state = 'SC' where city = 'Palhoca' and zip_code_prefix = 88136 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Curitiba' and zip_code_prefix = 80240 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Londrina' and zip_code_prefix = 86076 and state = 'SP';
 update sales.olist_locations set state = 'RJ' where city = 'Rio de Janeiro' and zip_code_prefix = 21210 and state = 'RN';
 update sales.olist_locations set state = 'SC' where city = 'Itajai' and zip_code_prefix = 88301 and state = 'SP';
 update sales.olist_locations set state = 'RJ' where city = 'Rio de Janeiro' and zip_code_prefix = 21320 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Curitiba' and zip_code_prefix = 81020 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Marechal Candido Rondon' and zip_code_prefix = 85960 and state = 'PA';
 update sales.olist_locations set state = 'RS' where city = 'Caxias do Sul' and zip_code_prefix = 95076 and state = 'SP';
 update sales.olist_locations set state = 'RS' where city = 'Caxias do Sul' and zip_code_prefix = 95055 and state = 'SP';
 update sales.olist_locations set state = 'RS' where city = 'Porto Alegre' and zip_code_prefix = 91520 and state = 'SP';
 update sales.olist_locations set state = 'RJ' where city = 'Rio de Janeiro' and zip_code_prefix = 22783 and state = 'SP';
 update sales.olist_locations set state = 'MG' where city = 'Belo Horizonte' and zip_code_prefix = 31160 and state = 'SP';
 update sales.olist_locations set state = 'MG' where city = 'Juiz de Fora' and zip_code_prefix = 36010 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Curitiba' and zip_code_prefix = 81560 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Laranjeiras do Sul' and zip_code_prefix = 85301 and state = 'SP';
 update sales.olist_locations set state = 'BA' where city = 'Ipira' and zip_code_prefix = 44600 and state = 'SP';
 update sales.olist_locations set state = 'ES' where city = 'Vila Velha' and zip_code_prefix = 29101 and state = 'SP';
 update sales.olist_locations set state = 'SC' where city = 'Florianopolis' and zip_code_prefix = 88075 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Marechal Candido Rondon' and zip_code_prefix = 85960 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Sertanopolis' and zip_code_prefix = 86170 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Pinhais' and zip_code_prefix = 83321 and state = 'SP';
 update sales.olist_locations set state = 'PR' where city = 'Goioere' and zip_code_prefix = 87360 and state = 'SP';
 update sales.olist_locations set state = 'MG' where city = 'Tocantins' and zip_code_prefix = 36512 and state = 'SP';
 update sales.olist_locations set state = 'MG' where city = 'Belo Horizonte' and zip_code_prefix = 31570 and state = 'SP';
 update sales.olist_locations set state = 'MG' where city = 'Andradas' and zip_code_prefix = 37795 and state = 'SP';
 update sales.olist_locations set state = 'RJ' where city = 'Rio Bonito' and zip_code_prefix = 28810 and state = 'SP';
 commit transaction;

 -- Removed dublicates in the sales.olist_locations table 
begin transaction
delete res
from (
select * 
	from 
	 (
		 select r.*, row_number() over(partition by zip_code_prefix, state, city order by (select null)) rank
		 from sales.olist_locations r
	 ) t
 where rank > 1
 ) res;
 commit transaction

  select * 
	from 
	 (
		 select r.*, row_number() over(partition by zip_code_prefix order by (select null)) rank
		 from sales.olist_locations r
	 ) t
 where rank > 1
 order by zip_code_prefix

--Added Primary Key to the  sales.olist_locations table
alter table sales.olist_locations add constraint pk_olist_locations primary key(zip_code_prefix);

--Anti Left Join Check for tables sales.olist_customers and sales.olist_locations
select *
from sales.olist_customers c left join sales.olist_locations l on
c.customer_zip_code_prefix = l.zip_code_prefix
where  l.zip_code_prefix is null;
--Anti Left Join Check for tables sales.olist_sellers and sales.olist_locations
select *
from sales.olist_sellers c left join sales.olist_locations l on
c.seller_zip_code_prefix = l.zip_code_prefix
where  l.zip_code_prefix is null;


--Removed columns "customer_city" and "customer_state" from sales.olist_customers 
alter table sales.olist_customers drop column customer_city, customer_state;
--Removed columns "seller_city" and "seller_state" from sales.olist_sellers 
alter table sales.olist_sellers drop column seller_city, seller_state;

--Added Foreign Key on column "customer_zip_code_prefix" to sales.olist_customers(zip_code_prefix)
alter table sales.olist_customers add constraint fk_customers_zip_code foreign key(customer_zip_code_prefix) references sales.olist_locations(zip_code_prefix);
--Added Foreign Key on column "seller_zip_code_prefix" to sales.olist_sellers(zip_code_prefix)
alter table sales.olist_sellers add constraint fk_seller_zip_code foreign key(seller_zip_code_prefix) references sales.olist_locations(zip_code_prefix);
