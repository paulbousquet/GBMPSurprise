# GBMPSurprise 

This repo builds on Miguel Acosta's [replication code](https://github.com/miguel-acosta/RomerRomer2004) for Romer and Romer (2004)
* `MRExtend.do` replicates and extends [Miranda-Agrippino and Ricco (2021)](https://www.dropbox.com/scl/fi/nkanvyky8fiubsazp1sib/MAIN_TransmissionMP.pdf?rlkey=toteh0er285wn2ydqlgb395g9&e=1&dl=0) with the help of data made available by the [USMPD](https://www.frbsf.org/research-and-insights/data-and-indicators/us-monetary-policy-event-study-database/) and [Marek Jarocinski](https://github.com/marekjarocinski)
* `updated_shocks.csv` has the output of the replication.
  * `mr_new` is the updated shock series with a tweak in how autocorrelation is handled
  * `mr_rep` is a replication of the original series. Correlation is .998; the replication files discuss some potential reasons for differences
  * `mr_ext` is the extended series with the original treatment for autocorrelation 
* `GBExtend.do` replicates the expanded series of forecasts used in the construction of the monetary shock series of [Aruoba and Drechsel (2025)](https://econweb.umd.edu/~drechsel/papers/Aruoba_Drechsel.pdf). 

## A Note on Data Construction 

The data in this repo represents a combination of various sources. I expect the new USMPD to become the defacto sole source of high frequency instruments going forward. I have augmented the database with data before 1994, included a few additional dates, and taken away a couple. I have also added anything necessary to fully replicate the original MR series. For the post-1994 changes (relative to the USMPD): 
* Bauer and Swanson note that the closure of financial markets means we probably should not use the 9/17/2001 surprise, but it's included here for completeness
* 11/25/2008 and 12/1/2008 are added from GFC
* 10/04/2019 is replaced with 10/11/2019
* Some 2020 (COVID) dates have been deleted (everything in March after 3/15 and 8/27)
* 6/13/2022 was added -- a Nick Timiaros article led to a more potent "surprise" than the actual press conference. 
