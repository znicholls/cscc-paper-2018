# Compute country-level social cost of carbon
#
# Any questions: laurent.drouet@eiee.org
# Launch Rscript ./generate_cscc.R to see usage
# Check the Rmd file for an example of use
# Outputs are expressed in USD 2005

library(data.table)
library(docopt)

'usage: generate_cscc.R -s <ssp> -c <rcp> [ -r <runid> -p <type> -l <clim> -f <name>] [-a] [-o] [-d] [-w]

options:
 -s <ssp>   SSP baseline (random(default), SSP1, SSP2,..., SSP5)
 -c <rcp>   RCP (random(default), rcp45, rcp60, rcp85)
 -r <runid> Bootstart run for the damage function parameter, 0 is estimates (0<=id<=1000)
 -p <type>  projection type (constant (default),horizon2100)
 -l <clim>  climate models (ensemble (default), mean[-ensemble])
 -o         does not allow for out-of-sample damage prediction (default, allows)
 -d         rich/poor damage function specification (default, pooled)
 -a         5-lag damage function specification (default, 0-lag)
 -f <name>  damage function (default=bhm (Burke et al.), djo (Dell et al.))
 -w         save raw data' -> doc
opts <- docopt(doc)

# Some tests
#opts <- docopt(doc, "-s SSP2 -c rcp60 -w") # Default case
#opts <- docopt(doc, "-s SSP3 -c rcp85 -r 1 -w -a -d")
#opts <- docopt(doc, "-s SSP2 -c rcp60 -r 0 -l mean -w -a -d")
#opts <- docopt(doc, "-s SSP2 -c rcp60 -r 0 -w -d -f djo")

t0 <- Sys.time()

# GLOBAL VARIABLES
if (is.null(opts[["s"]])) {
  ssp = sample(paste0("SSP",1:5),1) # SSP{1,2,3,4,5}
} else {
  ssp = as.character(opts["s"])
}
if (is.null(opts[["c"]])) {
  .rcp = sample(c("rcp45","rcp60","rcp85"),1)
} else {
  .rcp = as.character(opts["c"]) 
}
if (is.null(opts[["r"]])) {
  dmg_func = "estimates" # dmg function
  runid = 0
} else {
  print(paste("r:",opts['r']))
  runid = as.integer(max(0,min(1000,as.numeric(opts['r']))))
  if (runid == 0) {
    dmg_func = "estimates"
  }else{
    dmg_func = paste0("bootstrap")
  }
}
if (is.null(opts[["p"]])) {
  project_val = "constant" # growth rate constant
} else {
  project_val = as.character(opts["p"])
}
if (is.null(opts[["l"]])) {
  clim = "ensemble"
} else {
  clim = "mean"
  if (runid != 0) {
    dmg_func = "bootstrap"
    runid = 1:1000
  }
}
if (is.null(opts[["f"]])) {
  dmg_ref = "bhm"
} else {
  dmg_ref = as.character(opts["f"])
}

out_of_sample = !opts[['o']]
rich_poor = opts[['d']]
lag5 = opts[['a']]
save_raw_data = opts[['w']]
very_last_year = 2200
impulse_year = 2020
preffdir = "res"
pulse_scale = 1e6 # Gt=1e9 Mt=1e6 kt=1e3 t=1 
reftemplastyear = F

if (dmg_ref == "djo") {
  rich_poor = T
  out_of_sample = T
  lag5 = F
  dmg_func = "estimates"
  reftemplastyear = T
}

# Print simulation paramters
print(paste("SSP: ",ssp))
print(paste("RCP: ",.rcp))
print(paste("dmg_func: ",dmg_func))
print(paste("last year: ",very_last_year))
print(paste("prefix dir: ",preffdir))
print(paste("climate ensemble: ",clim))
print(paste("impulse year: ",impulse_year))
print(paste("projection post2100: ",project_val))
print(paste("out_of_sample: ",out_of_sample))
print(paste("richpoor: ",rich_poor))
print(paste("LR (lag5): ", lag5))
print(paste("damage function:",dmg_ref))

if (dmg_ref == "bhm") {
  dmg_ref = ""
}else{
  dmg_ref = paste0("_",dmg_ref)
}

resdir = paste0(preffdir,"_stat",dmg_ref)
if (!out_of_sample) {resdir = paste0(resdir,"_30C")}
if (rich_poor) {resdir = paste0(resdir,"_richpoor")}
if (lag5) {resdir = paste0(resdir,"_lr")}

resboot = paste0(preffdir,"_boot")
if (!out_of_sample) {resboot = paste0(resboot,"_30C")}
if (rich_poor) {resboot = paste0(resboot,"_richpoor")}
if (lag5) {resboot = paste0(resboot,"_lr")}

if (dmg_func == "bootstrap" & clim == "ensemble") {
  ddd = file.path(resboot,paste0(ssp,"-",.rcp))
  filename = file.path(ddd,paste0("store_scc_",project_val,"_",runid,dmg_ref,".RData"))
  if (file.exists(filename)) {
    stop("already computed")
  }
}

# Load data 
source("modules/gdpssp.R")
if (dmg_ref == "") {
  source("modules/bhm_replica.R")
} else {
  source("modules/djo_replica.R")
}
source("modules/cmip5.R")
source("modules/impulse_response.R")
print(Sys.time() - t0)

# All combination of models available (CC x GCM for each RCP)
ssp_cmip5_models_temp <- ctemp[rcp == .rcp,unique(model)]
model_comb <- cpulse[ISO3 == "USA" & mid_year == 0.5 & 
                       model %in% ssp_cmip5_models_temp, 
                     .(model,ccmodel)]

# Future years
fyears <- impulse_year:2100

# Impulse year
cpulse[,year := mid_year - 0.5 + fyears[1]]
epulse[,year := mid_year - 0.5 + fyears[1]]

project_gdpcap_nocc <- function(SD){
  .gdpcap <- SD$gdpcap
  .gdpr <- SD$gdpr
  .gdpcap_tm1 <- SD$gdpcap[1]/(1 + SD$gdpr[1]) # gdpcap in 2019
  for (i in seq_along(c(fyears))) {
    .gdpcap[i] <- .gdpcap_tm1 * (1 + SD$gdpr[i])
    .gdpcap_tm1 <- .gdpcap[i]
  }
  return(list(year = fyears, 
              gdpcap = .gdpcap,
              gdprate = SD$gdpr,
              delta = NA))
}

project_gdpcap_cc <- function(SD){
  .gdpcap <- SD$gdpcap
  .gdprate <- SD$gdpr
  .delta <- rep(NA,length(SD$gdpr))
  .gdpcap_tm1 <- .gdpcap[1]/(1 + SD$gdpr[1]) # gdpcap nocc in 2019
  .ref_temp <- SD$temp[1] # reftemp is baseline temp for BHM and temp_tm1 for DJO
  for (i in seq_along(c(fyears))) {
    if (dmg_ref == "") {.ref_temp <- SD$basetemp[i]}
    .delta[i] <- warming_effect(SD$temp[i], .ref_temp, .gdpcap_tm1, nid)
    .gdprate[i] <- (SD$gdpr[i] + .delta[i])
    .gdpcap[i] <- .gdpcap_tm1 * (1 + .gdprate[i])
    .gdpcap_tm1 <- .gdpcap[i]
    .ref_temp <- SD$temp[i]
  }
  return(list(year = fyears, 
              gdpcap = .gdpcap,
              gdprate = .gdprate,
              delta = .delta))
}

project_gdpcap_cc_pulse <- function(SD){
  .gdpcap <- SD$gdpcap
  .gdprate <- SD$gdpr
  .delta <- rep(NA,length(SD$gdpr))
  .gdpcap_tm1 <- .gdpcap[1]/(1 + SD$gdpr[1]) # gdpcap nocc in 2019
  .ref_temp <- SD$temp[1] # reftemp is baseline temp for BHM and temp_tm1 for DJO
  for (i in seq_along(c(fyears))) {
    if (dmg_ref == "") {.ref_temp <- SD$basetemp[i]}
    .delta[i] <- warming_effect(SD$temp_pulse[i], .ref_temp, .gdpcap_tm1, nid)
    .gdprate[i] <- (SD$gdpr[i] + .delta[i])
    .gdpcap[i] <- .gdpcap_tm1 * (1 + .gdprate[i])
    .gdpcap_tm1 <- .gdpcap[i]
    .ref_temp <- SD$temp[i]
  }
  return(list(year = fyears, 
              gdpcap = .gdpcap,
              gdprate = .gdprate,
              delta = .delta))
}

# Project all scenarios
project_gdpcap <- function(SD){
  .gdpcap <- SD$gdpcap
  .gdpcap_cc <- SD$gdpcap
  .gdpcap_imp <- SD$gdpcap
  
  .gdprate_cc <- SD$gdpr
  
  .gdpcap_tm1 <- .gdpcap[1]/(1 + SD$gdpr[1]) # gdpcap nocc in 2019
  .gdpcap_tm1_cc <- .gdpcap[1]/(1 + SD$gdpr[1]) # gdpcap nocc in 2019
  .gdpcap_tm1_imp <- .gdpcap[1]/(1 + SD$gdpr[1]) # gdpcap nocc in 2019
  
  .ref_temp <- SD$temp[1] # reftemp is baseline temp for BHM and temp_tm1 for DJO
  if (!reftemplastyear) {.ref_temp <- SD$basetemp[1]}
  
  for (i in seq_along(c(fyears))) {
    # No climate change
    .gdpcap[i] <- .gdpcap_tm1 * (1 + SD$gdpr[i])
    .gdpcap_tm1 <- .gdpcap[i]
    # With climate change
    .gdprate_cc[i] <- SD$gdpr[i] + warming_effect(SD$temp[i], .ref_temp, .gdpcap_tm1_cc, nid, out_of_sample)
    .gdpcap_cc[i] <- .gdpcap_tm1_cc * (1 + .gdprate_cc[i])
    .gdpcap_tm1_cc <- .gdpcap_cc[i]
    # With climate change and pulse
    .gdpcap_imp[i] <- .gdpcap_tm1_imp * (1 + (SD$gdpr[i] + warming_effect(SD$temp_pulse[i], .ref_temp, .gdpcap_tm1_imp, nid, out_of_sample)))
    .gdpcap_tm1_imp <- .gdpcap_imp[i]
    if (reftemplastyear) {.ref_temp <- SD$temp[i]}
  }
  return(list(year = fyears, 
              gdpcap = .gdpcap,
              gdpcap_cc = .gdpcap_cc,
              gdpcap_imp = .gdpcap_imp,
              gdprate_cc = .gdprate_cc
  ))
}

lcscc = NULL
lwscc = NULL

for (nid in runid) {
  
  # Create dataset for SSP
  # ISO3 x model x ccmodel x years
  ssp_gr <- growthrate[SSP == ssp & year %in% fyears]
  if (clim == "ensemble") {
    ssp_temp <- ctemp[rcp == .rcp & year %in% fyears]
  } else {
    ssp_temp <- etemp[rcp == .rcp & year %in% fyears]
  }
  ssp_temp = merge(ssp_temp,basetemp,by = c("ISO3")) # add basetemp
  ssp_gdpr <- merge(ssp_gr,ssp_temp,by = c("ISO3","year")) # merge growth rate and temp
  ssp_gdpr = merge(ssp_gdpr, sspgdpcap[SSP == ssp & year == fyears[1]],
                   by = c("SSP","ISO3","year"),all.x = T) # add gdpcap0
  if (clim == "ensemble") {
    ssp_gdpr = merge(cpulse[model %in% ssp_cmip5_models_temp & year %in% fyears],
                     ssp_gdpr, by = c("ISO3","year","model"), all.x = T) 
    ssp_gdpr[,model_id := paste(model,ccmodel)]
  }else{
    ssp_gdpr = merge(epulse[year %in% fyears],
                     ssp_gdpr, by = c("ISO3","year"), all.x = T) 
  }
  miss_val_iso3 <- unique(ssp_gdpr[year == impulse_year & is.na(gdpcap),ISO3])
  ssp_gdpr <- ssp_gdpr[!ISO3 %in% miss_val_iso3]
  
  
  if (clim == "ensemble") {
    # keep only model combination
    model_comb[,model_id := paste(model,ccmodel)]
    ssp_gdpr <- ssp_gdpr[model_id %in% model_comb$model_id,
                         .(model_id,ISO3,year,temp,temp_pulse,basetemp,gdpr,gdpcap)]
  } else {
    ssp_gdpr <- ssp_gdpr[,.(model_id = nid,ISO3,year,temp,temp_pulse,basetemp,gdpr,gdpcap)]
  }
  ssp_gdpr[,temp_pulse := temp + temp_pulse * 1e-3 / 44 * 12 * (pulse_scale * 1e-9)]
  setkey(ssp_gdpr,model_id,ISO3)
  print(Sys.time() - t0)

  res_scc <- ssp_gdpr[,project_gdpcap(.SD),by = c("model_id","ISO3")]
  print(Sys.time() - t0)
  
  # yearly population 
  popyear <- pop[SSP == ssp,approx(year,pop,fyears),by = c("SSP","ISO3")]
  setnames(popyear,c("x","y"),c("year","pop"))
  res_scc <- merge(res_scc,popyear,by = c("ISO3","year"))
  print(Sys.time() - t0)
  
  # create main table for world
  res_wscc <- res_scc[,.(gdpcap_cc = weighted.mean(gdpcap_cc,pop)),
                      by = c("year",c("model_id"),"SSP")]
  
  # Compute average annual growth rate of per capita consumption between now and year t
  # for the computation of discount factor
  #countries
  gdprate_cc_impulse_year = res_scc[year == impulse_year,
                                    .(gdpcap_cc_impulse_year = gdpcap_cc),
                                    by = c("model_id","ISO3")]
  res_scc <- merge(res_scc,gdprate_cc_impulse_year,by = c("model_id","ISO3"))
  res_scc[, gdprate_cc_avg := ifelse(year == impulse_year,
                                     gdprate_cc,
                                     (gdpcap_cc/gdpcap_cc_impulse_year)^(1/(year - impulse_year)) - 1)]

  #World
  gdprate_cc_impulse_year = res_wscc[year == impulse_year,
                                     .(gdpcap_cc_impulse_year = gdpcap_cc),
                                     by = c("model_id")]
  res_wscc <- merge(res_wscc,gdprate_cc_impulse_year,
                    by = c("model_id"))
  res_wscc[, gdprate_cc_avg := ifelse(year == impulse_year,
                                      NA,
                                      (gdpcap_cc/gdpcap_cc_impulse_year)^(1/(year - impulse_year)) - 1)]
  res_wscc = merge(res_wscc,res_wscc[year == (impulse_year + 1),
                                     .(model_id,gdprate_cc_avg_impulse_year = gdprate_cc_avg)],
                   by = "model_id")
  res_wscc[year == impulse_year,gdprate_cc_avg := gdprate_cc_avg_impulse_year]
  res_wscc[,gdprate_cc_avg_impulse_year := NULL]
  
  print(Sys.time() - t0)
  
  # Compute SCC according to Anthoff and Tol equation A3 in Appendix
  # \dfrac {\partial C_{t}} {\partial E_{0}}\times P_{t}
  # approximate by change in GDP rather than consumption
  res_scc[, scc := -(gdpcap_imp - gdpcap_cc) * pop * (1e6 / pulse_scale)] # $2005/tCO2
  sum_res_scc = res_scc[, .(scc = sum(scc)), 
                        by = c("year",c("model_id"))]
  res_wscc = merge(res_wscc,sum_res_scc,
                   by = c("year",c("model_id")))
  
  # Extrapolation SCC (before discounting)
  extrapolate_scc <- function(SD){
    if (project_val == "horizon2100") {
      .scc = 0
      .gdprate_cc_avg = 0
    } 
    if (project_val == "constant") {
      .scc = SD[year == 2100,scc]
      .gdpr = (SD[year == 2100,gdpcap_cc]/SD[year == 2100,gdpcap_cc_impulse_year])^(1/(2100 - impulse_year)) - 1
      if (.gdpr < 0) {
        .gdprate_cc_avg = (SD[year == 2100,gdpcap_cc]/SD[year == 2100,gdpcap_cc_impulse_year])^(1/((2101:very_last_year) - impulse_year)) - 1
      } else {
        .gdprate_cc_avg = .gdpr
      }
    }
    return(list(year = 2101:very_last_year, scc = .scc, gdprate_cc_avg = .gdprate_cc_avg))
  }
  
  # combine if necessary
  if (project_val != "horizon2100") {
    res_scc_future <- res_scc[,extrapolate_scc(.SD),by = c("ISO3",c("model_id"))]
    res_wscc_future <- res_wscc[,extrapolate_scc(.SD),by = c("model_id")]
    res_scc <- rbindlist(list(res_scc,res_scc_future),fill = T)
    res_wscc <- rbindlist(list(res_wscc,res_wscc_future),fill = T)
  }
  print(Sys.time() - t0)
  
  # Discount SCC according to Anthoff and Tol equation A3 in Appendix
  # elasticity of marginal utility of consumption = 1
  # based on Table 3.2 in IPCC AR5 WG2 Chapter 3
  # added 3% prtp to be compatible with EPA
  prtps = c(2) # %
  etas = c(1.5) 
  
  cscc = NULL
  for (.prtp in prtps) {
    for (.eta in etas) {
      dscc = res_scc[,list(ISO3,model_id,year,gdprate_cc_avg,scc)]
      dscc[,dfac := (1/(1 + .prtp/100 + .eta * gdprate_cc_avg)^(year - impulse_year))]
      dscc[,dscc := dfac * scc]
      cscc = rbind(cscc,dscc[,.(prtp = .prtp,eta = .eta,scc = sum(dscc)),
                             by = c("ISO3","model_id")],fill = T)
    }
  }
  wscc = cscc[,list(scc = sum(scc)),by = c("prtp","eta","model_id")]
  
  # Comparison EPA (SC-CO2) [[http://www3.epa.gov/climatechange/EPAactivities/economics/scc.html]]
  drs = c(2.5,3,5) #%
  cscc0 = NULL
  for (.dr in drs) {
    dscc = res_scc[,list(ISO3,model_id,year,scc)]
    dscc[,dfac := (1/(1 + .dr/100)^(year - impulse_year))]
    dscc[,dscc := dfac * scc]
    cscc0 = rbind(cscc0,dscc[,.(dr = .dr,scc = sum(dscc)),
                             by = c("ISO3","model_id")])
  }
  cscc = rbindlist(list(cscc0,cscc),fill = T)
  wscc = rbindlist(list(wscc,cscc0[,.(scc = sum(scc)),
                                   by = c("dr","model_id")]),
                   fill = T)
  
  print(Sys.time() - t0)
  
  # ID to be used
  wscc[, ISO3 := "WLD"]
  cscc[, ID := paste(prtp, eta, dr, ISO3, sep = "_")]
  wscc[, ID := paste(prtp, eta, dr, ISO3, sep = "_")]
  cscc[, ID := str_replace(ID, "\\.", "p")]
  wscc[, ID := str_replace(ID, "\\.", "p")]
  
  
  lcscc = c(lcscc, list(cscc[, .(scc, ID)]))
  lwscc = c(lwscc, list(wscc[, .(scc, ID)]))
  
}

cscc = rbindlist(lcscc)
wscc = rbindlist(lwscc)

store_scc <- rbind(cscc, wscc)
store_scc_flat <- split(store_scc$scc, store_scc$ID)

print(Sys.time() - t0)

compute_stat <- function(.data) {
  res <- c(list(mean = mean(.data)),
           as.list(quantile(.data, probs = c(
             0.1, 0.25, 0.5, 0.75, 0.9
           ))))
  return(as.data.table(res))
}

# Bayesian bootstrap to check quality of statistics
#lapply(store_scc_flat, bayesboot, mean)

if (save_raw_data) {
  dir.create(file.path(resdir), recursive = T, showWarnings = F)
  filename = file.path(resdir,paste0("raw_scc_",ssp,"_",.rcp,"_",project_val,"_",dmg_func,"_clim",clim,dmg_ref,".RData"))
  save(store_scc_flat, file = filename)
}

if (dmg_func == "estimates" | clim == "mean") {
  stat_scc <- rbindlist(lapply(store_scc_flat, compute_stat))
  stat_scc$ID <- names(store_scc_flat)
  dir.create(file.path(resdir), recursive = T, showWarnings = F)
  filename = file.path(resdir,paste0("statscc_",ssp,"_",.rcp,"_",project_val,"_",dmg_func,"_clim",clim,dmg_ref,".RData"))
  save(stat_scc, file = filename)
  print(paste(filename,"saved"))
} else {
  ddd = file.path(resboot,paste0(ssp,"-",.rcp))
  dir.create(ddd, recursive = T, showWarnings = F)
  filename = file.path(ddd,paste0("store_scc_",project_val,"_",runid,dmg_ref,".RData"))
  save(store_scc_flat, file = filename)
  print(paste(filename,"saved"))
}
print(Sys.time() - t0)
print("end")
