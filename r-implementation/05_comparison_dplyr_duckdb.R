# this little script shows that reading information into a database is fraught with error and complexity!


csv = 'raw_data/98-401-X2021006_English_CSV_data_BritishColumbia-utf8.csv'

db <- duckdb::dbConnect(duckdb::duckdb())

# this gives an error cuz it thinks the "SYMBOL" column is a boolean
duckdb::duckdb_read_csv(db, name = "mytable", files = csv, header = TRUE, transaction = T)



# we can force the read command to consider more rows when determining the datatypes
x = 500 # the default
while (T) {
  tryCatch({
    duckdb::duckdb_read_csv(db, name = "mytable", files = csv, header = TRUE, transaction = T, nrow.check = x)
    break
  }, error = function(e) cat("Nope! x = ", x, "\n")
  )
  x = x + 500
}


dplyr::tbl(db, "mytable") |>
  dplyr::select(SYMBOL) |>
  dplyr::count(SYMBOL) |>
  dplyr::collect()


# compare duckplyr speeds versus regular dplyr

# basically all I'm doing is reading some csv files into either memory or a duck db and running a few made up queries to see what all goes fastest.

# look at the interim_results tibble at the end to see the times.

pacman::p_load(tictoc, tidyverse)

csvs = fs::dir_ls("raw_data", regexp = "csv$") |>
  head(5)

exprs_dplyr = list(
  expr(df |>
         mutate(C1_COUNT_TOTAL = as.double(C1_COUNT_TOTAL)) |>
         group_by(CENSUS_YEAR, GEO_LEVEL, GEO_NAME) |>
         summarise(sum(C1_COUNT_TOTAL))
  ),
  expr(df |>
         mutate(C1_COUNT_TOTAL = as.double(C1_COUNT_TOTAL)) |>
         group_by(CHARACTERISTIC_NAME) |>
         summarise(sum(C1_COUNT_TOTAL))
  ),
  expr(df |>
         summarise(across(where(is.integer), sum))
  ),
  expr(df |>
         group_by(STUDY_ID) |>
         count(CITY) |>
         arrange(desc(n))
  ),
  expr(df |>
         group_by(CMA) |>
         summarise(mean = mean(CONDO))
  )
)

exprs_duck = list(
  expr(df |>
         mutate(C1_COUNT_TOTAL = as.double(C1_COUNT_TOTAL)) |>
         duckplyr::as_duckplyr_tibble() |>
         group_by(CENSUS_YEAR, GEO_LEVEL, GEO_NAME) |>
         summarise(sum(C1_COUNT_TOTAL))
  ),
  expr(df |>
         mutate(C1_COUNT_TOTAL = as.double(C1_COUNT_TOTAL)) |>
         duckplyr::as_duckplyr_tibble() |>
         group_by(CHARACTERISTIC_NAME) |>
         summarise(sum(C1_COUNT_TOTAL))
  ),
  expr(df |>
         duckplyr::as_duckplyr_tibble() |>
         summarise(across(where(is.integer), sum))
  ),
  expr(df |>
         duckplyr::as_duckplyr_tibble() |>
         group_by(STUDY_ID) |>
         count(CITY) |>
         arrange(desc(n))
  ),
  expr(df |>
         duckplyr::as_duckplyr_tibble() |>
         group_by(CMA) |>
         summarise(mean = mean(CONDO))
  )
)

exprs_duck_db = list(
  expr(tbl(db_con, "t1") |>
         mutate(C1_COUNT_TOTAL = as.double(C1_COUNT_TOTAL)) |>
         duckplyr::as_duckplyr_tibble() |>
         group_by(CENSUS_YEAR, GEO_LEVEL, GEO_NAME) |>
         summarise(sum(C1_COUNT_TOTAL))
  ),
  expr(tbl(db_con, "t2") |>
         mutate(C1_COUNT_TOTAL = as.double(C1_COUNT_TOTAL)) |>
         duckplyr::as_duckplyr_tibble() |>
         group_by(CHARACTERISTIC_NAME) |>
         summarise(sum(C1_COUNT_TOTAL))
  ),
  expr(tbl(db_con, "t3") |>
         duckplyr::as_duckplyr_tibble() |>
         summarise(across(where(is.integer), sum))
  ),
  expr(tbl(db_con, "t4") |>
         group_by(STUDY_ID) |>
         count(CITY) |>
         arrange(desc(n))
  ),
  expr(tbl(db_con, "t5") |>
         group_by(CMA) |>
         summarise(mean = mean(CONDO))
  )
)

db_con <- duckdb::dbConnect(duckdb::duckdb())

n_trials = 2 # adjust this as you like
results = tibble()

for (n in 1:n_trials) {
  cat("\nn:", n)

  interim_results = tibble(
    csv = fs::path_file(csvs),
    expr_dplyr = as.character(exprs_dplyr),
    file_size = NA_real_,
    nrow = NA_integer_,
    load_time_dplyr = NA_real_,
    load_time_duck_db = NA_real_,
    eval_time_dplyr = NA_real_,
    eval_time_duck = NA_real_,
    eval_time_duck_db = NA_real_
  )

  for (i in 1:5) {

    cat("\ni:", i, "\n")

    # read the csv into memory in R
    tic()
    df = read.csv2(csvs[i], sep = ",", quote = "\"", na.strings = "") |>
      as_tibble()
    toc(log = T)
    interim_results[i, 'load_time_dplyr'] = as.double(word(tail(tic.log(), 1, 1)))

    # run a dplyr expression on the df
    tic()
    eval(exprs_dplyr[[i]])
    toc(log = T)
    interim_results[i, 'eval_time_dplyr'] = as.double(word(tail(tic.log(), 1, 1)))

    # run a duckplyr expression on the df
    tic()
    eval(exprs_duck[[i]])
    toc(log = T)
    interim_results[i, 'eval_time_duck'] = as.double(word(tail(tic.log(), 1, 1)))

    # read the csv into the duck database
    tic()

    # see 'test nrow check.R' for the reasoning here
    if (i == 1) duckdb::duckdb_read_csv(db_con, name = paste0("t", as.character(i)), files = csvs[i], header = TRUE, transaction = T, nrow.check = 8500) else duckdb::duckdb_read_csv(db_con, name = paste0("t", as.character(i)), files = csvs[i], header = TRUE, transaction = T)
    toc(log = T)
    interim_results[i, 'load_time_duck_db'] = as.double(word(toc()$callback_msg, 1))

    # run the dbplyr expression on the database
    tic()
    eval(exprs_duck_db[[i]])
    toc(log = T)
    interim_results[i, 'eval_time_duck_db'] = as.double(word(tail(tic.log(), 1, 1)))

    interim_results[i, 'file_size'] = round(file.info(csvs[i])$size / 1e9, 2)
    interim_results[i, 'nrow'] = nrow(df)
  }
  interim_results = mutate(interim_results, n = n, .before=1)
  results = bind_rows(results, interim_results)
}



# Show how many tables in database
dbListTables(db_con)


saveRDS(results, "results.Rds")

# total time (almost)
sum(results[, 6:10]) / 60


# means
results |>
  group_by(csv) |>
  summarise(across(matches("time"), mean))

# means graphed
results |>
  group_by(csv) |>
  summarise(across(matches("time"), mean)) |>
  pivot_longer(cols = -1) |>
  mutate(is_load = str_detect(name, "load")) |>
  ggplot(aes(x=name, y=value, fill=is_load)) +
  geom_col() +
  facet_wrap(vars(csv), scales='free') +
  ggthemes::theme_clean() +
  theme(legend.position = 'none')

# snazzy histogram - maybe gives a sense of the distribution of times?
results |>
  select(n, csv, matches("time")) |>
  pivot_longer(cols = 3:7) |>
  ggplot(aes(x=value, fill=name)) +
  geom_histogram() +
  facet_wrap(vars(name, csv), scales='free') +
  ggthemes::theme_clean() +
  theme(legend.position = 'none')
