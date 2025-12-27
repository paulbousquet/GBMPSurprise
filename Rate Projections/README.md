Greenbook/Tealbook forecasts for the fed funds rate are publicly available through 2014. Additional data is filled in by scraping data from graphs in the Tealbooks. This is saved in `ffr_forecasts.csv`. 
* Please email me with any comments 
* The code uses interpolation to deal with some impercisions from the "visual fitting". As the last cell in the notebook shows even this is not enough (sometimes the previous Tealbook line is too close), but the errors are still relatively small and the most glaring ones are taken care of.
* The data is meant to represent average over the quarter to be consistent with the prior GB/TB data
