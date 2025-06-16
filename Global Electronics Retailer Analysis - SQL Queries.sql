--I. Date Prepared
	--1.Clean Unit Cost USD and Unit Price USD in the Products table
		--1A. Add new columns for numeric versions
ALTER TABLE Products
ADD Unit_Cost_Float FLOAT,
    Unit_Price_Float FLOAT;
		
		--1B. Convert and populate the numeric values
UPDATE Products
SET 
    Unit_Cost_Float = TRY_CAST(REPLACE(REPLACE([Unit_Cost_USD], '$', ''), ',', '') AS FLOAT),
    Unit_Price_Float = TRY_CAST(REPLACE(REPLACE([Unit_Price_USD], '$', ''), ',', '') AS FLOAT);

SELECT TOP 10 
    [Product_Name], 
    [Unit_Cost_USD], 
    Unit_Cost_Float, 
    [Unit_Price_USD], 
    Unit_Price_Float
FROM Products;

	--2.Clean Order_Date and Delivery_Date in the Sales table
		--2A. Add new columns with proper DATE types
ALTER TABLE dbo.Sales
ADD Order_Date_Formatted DATE,
    Delivery_Date_Formatted DATE;

UPDATE Sales
SET
Order_Date_Formatted = TRY_CAST([Order_Date] AS DATE),
Delivery_Date_Formatted = TRY_CAST([Delivery_Date] AS DATE);

UPDATE Sales
SET Delivery_Date_Formatted = 
    CASE 
        WHEN NULLIF(LTRIM(RTRIM(Delivery_Date)), '') IS NULL 
            THEN NULL
        ELSE CONVERT(DATE, Delivery_Date)
    END;

SELECT TOP 10 
    [Order_Number] 
    [Order_Date], 
    Order_Date_Formatted, 
    [Delivery_Date], 
    Delivery_Date_Formatted
FROM Sales;

	--3. Clean Birthday in Customers
SELECT 
    COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Customers';
	
		--3A. Add a cleaned date column:
ALTER TABLE Customers
ADD Birthday_Formatted DATE;

UPDATE Customers
SET Birthday_Formatted = TRY_CAST([Birthday] AS DATE);

		--3B. Add an Age column
ALTER TABLE Customers
ADD Customer_Age AS
DATEDIFF(YEAR, Birthday_Formatted, GETDATE());

		--3C. Group Customers into Age Bands
ALTER TABLE Customers
ADD Age_Band AS (
CASE 
	WHEN DATEDIFF(YEAR, Birthday_Formatted, GETDATE()) BETWEEN 18 AND 25 THEN '18-25'
	WHEN DATEDIFF(YEAR, Birthday_Formatted, GETDATE()) BETWEEN 26 AND 35 THEN '26-35'
	WHEN DATEDIFF(YEAR, Birthday_Formatted, GETDATE()) BETWEEN 36 AND 45 THEN '36-45'
	WHEN DATEDIFF(YEAR, Birthday_Formatted, GETDATE()) BETWEEN 46 AND 60 THEN '46-60'
	WHEN DATEDIFF(YEAR, Birthday_Formatted, GETDATE()) > 60 THEN '60+'
	ELSE 'UNKNOWN'
END
);
SELECT TOP 10
	[CustomerKey],
	[Birthday],
	[Birthday_Formatted],
	Customer_Age,
	Age_Band
FROM Customers;

	--4 Clean Quanity in Sales

ALTER TABLE Sales
ADD Quantity_Cleaned FLOAT;

UPDATE Sales
SET Quantity_Cleaned = TRY_CAST(Quantity AS FLOAT);

	--5.Check for missing CustomerKey, ProductKey, or StoreKey in Sales
 SELECT *
 FROM Sales
 WHERE CustomerKey IS NULL
	OR ProductKey IS NULL
	OR StoreKey IS NULL;
	
	--6. Calculate Revenue

ALTER TABLE Sales
ADD Revenue FLOAT;

UPDATE Sales
SET Revenue = ROUND(s.Quantity_Cleaned*p.Unit_Price_USD, 2)
FROM Sales AS s
	LEFT JOIN Products AS P
		ON p.ProductKey = s.ProductKey;

SELECT s.Order_Number,
       s.Quantity,
	   p.Unit_Price_USD,
	   s.Revenue
FROM Sales AS s
LEFT JOIN Products AS p 
ON p.ProductKey = s.ProductKey

	--7. Profit
ALTER TABLE Sales
ADD Profit FLOAT;

UPDATE Sales
SET Profit = ROUND(s.Revenue - p.Unit_Cost_USD, 2)
FROM Sales AS s
	LEFT JOIN Products AS p
		ON p.ProductKey = s.ProductKey

SELECT s.Order_Number,
       s.Quantity,
	   s.Profit,
	   s.Revenue
FROM Sales AS s
LEFT JOIN Products AS p 
ON p.ProductKey = s.ProductKey


--II. Data Insight
	--1.Top Products by Revenue
SELECT 
    p.Product_Name,
    SUM(s.Quantity_Cleaned) AS Total_Units_Sold,
    SUM(s.Revenue) AS Total_Revenue
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
WHERE s.StoreKey <> 0
GROUP BY p.Product_Name
ORDER BY Total_Revenue DESC;
	
	--2.Monthly Revenue and Order Trends
SELECT 
    FORMAT(Order_Date_Formatted, 'yyyy-MM') AS Order_Month,
    COUNT(DISTINCT Order_Number) AS Orders_Count,
    ROUND(SUM(Revenue), 2) AS Total_Revenue_AUD
FROM Sales
WHERE StoreKey <> 0
GROUP BY FORMAT(Order_Date_Formatted, 'yyyy-MM')
ORDER BY Order_Month;
	
	--3.Revenue by Age Band
SELECT 
    c.Age_Band,
    COUNT(DISTINCT s.Order_Number) AS Orders,
    ROUND(SUM(s.Revenue), 2) AS Total_Revenue
FROM Sales s
JOIN Customers c ON s.CustomerKey = c.CustomerKey
GROUP BY c.Age_Band
ORDER BY Total_Revenue DESC;
    
	--4.Top 10 Customers Who Contribute the Most to Revenue
SELECT 
    CustomerKey,
    SUM(Revenue) AS Total_Revenue
FROM Sales
GROUP BY CustomerKey
ORDER BY Total_Revenue DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;

	--5.What types of products does the company sell, and where are customers located?
SELECT 
    p.Category,
    COUNT(DISTINCT p.ProductKey) AS Number_of_Products,
    COUNT(DISTINCT c.CustomerKey) AS Number_of_Customers,
    c.Country
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
JOIN Customers c ON s.CustomerKey = c.CustomerKey
GROUP BY p.Category, c.Country
ORDER BY p.Category, Number_of_Customers DESC;

	--6.How delivery speed has changed month-to-month
SELECT 
    FORMAT(Order_Date_Formatted, 'yyyy-MM') AS Order_Month,
    AVG(DATEDIFF(DAY, Order_Date_Formatted, Delivery_Date_Formatted)) AS Avg_Delivery_Days
FROM Sales
WHERE Delivery_Date_Formatted IS NOT NULL AND Order_Date_Formatted IS NOT NULL
GROUP BY FORMAT(Order_Date_Formatted, 'yyyy-MM')
ORDER BY Order_Month;

	--7.Delivery Performance
SELECT 
    CASE 
        WHEN DATEDIFF(DAY, Order_Date_Formatted, Delivery_Date_Formatted) <= 7 THEN 'On Time'
        ELSE 'Late'
    END AS Delivery_Status,
    COUNT(*) AS Total_Orders
FROM Sales
WHERE Delivery_Date_Formatted IS NOT NULL
GROUP BY 
    CASE 
        WHEN DATEDIFF(DAY, Order_Date_Formatted, Delivery_Date_Formatted) <= 7 THEN 'On Time'
        ELSE 'Late'
    END;


	--8.Repeat vs One-Time Customers
WITH Customer_Orders AS (
    SELECT 
        CustomerKey,
        COUNT(DISTINCT Order_Number) AS Order_Count,
        SUM(Revenue) AS Revenue
    FROM Sales
    GROUP BY CustomerKey
)
SELECT 
    CASE 
        WHEN Order_Count = 1 THEN 'One-Time'
        ELSE 'Repeat'
    END AS Customer_Type,
    COUNT(*) AS Customers,
    ROUND(SUM(Revenue), 2) AS Total_Revenue
FROM Customer_Orders
GROUP BY 
    CASE 
        WHEN Order_Count = 1 THEN 'One-Time'
        ELSE 'Repeat'
    END;

	--9.Customer Lifetime Value Estimation
SELECT 
    CustomerKey,
    COUNT(DISTINCT Order_Number) AS Total_Orders,
    SUM(Revenue) AS Total_Revenue,
    ROUND(AVG(Revenue), 2) AS Avg_Order_Value
FROM Sales
GROUP BY CustomerKey
ORDER BY Total_Revenue DESC;

	--10.Popular Product Categories by Country
SELECT 
    st.Country,
    p.Category,
    SUM(s.Quantity_Cleaned) AS Units_Sold,
    ROUND(SUM(s.Revenue), 2) AS Total_Revenue
FROM Sales s
JOIN Products p ON s.ProductKey = p.ProductKey
JOIN Stores st ON s.StoreKey = st.StoreKey
GROUP BY st.Country, p.Category
ORDER BY st.Country, Total_Revenue DESC;
	
	--11.Identify Most Profitable Countries
SELECT 
    c.Country,
    ROUND(SUM(s.Revenue), 2) AS Total_Revenue,
    ROUND(SUM(s.Profit), 2) AS Total_Profit,
    ROUND(AVG(s.Profit/s.Revenue), 2) AS Avg_Profit_Margin
FROM Sales AS s
LEFT JOIN Customers AS c
ON c.CustomerKey =  s.CustomerKey
GROUP BY c.Country
ORDER BY Total_Profit DESC;


	--12.Top Performing Stores by avegreate order value
SELECT 
    st.StoreKey,
    st.Country,
    COUNT(DISTINCT s.Order_Number) AS Orders,
    ROUND(SUM(s.Revenue), 2) AS Total_Revenue,
    ROUND(SUM(s.Revenue) * 1.0 / COUNT(DISTINCT s.Order_Number), 2) AS Avg_Order_Value
FROM Sales s
JOIN Stores st ON s.StoreKey = st.StoreKey
WHERE s.StoreKey <> 0
GROUP BY st.StoreKey, st.Country
ORDER BY Avg_Order_Value DESC;

 --13. Most Profitable Products
SELECT 
    p.Product_Name,
    SUM(s.Quantity_Cleaned) AS total_units_sold,
    SUM(s.Revenue) AS total_revenue,
    ROUND(SUM(s.Profit),2) AS total_profit,
    ROUND(SUM(s.Profit) * 100.0 / NULLIF(SUM(s.Revenue), 0), 2) AS profit_margin_pct
FROM Products AS p
LEFT JOIN Sales AS s ON
s.ProductKey = p.ProductKey
GROUP BY p.Product_Name
ORDER BY total_profit DESC;

 --III. For Visualisation 
	
	--1.Sales Info Table
SELECT 
    Order_Number,
    Order_Date_Formatted,
    Delivery_Date_Formatted,
    CASE 
        WHEN Delivery_Date_Formatted IS NULL THEN NULL
        ELSE DATEDIFF(DAY, TRY_CAST(Order_Date AS DATE), TRY_CAST(Delivery_Date_Formatted AS DATE))
    END AS Delivery_Days,
    CASE 
        WHEN Delivery_Date_Formatted IS NULL THEN 'N/A'
        WHEN DATEDIFF(DAY, TRY_CAST(Order_Date AS DATE), TRY_CAST(Delivery_Date_Formatted AS DATE)) <= 7 THEN 'On-Time'
        ELSE 'Late'
    END AS Delivery_Status,
    CustomerKey,
    ProductKey,
    StoreKey,
    Revenue,
	Profit

FROM Sales;

	--2.Customers Info Table

WITH CustomerOrders AS (
    SELECT 
        CustomerKey,
        COUNT(DISTINCT Order_Number) AS Order_Count
    FROM Sales
    GROUP BY CustomerKey
)

SELECT
    c.CustomerKey,
    c.Country AS Customer_Country,
    c.Birthday_Formatted,
    -- Calculate Age
    DATEDIFF(YEAR, c.Birthday_Formatted, GETDATE()) AS Age,
    -- Create Age Band
    CASE
        WHEN DATEDIFF(YEAR, c.Birthday_Formatted, GETDATE()) < 20 THEN '<20'
        WHEN DATEDIFF(YEAR, c.Birthday_Formatted, GETDATE()) BETWEEN 20 AND 29 THEN '20-29'
        WHEN DATEDIFF(YEAR, c.Birthday_Formatted, GETDATE()) BETWEEN 30 AND 39 THEN '30-39'
        WHEN DATEDIFF(YEAR, c.Birthday_Formatted, GETDATE()) BETWEEN 40 AND 49 THEN '40-49'
        WHEN DATEDIFF(YEAR, c.Birthday_Formatted, GETDATE()) BETWEEN 50 AND 59 THEN '50-59'
        ELSE '60+'
    END AS Age_Band,
    -- Add Customer Type (Repeat or One-Time)
    CASE 
        WHEN co.Order_Count > 1 THEN 'Repeat'
        ELSE 'One-Time'
    END AS Customer_Type
FROM Customers c
JOIN CustomerOrders co
    ON c.CustomerKey = co.CustomerKey;

 
	--3.Products Table
SELECT 
    ProductKey,
    Product_Name,
    Category AS Product_Category,
	Subcategory AS Product_Subcategory
FROM Products;
 
	--4.Store Table
SELECT 
    StoreKey,
    Country AS Store_Country
FROM Stores;

