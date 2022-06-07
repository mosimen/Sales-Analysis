select *
from sales_data

--- Data  cleaning
--check for duplicates

select *
from
	(select *,
		row_number()over(partition by ordernumber, quantityordered, customername,sales order by orderdate) as dupflag
	from sales_data) as salesdata
where dupflag>1
---No duplicates

---Total sales per year
select distinct YEAR_ID, 
	round(sum(SALES) over(partition by year_id),2) as sum_of_sales 
from sales_data
order by 2 desc

--- Sales was low in 2015, how many months did they worked in 2015
select distinct
	YEAR_ID,
	MONTH_ID
from sales_data
where YEAR_ID = '2005'

--- Analysis
--Grouping sales by productline

-- Which productline is generating more revenue
select
	PRODUCTLINE,
	round(sum(SALES),2) as Revenue
from sales_data
group by PRODUCTLINE
order by 2 desc

--Which year generated the highest revenue
select
	YEAR_ID, round(sum(SALES),2) as Revenue
from sales_data
group by YEAR_ID
order by 2 desc

--- Which productline generated the highest revenue and in what year?
select
	YEAR_ID,PRODUCTLINE,round(sum(SALES),2) as Revenue
from sales_data
group by YEAR_ID, PRODUCTLINE
order by 3 desc

--- Which dealsize is generating more Revenue
select 
	DEALSIZE, round(sum(SALES),2) as Revenue
from sales_data
group by DEALSIZE
order by 2 desc

select 
	YEAR_ID,
	DEALSIZE, round(sum(SALES),2) as Revenue
from sales_data
group by year_id,DEALSIZE
order by 3 desc

--- What was the best month for sales in a specific year? How much was earned that month
select 
	month_id,
	round(sum(SALES),2) as revenue,
	count(ORDERNUMBER) as freq_of_orders
from sales_data
where YEAR_ID = 2003
group by MONTH_ID
order by 2 desc

--- what type of product did they order frequently in November
select PRODUCTLINE,round(sum(SALES),2)as revenue,count(ORDERNUMBER) as orderfreq
from sales_data
where YEAR_ID=2003 and month_id=11
group by PRODUCTLINE
order by 2 desc

--- Who is our best customer?
--We will use the RFM technique,
--RFM is an indexing technique that uses past purchase behaviour to segment
--customers
--RFM uses 3 key metrics
--1. Recency - Last order date (how long ago was their last purchase)
--2. Frequency - Count of Total Order (how often did they purchase)
--3. Monetary value - Total spend (how much they spent)

select 
	CUSTOMERNAME,year_id,
	---min(ORDERDATE) as date_of_1st_order,
	max(ORDERDATE) as cust_recent_order_date,
	--(select max(ORDERDATE) from [dbo].[sales_data_sample]) as recent_order_date,
	DATEDIFF(DD, max(ORDERDATE), (select max(ORDERDATE) from sales_data)) as recency_days,
	count(ORDERNUMBER) as frequency_of_orders,
	sum(QUANTITYORDERED) as total_quantity_ordered,
	round(sum(SALES),2) as revenue	
from sales_data
group by CUSTOMERNAME, YEAR_ID
order by revenue desc

---N TILE
drop table if exists #rfm
;with rfm as 
(
	select 
		CUSTOMERNAME,year_id,
		max(ORDERDATE) as cust_recent_order_date,
		DATEDIFF(DD, max(ORDERDATE), (select max(ORDERDATE) from sales_data)) as recency_days,
		count(ORDERNUMBER) as frequency_of_orders,
		sum(QUANTITYORDERED) as total_quantity_ordered,
		round(sum(SALES),2) as revenue	
	from sales_data
	group by CUSTOMERNAME, year_id
),
rfm_calc as
(
	select *,
		NTILE(4) over (order by recency_days desc) as rfm_recency,
		NTILE(4) over (order by frequency_of_orders) as rfm_fequency,
		NTILE(4) over (order by revenue) as rfm_revenue
	from rfm
)
select *, rfm_recency+rfm_fequency+rfm_revenue as rfm_cell,
	cast(rfm_recency as varchar) +cast(rfm_fequency as varchar)+ cast(rfm_revenue as varchar) as rfm_cell_string
into #rfm
from rfm_calc

select * from #rfm

-- low rfm value == did not purchase recently, low frequency of orders, low revenue
-- high rfm value == purchased recently, high freuency of orders, high revenue
drop table if exists #rfmtab
select CUSTOMERNAME,YEAR_ID, rfm_recency, rfm_fequency, rfm_revenue,
	case
		when rfm_cell_string in (111, 112, 121, 122, 123, 132, 211, 212, 114, 141) then 'lost_customers' ---lost customers
		when rfm_cell_string in (133, 134, 143, 234, 244, 334, 343, 344, 144) then 'sliping away, cannot afford to lose them' ---(big spenders who haven't purchased lately)
		when rfm_cell_string in (311, 411, 331) then 'new customers'
		when rfm_cell_string in (222, 223, 233, 322) then 'potential churners'
		when rfm_cell_string in (323, 333, 321, 422, 332, 432) then 'active'
		when rfm_cell_string in (433, 434, 443, 444) then 'loyal'
	end rfm_segment
into #rfmtab
from #rfm

select CUSTOMERNAME ,YEAR_ID,rfm_segment from #rfmtab
where rfm_segment is not null

