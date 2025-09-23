/******************************************************************************/
/* Code to replicate and update Romer and Romer (2004) shocks                 */
/*                                                                            */
/* By: Miguel Acosta (modified by Paul Bousquet )                                                         */
/******************************************************************************/

/******************************************************************************/ 
/* Preliminaries                                                              */ 
/******************************************************************************/ 
/* Update Fed-Funds target from FRED again? */ 

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

sort fomc

    foreach vv in gRGDP gPGDP UNEMP {
        /* back-cast */ 
       quietly gen     D`vv'B1 = `vv'B1 - `vv'B1[_n-1] /*
        */      if gbYQ == gbYQ[_n-1]
        quietly replace D`vv'B1 = `vv'B1 - `vv'F0[_n-1] /*
        */      if gbYQ >  gbYQ[_n-1]

        /* forecast */ 
        forvalues hh=0/3 {
            local hh1 = `hh' + 1
           quietly gen      D`vv'F`hh' = /*
            */       `vv'F`hh' - `vv'F`hh'[_n-1]  /* 
            */       if gbYQ == gbYQ[_n-1]
			if (`hh'<9) {
				     quietly replace  D`vv'F`hh' = /*
            */       `vv'F`hh' - `vv'F`hh1'[_n-1] /*
            */       if gbYQ >  gbYQ[_n-1]
			}
        }
    }
    
gen daten = mdy(month(fomc), 1, year(fomc))
format daten %td

drop if DATE < 1972 | DATE==.

tempfile gbs
save `gbs', replace

import delimited "https://raw.githubusercontent.com/paulbousquet/GBMPSurprise/main/jk_source.csv", clear

gen mr_fomc = date(fomc_latest, "MDY")
format mr_fomc %tdDDmonYY

gen daten = mdy(month(mr_fomc), 1, year(mr_fomc))
format daten %td

gen raw_date = date(date, "MDY")
format mr_fomc %tdDDmonYY

gen raw_daten = mdy(month(raw_date), 1, year(raw_date))
format raw_daten %td

merge m:1 daten using `gbs', nogenerate

* When an unscheduled meeting takes place in the next quarter, scroll forecasts

gen mismatch = (quarter(mr_fomc) != quarter(raw_daten) | year(mr_fomc) != year(raw_daten))

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

* "edge" cases 
replace gRGDPF3 = gRGDPF4 if mismatch == 1
replace gPGDPF3 = gPGDPF4 if mismatch == 1
replace UNEMPF0 = UNEMPF1 if mismatch == 1

* Keeping with convention to set revision variables to 0 for unscheduled 
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

 gen monthly = mofd(raw_daten)
format monthly %tm

 drop if monthly >= m(2020m1) | monthly==. | ff4==.
 
/*
MR's default procedure uses two steps. 1. project and collect residuals from forecasts
2. regress these residuals on lags of these residuals. In my view, this compounds
the generated regressor problem and is inconsistent with the learning model presented. 
So I instead include ff4 lags directly and only do one stage. One argument in favor
of the two step procedure is the aggregation can better handle the lack of forecast
updates for unscheduled meetings. 
*/
sort raw_date
gen t = _n
 
tsset t

reg ff4 gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 gRGDPF3 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 gPGDPF3 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2 UNEMPF0 L(1/12).ff4

predict mrr, residuals 

egen mr_new = total(mrr), by(raw_daten)
 replace mr_new = . if !e(sample)
 
 * instead, here is the original procedure 
 
 reg ff4 gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 gRGDPF3 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 gPGDPF3 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2 UNEMPF0 

predict res, residuals 

egen res_sum = total(res), by(raw_daten)
 replace res_sum = . if !e(sample)
 
* As a sanity check, we try to replicate the original series exactly 
 
/*
Below is a modification only for the sake of replication 

On 4 dates where there was an unscheduled meeting on the last month of a quarter (12/7/1990, 9/13/91,9/4/1992,9/17/2001) the imputed forecast is scrolled ahead as if it occurred in a different quarter. For example, UNEMPF0 in Nov 1990 is different than what's imputed for the unscheduled 12/7/1990 date. This goes against my understanding of the greenbook forecast definitions. 
*/
gen mr_mismatch = 1 if raw_date == 11298 | raw_date == 11578 | raw_date == 11935 /* */| raw_date == 15235 

local prefixes "gRGDP DgRGDP gPGDP DgPGDP DUNEMP"

* Loop through each prefix and perform rollover
quietly foreach prefix of local prefixes {
    * Roll B1 <- F0
    replace `prefix'B1 = `prefix'F0 if mr_mismatch == 1
    
    * Roll forward F0, F1, F2 (F0<-F1, F1<-F2, F2<-F3)
    forvalues i = 0/2 {
        local j = `i' + 1
        replace `prefix'F`i' = `prefix'F`j' if mr_mismatch == 1
    }
}

* "edge" cases 
replace gRGDPF3 = gRGDPF4 if mr_mismatch == 1
replace gPGDPF3 = gPGDPF4 if mr_mismatch == 1
replace UNEMPF0 = UNEMPF1 if mr_mismatch == 1

local mr_order gRGDPB1 gRGDPF0 gRGDPF1 gRGDPF2 gRGDPF3 gPGDPB1 gPGDPF0 gPGDPF1 gPGDPF2 gPGDPF3 UNEMPF0 DgRGDPB1 DgRGDPF0 DgRGDPF1 /*
  */ DgRGDPF2 DgPGDPB1 DgPGDPF0 DgPGDPF1 /*
  */ DgPGDPF2  DUNEMPB1 DUNEMPF0 DUNEMPF1 DUNEMPF2 

reg ff4_mr `mr_order' if monthly < m(2010m1), r 

  
  predict res_rep, residuals 

egen rep_sum = total(res_rep), by(raw_daten)
 replace rep_sum = . if !e(sample)
 
 collapse (firstnm) monthly mr_new res_sum rep_sum, by(raw_daten)
 
 /*
There are some minor differences with the original series.
My guess is it has to do with the AR process.
For example, if the dates where there is no shock are not
imputed with zeros, stata performs a "filtering" procedure.
My inference after trying many different approaches is some
sort of filtering was used (at least, that produces the closest
match to the original). 
I've left some lines commented out that are useful for trying different
approaches. 
*/
 
tsset monthly

tsfill, full 

insobs 1, before(1)

//gen t = _n
 
//tsset t
 
//replace res_sum = 0 if res_sum == . 
//replace rep_sum = 0 if rep_sum == . & monthly < m(2010m1)
//replace rep_sum = 0 if t==1
 
arima res_sum, ar(1/12)

predict mr_ext, res


arima rep_sum, ar(1/12)

predict mr_rep, res


drop if monthly < m(1991m1)
replace mr_new = 0 if mr_new == . & monthly > m(1991m1)
replace mr_rep = 0 if mr_rep==. & monthly < m(2010m1)
replace mr_ext = 0 if res_sum == .

export delimited monthly mr_new mr_rep mr_ext using "updated_shocks.csv", replace
