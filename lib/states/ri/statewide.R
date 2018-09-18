source("common.R")


load_raw <- function(raw_data_dir, n_max) {
  d <- load_all_csvs(raw_data_dir, n_max = n_max)
  bundle_raw(d$data, d$loading_problems)
}


clean <- function(d, helpers) {
  tr_race <- c(
    B = "black",
    H = "hispanic",
    I = "asian/pacific islander",
    # NOTE: L corresponds to "Black Hispanic" which is mapped to "hispanic".
    # This is consistent with coding policies in other states.
    L = "hispanic",
    N = "other/unknown",
    W = "white",
    O = "other/unknown"
  )

  tr_reason_for_stop <- c(
    AP = "APB",
    CS = "Call for Service",
    EQ = "Equipment/Inspection Violation",
    MO = "Motorist Assist/Courtesy",
    OT = "Other Traffic Violation",
    RV = "Registration Violation",
    SB = "Seatbelt Violation",
    SD = "Special Detail/Directed Patrol",
    SP = "Speeding",
    SU = "Suspicious Person",
    VO = "Violation of City/Town Ordinance",
    WA = "Warrant"
  )

  tr_reason_for_search <- c(
    "A" = "Incident to Arrest",
    "C" = "Plain View",
    "I" = "Inventory/Tow",
    "O" = "Odor of Drugs/Alcohol",
    "P" = "Probable Cause",
    "R" = "Reasonable Suspicion",
    "T" = "Terry Frisk"
  )

  d$data %>%
    rename(
      # NOTE: Best lead on mapping trooper zone to location:
      # http://www.scannewengland.net/wiki/index.php?title=Rhode_Island_State_Police
      zone = Zone,
      department_id = AgencyORI,
      vehicle_make = Make,
      vehicle_model = Model
    ) %>%
    mutate(
      date = parse_date(StopDate, "%Y%m%d"),
      time = parse_time(StopTime, "%H%M"),
      subject_yob = YearOfBirth,
      subject_race = fast_tr(OperatorRace, tr_race),
      subject_sex = fast_tr(OperatorSex, tr_sex),
      # NOTE: Data received in Apr 2016 were specifically from a request for
      # vehicular stops.
      type = "vehicular",
      arrest_made = ResultOfStop == "D" | ResultOfStop == "P",
      citation_issued = ResultOfStop == "M",
      warning_issued = ResultOfStop == "W",
      outcome = first_of(
        "arrest" = arrest_made,
        "citation" = citation_issued,
        "warning" = warning_issued
      ),
      contraband_drugs = SearchResultOne == "A" | SearchResultOne == "D",
      contraband_weapons = SearchResultOne == "W",
      contraband_found = contraband_drugs | contraband_weapons,
      frisk_performed = Frisked == "Y",
      search_conducted = Searched == "Y" | frisk_performed,
      multi_search_reasons = str_c_na(
        SearchReasonOne,
        SearchReasonTwo,
        SearchReasonThree,
        sep = "|"
      ),
      search_basis = first_of(
        "plain view" = str_detect(multi_search_reasons, "C"),
        "probable cause" = str_detect(multi_search_reasons, "O|P"),
        "other" = str_detect(multi_search_reasons, "A|I|R|T"),
        "probable cause" = search_conducted
      ),
      reason_for_search = str_c_na(
        fast_tr(SearchReasonOne, tr_reason_for_search),
        fast_tr(SearchReasonTwo, tr_reason_for_search),
        fast_tr(SearchReasonThree, tr_reason_for_search),
        sep = "|"
      ),
      reason_for_search = if_else(
        reason_for_search == "",
        NA_character_,
        reason_for_search
      ),
      reason_for_stop = fast_tr(BasisForStop, tr_reason_for_stop)
    ) %>%
    standardize(d$metadata)
}