# squirrel_poc.py

import pyspark.sql.functions as F
import pandas as pd

# Get parameters dynamically from job run
storage_account = dbutils.widgets.get("storage_account")
input_container = dbutils.widgets.get("input_container")
output_container = dbutils.widgets.get("output_container")
csv_file = dbutils.widgets.get("csv_file")

# Mount input and output containers using managed identity
input_mount = "/mnt/input"
output_mount = "/mnt/output"

# Mount input if not exists
if not any(mount.mountPoint == input_mount for mount in dbutils.fs.mounts()):
  dbutils.fs.mount(
    source = f"abfss://{input_container}@{storage_account}.dfs.core.windows.net/",
    mount_point = input_mount,
    extra_configs = {"fs.azure.account.auth.type": "MSI"}
  )

# Mount output if not exists
if not any(mount.mountPoint == output_mount for mount in dbutils.fs.mounts()):
  dbutils.fs.mount(
    source = f"abfss://{output_container}@{storage_account}.dfs.core.windows.net/",
    mount_point = output_mount,
    extra_configs = {"fs.azure.account.auth.type": "MSI"}
  )

# Load CSV from input
df = spark.read.csv(f"{input_mount}/{csv_file}", header=True, inferSchema=True)

# Process data
aggregated_df = df.groupBy("Area Name").agg(
  F.sum("Number of Squirrels").alias("Total Squirrels"),
  F.sum("Total Time (in minutes, if available)").alias("Total Observation Time")
).orderBy("Total Squirrels", ascending=False)

# Save as XLSX to output
pandas_df = aggregated_df.toPandas()
output_path = f"{output_mount}/squirrel_output.xlsx"
pandas_df.to_excel(output_path, index=False)
print(f"XLSX saved to {output_path}")