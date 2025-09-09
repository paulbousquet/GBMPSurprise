/******************************************************************************/
/* Code to replicate and update Romer and Romer (2004) shocks                 */
/*                                                                            */
/* By: Miguel Acosta                                                          */
/******************************************************************************/

/******************************************************************************/ 
/* Preliminaries                                                              */ 
/******************************************************************************/ 
/* Update Fed-Funds target from FRED again? */ 
local reloadFFR 0

/******************************************************************************/
/* Read in Romer & Romer replication material                                 */
/******************************************************************************/
import excel using inputs/RomerandRomerDataAppendix.xls, /*
  */   first clear sheet("DATA BY MEETING")

/* Clean up dates */ 
tostring MTGDATE, replace
replace MTGDATE = "0" + MTGDATE if strlen(MTGDATE)==5
gen fomc = date(MTGDATE,"MD19Y")
replace fomc = mdy(2,11,1987) if fomc == mdy(2,12,1987)

/* Convert to numeric */ 
foreach vv of varlist RESID* GR* IG* {
    destring `vv', replace force 
}


/* Save for later */
tempfile RR
save `RR', replace 

/******************************************************************************/
/* Load FFR from FRED if desired                                              */
/******************************************************************************/
if `reloadFFR' { 
    freduse DFEDTARU DFEDTAR DFEDTARL, clear 

    /* Use target when available, and midpoint of range thereafter */ 
    gen FFR = DFEDTAR
    replace FFR = (DFEDTARU + DFEDTARL)/2 if missing(FFR)
    sort daten
    /* These are all daily series, but not available every day */ 
    gen LFFR = FFR[_n-1]
    gen DFFR = FFR - LFFR
    rename daten fomc
    keep fomc FFR DFFR LFFR
    save intermediates/FFRfred.dta, replace
}

/******************************************************************************/
/* Load Philadelphia Fed Greenbook dataset                                    */
/******************************************************************************/
/* Created in getGBdates.py*/ 
import delimited using intermediates/GBFOMCmapping.csv, /*
  */   stringcols(_all) clear case(preserve)

gen fomc   = date(FOMCdate,"YMD")

/* Merge on each sheet */ 
foreach sheet in gRGDP gPGDP UNEMP {
    preserve 
    import excel intermediates/gbweb_row_format.xlsx, clear first sheet(`sheet')
    cap tostring GBdate, replace 
    tempfile temp
    save `temp', replace
    restore
    merge 1:1 GBdate using `temp', keep(match master) nogen 
}

gen gb = date(GBdate,"YMD")

/* Will need this for determining forecast horizon */ 
gen gbYQ   = yq(year(gb),quarter(gb))

/* A few discrepancies between RR and Philly Fed                             */
/* (not correcting Philly Fed 1977 April values -- those seem to be updates) */
/* Most of these have subsequently been replaced by Philly Fed after some    */
/* correpondence                                                             */ 
replace gRGDPF2 = 0.1 if gb == mdy(12,10,1969)
replace gPGDPB1 = 3.7 if gb == mdy( 5,12,1976)
replace gRGDPB1 = 2.2 if gb == mdy( 7, 1,1987)
replace gRGDPB2 = 4.8 if gb == mdy( 7, 1,1987)
replace gRGDPB1 = 4.6 if gb == mdy( 3,22,1995)


/******************************************************************************/
/* Merge datasets                                                             */
/******************************************************************************/
/* Merge in FF target */
merge 1:1 fomc using intermediates/FFRfred.dta, keep(match master) nogen 

/* Merge in Romer & Romer data  */
merge 1:1 fomc using `RR', gen(merge_rr)

/* A couple of additions that Romer & Romer have but I cannot find in the */ 
/* original  Greenbooks -- the GBs on the Fed's website don't forecast    */
/* this far in the future                                                 */ 
replace gRGDPF2 = GRAY2 if gb == mdy(1,29,1969)
replace gPGDPF2 = GRAD2 if gb == mdy(1,29,1969)
replace gPGDPF3 = 3.5   if gb == mdy(6,18,1969)
replace gRGDPF3 = -0.1  if gb == mdy(6,18,1969)

/* Use Romer & Romer target FFR values when available */ 
replace FFR = OLDTARG + DTARG if !missing(OLDTARG)
replace DFFR = DTARG if !missing(DTARG)
replace LFFR = OLDTARG if !missing(OLDTARG)


/******************************************************************************/
/* Just to make sure that I am computing forecast revisions correctly,        */
/* replace Philly Fed forecasts in *levels* with R&R forecasts in levels,     */
/* then take differences.                                                     */
/******************************************************************************/
drop if fomc == mdy(10,6,1979)
sort fomc


/* Back-casts */ 
gen     gRGDPB1RR = gRGDPB1
replace gRGDPB1RR = GRAYM if !missing(GRAYM)

gen     gPGDPB1RR = gPGDPB1
replace gPGDPB1RR = GRADM if !missing(GRADM)

/* Forecasts */ 
foreach h in 0 1 2  { 
    gen     gRGDPF`h'RR = gRGDPF`h'
    replace gRGDPF`h'RR = GRAY`h' if !missing(GRAY`h')

    gen     gPGDPF`h'RR = gPGDPF`h'
    replace gPGDPF`h'RR = GRAD`h' if !missing(GRAD`h')
}
/* Don't have 3-quarter-ahead  from Romer and Romer  */ 
gen gRGDPF3RR = gRGDPF3
gen gPGDPF3RR = gPGDPF3

gen gRGDPF4RR = gRGDPF4
gen gPGDPF4RR = gPGDPF4

/* Unemployment rate is in levels */ 
gen UNEMPB1RR = UNEMPB1
gen UNEMPF0RR = UNEMPF0
gen UNEMPF1RR = UNEMPF1
gen UNEMPF2RR = UNEMPF2
gen UNEMPF3RR = UNEMPF3
gen UNEMPF4RR = UNEMPF4

replace UNEMPF0RR = GRAU0 if !missing(GRAU0)

/******************************************************************************/
/* create forecast revisions                                                  */
/******************************************************************************/
/* "suff" is either Philly Fed ("") or Philly-fed replaced with RR when*/
/* possible                                                            */
quietly foreach suff in "" RR {
	        /* back-cast */ 
        gen     DUNEMPB1`suff' = UNEMPB1`suff' - UNEMPB1`suff'[_n-1] /*
        */      if gbYQ == gbYQ[_n-1]
        replace DUNEMPB1`suff' = UNEMPB1`suff' - UNEMPF0`suff'[_n-1] /*
        */      if gbYQ >  gbYQ[_n-1]

        /* forecast */ 
        foreach hh in 0 1 2 3 {
            local hh1 = `hh' + 1
            gen      DUNEMPF`hh'`suff' = /*
            */       UNEMPF`hh'`suff' - UNEMPF`hh'`suff'[_n-1]  /* 
            */       if gbYQ == gbYQ[_n-1]
            replace  DUNEMPF`hh'`suff' = /*
            */       UNEMPF`hh'`suff' - UNEMPF`hh1'`suff'[_n-1] /*
            */       if gbYQ >  gbYQ[_n-1]
        }
    /* P = inflation, R = GDP */ 
    foreach vv in P R {
        /* back-cast */ 
        gen     Dg`vv'GDPB1`suff' = g`vv'GDPB1`suff' - g`vv'GDPB1`suff'[_n-1] /*
        */      if gbYQ == gbYQ[_n-1]
        replace Dg`vv'GDPB1`suff' = g`vv'GDPB1`suff' - g`vv'GDPF0`suff'[_n-1] /*
        */      if gbYQ >  gbYQ[_n-1]

        /* forecast */ 
        foreach hh in 0 1 2 3 {
            local hh1 = `hh' + 1
            gen      Dg`vv'GDPF`hh'`suff' = /*
            */       g`vv'GDPF`hh'`suff' - g`vv'GDPF`hh'`suff'[_n-1]  /* 
            */       if gbYQ == gbYQ[_n-1]
            replace  Dg`vv'GDPF`hh'`suff' = /*
            */       g`vv'GDPF`hh'`suff' - g`vv'GDPF`hh1'`suff'[_n-1] /*
            */       if gbYQ >  gbYQ[_n-1]
        }
    }
}
    
/******************************************************************************/ 
/* Create residuals                                                           */ 
/******************************************************************************/ 
/* Exact replication */ 
reg  DFFR LFFR GRADM GRAD0 GRAD1 GRAD2 IGRDM IGRD0 IGRD1 IGRD2 GRAYM /*
  */ GRAY0 GRAY1 GRAY2 IGRYM IGRY0 IGRY1 IGRY2 GRAU0 if !missing(RESID)
predict shock_rep_exact if !missing(RESID), resid

/* Using reconstructed variables -- slight differences because I */ 
/* don't have 3-quarter-ahead RR variables                       */ 
reg  DFFR LFFR gRGDPB1RR gRGDPF0RR gRGDPF1RR gRGDPF2RR DgRGDPB1RR DgRGDPF0RR /*
  */ DgRGDPF1RR DgRGDPF2RR gPGDPB1RR gPGDPF0RR gPGDPF1RR gPGDPF2RR /*
  */ DgPGDPB1RR DgPGDPF0RR DgPGDPF1RR DgPGDPF2RR UNEMPF0RR if !missing(RESID)
predict shock_rep if !missing(RESID), resid


/* Using Philly-Fed values */ 
reg DFFR LFFR gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2 UNEMPF0 if merge_rr == 3
predict shock_repsamp, resid


/* Using Philly-Fed all the way through */ 
reg DFFR LFFR gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2 UNEMPF0 
predict shock_update, resid

cor shock_* RESID

gen daten = mdy(month(fomc), 1, year(fomc))
format daten %td

drop if DATE < 1972 | DATE==.

tempfile gbs
save `gbs', replace

//import delimited "https://raw.githubusercontent.com/paulbousquet/GBMPSurprise/main/jk_source.csv", clear

import delimited "C:\Users\pblit\Downloads\jk_source.csv", clear


gen mr_fomc = date(fomc_latest, "MDY")
format mr_fomc %tdDDmonYY

gen daten = mdy(month(mr_fomc), 1, year(mr_fomc))
format daten %td

gen raw_date = date(date, "MDY")
format mr_fomc %tdDDmonYY

gen raw_daten = mdy(month(raw_date), 1, year(raw_date))
format raw_daten %td

merge m:1 daten using `gbs', nogenerate

gen mismatch = (quarter(mr_fomc) != quarter(raw_daten) | year(mr_fomc) != year(raw_daten))

replace mismatch = 1 if raw_date == 11298 | raw_date == 11578 | raw_date == 11935 /* */| raw_date == 15235 

local prefixes "gRGDP DgRGDP gPGDP DgPGDP DUNEMP"

* Loop through each prefix and perform rollover
quietly foreach prefix of local prefixes {
    * Roll B1 <- F0
    replace `prefix'B1 = `prefix'F0 if mismatch == 1
    
    * Roll forward F0, F1, F2 (F0<-F1, F1<-F2, F2<-F3)
    forvalues i = 0/2 {
        local j = `i' + 1
        replace `prefix'F`i' = `prefix'F`j' if mismatch == 1
    }
}

generate unscheduled = strpos(event, "(Unscheduled)") > 0 | strpos(event, "statement") > 0 | strpos(event, "announces") > 0

local prefixes "DgRGDP DgPGDP DUNEMP"

* Loop through each prefix and perform rollover
quietly foreach prefix of local prefixes {
    * Get list of variables that start with this prefix
    ds `prefix'*
    local varlist `r(varlist)'
    
    * Loop through each variable in the list
    foreach var of local varlist {
        replace `var' = 0 if unscheduled == 1
    }
}

replace gRGDPF3 = gRGDPF4 if mismatch == 1
replace gPGDPF3 = gPGDPF4 if mismatch == 1
replace UNEMPF0 = UNEMPF1 if mismatch == 1

 gen monthly = mofd(raw_daten)
format monthly %tm

local mr_order gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 gRGDPF3 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 gPGDPF3 UNEMPF0 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2  DUNEMPB1 DUNEMPF0 DUNEMPF1 DUNEMPF2 

reg ff4_mr `mr_order' if monthly < m(2010m1), r 

  drop if monthly >= m(2020m1) | monthly==. | ff4==.
  
  preserve 
  
  keep if e(sample)==1
  sort raw_date 
  keep ff4_mr `mr_order'
  order ff4_mr `mr_order'
export delimited using "regression_sample.csv", replace
restore

  sort raw_date
  predict res_rep, residuals 

egen rep_sum = total(res_rep), by(raw_daten)
 replace rep_sum = . if !e(sample)
 

reg ff4 gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 gRGDPF3 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 gPGDPF3 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2 UNEMPF0 

predict res, residuals 

egen res_sum = total(res), by(raw_daten)
 replace res_sum = . if !e(sample)

 collapse (firstnm) monthly res_sum rep_sum, by(raw_daten)
 
tsset monthly

tsfill, full 

insobs 1, before(1)

gen t = _n
 
tsset t
 
replace res_sum = 0 if res_sum == . 
replace rep_sum = 0 if rep_sum == . & monthly < m(2010m1)
replace rep_sum = 0 if t==1
 
arima res_sum, ar(1/12)

predict mr_ext, res


arima rep_sum, ar(1/12)

predict mr_rep, res


