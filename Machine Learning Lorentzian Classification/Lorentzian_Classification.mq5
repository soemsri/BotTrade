//+------------------------------------------------------------------+
//|                                     Lorentzian_Classification.mq5|
//|                                                       @jdehorty  |
//|                                             https://tradeview.com|
//+------------------------------------------------------------------+
#property copyright "jdehorty"
#property link      "https://tradingview.com/v/WhBzgfDu/"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 18
#property indicator_plots   2

// Plot 1: Kernel Line
#property indicator_label1  "Kernel Regression"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'0x00,0x99,0x88', C'0xCC,0x33,0x11'
#property indicator_width1  2

// Plot 2: Candles (Dynamic colors)
#property indicator_label2  "Lorentzian Candles"
#property indicator_type2   DRAW_COLOR_CANDLES
#property indicator_color2  C'0x15,0xFF,0x00', C'0xCC,0x33,0x11', clrGray

//--- Input Parameters
input group "General Settings"
input int      InpNeighborsCount      = 8;                 // Neighbors Count (K)
input int      InpMaxBarsBack         = 2000;              // Max Bars Back
input int      InpFeatureCount        = 5;                 // Feature Count (2-5)
input int      InpColorCompression    = 1;                 // Color Compression (1-10)
input bool     InpShowExits           = false;             // Show Default Exits
input bool     InpUseDynamicExits     = false;             // Use Dynamic Exits

input group "Filters"
input bool     InpUseVolatilityFilter = true;              // Use Volatility Filter
input bool     InpUseRegimeFilter     = true;              // Use Regime Filter
input bool     InpUseAdxFilter        = false;             // Use ADX Filter
input double   InpRegimeThreshold     = -0.1;              // Regime Threshold
input int      InpAdxThreshold        = 20;                // ADX Threshold
input bool     InpUseEmaFilter        = false;             // Use EMA Filter
input int      InpEmaPeriod           = 200;               // EMA Period
input bool     InpUseSmaFilter        = false;             // Use SMA Filter
input int      InpSmaPeriod           = 200;               // SMA Period

input group "Kernel Settings"
input bool     InpUseKernelFilter     = true;              // Trade with Kernel
input bool     InpShowKernelEstimate  = true;              // Show Kernel Estimate
input bool     InpUseKernelSmoothing   = false;             // Enhance Kernel Smoothing
input int      InpH                   = 8;                 // Lookback Window
input double   InpR                   = 8.0;               // Relative Weighting (r)
input int      InpX                   = 25;                // Regression Level
input int      InpLag                 = 2;                 // Lag

input group "LINE Alerts"
input string   InpLineToken           = "";                // LINE Channel Access Token
input string   InpLineUserId          = "";                // LINE User ID / Group ID (Optional)

//--- Buffers
double BufferKernelLine[];
double BufferKernelColor[];
double BufferCandleOpen[];
double BufferCandleHigh[];
double BufferCandleLow[];
double BufferCandleClose[];
double BufferCandleColor[];

//--- Global Variables for Indicators
int handleRsi14, handleRsi9, handleCci20, handleAdx20, handleEmaFilter, handleSmaFilter, handleAtr1, handleAtr10;
double arrRsi14[], arrRsi9[], arrCci20[], arrAdx20[], arrEmaFilter[], arrSmaFilter[], arrAtr1[], arrAtr10[];

//--- Dynamic Arrays for Features & Labels
double f1_clean[], f2_clean[], f3_clean[], f4_clean[], f5_clean[];
double y_train[];
double y_train_cache[];

//--- WaveTrend Persistent Buffers
double wt_ema1[], wt_ema2[], wt_ci[], wt_wt1[], wt_wt2[];

//--- Running Min/Max for Normalization
double cci_min = 10e10, cci_max = -10e10;
double wt_min = 10e10, wt_max = -10e10;

//--- Precalculated Kernel Weights
double rq_weights[];
double ga_weights[];

//--- Asynchronous Alert Variables
datetime lastAlertTime = 0;

//--- Structure for nearest neighbors classification
struct Neighbor {
   double distance;
   int prediction;
};

//+------------------------------------------------------------------+
//| Custom functions for math & indicators                           |
//+------------------------------------------------------------------+
double math_pow(double base, double exponent) { return MathPow(base, exponent); }
double math_abs(double val) { return MathAbs(val); }
double math_log(double val) { return MathLog(val); }
double math_exp(double val) { return MathExp(val); }

//--- Rational Quadratic Kernel
double rationalQuadratic(const double &src[], int index, int lookback, double relativeWeight, int startAtBar) {
   double currentWeight = 0.0;
   double cumulativeWeight = 0.0;
   int size = ArraySize(src);
   int limit = MathMin(size - 1, index + lookback + startAtBar);
   
   for(int i = index; i <= limit; i++) {
      int relative_index = i - index;
      double y = src[i];
      double w = (relative_index < ArraySize(rq_weights)) ? rq_weights[relative_index] : 0.0;
      currentWeight += y * w;
      cumulativeWeight += w;
   }
   return cumulativeWeight > 0 ? (currentWeight / cumulativeWeight) : src[index];
}

//--- Gaussian Kernel
double gaussian(const double &src[], int index, int lookback, int startAtBar) {
   double currentWeight = 0.0;
   double cumulativeWeight = 0.0;
   int size = ArraySize(src);
   int limit = MathMin(size - 1, index + lookback + startAtBar);
   
   for(int i = index; i <= limit; i++) {
      int relative_index = i - index;
      double y = src[i];
      double w = (relative_index < ArraySize(ga_weights)) ? ga_weights[relative_index] : 0.0;
      currentWeight += y * w;
      cumulativeWeight += w;
   }
   return cumulativeWeight > 0 ? (currentWeight / cumulativeWeight) : src[index];
}

//--- Asynchronous LINE Sender
void SendLineNotification(string message) {
   if(InpLineToken == "") return;
   
   // Create custom chart event to be processed asynchronously by a helper EA
   // We will broadcast a Custom Event: Event ID = 0x87E2
   EventChartCustom(0, 0x87E2, 0, 0.0, message);
}

// Note: CalculateWaveTrend has been optimized out into incremental O(1) buffers wt_wt1 and wt_wt2.

//+------------------------------------------------------------------+
//| Indicator Initialization                                         |
//+------------------------------------------------------------------+
int OnInit() {
   // Set up Buffer Mapping
   SetIndexBuffer(0, BufferKernelLine, INDICATOR_DATA);
   SetIndexBuffer(1, BufferKernelColor, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, BufferCandleOpen, INDICATOR_DATA);
   SetIndexBuffer(3, BufferCandleHigh, INDICATOR_DATA);
   SetIndexBuffer(4, BufferCandleLow, INDICATOR_DATA);
   SetIndexBuffer(5, BufferCandleClose, INDICATOR_DATA);
   SetIndexBuffer(6, BufferCandleColor, INDICATOR_COLOR_INDEX);
   
   SetIndexBuffer(7, f1_clean, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, f2_clean, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, f3_clean, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, f4_clean, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, f5_clean, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, y_train, INDICATOR_CALCULATIONS);
   
   SetIndexBuffer(13, wt_ema1, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, wt_ema2, INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, wt_ci, INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, wt_wt1, INDICATOR_CALCULATIONS);
   SetIndexBuffer(17, wt_wt2, INDICATOR_CALCULATIONS);
   
   // Plot settings
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_COLOR_LINE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_COLOR_CANDLES);
   
   // Clean up any orphaned display tables
   TableDelete();
   
   // Initialize Indicators
   PrintFormat("LDC INIT PARAMETERS RECEIVED: InpNeighborsCount=%d, InpMaxBarsBack=%d, InpFeatureCount=%d, InpColorCompression=%d", 
               InpNeighborsCount, InpMaxBarsBack, InpFeatureCount, InpColorCompression);
   
    handleRsi14 = iRSI(Symbol(), Period(), 14, PRICE_CLOSE);
    handleRsi9  = iRSI(Symbol(), Period(), 9, PRICE_CLOSE);
    handleCci20 = iCCI(Symbol(), Period(), 20, PRICE_CLOSE);
    handleAdx20 = iADX(Symbol(), Period(), 20);
    handleAtr1  = iATR(Symbol(), Period(), 1);
    handleAtr10 = iATR(Symbol(), Period(), 10);
    
    if(InpUseEmaFilter) handleEmaFilter = iMA(Symbol(), Period(), InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    if(InpUseSmaFilter) handleSmaFilter = iMA(Symbol(), Period(), InpSmaPeriod, 0, MODE_SMA, PRICE_CLOSE);
     
   // Precalculate Kernel Weights
   int rq_size = InpH + InpX + 1;
   ArrayResize(rq_weights, rq_size);
   double k_rq = math_pow(InpH, 2) * 2.0 * InpR;
   for(int i = 0; i < rq_size; i++) {
      rq_weights[i] = math_pow(1.0 + (math_pow(i, 2) / k_rq), -InpR);
   }
   
   int ga_size = (InpH - InpLag) + InpX + 1;
   ArrayResize(ga_weights, ga_size);
   double k_ga = 2.0 * math_pow(InpH - InpLag, 2);
   for(int i = 0; i < ga_size; i++) {
      ga_weights[i] = k_ga > 0 ? math_exp(-math_pow(i, 2) / k_ga) : 0.0;
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Indicator Deinitialization                                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   TableDelete();
}

//+------------------------------------------------------------------+
//| Main Iteration Calculations                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) 
{
   if(rates_total < 300) return(0);
   
   // Prepare timeseries order (0 is current bar, oldest is rates_total - 1)
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   
   // Determine start index for calculations
   int limit = rates_total - prev_calculated;
   if(limit <= 0) {
      if(MQLInfoInteger(MQL_TESTER)) return(rates_total);
      limit = 1;
   } else if(prev_calculated > 0) {
      limit = 2;
   }
   if(prev_calculated == 0) limit = rates_total - 250;
   
   // Sync Indicators Buffers
    if(CopyBuffer(handleRsi14, 0, 0, rates_total, arrRsi14) < 0 ||
       CopyBuffer(handleRsi9, 0, 0, rates_total, arrRsi9) < 0 ||
       CopyBuffer(handleCci20, 0, 0, rates_total, arrCci20) < 0 ||
       CopyBuffer(handleAdx20, 0, 0, rates_total, arrAdx20) < 0 ||
       CopyBuffer(handleAtr1, 0, 0, rates_total, arrAtr1) < 0 ||
       CopyBuffer(handleAtr10, 0, 0, rates_total, arrAtr10) < 0) {
       return(0);
    }
    ArraySetAsSeries(arrRsi14, true);
    ArraySetAsSeries(arrRsi9, true);
    ArraySetAsSeries(arrCci20, true);
    ArraySetAsSeries(arrAdx20, true);
    ArraySetAsSeries(arrAtr1, true);
    ArraySetAsSeries(arrAtr10, true);
    ArraySetAsSeries(f1_clean, true);
    ArraySetAsSeries(f2_clean, true);
    ArraySetAsSeries(f3_clean, true);
    ArraySetAsSeries(f4_clean, true);
    ArraySetAsSeries(f5_clean, true);
    ArraySetAsSeries(y_train, true);
    ArraySetAsSeries(wt_ema1, true);
    ArraySetAsSeries(wt_ema2, true);
    ArraySetAsSeries(wt_ci, true);
    ArraySetAsSeries(wt_wt1, true);
    ArraySetAsSeries(wt_wt2, true);
    
    // Set Indicator Buffers as Series
    ArraySetAsSeries(BufferKernelLine, true);
    ArraySetAsSeries(BufferKernelColor, true);
    ArraySetAsSeries(BufferCandleOpen, true);
    ArraySetAsSeries(BufferCandleHigh, true);
    ArraySetAsSeries(BufferCandleLow, true);
    ArraySetAsSeries(BufferCandleClose, true);
    ArraySetAsSeries(BufferCandleColor, true);
    
    ArrayResize(y_train_cache, rates_total);
    ArraySetAsSeries(y_train_cache, true);
    
    if(prev_calculated == 0) {
       PrintFormat("LDC INIT DEBUG: rates_total=%d | handleCci20=%d | arrRsi14[0..2]=%.2f,%.2f,%.2f | arrCci20[0..2]=%.2f,%.2f,%.2f | arrAdx20[0..2]=%.2f,%.2f,%.2f",
                   rates_total, handleCci20, arrRsi14[0], arrRsi14[1], arrRsi14[2], arrCci20[0], arrCci20[1], arrCci20[2], arrAdx20[0], arrAdx20[1], arrAdx20[2]);
    }
   
   if(InpUseEmaFilter) {
      CopyBuffer(handleEmaFilter, 0, 0, rates_total, arrEmaFilter);
      ArraySetAsSeries(arrEmaFilter, true);
   }
   if(InpUseSmaFilter) {
      CopyBuffer(handleSmaFilter, 0, 0, rates_total, arrSmaFilter);
      ArraySetAsSeries(arrSmaFilter, true);
   }
   
   // Prepare Dynamic Caches for Features
   double hlc3[];
   ArrayResize(hlc3, rates_total);
   for(int i = 0; i < rates_total; i++) {
      hlc3[i] = (high[i] + low[i] + close[i]) / 3.0;
   }
   
   //--- Step 1: Precalculate WaveTrend in a single chronological pass
   if(prev_calculated == 0) {
      int oldest_idx = rates_total - 1;
      wt_ema1[oldest_idx] = hlc3[oldest_idx];
      wt_ema2[oldest_idx] = 0.0;
      wt_ci[oldest_idx] = 0.0;
      wt_wt1[oldest_idx] = 0.0;
      wt_wt2[oldest_idx] = 0.0;
      
      double k1 = 2.0 / (10.0 + 1.0);
      double k2 = 2.0 / (11.0 + 1.0);
      for(int i = oldest_idx - 1; i >= 0; i--) {
         wt_ema1[i] = (hlc3[i] * k1) + (wt_ema1[i+1] * (1.0 - k1));
         wt_ema2[i] = (math_abs(hlc3[i] - wt_ema1[i]) * k1) + (wt_ema2[i+1] * (1.0 - k1));
         wt_ci[i] = wt_ema2[i] > 0 ? ((hlc3[i] - wt_ema1[i]) / (0.015 * wt_ema2[i])) : 0.0;
         wt_wt1[i] = (wt_ci[i] * k2) + (wt_wt1[i+1] * (1.0 - k2));
      }
      
      for(int i = oldest_idx; i >= 0; i--) {
         if(i + 3 < rates_total) {
            wt_wt2[i] = (wt_wt1[i] + wt_wt1[i+1] + wt_wt1[i+2] + wt_wt1[i+3]) / 4.0;
         } else {
            wt_wt2[i] = wt_wt1[i];
         }
      }
   } else {
      int start_idx = limit;
      if(start_idx >= rates_total) start_idx = rates_total - 1;
      
      double k1 = 2.0 / (10.0 + 1.0);
      double k2 = 2.0 / (11.0 + 1.0);
      for(int i = start_idx; i >= 0; i--) {
         wt_ema1[i] = (hlc3[i] * k1) + (wt_ema1[i+1] * (1.0 - k1));
         wt_ema2[i] = (math_abs(hlc3[i] - wt_ema1[i]) * k1) + (wt_ema2[i+1] * (1.0 - k1));
         wt_ci[i] = wt_ema2[i] > 0 ? ((hlc3[i] - wt_ema1[i]) / (0.015 * wt_ema2[i])) : 0.0;
         wt_wt1[i] = (wt_ci[i] * k2) + (wt_wt1[i+1] * (1.0 - k2));
      }
      
      for(int i = start_idx; i >= 0; i--) {
         if(i + 3 < rates_total) {
            wt_wt2[i] = (wt_wt1[i] + wt_wt1[i+1] + wt_wt1[i+2] + wt_wt1[i+3]) / 4.0;
         } else {
            wt_wt2[i] = wt_wt1[i];
         }
      }
   }

   int limit_features = (prev_calculated == 0) ? rates_total - 1 : limit - 1;
   for(int i = limit_features; i >= 0; i--) {
      // Feature 1: RSI (14) rescaled to 0-1
      f1_clean[i] = arrRsi14[i] / 100.0;
      
      // Feature 2: WaveTrend (10, 11) normalized
      double wt_diff = wt_wt1[i] - wt_wt2[i];
      wt_min = fmin(wt_diff, wt_min);
      wt_max = fmax(wt_diff, wt_max);
      f2_clean[i] = (wt_max - wt_min > 1e-10) ? ((wt_diff - wt_min) / (wt_max - wt_min)) : 0.5;
      
      // Feature 3: CCI (20) normalized
      double cci_val = arrCci20[i];
      if(cci_val != EMPTY_VALUE && cci_val > -100000.0 && cci_val < 100000.0) {
         cci_min = fmin(cci_val, cci_min);
         cci_max = fmax(cci_val, cci_max);
         f3_clean[i] = (cci_max - cci_min > 1e-10) ? ((cci_val - cci_min) / (cci_max - cci_min)) : 0.5;
      } else {
         f3_clean[i] = 0.5;
      }
      
      // Feature 4: ADX (20) rescaled
      f4_clean[i] = arrAdx20[i] / 100.0;
      
      // Feature 5: RSI (9) rescaled
      f5_clean[i] = arrRsi9[i] / 100.0;
      
      // Training label: went up = 1 (bullish), went down = -1 (bearish)
      // Note: index i-4 is 4 bars in the FUTURE relative to bar i since index 0 is newest.
      if(i - 4 >= 0) {
         y_train_cache[i] = (close[i-4] > close[i]) ? 1.0 : ((close[i-4] < close[i]) ? -1.0 : 0.0);
      } else {
         y_train_cache[i] = 0.0;
      }
      y_train[i] = y_train_cache[i];
   }
   
   if(prev_calculated == 0) {
      PrintFormat("LDC INIT DEBUG: y_train[0..5]=%.1f,%.1f,%.1f,%.1f,%.1f,%.1f | close[0..5]=%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
                  y_train[0], y_train[1], y_train[2], y_train[3], y_train[4], y_train[5], close[0], close[1], close[2], close[3], close[4], close[5]);
   }
   
   // Variables for Stats tracking
   int wins = 0, losses = 0, total_trades = 0;
   
   // Step 2: Main Calculation Loop (Newest to Oldest)
   for(int index = limit - 1; index >= 0; index--) {
      //--- Volatility Filter
      double recentAtr = arrAtr1[index];
      double historicalAtr = arrAtr10[index];
      bool volatilityPass = !InpUseVolatilityFilter || (recentAtr > historicalAtr);
      
      //--- ADX Filter
      bool adxPass = !InpUseAdxFilter || (arrAdx20[index] > InpAdxThreshold);
      
      //--- Regime Filter (Slope of Rational Quadratic Kernel)
      double rq1 = rationalQuadratic(close, index, InpH, InpR, InpX);
      double rq2 = rationalQuadratic(close, index + 1, InpH, InpR, InpX);
      double slope = rq1 - rq2;
      bool regimePass = !InpUseRegimeFilter || (slope >= InpRegimeThreshold);
      
      bool filter_all = volatilityPass && adxPass && regimePass;
      
      //--- Trend Filters (EMA & SMA)
      bool emaPassBuy = !InpUseEmaFilter || (close[index] > arrEmaFilter[index]);
      bool emaPassSell = !InpUseEmaFilter || (close[index] < arrEmaFilter[index]);
      bool smaPassBuy = !InpUseSmaFilter || (close[index] > arrSmaFilter[index]);
      bool smaPassSell = !InpUseSmaFilter || (close[index] < arrSmaFilter[index]);
      
      //--- CORE k-NN Classification in Lorentzian Space
      double distances[];
      int predictions[];
      ArrayResize(distances, 0);
      ArrayResize(predictions, 0);
      
      double lastDistance = -1.0;
      int sizeLoop = MathMin(InpMaxBarsBack - 1, rates_total - 20);
      
      for(int i = index + 4; i < sizeLoop; i++) {
         if(i % 4 == 0) continue; // Chronological spacing rule!
         
         // Calculate Lorentzian distance
         double d = 0.0;
         if(InpFeatureCount >= 2) {
            d += math_log(1.0 + math_abs(f1_clean[index] - f1_clean[i]));
            d += math_log(1.0 + math_abs(f2_clean[index] - f2_clean[i]));
         }
         if(InpFeatureCount >= 3) {
            d += math_log(1.0 + math_abs(f3_clean[index] - f3_clean[i]));
         }
         if(InpFeatureCount >= 4) {
            d += math_log(1.0 + math_abs(f4_clean[index] - f4_clean[i]));
         }
         if(InpFeatureCount >= 5) {
            d += math_log(1.0 + math_abs(f5_clean[index] - f5_clean[i]));
         }
         
         if(index == 1 && i <= 8) {
            PrintFormat("LDC LOOP i=%d: d=%.6f, lastDist=%.6f, f1_idx=%.4f, f1_i=%.4f, f3_idx=%.4f, f3_i=%.4f", 
                        i, d, lastDistance, f1_clean[index], f1_clean[i], f3_clean[index], f3_clean[i]);
         }
         
         if(d >= lastDistance) {
            lastDistance = d;
            int dist_size = ArraySize(distances);
            ArrayResize(distances, dist_size + 1);
            ArrayResize(predictions, dist_size + 1);
            distances[dist_size] = d;
            predictions[dist_size] = (int)y_train_cache[i];
            
            if(ArraySize(predictions) > InpNeighborsCount) {
               int cutoff_idx = (int)MathRound(InpNeighborsCount * 3.0 / 4.0);
               lastDistance = distances[cutoff_idx];
               
               // Shift left (remove first element)
               for(int k = 0; k < ArraySize(distances) - 1; k++) {
                  distances[k] = distances[k+1];
                  predictions[k] = predictions[k+1];
               }
               ArrayResize(distances, InpNeighborsCount);
               ArrayResize(predictions, InpNeighborsCount);
            }
         }
      }
      
      // Sum the predictions
      int prediction_sum = 0;
      for(int k = 0; k < ArraySize(predictions); k++) {
         prediction_sum += predictions[k];
      }
      
      // Determine ML Signal
      int signal = 0; // Neutral
      if(prediction_sum > 0 && filter_all) signal = 1;
      else if(prediction_sum < 0 && filter_all) signal = -1;
      
      if(index == 1) {
         string pred_vals = "";
         for(int k=0; k<ArraySize(predictions); k++) pred_vals += IntegerToString(predictions[k]) + ",";
         PrintFormat("LDC DEBUG Summary: index=1 | prediction_sum=%d | filter_all=%d (volPass=%d, adxPass=%d, regimePass=%d)", prediction_sum, filter_all, volatilityPass, adxPass, regimePass);
         PrintFormat("LDC DEBUG Inputs: volFil=%d, regFil=%d, adxFil=%d | size=%d | sizeLoop=%d | MaxBars=%d | Neighbors=%d | Features=%d", InpUseVolatilityFilter, InpUseRegimeFilter, InpUseAdxFilter, ArraySize(predictions), sizeLoop, InpMaxBarsBack, InpNeighborsCount, InpFeatureCount);
         PrintFormat("LDC DEBUG Features: f1=%.4f, f2=%.4f, f3=%.4f, f4=%.4f, f5=%.4f", f1_clean[1], f2_clean[1], f3_clean[1], f4_clean[1], f5_clean[1]);
         PrintFormat("LDC DEBUG Raws: rsi14=%.2f, cci=%.2f, adx=%.2f, rsi9=%.2f", arrRsi14[1], arrCci20[1], arrAdx20[1], arrRsi9[1]);
         PrintFormat("LDC DEBUG Queue: predictions=%s | y_train[10..15]=%.1f,%.1f,%.1f,%.1f,%.1f,%.1f", pred_vals, y_train_cache[10], y_train_cache[11], y_train_cache[12], y_train_cache[13], y_train_cache[14], y_train_cache[15]);
      }
      
      //--- Kernel Regression Lines
      double yhat1 = rationalQuadratic(close, index, InpH, InpR, InpX);
      double yhat2 = gaussian(close, index, InpH - InpLag, InpX);
      
      bool isBullishSmooth = yhat2 >= yhat1;
      bool isBullishRate = yhat1 > rq2;
      
      bool isBullish = InpUseKernelFilter ? (InpUseKernelSmoothing ? isBullishSmooth : isBullishRate) : true;
      bool isBearish = InpUseKernelFilter ? (InpUseKernelSmoothing ? !isBullishSmooth : !isBullishRate) : true;
      
      // Set Kernel Line Buffer
      BufferKernelLine[index] = yhat1;
      BufferKernelColor[index] = isBullish ? 0 : 1;
      
      // Set Candles Buffer colors
      BufferCandleOpen[index]  = open[index];
      BufferCandleHigh[index]  = high[index];
      BufferCandleLow[index]   = low[index];
      BufferCandleClose[index] = close[index];
      
      if(signal > 0 && isBullish && emaPassBuy && smaPassBuy) {
         BufferCandleColor[index] = 0; // Green
         // Check for new Buy Signal (state transition)
         if(index + 1 < rates_total && BufferCandleColor[index+1] != 0) {
            DrawArrowLabel("BuyArrow_" + (string)time[index], time[index], low[index], true, prediction_sum);
            // Trigger alerts
            if(index == 1) {
               TriggerAlert(true, close[index], prediction_sum);
            }
         }
      } else if(signal < 0 && isBearish && emaPassSell && smaPassSell) {
         BufferCandleColor[index] = 1; // Red
         // Check for new Sell Signal (state transition)
         if(index + 1 < rates_total && BufferCandleColor[index+1] != 1) {
            DrawArrowLabel("SellArrow_" + (string)time[index], time[index], high[index], false, prediction_sum);
            // Trigger alerts
            if(index == 1) {
               TriggerAlert(false, close[index], prediction_sum);
            }
         }
      } else {
         BufferCandleColor[index] = 2; // Gray
      }
      
      // Mock Backtest metrics
      if(index - 4 >= 0 && index + 4 < rates_total) {
         bool isBuy = (BufferCandleColor[index] == 0);
         bool isSell = (BufferCandleColor[index] == 1);
         if(isBuy) {
            total_trades++;
            if(close[index-4] > close[index]) wins++;
            else losses++;
         }
         if(isSell) {
            total_trades++;
            if(close[index-4] < close[index]) wins++;
            else losses++;
         }
      }
   }
   
   // Update bottom-right stats table
   if(total_trades > 0) {
      UpdateStatsTable(total_trades, wins, losses);
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Support Drawing and Alerts                                       |
//+------------------------------------------------------------------+
void DrawArrowLabel(string name, datetime time, double price, bool isBuy, int score) {
   ObjectDelete(0, name);
   if(isBuy) {
      ObjectCreate(0, name, OBJ_TEXT, 0, time, price - 2.0);
      ObjectSetString(0, name, OBJPROP_TEXT, "▲\n" + (string)score);
      ObjectSetInteger(0, name, OBJPROP_COLOR, C'0x15,0xFF,0x00');
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_TOP);
   } else {
      ObjectCreate(0, name, OBJ_TEXT, 0, time, price + 2.0);
      ObjectSetString(0, name, OBJPROP_TEXT, (string)score + "\n▼");
      ObjectSetInteger(0, name, OBJPROP_COLOR, C'0xCC,0x33,0x11');
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   }
}

void TriggerAlert(bool isBuy, double price, int score) {
   if(TimeCurrent() - lastAlertTime < 60) return;
   lastAlertTime = TimeCurrent();
   
   string signalStr = isBuy ? "BUY" : "SELL";
   string msg = StringFormat("Lorentzian ML Signal: %s | Price: %.2f | Score: %d | Symbol: %s | TF: %s", 
                             signalStr, price, score, _Symbol, EnumToString(Period()));
   
   Alert(msg);
   SendLineNotification(msg);
}

//--- Bottom-Right Dashboard Table
void UpdateStatsTable(int totalTrades, int wins, int losses) {
   string tbl_name = "LorentzianStatsTable";
   TableDelete();
   
   int columns = 2;
   int rows = 4;
   if(!TableCreate(tbl_name, columns, rows)) return;
   
   double winrate = (wins + losses > 0) ? ((double)wins / (double)(wins + losses) * 100.0) : 0.0;
   double wl_ratio = (losses > 0) ? ((double)wins / (double)losses) : wins;
   
   // Set cell values
   TableSetCell(tbl_name, 0, 0, "📊 LDC ML Stats", clrDarkSlateGray);
   TableSetCell(tbl_name, 1, 0, "", clrDarkSlateGray);
   
   TableSetCell(tbl_name, 0, 1, "Winrate", clrDimGray);
   TableSetCell(tbl_name, 1, 1, StringFormat("%.1f%%", winrate), winrate >= 50 ? clrTeal : clrFireBrick);
   
   TableSetCell(tbl_name, 0, 2, "Trades Count", clrDimGray);
   TableSetCell(tbl_name, 1, 2, StringFormat("%d (%d|%d)", totalTrades, wins, losses), clrSilver);
   
   TableSetCell(tbl_name, 0, 3, "WL Ratio", clrDimGray);
   TableSetCell(tbl_name, 1, 3, StringFormat("%.2f", wl_ratio), clrSilver);
}

bool TableCreate(string name, int cols, int rows) {
   if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) {
      // If table exists, delete and recreate
      ObjectDelete(0, name);
      if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) return false;
   }
   // Hide button background to make it look like a floating panel
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 10);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, 200);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, 90);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C'0x1C,0x1C,0x1C');
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDarkGray);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, name, OBJPROP_TEXT, "");
   
   // Create labels inside the button box
   for(int r = 0; r < rows; r++) {
      for(int c = 0; c < cols; c++) {
         string cell_name = StringFormat("%s_cell_%d_%d", name, c, r);
         ObjectCreate(0, cell_name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, cell_name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
         ObjectSetInteger(0, cell_name, OBJPROP_XDISTANCE, 10 + (1 - c) * 90);
         ObjectSetInteger(0, cell_name, OBJPROP_YDISTANCE, 15 + (rows - 1 - r) * 18);
         ObjectSetInteger(0, cell_name, OBJPROP_SELECTABLE, false);
      }
   }
   return true;
}

void TableSetCell(string tbl_name, int col, int row, string text, color clr) {
   string cell_name = StringFormat("%s_cell_%d_%d", tbl_name, col, row);
   ObjectSetString(0, cell_name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, cell_name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, cell_name, OBJPROP_FONTSIZE, 9);
}

void TableDelete() {
   string tbl_name = "LorentzianStatsTable";
   ObjectDelete(0, tbl_name);
   for(int r = 0; r < 10; r++) {
      for(int c = 0; c < 5; c++) {
         ObjectDelete(0, StringFormat("%s_cell_%d_%d", tbl_name, c, r));
      }
   }
}
