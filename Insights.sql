USE [porfolio_project_sales];
GO

-- 1. How satisfied are customers with their orders?
select 'Dissatisfied reviews' as customer_satisfaction, count(r.order_id) amount_orders 
from sales.v_last_order_reviews r
where r.review_score in (1,2)
union all
select 'Satisfied reviews', count(r.order_id)
from sales.v_last_order_reviews r
where r.review_score in (3, 4, 5)
union all
select 'Orders without review', count(distinct o.order_id) amount_orders_without_review
from sales.olist_orders o left join sales.v_last_order_reviews r on o.order_id = r.order_id
where r.order_id is null;

-- 2. What is the number of unique orders per review score?
with reviews as (
	select e.review_score, count(order_id) amount_orders
	from sales.v_last_order_reviews e
	group by e.review_score
)
select r.review_score
      , r.amount_orders
      , sum(amount_orders) over(order by amount_orders desc) running_amount_sum
      , sum(amount_orders) over(order by amount_orders desc)/cast(sum(amount_orders)over() as float)*100 running_percent_amount_orders
from reviews r
order by 2 desc

-- 3. What is the order satisfaction rate for on-time and late deliveries?
with delivery_orders  as
(
   select case when  r.review_score is null then 'Order without review'
               when  r.review_score < 3     then 'Dissatisfied reviews'
	           else 'Satisfied reviews'     end order_statisfaction,
		  o.order_id, 
		  r.review_score,order_delivered_customer_date, order_estimated_delivery_date,
		  datediff(day, order_estimated_delivery_date, order_delivered_customer_date ) diff_days
  from sales.olist_orders o left join sales.v_last_order_reviews r on o.order_id  = r.order_id
  where o.order_status = 'delivered' 
 )
 select order_statisfaction,
        sum(case when diff_days <= 0 then 1 else 0 end) amount_orders_in_time,
        sum(case when diff_days > 0 then 1 else 0 end) amount_late_orders
 from delivery_orders
group by order_statisfaction;

-- 4. What is the average/max/min/median duration of delivery for an order by review satisfaction?
with delivery_orders  as
(
   select case when  r.review_score is null then 'Order without review'
               when  r.review_score < 3     then 'Dissatisfied reviews'
	           else 'Satisfied reviews'     end order_statisfaction,
		  o.order_id, 
		  datediff(day, order_purchase_timestamp, order_delivered_customer_date ) delivery_days,
		  datediff(day, order_purchase_timestamp, order_estimated_delivery_date ) estimated_delivery_days
  from sales.olist_orders o left join sales.v_last_order_reviews r on o.order_id  = r.order_id
  where o.order_status = 'delivered' 
 )
select distinct
       order_statisfaction, 
       avg(delivery_days) over(partition by order_statisfaction) average_days_for_delivery,
	   avg(estimated_delivery_days) over(partition by order_statisfaction) estimated_delivery_days,
       percentile_disc(0.5) within group (order by delivery_days) over (partition by order_statisfaction) median_days_for_delivery,
	   max(delivery_days) over(partition by order_statisfaction) max_days_for_delivery,
	   min(delivery_days) over(partition by order_statisfaction)  min_days_for_delivery
from delivery_orders;

-- 5. What are the total number of reviews, the count of negative reviews, and the percentage of negative reviews for each month and year?
select year, r.month, r.month_name, 
       r.amount_reviews, r.amount_negative_reviews, r.percent_negative_reviews
from (
	select  
			 year(review_creation_date) as year
		   , month(review_creation_date) as month
		   , datename(month, review_creation_date) as month_name
		   , count(order_id)  amount_reviews
		   , sum(case when review_score < 3 then 1 else 0 end)  amount_negative_reviews
		   , round(sum(case when review_score < 3 then 1 else 0 end)/ 
			 cast(count(order_id) as float) * 100, 2)  percent_negative_reviews
	from sales.v_last_order_reviews
	group by year(review_creation_date), month(review_creation_date), datename(month, review_creation_date)
) r
order by 1, 2

-- 6. What is the satisfaction rate categorized by order status?
select order_status, coalesce(dissatisfied_reviews, 0) as dissatisfied_reviews, 
coalesce(satisfied_reviews, 0) as satisfied_reviews, coalesce(without_review, 0) as without_review
from (
	select o.order_status, case when  r.review_score is null then 'without_review'
						   when r.review_score < 3 then 'dissatisfied_reviews'
								else 'satisfied_reviews' end order_statisfaction,
		 count(o.order_id) amount_orders
	from sales.olist_orders o left join sales.v_last_order_reviews r on o.order_id = r.order_id
	group by o.order_status, case when  r.review_score is null then 'without_review'
								  when r.review_score < 3 then 'dissatisfied_reviews'
								  else 'satisfied_reviews' end
) TableForPivot
pivot(
  sum(amount_orders)  
  for order_statisfaction in (dissatisfied_reviews, satisfied_reviews, without_review)
) as PivotTable
order by (case when order_status = 'created' then 1
               when order_status = 'approved' then 2
			   when order_status = 'unavailable' then 3
			   when order_status = 'canceled' then 4
			   when order_status = 'invoiced' then 5
			   when order_status = 'processing' then  6
			   when order_status = 'shipped' then 7
			   else 8 end);

 -- 7. What is the satisfaction rate categorized by top 10 sellers?
 with sellers as (
 select l.full_name_state, 
 case when r.review_score is null then 'without_review'
      when r.review_score < 3 then 'dissatisfied_reviews'
      else 'satisfied_reviews' end order_statisfaction, 
count(distinct i.order_id) amount_orders
 from sales.olist_order_items i inner join sales.olist_sellers s on i.seller_id = s.seller_id
                                inner join sales.olist_locations l on s.seller_zip_code_prefix = l.zip_code_prefix
                                left join sales.v_last_order_reviews r on i.order_id = r.order_id 
							
 group by l.full_name_state,
          case when r.review_score is null then 'without_review'
               when r.review_score < 3 then 'dissatisfied_reviews'
          else 'satisfied_reviews' end
having count(distinct i.order_id) > 10
)
select top(10) with ties
      full_name_state, 
	  coalesce(satisfied_reviews,  0)  satisfied_reviews,
      coalesce(dissatisfied_reviews,  0) dissatisfied_reviews, 
	  coalesce(without_review,  0) without_review,
	  round(coalesce(dissatisfied_reviews,  0)/cast( coalesce(dissatisfied_reviews,  0) + coalesce(satisfied_reviews,  0) + coalesce(without_review,  0) as float)*100, 2) percent_dissatisfied_reviews
from sellers TableForPivot
pivot  
(  
  sum(amount_orders)  
  for order_statisfaction in (satisfied_reviews, dissatisfied_reviews, without_review)  
) as PivotTable
order by  (coalesce(dissatisfied_reviews,  0) + coalesce(satisfied_reviews,  0) + coalesce(without_review,  0) ) desc;

 -- 8. What is the satisfaction rate categorized by top 10 sold product categories?
 with product_categories as (
 select t.product_category_name_english product_category_name, 
 case when r.review_score is null then 'without_review'
      when r.review_score < 3 then 'dissatisfied_reviews'
      else 'satisfied_reviews' end order_statisfaction, 
	    count(distinct i.order_id) amount_orders
 from sales.olist_order_items i inner join sales.olist_products p on i.product_id = p.product_id
                                left join sales.v_last_order_reviews r on i.order_id = r.order_id
								left join sales.olist_product_category_name_translation t on p.product_category_name = t.product_category_name
 group by t.product_category_name_english, 
  case when r.review_score is null then 'without_review'
       when r.review_score < 3 then 'dissatisfied_reviews'
       else 'satisfied_reviews' end 
)
select top(10) with ties
      product_category_name,
      coalesce(satisfied_reviews, 0)  satisfied_reviews,
      coalesce(dissatisfied_reviews, 0) dissatisfied_reviews,
	  coalesce(without_review, 0) without_review,
	  round(coalesce(dissatisfied_reviews, 0)/
	  cast( coalesce(dissatisfied_reviews, 0) + coalesce(satisfied_reviews, 0) + coalesce(without_review, 0)  as float) *100, 2) percent_dissatisfied_reviews 
from  product_categories
pivot  
(  
  sum(amount_orders)  
  for order_statisfaction in (dissatisfied_reviews, satisfied_reviews, without_review)  
) as PivotTable
order by  (coalesce(dissatisfied_reviews, 0) + coalesce(satisfied_reviews, 0) + coalesce(without_review, 0)) desc;  