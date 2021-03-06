source(here::here("lib", "common.R"))


load_raw <- function(raw_data_dir, n_max) {
  d <- load_years(raw_data_dir, n_max)
  bundle_raw(d$data, d$loading_problems)
}


clean <- function(d, helpers) {
  enum_col_trs <- lapply(helpers$load_json("ITSS_Field_Values.json"), unlist)
  enum_col_names <- names(enum_col_trs)

  # NOTE: Enum columns should have integer values, but when encoded as
  # characters some have a trailing ".0" while some do not. We normalize this
  # here.
  for (col_name in enum_col_names) {
    d$data[[col_name]] <- parse_number(d$data[[col_name]])
  }

  tr_reason_for_stop = enum_col_trs$ReasonForStop
  tr_moving_violation = enum_col_trs$TypeOfMovingViolation

  tr_sex <- c(
    "1" = "male",
    "2" = "female"
  )

  tr_race <- c(
    "1" = "white",
    "2" = "black",
    # American Indian or Alaska Native
    "3" = "other",
    "4" = "hispanic",
    # Asian
    "5" = "asian/pacific islander",
    # Native Hawaiian or Other Pacific Islander
    "6" = "asian/pacific islander"
  )

  tr_outcome <- c(
    "1" = "citation",
    # Written Warning
    "2" = "warning",
    # Verbal Warning (stop card)
    "3" = "warning"
  )

  d$data %>%
    add_raw_colname_prefix(
      DriverRace,
      ResultOfStop,
      ReasonForStop,
      TypeOfMovingViolation
    ) %>% 
    rename(
      location = ZIP,
      # TODO(walterk): Determine whether Chicago should be removed from this
      # dataset.
      # https://app.asana.com/0/456927885748233/727769678078651
      department_name = AgencyName,
      department_id = AgencyCode,
      vehicle_make = VehicleMake,
      vehicle_year = VehicleYear,
      time = TimeOfStop
    ) %>%
    mutate(
      date_tmp = as.character(DateOfStop),
      date = coalesce(
        parse_date(date_tmp, "%m/%d/%Y"),
        parse_date(date_tmp, "%m/%d/%Y %H:%M:%S"),
        parse_date(date_tmp, "%m-%d-%Y %H:%M:%S"),
        parse_date(date_tmp, "%m-%d-%Y"),
        parse_date(date_tmp, "%Y-%m-%d %H:%M:%S"),
        parse_date(date_tmp, "%Y-%m-%d")
      ),
      subject_dob = parse_datetime(as.character(DriversYearofBirth), "%m/%d/%Y"),
      subject_yob = coalesce(
        parse_number(DriversYearofBirth),
        year(subject_dob)
      ),
      subject_age = year(date) - subject_yob,
      subject_sex = tr_sex[as.character(DriverSex)],
      subject_race = tr_race[as.character(raw_DriverRace)],
      beat = if_else(
        department_name == "ILLINOIS STATE POLICE",
        str_pad(BeatLocationOfStop, width = "2", side = "left", pad = "0"),
        BeatLocationOfStop
      ),
      # NOTE: The schema indicates that this data is vehicle specific. All
      # subject and search related columns are prefaced with Vehicle, Driver, or
      # Passenger.
      type = "vehicular",
      citation_issued = raw_ResultOfStop == 1,
      warning_issued = raw_ResultOfStop == 2 | raw_ResultOfStop == 3,
      outcome = tr_outcome[as.character(raw_ResultOfStop)],
      contraband_drugs = VehicleDrugsFound == 1
        | VehicleDrugParaphernaliaFound == 1
        | VehicleDrugAmount > 0
        | DriverPassengerDrugsFound == 1
        | DriverPassengerDrugParaphernaliaFound == 1
        | DriverPassengerDrugAmount > 0
        | PoliceDogDrugsFound == 1
        | PoliceDogDrugParaphernaliaFound == 1
        | PoliceDogDrugAmount > 0,
      contraband_weapons = VehicleWeaponFound == 1
        | DriverPassengerWeaponFound == 1
        | PoliceDogWeaponFound == 1,
      contraband_found = contraband_drugs | contraband_weapons,
      search_person = DriverSearchConducted == 1
        | PassengerSearchConducted == 1,
      search_vehicle = VehicleSearchConducted == 1
        | PoliceDogVehicleSearched == 1,
      search_conducted = search_person | search_vehicle,
      search_basis = if_else(
        PoliceDogAlertIfSniffed == 1 | PoliceDogPerformSniffOfVehicle == 1,
        "k9",
        if_else(
          VehicleConsentGiven == 1
            | DriverConsentGiven == 1
            | PassengerConsentGiven == 1,
          "consent",
          NA_character_
        )
      ),
      reason_for_stop = if_else(
        raw_ReasonForStop == 1,
        str_c_na(
          tr_reason_for_stop[as.character(raw_ReasonForStop)],
          tr_moving_violation[as.character(raw_TypeOfMovingViolation)],
          sep=": "
        ),
        tr_reason_for_stop[as.character(raw_ReasonForStop)]
      ),
      violation = reason_for_stop
    ) %>%
    standardize(d$metadata)
}
