use adventure_works

drop table if exists salesdata
select sd.CustomerKey,od.Channel,dd.Full_Date,pd.Category,pd.Subcategory,pd.Model,pd.Standard_Cost,pd.List_Price,sd.Order_Quantity,pd.Color,sd.Sales_Amount,
	cd.Customer,td.Region,td.Country,cd.State_Province,cd.City
into salesdata
from Sales_data sd
left join Customer_data cd
on sd.CustomerKey =cd.CustomerKey
left join Product_data pd
on sd.ProductKey=pd.ProductKey
left join Date_data dd
on sd.DueDateKey=dd.DateKey
left join Territory_data td
on td.SalesTerritoryKey=sd.SalesTerritoryKey
left join SalesOrder_data od
on od.SalesOrderLineKey=sd.SalesOrderLineKey
where sd.CustomerKey!=-1

select * from salesdata

---Total sales per year
select distinct year(Full_Date) year,
	round(sum(Sales_Amount) over (partition by year(full_date)),2) total_sales
from salesdata

--Which year generated the highest revenue
select year(Full_Date), round(sum(Sales_Amount),2) TotalSales
from salesdata
group by year(Full_Date)
order by 2 desc

---Total sales by country
select distinct Country, round(sum(Sales_Amount) over(partition by country),2) TotalSales
from salesdata
order by 2 desc

---Revenue by customer
select distinct Customer,sum(cast(Order_Quantity as int)) SumOfOrders,round(sum(Sales_Amount),2) TotalSales
from salesdata
group by Customer
order by 2 desc

-- Which product category generated more revenue
select distinct Category, round(sum(Sales_Amount) over(partition by category),2) TotalSales
from salesdata
order by 2 desc

--- Which product category generated the highest revenue and in what year?
select year(Full_Date),Category,round(sum(Sales_Amount),2) TotalSales
from salesdata
group by year(Full_Date),Category
order by 3 desc

--- What was the best month for sales in 2019? How much was earned that month
select month(Full_Date) month, round(sum(Sales_Amount),2) TotalSales
from salesdata
where year(Full_Date)=2019
group by month(Full_Date)
order by 2 desc

--- what type of product did they order frequently that month
select Model,sum(cast(Order_Quantity as int)) SumOfOrders,round(sum(Sales_Amount),2) TotalSales
from salesdata
where year(Full_Date)=2019 and month(Full_Date)=11
group by Model
order by 2 desc

---What colour of product did people order most
select distinct Model,Color,sum(cast(Order_Quantity as int)) over(partition by model,color) as SumQtyOrdered
from salesdata
where color not like 'na'
order by 3 desc

--- Who are our active and loyal customers, which customers are likely to churn?
--We will use the RFM technique to answer these questions.
--RFM is an indexing technique that uses past purchase behaviour to segment
--customers
--RFM uses 3 key metrics
--1. Recency - Last order date (how long ago was their last purchase)
--2. Frequency - Count of Total Order (how often did they purchase)
--3. Monetary value - Total spend (how much they spent)

select 
	CustomerKey,
	max(Full_Date) as cust_recent_order_date,
	DATEDIFF(DD, max(Full_Date), (select max(Full_Date) from salesdata)) as recency_days,
	sum(cast(Order_Quantity as float)) as total_quantity_ordered,
	round(sum(sales_amount),2) as revenue	
from salesdata
group by CustomerKey
order by revenue desc

---N TILE
drop table if exists salesrfm
;with rfm as 
(
	select 
	CustomerKey,
	max(Full_Date) as cust_recent_order_date,
	DATEDIFF(DD, max(Full_Date), (select max(Full_Date) from salesdata)) as recency_days,
	sum(cast(Order_Quantity as float)) as total_quantity_ordered,
	round(sum(sales_amount),2) as revenue	
from salesdata
group by CustomerKey
),
rfm_calc as
(
	select *,
		NTILE(4) over (order by recency_days desc) as rfm_recency,
		NTILE(4) over (order by total_quantity_ordered) as rfm_fequency,
		NTILE(4) over (order by revenue) as rfm_revenue
	from rfm
)
select *, rfm_recency+rfm_fequency+rfm_revenue as rfm_cell,
	cast(rfm_recency as varchar) +cast(rfm_fequency as varchar)+ cast(rfm_revenue as varchar) as rfm_cell_string
into salesrfm
from rfm_calc

select * from salesrfm

-- low rfm value == did not purchase recently, low frequency of orders, low revenue
-- high rfm value == purchased recently, high freuency of orders, high revenue
drop table if exists rfmtable
select CustomerKey,rfm_cell_string,
	case
		when rfm_cell_string in (111, 112, 113, 121, 122, 123, 132, 211, 212, 114, 141,131,142) then 'not active' ---lost customers
		when rfm_cell_string in (133, 134, 143,214, 234, 244, 334, 343, 344, 144,233,213,224,124) then 'slipping away' ---(big spenders who haven't purchased lately)
		when rfm_cell_string in (311,312, 341, 411, 421, 431, 331) then 'new customer'
		when rfm_cell_string in (221,222, 223, 231, 322,242,232,241,243) then 'less active'
		when rfm_cell_string in (323, 313,324,333, 321, 422, 332, 432, 342,314,441,412) then 'active'
		when rfm_cell_string in (424, 433, 434, 443, 444,442,423,414,413) then 'loyal'
	end rfm_segment
into rfmtable
from salesrfm

select * from rfmtable
where rfm_segment is null

drop table if exists salesrfm_tab
select sd.*,rt.rfm_segment
into salesrfm_tab
from salesdata sd
left join rfmtable rt
on sd.CustomerKey=rt.CustomerKey

select * from salesrfm_tab
---Who are our loyal customers
select distinct Customer, sum(cast(Order_Quantity as int)) as SumOfOrders, round(sum(Sales_Amount),2) TotalSales
from salesrfm_tab
where rfm_segment like 'loyal'
group by Customer
order by 3 desc,1 desc

---Which customers are no longer active
select distinct Customer, sum(cast(Order_Quantity as int)) as SumOfOrders, round(sum(Sales_Amount),2) TotalSales
from salesrfm_tab
where rfm_segment like 'not active'
group by Customer

---which country has the highest number of customers that are no longer active?
select distinct Country, count(Country) Count
from salesrfm_tab
where rfm_segment like 'not active'
group by Country
order by 2 desc

---which country has the highest number of customers that are slipping way?
select distinct Country, count(Country) Count
from salesrfm_tab
where rfm_segment like 'slipping away'
group by Country
order by 2 desc

---which country has the highest number of customers that are slipping way in 2020?
select distinct Country, count(Country) Count
from salesrfm_tab
where rfm_segment like 'slipping away' and year(Full_Date)=2020
group by Country
order by 2 desc

---What  city in Australia had the highest number of customers that are slippng away in 2020
select distinct City, count(city) Count
from salesrfm_tab
where rfm_segment like 'slipping away' and year(Full_Date)=2020 and Country like 'australia'
group by city
order by 2 desc

---What  city in Australia had the highest number of customers that are not active in 2020
select distinct City, count(city) Count
from salesrfm_tab
where rfm_segment like 'not active' and year(Full_Date)=2020 and Country like 'australia'
group by City
order by 2 desc	


---TIME BASED COHORT ANALYSIS
--This is carried out to understand the behaviour of group of customers,
--we are looking out for trends, patterns

--metrics of  cohort analysis
--1. unique identifier i.e customerid
--2. initial start date i.e first date a customer made a purchase
--3. revenue

drop table if exists salescohort
select CustomerKey,
	min(Full_Date) as firstorderdate,
	DATEFROMPARTS(YEAR(min(Full_Date)),MONTH(min(Full_Date)),1) as cohortdate
into salescohort
from salesrfm_tab
group by CustomerKey

select * from salescohort

--Next we create a cohort index
--This is a representation of the number of months that has passed since the customer's
--first purchase

drop table if exists cohortretentn_tab
select ct2.*,
	cohortindex=year_diff * 12 + month_diff + 1
into cohortretentn_tab
from (
	select ct.*,
		year_diff=orderyear-cohortyear,
		month_diff=ordermonth-cohortmonth
	from(
		select sd.*,
			sc.cohortdate,
			YEAR(sd.Full_Date) orderyear,
			month(sd.Full_Date) ordermonth,
			year(sc.cohortdate) cohortyear,
			month(sc.cohortdate) cohortmonth
		from salesrfm_tab as sd
		left join salescohort as sc
		on sd.CustomerKey=sc.CustomerKey) as ct
) as ct2

select CustomerKey,cohortdate,cohortindex from cohortretentn_tab

drop table if exists final_salesdata
select cast(Full_Date as date) as orderdate,CustomerKey,Customer,Channel,Category,Subcategory,
	Model,Standard_Cost,List_Price,ordermonth,Color,Sales_Amount,Region,State_Province,City,Country,rfm_segment,cohortindex
into final_salesdata
from cohortretentn_tab 

select * from final_salesdata

--select distinct CustomerKey,
--	cohortdate,
--	cohortindex
--from cohortretentn_tab
--order by 1,3

--cohortindex 1 means the customer made their next purchase in the same month they made their first 
--purchase

---Pivot data to see the cohort table
drop table if exists cohortpivot_tab
select *
into cohortpivot_tab
from (
	select distinct CustomerKey,
		cohortdate,
		cohortindex
	from cohortretentn_tab) as cohtab
pivot(
	count(CustomerKey)
	for cohortindex in 
		([1],[2],[3],[4],[5],[6],[7],[8],[9],
		[10],[11],[12],[13])
) as pvt

select * from cohortpivot_tab
order by 1


select cohortdate ,
	(1.0 * [1]/[1] * 100) as [1], 
    1.0 * [2]/[1] * 100 as [2], 
    1.0 * [3]/[1] * 100 as [3],  
    1.0 * [4]/[1] * 100 as [4],  
    1.0 * [5]/[1] * 100 as [5], 
    1.0 * [6]/[1] * 100 as [6], 
    1.0 * [7]/[1] * 100 as [7], 
	1.0 * [8]/[1] * 100 as [8], 
    1.0 * [9]/[1] * 100 as [9], 
    1.0 * [10]/[1] * 100 as [10],   
    1.0 * [11]/[1] * 100 as [11],  
    1.0 * [12]/[1] * 100 as [12],  
	1.0 * [13]/[1] * 100 as [13]
from cohortpivot_tab
order by cohortdate
