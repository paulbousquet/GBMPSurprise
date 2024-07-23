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

// AD forecast inclusions 

local sets gRGDP gPGDP UNEMP HSTART gIP gRGOVF

/* Merge on each sheet */ 
foreach sheet of local sets {
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


/* Use Romer & Romer target FFR values when available */ 
replace FFR = OLDTARG + DTARG if !missing(OLDTARG)
replace DFFR = DTARG if !missing(DTARG)
replace LFFR = OLDTARG if !missing(OLDTARG)

local sets gRGDP gPGDP UNEMP HSTART gIP gRGOVF
/******************************************************************************/
/* create forecast revisions                                                  */
/******************************************************************************/
    foreach vv of local sets {
        /* back-cast */ 
        gen     D`vv'B1 = `vv'B1 - `vv'B1[_n-1] /*
        */      if gbYQ == gbYQ[_n-1]
        replace D`vv'B1 = `vv'B1 - `vv'F0[_n-1] /*
        */      if gbYQ >  gbYQ[_n-1]

        /* forecast */ 
        forvalues hh=0/8 {
            local hh1 = `hh' + 1
            gen      D`vv'F`hh' = /*
            */       `vv'F`hh' - `vv'F`hh'[_n-1]  /* 
            */       if gbYQ == gbYQ[_n-1]
            replace  D`vv'F`hh' = /*
            */       `vv'F`hh' - `vv'F`hh1'[_n-1] /*
            */       if gbYQ >  gbYQ[_n-1]
        }
    }
	
	
// Matching the beginning of AD 

	drop if _n < 187
	
// Dropping variables we don't need 	
	
	forvalues i=2/4 {
		ds *B`i'
		drop `r(varlist)'
	}
	
drop gb*

order FOMCdate GBdate DATE DFFR LFFR g* Dg* U* DU* H* DH* 

keep FOMCdate-DHSTARTF8

export delimited using "GBdata.csv", replace

