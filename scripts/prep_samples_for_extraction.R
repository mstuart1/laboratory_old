# This is a script for adding samples that are not in the laboratory database and have not been extracted yet
# library(RMySQL)
library(dplyr)
source("scripts/lab_helpers.R")


#### obtain a list of all clownfish sample ids from the Leyte database ####

# connect to leyte fieldwork db
leyte <- write_db("Leyte")

# import fish table
# select down to only sample_id numbers and remove any rows without a sample
fish <- dbReadTable(leyte, "clownfish") %>% 
  select(sample_id) %>%                      # select only the column sample_id
  filter(!is.na(sample_id)) %>%              # remove any non-sample observations
  distinct(sample_id)                        # remove any repeat sample_ids (this should not be needed)

#### compare that list to samples that have already been extracted ####

# make sure each sample_id is only represented once
fish <- distinct(fish)

#connect to laboratory db
lab <- write_db("Laboratory")

# import extraction table and reduce to only the sample_id column
extr <- dbReadTable(lab, "extraction") %>% 
  select(sample_id)
dbDisconnect(lab)
rm(lab)
# select any samples in "fish" that have been extracted in "extr" (don't know how to do "not in")
done <- fish %>% 
  filter(sample_id %in% extr$sample_id)

work <- anti_join(fish, done)

# remove samples that cannot be extracted
errors <- c("APCL12_271", "APCL13_024", "APCL13_547", "APCL13_549", "APCL13_551", "APCL13_553", "APCL14_030", "APCL14_157", "APCL14_161", "APCL14_164", "APCL14_301", "APCL14_304", "APCL14_305", "APCL14_306", "APCL14_492", "APCL14_494", "APCL15_355550", "APCL15_404305", "APCL15_405807")
rem <- work %>% 
  filter(sample_id %in% errors)
work <- anti_join(work, rem)

work <- select(work, sample_id) %>% 
  arrange(sample_id)


# how many plates would these make, 94 samples plus 2 blanks per plate
(nplates <- floor(nrow(work)/94)) # extra parenthesis are to print

# define wells
well <- 1:(96*nplates)

# separate list of samples out into plates

# insert the negative controls
a <- (nrow(work)+1)
work[a, ] <- "XXXX"

extr <- data.frame()
for (i in 1:nplates){
  c <- 94*i-93 # well 1 on a plate
  d <- 94*i-83 # 11
  e <- 94*i-82 # 12 negative control well
  f <- 94*i-81 # 13
  g <- 94*i-34 # 60
  h <- 94*i-33 # 61 negative control well
  j <- 94*i-32 # 62
  k <- 94*i + 2 # 96
  l <- 94*i - 35 # 59
  m <- 94 * i #94
  str1 <- as.data.frame(cbind(well[c:d], work[c:d,])) # 1:11
  names(str1) <- c("well", "sample_id")
  str2 <- as.data.frame(cbind(well[e], work[a,])) # because the first blank is in the 12th position
  names(str2) <- c("well", "sample_id")
  str3 <- as.data.frame(cbind(well[f:g], work[e:l,])) #13:60 in plate, 12:59 in list
  names(str3) <- c("well", "sample_id")
  str4 <- as.data.frame(cbind(well[h], work[a,])) # because the 2nd blank is in the 61st position
  names(str4) <- c("well", "sample_id")
  str5 <- as.data.frame(cbind(well[j:k], work[g:m,]))# 62:96 in plate, 60:94 in list
  names(str5) <- c("well", "sample_id")
  
  # and stick all of the rows together
  temp <- data.frame(rbind(str1, str2, str3, str4, str5))
  temp$Row <- rep(LETTERS[1:8], 12)
  temp$Col <- unlist(lapply(1:12, rep, 8))
  temp$plate <- paste("plate", i, sep = "")
  extr <- rbind(extr, temp)
  
}

# put the samples in order of extraction (with negative controls inserted)
extr <- arrange(extr, sample_id)
extr$sample_id <- as.character(extr$sample_id)

#### make a plate map of sample IDs (for knowing where to place fin clips) ####

# make a list of all of the plates
platelist <- distinct(extr, plate)
for (i in 1:nrow(platelist)){
  plate <- extr %>% 
    filter(plate == platelist[i,]) %>% 
    select(Row, Col, sample_id)
  
  platemap <- as.matrix(reshape2::acast(plate, plate[,1] ~ plate[,2]), value.var = plate[,3])
  write.csv(platemap, file = paste("./output/",Sys.Date(), "extract_map", i, ".csv", sep = ""))
}

### ONLY DO THIS ONCE ### generate extract numbers for database ####
# lab <- dbConnect(MySQL(), "Laboratory", default.file = path.expand("~/myconfig.cnf"), port = 3306, create = F, host = NULL, user = NULL, password = NULL)

# get the last number used for extract and add extraction_id
extracted <- dbReadTable(lab, "extraction")
dbDisconnect(lab)
rm(lab)

extracted <- extracted %>% 
  filter(sample_id != "XXXX")

extr <- extr %>% 
  arrange(sample_id, well) 

x <- as.numeric(max(substr(extracted$extraction_id, 2,5)))

for (i in 1:nrow(extr)){
  y <- x + well[i]
  extr$extraction_id[i] <- paste("E", y, sep = "")
}

# combine Row and Col into plate well
extr$well <- paste(extr$Row, extr$Col, sep = "")

# make a note that these are planned extracts that haven't happened yet
extr$notes <- "extracts planned for August 2017 by MRS"

# select columns for db
extr <- extr %>% 
  mutate(date = NA) %>% 
  mutate(method = "DNeasy96") %>% 
  mutate(final_vol = "200") %>% 
  mutate(quant = NA) %>% 
  mutate(gel = NA) %>% 
  mutate(correction = NA) %>%
  mutate(corr_message = NA) %>% 
  mutate(corr_editor = NA) %>% 
  mutate(corr_date = NA) %>% 
  select(extraction_id, sample_id, date, method, final_vol, quant, gel, well, plate, notes, correction, corr_message, corr_editor, corr_date)

# change plate name to match extraction range
for (i in 1:nplates){
  x <- paste("plate", i, sep = "")
  blip <- extr %>% 
    filter(plate == x)
  if (nrow(blip) > 0){
    extr <- anti_join(extr, blip) # remove these rows from extr
    a <- blip %>% filter(well == "A1") %>% select(extraction_id)
    b <- blip %>% filter(well == "H12") %>% select(extraction_id)
    blip$plate <- paste(a, "-", b, sep = "")
    extr <- rbind(extr, blip) # add rows back in to extr
  }
}
  

  
### import the extract_list into the database ####
# lab <- dbConnect(MySQL(), "Laboratory", default.file = path.expand("~/myconfig.cnf"), port = 3306, create = F, host = NULL, user = NULL, password = NULL)

dbWriteTable(lab, "extraction", extr, row.names = F, overwrite = F, append = T)

dbDisconnect(lab)
rm(lab)
