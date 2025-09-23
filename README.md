# GBMPSurprise 

This repo builds on Miguel Acosta's [replication code](https://github.com/miguel-acosta/RomerRomer2004) for Romer and Romer (2004)
* `MRExtend.do` replicates and extends [Miranda-Agrippino and Ricco (2021)](https://www.dropbox.com/scl/fi/nkanvyky8fiubsazp1sib/MAIN_TransmissionMP.pdf?rlkey=toteh0er285wn2ydqlgb395g9&e=1&dl=0) with the help of data made available by [Marek Jarocinski](https://github.com/marekjarocinski)
* `updated_shocks.csv` has the output of the replication.
  * `mr_new` is the updated shock series with a tweak in how autocorrelation is handled
  * `mr_rep` is a replication of the original series. Correlation is .998; the replication files discuss some potential reasons for differences
  * `mr_ext` is the extended series with the original treatment for autocorrelation 
* `GBExtend.do` replicates the expanded series of forecasts used in the construction of the monetary shock series of [Aruoba and Drechsel (2025)](https://econweb.umd.edu/~drechsel/papers/Aruoba_Drechsel.pdf). 

