import pandas as pd
from sqlalchemy import create_engine

# edit these two lines
folder = r"C:\all resumae projects\SQL-POWER BI PROJECT"
engine = create_engine("mysql+pymysql://root:Pranavmay09*@localhost:3306/Adventureworks")

files = {
    "salesorderheader":   "Sales.SalesOrderHeader.csv",
    "salesorderdetail":   "Sales.SalesOrderDetail.csv",
    "product":            "Production.Product.csv",
    "productsubcategory": "Production.ProductSubcategory.csv",
    "productcategory":    "Production.ProductCategory.csv",
    "salesterritory":     "Sales.SalesTerritory.csv",
    "customer":           "Sales.Customer.csv",
}

for table, fname in files.items():
    df = pd.read_csv(folder + "\\" + fname)
    df.columns = [c.lower() for c in df.columns]
    df.to_sql(table, engine, if_exists="replace", index=False)
    print(f"loaded {table}: {len(df)} rows")
