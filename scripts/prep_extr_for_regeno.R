# prep samples for digest #### 
# this script will examine the extraction table, find candidates for future digests, and place them in a digest plate plan

# because it is easiest to use a multichannel pipet to pipet from plate to plate, changing this code to arrange plate then fill holes. 10/17/2017

# connect to the database
library(dplyr)
library(ggplot2)
source("scripts/lab_helpers.R")

lab <- write_db("Laboratory")

# get a list of digested samples
dig <- dbReadTable(lab, "digest")

# for re-digesting extractions, pull db info for a list of extracts
samples <- c("E0371", "E0428", "E0270", "E0645", "E1054", "E1788", "E2317", "E1211", "E1856", "E2401", "E2462", "E2503", "E2912", "E2907", "E0380", "E0429", "E0284", "E0665", "E1045", "E1869", "E2326", "E0539", "E2350", "E2398", "E2453", "E2495") # all quants are > 3

extr <- dbReadTable(lab, "extraction") %>% 
  filter(extraction_id %in% samples) %>% 
  select(extraction_id, well, plate) %>% 
  arrange(extraction_id)

rm(dig)


# set up the plates ####

# create a destination plate
dest <- data_frame(row = rep(LETTERS[1:8], 12), col = unlist(lapply(1:12, rep, 8)))
dest <- dest %>% 
  mutate(dig_well = paste(dest$row, dest$col, sep = ""), 
    col = factor(col, levels = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12))) %>% 
  arrange(col)

# create an empty data frame
digest <- data.frame()

# make a list of source plates
src <- extr %>%
  select(plate) %>% 
  distinct() %>% 
  arrange(plate)

# for all of the plates listed in the src table
for (i in seq(nrow(src))){ 
  # find the extracts in one plate
  temp <- extr %>%
    filter(plate == src$plate[i])
  # make a list of open wells on the destination plate 
    holes <- dest %>% 
      slice(1:nrow(temp))
    # add the samples into the holes
    temp <- temp %>% 
      # add a destination well
      mutate(dig_well = holes$dig_well)
    
    dest <- anti_join(dest, temp, by = "dig_well") %>% 
      arrange(col)
    digest <- rbind(digest, temp)
}

#### ONLY DO THIS ONCE ####
# generate digest numbers for database, get the last number used for digest and add digest_id
digested <- dbReadTable(lab, "digest") %>%
  summarize(
    x = max(digest_id)
  )
digested[1,1] <- substr(digested[1,1], 2, 5)

# dbDisconnect(lab)
# rm(lab)

# add digest_id
digest <- digest %>%
  mutate(digest_id = as.numeric(digested[1,1]) + as.numeric(digest_id), 
    # add a d
    digest_id = paste("D", digest_id, sep = ""), 
    # make a note that these are planned extracts that haven't happened yet
    notes = "digests planned for November 2017 by MRS") 

# make a plate name ####
# get the first digest
a <- digest %>% filter(dig_well == "A1") %>% select(digest_id) 
# get the last digest
b <- digest %>% slice(nrow(digest):nrow(digest)) %>% select(digest_id) 
digest$dig_plate <- paste(a$digest_id, "-", b$digest_id, sep = "")

# make a plate map of where extractions should end up ####
digest <- digest %>% 
  mutate(
    dig_row = substr(dig_well, 1, 1), 
    dig_col = substr(dig_well, 2, 3)
  )
extr_dest <- as.matrix(reshape2::acast(digest,dig_row ~ dig_col, value.var = "extraction_id"))

dig_dest <- as.matrix(reshape2::acast(digest,dig_row ~ dig_col, value.var = "digest_id"))
  
# get plate maps for sources ####
# pull extraction data from db
extr <- lab %>%
  tbl("extraction") %>%
  filter(extraction_id %in% digest$extraction_id) %>%
  collect()

# get list of distinct plates
extr_plates <- extr %>%
  distinct(plate)

# need whole plates from extractions, so create a new table of all of the extracts in source plates
source <- dbReadTable(lab, "extraction") %>% 
  filter(plate %in% extr_plates$plate)

# iterate through the list of plates and make plate maps with highlighted cells to pull extract from 
for(i in seq(nrow(extr_plates))){
  temp <- source %>%
    filter(plate == extr_plates$plate[i])
  plate <- plate_from_db(temp, "extraction_id") # this will give an error if you try to do more than one plate at once
  plate <- plate %>% 
    mutate(pull = ifelse(extraction_id %in% digest$extraction_id, "Y", NA)) %>% 
    mutate(row = factor(row, levels = c("H", "G", "F", "E", "D", "C", "B", "A")), 
      col = factor(col, levels = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)))
  heatmap <- ggplot(plate, mapping = aes(x = col, y = row, fill = pull))+
    geom_tile(color = "black")
  heatmap +
    geom_text(aes(col, row, label = extraction_id), color = "black", size = 4) 
  ggsave(paste("plots/", extr_plates$plate[i], ".pdf", sep = ""))
}


# select columns for db
digest <- digest %>%
  mutate(date = NA) %>%
  mutate(vol_in = "30") %>% # the volume used in this project
  mutate(ng_in = NA) %>%
  mutate(enzymes = "PstI_MluCI") %>% # the enzymes used in this project
  mutate(final_vol = NA) %>%
  mutate(quant = NA) %>%
  mutate(correction = NA) %>%
  mutate(corr_message = NA) %>%
  mutate(corr_editor = NA) %>%
  mutate(corr_date = NA) %>%
  select(digest_id, extraction_id, date, vol_in, ng_in, enzymes, final_vol, dig_well, dig_plate, notes, correction, corr_message, corr_editor, corr_date)

digest <- digest %>%
  rename(well = dig_well, 
    plate = dig_plate)

### import the digest list into the database ####
############# BE CAREFUL #################################
# lab <- write_db("Laboratory")
#
# dbWriteTable(lab, "digest", digest, row.names = F, overwrite = F, append = T)
#
# dbDisconnect(lab)
# rm(lab)
  


