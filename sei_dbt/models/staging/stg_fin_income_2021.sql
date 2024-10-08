
-- Load raw sales data from the CSV file

SELECT tax_year, postal_code, cast(median_income AS DOUBLE) AS median_income FROM
read_csv_auto('{{ target.external_root }}/FIN - Neighborhood Incomes 2021.csv')
WHERE median_income IS NOT NULL AND median_income <> '1.00E+05'
