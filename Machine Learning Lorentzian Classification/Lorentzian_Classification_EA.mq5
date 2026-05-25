//+------------------------------------------------------------------+
//|                                   Lorentzian_Classification_EA.mq5|
//|                                                       @jdehorty  |
//|                                             https://tradeview.com|
//+------------------------------------------------------------------+
#property copyright "jdehorty"
#property link      "https://tradingview.com/v/WhBzgfDu/"
#property version   "1.00"

//--- Include Trade library
#include <Trade\Trade.mqh>

//--- Input Parameters
input group "EA Trading Settings"
input double   InpLotSize             = 0.1;               // Lot Size
input ulong    InpMagicNumber         = 0x87E215B3;        // Magic Number
input int      InpSlippage            = 30;                // Slippage (points)
input bool     InpEnableBreakeven     = true;              // Enable 1:1 Breakeven
input double   InpBreakevenTriggerRatio = 1.0;             // Breakeven Trigger Ratio (R:R)
input bool     InpEnableTrailing      = false;             // Enable Trailing Stop

enum ENUM_SL_MODE {
   SL_MODE_FIXED,   // Fixed SL Points
   SL_MODE_DYNAMIC  // Dynamic SL (Indicator based)
};
input ENUM_SL_MODE InpSlMode          = SL_MODE_FIXED;     // Stop Loss Mode
input int      InpFixedSlPoints       = 1500;              // Fixed SL Points (15.00 USD for Gold)
input double   InpRiskRewardRatio     = 2.0;               // Risk-Reward Ratio (TP = SL * RR)

input group "Session Time Filter"
input bool     InpUseTimeFilter       = true;              // Use Time Filter (13:00-23:00 BKK)
input int      InpHourStart           = 8;                 // Server Hour Start (08:00 server = 13:00 BKK)
input int      InpHourEnd             = 18;                // Server Hour End (18:00 server = 23:00 BKK)

input group "ML Indicator Settings"
input int      InpNeighborsCount      = 8;                 // Neighbors Count (K)
input int      InpMaxBarsBack         = 2000;              // Max Bars Back
input int      InpFeatureCount        = 5;                 // Feature Count (2-5)
input int      InpColorCompression    = 1;                 // Color Compression (1-10)
input bool     InpShowExits           = false;             // Show Default Exits
input bool     InpUseDynamicExits     = false;             // Use Dynamic Exits

input group "ML Indicator Filters"
input bool     InpUseVolatilityFilter = true;              // Use Volatility Filter
input bool     InpUseRegimeFilter     = true;              // Use Regime Filter
input bool     InpUseAdxFilter        = false;             // Use ADX Filter
input double   InpRegimeThreshold     = -0.1;              // Regime Threshold
input int      InpAdxThreshold        = 20;                // ADX Threshold
input bool     InpUseEmaFilter        = false;             // Use EMA Filter
input int      InpEmaPeriod           = 200;               // EMA Period
input bool     InpUseSmaFilter        = false;             // Use SMA Filter
input int      InpSmaPeriod           = 200;               // SMA Period

input group "ML Kernel Settings"
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

//--- Global Variables
CTrade trade;
int handleIndicator;
datetime lastBarTime = 0;

//--- Asynchronous LINE Sender
void SendLineNotification(string message) {
   if(InpLineToken == "") return;
   
   // We will broadcast a Custom Event: Event ID = 0x87E2
   EventChartCustom(0, 0x87E2, 0, 0.0, message);
}

//+------------------------------------------------------------------+
//| EA Initialization                                                |
//+------------------------------------------------------------------+
int OnInit() {
   // Set up trading magic
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   
   // Clean up any orphaned display tables
   TableDelete();
   
   PrintFormat("LDC EA INIT: Lot=%.2f | Neighbors=%d | MaxBars=%d | FeatureCount=%d | ColorComp=%d | volFil=%d | regFil=%d | adxFil=%d",
               InpLotSize, InpNeighborsCount, InpMaxBarsBack, InpFeatureCount, InpColorCompression, InpUseVolatilityFilter, InpUseRegimeFilter, InpUseAdxFilter);
   
   // Load Custom Indicator
   handleIndicator = iCustom(Symbol(), Period(), "Lorentzian_Classification_v2",
                             "General Settings",
                             InpNeighborsCount, InpMaxBarsBack, InpFeatureCount, InpColorCompression,
                             InpShowExits, InpUseDynamicExits,
                             "Filters",
                             InpUseVolatilityFilter, InpUseRegimeFilter, InpUseAdxFilter, InpRegimeThreshold, InpAdxThreshold,
                             InpUseEmaFilter, InpEmaPeriod, InpUseSmaFilter, InpSmaPeriod,
                             "Kernel Settings",
                             InpUseKernelFilter, InpShowKernelEstimate, InpUseKernelSmoothing,
                             InpH, InpR, InpX, InpLag);
                             
   if(handleIndicator == INVALID_HANDLE) {
      Print("Error: Failed to load Lorentzian_Classification indicator!");
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EA Deinitialization                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   TableDelete();
}

//+------------------------------------------------------------------+
//| Main EA Tick Calculation                                         |
//+------------------------------------------------------------------+
void OnTick() {
   static int tick_count = 0;
   tick_count++;
   if(tick_count <= 10) {
      PrintFormat("LDC EA TICK: #%d | ask=%.2f | bid=%.2f | time=%s", tick_count, SymbolInfoDouble(Symbol(), SYMBOL_ASK), SymbolInfoDouble(Symbol(), SYMBOL_BID), TimeToString(TimeCurrent()));
   }

   // Verify connection and quotes
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   if(ask <= 0 || bid <= 0) return;
   
   // Check for New Bar to execute entry signals
   datetime currentBarTime = iTime(Symbol(), Period(), 0);
   bool isNewBar = (currentBarTime != lastBarTime);
   
   //--- Dynamic Position Management (Every Tick)
   ManageOpenPositions(bid, ask, point);
   
   if(isNewBar) {
      lastBarTime = currentBarTime;
      
      //--- Time Session Filter
      if(InpUseTimeFilter) {
         MqlDateTime dt;
         TimeToStruct(TimeCurrent(), dt);
         if(dt.hour < InpHourStart || dt.hour > InpHourEnd) {
            return; // Out of trading hours
         }
      }
      
      // Retrieve Indicator buffer color index for the completed closed bar (index 1)
      double arrCandleColor[3];
      if(CopyBuffer(handleIndicator, 6, 1, 2, arrCandleColor) < 0) {
         Print("Error: Failed to copy indicator color buffer!");
         return;
      }
      
      int closedBarColor = (int)arrCandleColor[1]; // Color of last closed bar (index 1)
      int prevBarColor   = (int)arrCandleColor[0]; // Color of index 2
      
      PrintFormat("LDC EA DEBUG: time=%s | closedBarColor=%d | prevBarColor=%d | raw_1=%.2f | raw_0=%.2f", 
                  TimeToString(currentBarTime), closedBarColor, prevBarColor, arrCandleColor[1], arrCandleColor[0]);
      
      // Check current positions
      int totalBuy = 0, totalSell = 0;
      CheckPositionsCount(totalBuy, totalSell);
      
      // BUY Signal: Color transitions to 0 (Green) from non-green
      if(closedBarColor == 0 && prevBarColor != 0) {
         if(totalBuy == 0) {
            // Close any open SELL positions first
            CloseAllPositions(POSITION_TYPE_SELL);
            
            // Calculate Stealth SL & TP targets
            double slPrice = ask - (InpFixedSlPoints * point);
            double tpPrice = ask + (InpFixedSlPoints * InpRiskRewardRatio * point);
            
            // Execute trade with NO physical SL/TP (sent as 0) to avoid broker stop hunting!
            if(trade.Buy(InpLotSize, Symbol(), ask, 0, 0, "LDC Buy Order")) {
               // Store Stealth SL & TP in persistent Global Variables
               string sl_name = StringFormat("LDC_SL_%d_%s", InpMagicNumber, Symbol());
               string tp_name = StringFormat("LDC_TP_%d_%s", InpMagicNumber, Symbol());
               string be_name = StringFormat("LDC_BE_%d_%s", InpMagicNumber, Symbol());
               
               GlobalVariableSet(sl_name, slPrice);
               GlobalVariableSet(tp_name, tpPrice);
               GlobalVariableSet(be_name, 0.0); // Breakeven not triggered yet
               
               SendLineNotification(StringFormat("▲ LDC Entry BUY: %.2f | SL (Virtual): %.2f | TP (Virtual): %.2f", ask, slPrice, tpPrice));
            }
         }
      }
      
      // SELL Signal: Color transitions to 1 (Red) from non-red
      if(closedBarColor == 1 && prevBarColor != 1) {
         if(totalSell == 0) {
            // Close any open BUY positions first
            CloseAllPositions(POSITION_TYPE_BUY);
            
            // Calculate Stealth SL & TP targets
            double slPrice = bid + (InpFixedSlPoints * point);
            double tpPrice = bid - (InpFixedSlPoints * InpRiskRewardRatio * point);
            
            // Execute trade with NO physical SL/TP (sent as 0) to avoid broker stop hunting!
            if(trade.Sell(InpLotSize, Symbol(), bid, 0, 0, "LDC Sell Order")) {
               // Store Stealth SL & TP in persistent Global Variables
               string sl_name = StringFormat("LDC_SL_%d_%s", InpMagicNumber, Symbol());
               string tp_name = StringFormat("LDC_TP_%d_%s", InpMagicNumber, Symbol());
               string be_name = StringFormat("LDC_BE_%d_%s", InpMagicNumber, Symbol());
               
               GlobalVariableSet(sl_name, slPrice);
               GlobalVariableSet(tp_name, tpPrice);
               GlobalVariableSet(be_name, 0.0); // Breakeven not triggered yet
               
               SendLineNotification(StringFormat("▼ LDC Entry SELL: %.2f | SL (Virtual): %.2f | TP (Virtual): %.2f", bid, slPrice, tpPrice));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dynamic Position Management Functions                            |
//+------------------------------------------------------------------+
void ManageOpenPositions(double bid, double ask, double point) {
   string sl_name = StringFormat("LDC_SL_%d_%s", InpMagicNumber, Symbol());
   string tp_name = StringFormat("LDC_TP_%d_%s", InpMagicNumber, Symbol());
   string be_name = StringFormat("LDC_BE_%d_%s", InpMagicNumber, Symbol());
   
   if(!GlobalVariableCheck(sl_name) || !GlobalVariableCheck(tp_name)) return;
   
   double virtualSl = GlobalVariableGet(sl_name);
   double virtualTp = GlobalVariableGet(tp_name);
   double isBeTriggered = GlobalVariableGet(be_name);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         if(posType == POSITION_TYPE_BUY) {
            // Check 1:1 Breakeven trigger
            if(InpEnableBreakeven && isBeTriggered == 0.0) {
               double targetPrice = openPrice + (InpFixedSlPoints * InpBreakevenTriggerRatio * point);
               if(bid >= targetPrice) {
                  // Pull SL to entry price + 10 points (to cover spread/comms)
                  double newSl = openPrice + (10 * point);
                  GlobalVariableSet(sl_name, newSl);
                  GlobalVariableSet(be_name, 1.0); // Mark BE triggered
                  Print("LDC: 1:1 Breakeven protection activated for BUY position.");
                  SendLineNotification(StringFormat("🔒 LDC Buy SL locked to Breakeven (+10 pts): %.2f", newSl));
                  virtualSl = newSl;
               }
            }
            
            // Check Virtual Stop Loss
            if(bid <= virtualSl && virtualSl > 0.0) {
               trade.PositionClose(ticket);
               Print("LDC: Virtual Stop Loss triggered for BUY position.");
               SendLineNotification(StringFormat("🛑 LDC Buy Virtual SL Hit: %.2f", bid));
               GlobalVariableDel(sl_name);
               GlobalVariableDel(tp_name);
               GlobalVariableDel(be_name);
            }
            // Check Virtual Take Profit
            else if(bid >= virtualTp && virtualTp > 0.0) {
               trade.PositionClose(ticket);
               Print("LDC: Virtual Take Profit triggered for BUY position.");
               SendLineNotification(StringFormat("🎯 LDC Buy Virtual TP Hit: %.2f", bid));
               GlobalVariableDel(sl_name);
               GlobalVariableDel(tp_name);
               GlobalVariableDel(be_name);
            }
         }
         else if(posType == POSITION_TYPE_SELL) {
            // Check 1:1 Breakeven trigger
            if(InpEnableBreakeven && isBeTriggered == 0.0) {
               double targetPrice = openPrice - (InpFixedSlPoints * InpBreakevenTriggerRatio * point);
               if(ask <= targetPrice) {
                  // Pull SL to entry price - 10 points (to cover spread/comms)
                  double newSl = openPrice - (10 * point);
                  GlobalVariableSet(sl_name, newSl);
                  GlobalVariableSet(be_name, 1.0); // Mark BE triggered
                  Print("LDC: 1:1 Breakeven protection activated for SELL position.");
                  SendLineNotification(StringFormat("🔒 LDC Sell SL locked to Breakeven (+10 pts): %.2f", newSl));
                  virtualSl = newSl;
               }
            }
            
            // Check Virtual Stop Loss
            if(ask >= virtualSl && virtualSl > 0.0) {
               trade.PositionClose(ticket);
               Print("LDC: Virtual Stop Loss triggered for SELL position.");
               SendLineNotification(StringFormat("🛑 LDC Sell Virtual SL Hit: %.2f", ask));
               GlobalVariableDel(sl_name);
               GlobalVariableDel(tp_name);
               GlobalVariableDel(be_name);
            }
            // Check Virtual Take Profit
            else if(ask <= virtualTp && virtualTp > 0.0) {
               trade.PositionClose(ticket);
               Print("LDC: Virtual Take Profit triggered for SELL position.");
               SendLineNotification(StringFormat("🎯 LDC Sell Virtual TP Hit: %.2f", ask));
               GlobalVariableDel(sl_name);
               GlobalVariableDel(tp_name);
               GlobalVariableDel(be_name);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check Positions Counts                                           |
//+------------------------------------------------------------------+
void CheckPositionsCount(int &buyCount, int &sellCount) {
   buyCount = 0;
   sellCount = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(posType == POSITION_TYPE_BUY) buyCount++;
         if(posType == POSITION_TYPE_SELL) sellCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions for specific type                            |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE typeToClose) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(PositionGetSymbol(i) == Symbol() && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber) {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(posType == typeToClose) {
            trade.PositionClose(ticket);
            
            // Delete persistent global variables
            string sl_name = StringFormat("LDC_SL_%d_%s", InpMagicNumber, Symbol());
            string tp_name = StringFormat("LDC_TP_%d_%s", InpMagicNumber, Symbol());
            string be_name = StringFormat("LDC_BE_%d_%s", InpMagicNumber, Symbol());
            GlobalVariableDel(sl_name);
            GlobalVariableDel(tp_name);
            GlobalVariableDel(be_name);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Table Management Functions (Clear on exit)                       |
//+------------------------------------------------------------------+
void TableDelete() {
   string tbl_name = "LorentzianStatsTable";
   ObjectDelete(0, tbl_name);
   for(int r = 0; r < 10; r++) {
      for(int c = 0; c < 5; c++) {
         ObjectDelete(0, StringFormat("%s_cell_%d_%d", tbl_name, c, r));
      }
   }
}
