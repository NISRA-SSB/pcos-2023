#edit 'covariates to include' as appropriate, and add/remove 'Reword value labels' as appropriate

library(here)
source(paste0(here(), "/code/config.R"))
source(paste0(here(), "/code/pfg_tables/Historic Data to R.R"))
source(paste0(here(), "/code/pfg_tables/PfG Historic Data Prep.R"))

if (!dir.exists(paste0(here(), "/outputs/PfG"))) {
  dir.create(paste0(here(), "/outputs/PfG"))
}

wb <- createWorkbook()

# Define all available years based on current_year value from config ####
data_years <- c(seq(2012, 2018, 2), 2019:current_year)

# Questions to analyse ####
questions <- c("TrustMedia2", "TrustAssemblyElectedBody2")

# Co-variates to include ####
co_vars <- c("LGD2014name", "URBH", "SEX", "AGE2","MS_GRP", "OwnRelig2", "LimLongStand", "Ethnic_white_other")

# Lookup table for EQUALGROUPS labels (taken from PfG documentation) ####
eq_labels <- read.xlsx(
  xlsxFile = paste0(here(), "/code/pfg_tables/Classifications_Equality Groups - Template.xlsx"),
  sheet = "Classifications_EQ - Template"
)

# Loop through questions ####

for (question in questions) {
  ## Create template of data frame ####
  
  ### for % data
  question_data <- data.frame(STATISTIC = character()) %>%
    mutate(
      `TLIST(A1)` = numeric(),
      EQUALGROUPS = character(),
      `Variable name` = character(),
      `Lower limit` = numeric(),
      VALUE = numeric(),
      `Upper limit` = numeric()
    )

  ### for n data
  question_n_data <- data.frame(STATISTIC = character()) %>%
    mutate(
      `TLIST(A1)` = numeric(),
      EQUALGROUPS = character(),
      `Variable name` = character(),
      VALUE = numeric()
    )
  
  for (year in data_years) {

  ## Select data (historic data prep reads in data from remote location) ####
  pfg_data_year <- eval((as.name(paste0("data_",year))))

    ## Run Analysis only if question is present in data ####

    if (question %in% names(pfg_data_year)) {
      ### Which weight variables to use depending on year ####

      # Set Refusals to NA
      pfg_data_year[[question]][pfg_data_year[[question]] == "Refusal"] <- NA
      
      #### NI level / Most co-vars ####
      ni_weight <- if (year == 2020) {
        "W4"
      } else if (year %in% 2012:2016) {
        "weight"
      } else {
        "W3"
      }

      #### Age co-vars ####
      age_weight <- if (year %in% 2012:2016) {
        "weight"
      } else if (year == 2020) {
        "W1a"
      } else {
        "W1"
      }

      #### Sex co-vars ####
      sex_weight <- if (year %in% 2012:2016) {
        "weight"
      } else {
        "W2"
      }

      ### Calculated weighted value for NI ####

      ni_value <- pfg_data_year %>%
        filter(!is.na(.[[question]]) & .[[question]] %in% c("Trust a great deal/Tend to trust", "Tend to trust/trust a great deal")) %>%
        pull(ni_weight) %>%
        sum() / pfg_data_year %>%
          filter(!is.na(.[[question]])) %>%
          pull(ni_weight) %>%
          sum() * 100

      ### Unweighted n for NI for year ####

      ni_n <- pfg_data_year %>%
        filter(!is.na(.[[question]])) %>%
        nrow()

      ### Confidence intervals for NI for year ####

      ni_ci <- f_confidence_interval(
        p = ni_value / 100,
        n = ni_n
      )

      ### Write NI row for year as data frame ####

      #### for % data
      ni_data <- data.frame(STATISTIC = character(1)) %>%
        mutate(
          `TLIST(A1)` = year,
          EQUALGROUPS = "N92000002",
          `Variable name` = "Northern Ireland",
          `Lower limit` = ni_ci[["lower_cl"]] * 100,
          VALUE = ni_value,
          `Upper limit` = ni_ci[["upper_cl"]] * 100
        )
      
      #### for n data
      ni_n_data <- data.frame(STATISTIC = character(1)) %>%
        mutate(
          `TLIST(A1)` = year,
          EQUALGROUPS = "N92000002",
          `Variable name` = "Northern Ireland",
          VALUE = ni_n
        )  

      ### Append this row to question_data data frame ####

      #### for % data
      question_data <- question_data %>%
        bind_rows(ni_data)
      
      #### for n data
      question_n_data <- question_n_data %>%
        bind_rows(ni_n_data)

      ### Loop through co-variates ####

      for (var in co_vars) {
        if (var %in% names(pfg_data_year)) {
          if (grepl("AGE", var)) {
            #### Reword value labels - age groups ####
            levels(pfg_data_year[[var]]) <- gsub(" ", "", levels(pfg_data_year[[var]]), fixed = TRUE) %>%
              gsub("andover", "+", .) %>%
              paste("Age", .)

            weight <- age_weight
          } else if (grepl("SEX", var)) {
            #### Reword value labels - sex ####
            pfg_data_year <- pfg_data_year %>%
              mutate(SEX = factor(SEX,
                levels = levels(SEX),
                labels = c("Sex - Male", "Sex - Female", "Refusal", "Don't Know")
              )) %>%
              filter(SEX %in% c("Sex - Male", "Sex - Female")) %>%
              mutate(SEX = factor(SEX,
                levels = c("Sex - Male", "Sex - Female")
              ))

            weight <- sex_weight
          } else {
            weight <- ni_weight
          }

          if (var == "OwnRelig2") {
            #### Reword value labels - religion ####
            new_levels <- levels(pfg_data_year$OwnRelig2)[!levels(pfg_data_year$OwnRelig2) %in% c("Refusal", "Dont know")]

            new_labels <- paste("Religion -", new_levels) %>%
              gsub("No Religion", "no religion", .)

            pfg_data_year <- pfg_data_year %>%
              filter(!OwnRelig2 %in% c("Refusal", "Dont know")) %>%
              mutate(OwnRelig2 = factor(OwnRelig2,
                levels = new_levels,
                labels = new_labels
              ))
          }

          if (var == "URBH") {
            #### Reword value labels - urban_rural ####
            pfg_data_year <- pfg_data_year %>%
              mutate(URBH = factor(URBH,
                levels = c("URBAN", "RURAL"),
                labels = c("Urban Rural - Urban", "Urban Rural - Rural")
              ))
          }
          
          if (var == "MS_GRP") {
            #### Reword value labels - marital status group ####
            pfg_data_year <- pfg_data_year %>%
              mutate(MS_GRP = factor(MS_GRP,
                                   levels = c("Single", "Married/CP", "Other"),
                                   labels = c("Marital status - Single", "Marital status - Married/Civil partnership", "Marital status - Other")
              ))
          }

          if (var == "Ethnic_white_other") {
            #### Reword value labels - ethnic group ####
            pfg_data_year <- pfg_data_year %>%
              mutate(Ethnic_white_other = factor(Ethnic_white_other,
                                     levels = c("White", "not White"),
                                     labels = c("Ethnic group - White", "Ethnic group - Other")
              ))
          }
          
          if (var == "LimLongStand") {
            #### Reword value labels - disability ####
            pfg_data_year <- pfg_data_year %>%
              mutate(LimLongStand = factor(LimLongStand,
                                                 levels = c("Limiting longstanding illness", "No Limiting longstanding illness"),
                                                 labels = c("Disability - Yes", "Disability - No")
              ))
          }
          
          #### Values to loop through ####

          co_vals <- levels(pfg_data_year[[var]])

          for (co_val in co_vals) {
            ##### Weighted p ####
            p_weighted <- pfg_data_year %>%
              filter(!is.na(.[[question]]) & .[[var]] == co_val & .[[question]] %in% c("Trust a great deal/Tend to trust", "Tend to trust/trust a great deal")) %>%
              pull(weight) %>%
              sum() / pfg_data_year %>%
                filter(!is.na(.[[question]]) & .[[var]] == co_val) %>%
                pull(weight) %>%
                sum() * 100


            ##### Unweighted n #####
            n_value <- pfg_data_year %>%
              filter(!is.na(.[[question]]) & .[[var]] == co_val) %>%
              nrow()

            ##### Confidence interval ####
            ci <- f_confidence_interval(
              p = p_weighted / 100,
              n = n_value
            )

            ##### EQUALGROUPS lookup ####

            EQUALGROUP <- if (co_val %in% eq_labels$VALUE) {
              eq_labels$CODE[eq_labels$VALUE == co_val]
            } else {
              ""
            }

            #### for % data
            new_row <- data.frame(STATISTIC = character(1)) %>%
              mutate(
                `TLIST(A1)` = year,
                EQUALGROUPS = EQUALGROUP,
                `Variable name` = co_val,
                `Lower limit` = ci[["lower_cl"]] * 100,
                VALUE = p_weighted,
                `Upper limit` = ci[["upper_cl"]] * 100
              )

            question_data <- question_data %>%
              bind_rows(new_row)
            
            #### for n data
            new_n_row <- data.frame(STATISTIC = character(1)) %>%
              mutate(
                `TLIST(A1)` = year,
                EQUALGROUPS = EQUALGROUP,
                `Variable name` = co_val,
                VALUE = n_value
              )
            
            question_n_data <- question_n_data %>%
              bind_rows(new_n_row)
          }
        }
      }
    }
  }

  ## Sort final data frame ####

  sort_order <- c("Northern Ireland")
  
  for (var in co_vars) {
    
    sort_order <- c(sort_order, levels(pfg_data_year[[var]]))
    
  }

  question_data <- question_data %>%
    mutate(`Variable name` = factor(`Variable name`,
      levels = sort_order
    )) %>%
    arrange(`Variable name`, `TLIST(A1)`)
  
  question_data_rounded <- question_data %>%
    mutate(`Lower limit` = round_half_up(`Lower limit`, 1),
           VALUE = round_half_up(VALUE, 1),
           `Upper limit` = round_half_up(`Upper limit`, 1))
  
  question_n_data <- question_n_data %>%
    mutate(`Variable name` = factor(`Variable name`,
                                    levels = sort_order
    )) %>%
    arrange(`Variable name`, `TLIST(A1)`)


  ## Write to Excel ####

  addWorksheet(wb, question, tabColour = "#00205B")

  writeDataTable(wb, question,
    x = question_data_rounded,
    tableStyle = "none",
    withFilter = FALSE
  )

  addStyle(wb, question,
    style = ns_pfg,
    rows = 2:(nrow(question_data_rounded) + 1),
    cols = 5:7,
    gridExpand = TRUE
  )

  setColWidths(wb, question,
    cols = 1:7,
    widths = c(22.86, 14.14, 12.86, 52.43, 10.14, 10.14, 10.71)
  )
  
  unrounded_sheet <- paste(substr(question, 1, 19), "(UNROUNDED)")
  
  addWorksheet(wb, unrounded_sheet, tabColour = "#3878C5")
  
  writeDataTable(wb, unrounded_sheet,
                 x = question_data,
                 tableStyle = "none",
                 withFilter = FALSE
  )
  
  addStyle(wb, unrounded_sheet,
           style = ns_pfg,
           rows = 2:(nrow(question_data) + 1),
           cols = 5:7,
           gridExpand = TRUE
  )
  
  setColWidths(wb, unrounded_sheet,
               cols = 1:7,
               widths = c(22.86, 14.14, 12.86, 52.43, 10.14, 10.14, 10.71)
  )
  
  n_sheet <- paste(substr(question, 1, 19), "(SAMPLENUM)")
  
  addWorksheet(wb, n_sheet, tabColour = "#d3d3d3")
  
  writeDataTable(wb, n_sheet,
                 x = question_n_data,
                 tableStyle = "none",
                 withFilter = FALSE
  )
  
  addStyle(wb, n_sheet,
           style = ns_n_pfg,
           rows = 2:(nrow(question_n_data) + 1),
           cols = 5:7,
           gridExpand = TRUE
  )
  
  setColWidths(wb, n_sheet,
               cols = 1:7,
               widths = c(22.86, 14.14, 12.86, 52.43, 10.14, 10.14, 10.71)
  )
  
}

xl_filename <- paste0(here(), "/outputs/PfG/PfG - Equality Groups Data (pfg covariates) with sample numbers ", current_year, ".xlsx")

saveWorkbook(wb, xl_filename, overwrite = TRUE)

openXL(xl_filename)
