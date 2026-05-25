//+------------------------------------------------------------------+
//|                               Uptrick_ML_Kernel_Trading_EA.mq5   |
//|                                                          Uptrick |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Uptrick"
#property link      "https://www.mql5.com"
#property version   "1.10"

// Include standard MQL5 Trade class
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_THEME {
   THEME_CLASSIC,
   THEME_CYBER_AQUA,
   THEME_CRIMSON_PULSE,
   THEME_ROYAL_PURPLE,
   THEME_EMERALD_NIGHT,
   THEME_MINIMAL_MONO,
   THEME_CLASSIC_EMERALD
};

enum ENUM_VISUAL {
   VIS_BANDS,
   VIS_SINGLE_LINE,
   VIS_TRAIL
};

enum ENUM_ANCHOR {
   ANCHOR_HIGH_LOW,
   ANCHOR_MAIN_LINE,
   ANCHOR_BANDS
};

enum ENUM_SL_MODE {
   SL_MODE_BAND,   // Stop Loss at opposite band
   SL_MODE_FIXED   // Fixed Stop Loss in points
};

enum ENUM_STRATEGY_MODE {
   STRAT_BREAKOUT,        // Breakout (Trend Following)
   STRAT_MEAN_REVERSION   // Mean Reversion (Counter-Trend)
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//--- Strategy Selection
input group "╔════════ Strategy Selection ════════╗"
input ENUM_STRATEGY_MODE InpStrategyMode = STRAT_MEAN_REVERSION; // Strategy Mode (Mean Reversion is recommended!)

//--- Trading Settings
input group "╔═════════ Trading Settings ═════════╗"
input double         InpLotSize         = 0.1;         // Lot Size
input ENUM_SL_MODE   InpSlMode          = SL_MODE_FIXED;// Stop Loss Mode
input int            InpFixedSlPoints   = 250;         // Fixed Stop Loss (points)
input double         InpRiskRewardRatio = 2.0;         // Risk-Reward Ratio (e.g. 2.0 = RR 1:2)
input ulong          InpMagicNumber     = 82809420;    // Magic Number
input ulong          InpSlippage        = 30;          // Max Slippage (points)

//--- Breakeven & Trailing Settings (New Optimization Features)
input group "╔═══════ Breakeven & Trailing ═══════╗"
input bool           InpEnableBreakeven       = false; // Enable Breakeven
input double         InpBreakevenTriggerRatio = 1.0;   // Breakeven Trigger (R:R Ratio, e.g. 1.0 = 1:1)
input bool           InpEnableTrailing        = true;  // Enable Trailing Stop (Opposite Band)

//--- Advanced Filters
input group "╔═════════ Advanced Filters ═════════╗"
input bool           InpUseEmaFilter          = true;  // Use EMA 200 Trend Filter
input int            InpEmaPeriod             = 200;   // EMA Trend Filter Period
input bool           InpUseTimeFilter         = true;  // Use Time Session Filter
input int            InpHourStart             = 8;     // Session Start Hour (Server Time, 8 = 13:00 BKK)
input int            InpHourEnd               = 18;    // Session End Hour (Server Time, 18 = 23:00 BKK)

//--- Kernel Regression Settings (Must match Indicator inputs)
input group "╔═════ Kernel Regression ═════╗"
input int         InpLookback       = 30;          // Lookback Window
input double      InpBandwidth      = 8.0;         // Base Bandwidth (h)
input bool        InpAdaptive       = true;        // Adaptive Bandwidth (ATR-scaled)
input int         InpAtrLen         = 14;          // ATR Length (adaptive)
input int         InpSmooth         = 3;           // MA Output Smoothing

//--- Residual Bands Settings (Must match Indicator inputs)
input group "╔═══════ Residual Bands ═══════╗"
input double      InpBandMult       = 1.0;         // Band Multiplier (sigma)
input int         InpBandLen        = 24;          // Band Lookback (sigma)
input int         InpBandSmooth     = 5;           // Band Smoothing

//--- LINE Messaging API Settings
input group "╔═══════ LINE Alerts Settings ═══════╗"
input bool     InpAlertLine       = true;        // Send LINE Alerts
input string   InpLineAccessToken = "maIdVxEOzBlYe+Rc3jwzvoTOLho8LhxOdmLaxdRibTDpZ0yZrw0A1PqF6sOs761qHbxlw74n/CJuBzzwLL3cLyCLjSXv/VBHms5jB8OTMUD8pUjkK6Wc6YEOZj7LePjdGsud9yEQ3Z/4YO0inNQTLgdB04t89/1O/w1cDnyilFU="; // Channel Access Token
input string   InpLineTargetId    = ""; // LINE Target ID (Group ID/User ID, optional)

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade      trade;
int         indicatorHandle;
int         emaHandle;
datetime    lastBarTime;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade class
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);

   // Load Custom Indicator
   // Note: We turn off popup/mobile/LINE alerts on indicator level (false) to let the EA manage notifications
   indicatorHandle = iCustom(_Symbol, _Period, "Uptrick_ML_Kernel_Regression",
                              InpLookback, InpBandwidth, InpAdaptive, InpAtrLen, InpSmooth,
                              InpBandMult, InpBandLen, InpBandSmooth,
                              VIS_BANDS, true, false, THEME_CLASSIC, ANCHOR_MAIN_LINE,
                              0.5, false, false, false);
                              
   if(indicatorHandle == INVALID_HANDLE)
   {
      Print("EA Init Error: Failed to load Custom Indicator 'Uptrick_ML_Kernel_Regression'!");
      return(INIT_FAILED);
   }

   // Load EMA Filter Indicator if enabled
   if(InpUseEmaFilter)
   {
      emaHandle = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaHandle == INVALID_HANDLE)
      {
         Print("EA Init Error: Failed to load EMA Indicator!");
         return(INIT_FAILED);
      }
   }
   else
   {
      emaHandle = INVALID_HANDLE;
   }

   lastBarTime = 0;
   Print("Uptrick Trading EA successfully initialized magic: ", InpMagicNumber, " strategy mode: ", InpStrategyMode);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(indicatorHandle != INVALID_HANDLE)
      IndicatorRelease(indicatorHandle);
      
   if(emaHandle != INVALID_HANDLE)
      IndicatorRelease(emaHandle);
      
   Print("Uptrick Trading EA Stopped.");
}

//+------------------------------------------------------------------+
//| Close all positions of a specific type                           |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == posType)
         {
            if(trade.PositionClose(ticket))
            {
               GlobalVariableDel("VSL_" + string(ticket));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if position of a specific type exists                       |
//+------------------------------------------------------------------+
bool PositionExists(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            PositionGetInteger(POSITION_TYPE) == posType)
         {
            return(true);
         }
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Send LINE Notification asynchronously                            |
//+------------------------------------------------------------------+
void SendLineNotification(string message)
{
   if(!InpAlertLine || StringLen(InpLineAccessToken) == 0)
      return;

   string url = "https://api.line.me/v2/bot/message/broadcast";
   if(StringLen(InpLineTargetId) > 0)
      url = "https://api.line.me/v2/bot/message/push";

   string headers = "Content-Type: application/json\r\n" +
                    "Authorization: Bearer " + InpLineAccessToken + "\r\n";

   string body = "";
   if(StringLen(InpLineTargetId) > 0)
   {
      body = "{\"to\":\"" + InpLineTargetId + "\",\"messages\":[{\"type\":\"text\",\"text\":\"" + message + "\"}]}";
   }
   else
   {
      body = "{\"messages\":[{\"type\":\"text\",\"text\":\"" + message + "\"}]}";
   }

   char post_data[];
   StringToCharArray(body, post_data, 0, StringLen(body), CP_UTF8);

   char result_data[];
   string result_headers;
   
   int res = WebRequest("POST", url, headers, 3000, post_data, result_data, result_headers);
   if(res == -1)
   {
      Print("EA LINE Alert Error: WebRequest failed with error ", GetLastError());
   }
   else
   {
      string res_str = CharArrayToString(result_data, 0, WHOLE_ARRAY, CP_UTF8);
      Print("EA LINE Alert Dispatch Success: ", res_str);
   }
}

//+------------------------------------------------------------------+
//| Cleanup Orphaned Stealth/Virtual SL Global Variables             |
//+------------------------------------------------------------------+
void CleanupOrphanGlobalVariables()
{
   int totalGVs = GlobalVariablesTotal();
   for(int i = totalGVs - 1; i >= 0; i--)
   {
      string gvName = GlobalVariableName(i);
      if(StringFind(gvName, "VSL_") == 0)
      {
         string ticketStr = StringSubstr(gvName, 4);
         ulong ticket = StringToInteger(ticketStr);
         if(!PositionSelectByTicket(ticket))
         {
            GlobalVariableDel(gvName);
            Print("EA VSL Cleanup: Removed orphaned virtual SL variable ", gvName);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Positions on Every Tick (Breakeven & Trailing Stops)       |
//+------------------------------------------------------------------+
void ManagePositionsOnTick()
{
   // Perform housekeeping first
   CleanupOrphanGlobalVariables();

   // Copy latest band values from indicator (index 1 is the last completed bar)
   double upperArr[];
   ArraySetAsSeries(upperArr, true);
   if(CopyBuffer(indicatorHandle, 2, 1, 1, upperArr) < 1) return;
   double upperBand = upperArr[0];

   double lowerArr[];
   ArraySetAsSeries(lowerArr, true);
   if(CopyBuffer(indicatorHandle, 4, 1, 1, lowerArr) < 1) return;
   double lowerBand = lowerArr[0];

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentTp  = PositionGetDouble(POSITION_TP);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            //--- Retrieve Virtual SL from Global Variables
            string gvName = "VSL_" + string(ticket);
            double virtualSl = 0;
            if(GlobalVariableCheck(gvName))
            {
               virtualSl = GlobalVariableGet(gvName);
            }
            else
            {
               // Fallback initial virtual SL calculation if missing
               if(type == POSITION_TYPE_BUY)
               {
                  if(InpSlMode == SL_MODE_BAND)
                     virtualSl = lowerBand;
                  else
                     virtualSl = entryPrice - InpFixedSlPoints * _Point;
                     
                  if(virtualSl >= entryPrice)
                     virtualSl = entryPrice - 100 * _Point;
               }
               else
               {
                  if(InpSlMode == SL_MODE_BAND)
                     virtualSl = upperBand;
                  else
                     virtualSl = entryPrice + InpFixedSlPoints * _Point;
                     
                  if(virtualSl <= entryPrice)
                     virtualSl = entryPrice + 100 * _Point;
               }
               GlobalVariableSet(gvName, virtualSl);
            }

            //--- A. BREAKEVEN PROTECTION
            if(InpEnableBreakeven)
            {
               if(type == POSITION_TYPE_BUY)
               {
                  double initialRisk = entryPrice - virtualSl;
                  if(virtualSl > 0 && virtualSl < entryPrice && initialRisk > 0)
                  {
                     double triggerPrice = entryPrice + initialRisk * InpBreakevenTriggerRatio;
                     if(bid >= triggerPrice)
                     {
                        double newSl = entryPrice + 10 * _Point; // Move SL to BE + 10 points
                        if(newSl > virtualSl)
                        {
                           GlobalVariableSet(gvName, newSl);
                           PrintFormat("EA VSL BE: Buy position #%d Virtual StopLoss moved to Breakeven at %.2f", ticket, newSl);
                           string msg = "🛡️ [EA Alert] BUY #" + string(ticket) + " Virtual StopLoss moved to Breakeven at " + DoubleToString(newSl, _Digits);
                           SendLineNotification(msg);
                           virtualSl = newSl; // Update working value
                        }
                     }
                  }
               }
               else if(type == POSITION_TYPE_SELL)
               {
                  double initialRisk = virtualSl - entryPrice;
                  if(virtualSl > 0 && virtualSl > entryPrice && initialRisk > 0)
                  {
                     double triggerPrice = entryPrice - initialRisk * InpBreakevenTriggerRatio;
                     if(ask <= triggerPrice)
                     {
                        double newSl = entryPrice - 10 * _Point; // Move SL to BE - 10 points
                        if(newSl < virtualSl)
                        {
                           GlobalVariableSet(gvName, newSl);
                           PrintFormat("EA VSL BE: Sell position #%d Virtual StopLoss moved to Breakeven at %.2f", ticket, newSl);
                           string msg = "🛡️ [EA Alert] SELL #" + string(ticket) + " Virtual StopLoss moved to Breakeven at " + DoubleToString(newSl, _Digits);
                           SendLineNotification(msg);
                           virtualSl = newSl; // Update working value
                        }
                     }
                  }
               }
            }

            //--- B. DYNAMIC TRAILING STOP
            if(InpEnableTrailing)
            {
               if(type == POSITION_TYPE_BUY)
               {
                  double newSl = lowerBand;
                  if(newSl > virtualSl && newSl < bid)
                  {
                     GlobalVariableSet(gvName, newSl);
                     PrintFormat("EA VSL TS: Buy position #%d Virtual Trailing StopLoss updated to LowerBand: %.2f", ticket, newSl);
                     virtualSl = newSl; // Update working value
                  }
               }
               else if(type == POSITION_TYPE_SELL)
               {
                  double newSl = upperBand;
                  if((newSl < virtualSl || virtualSl == 0) && newSl > ask)
                  {
                     GlobalVariableSet(gvName, newSl);
                     PrintFormat("EA VSL TS: Sell position #%d Virtual Trailing StopLoss updated to UpperBand: %.2f", ticket, newSl);
                     virtualSl = newSl; // Update working value
                  }
               }
            }

            //--- C. VIRTUAL STOP LOSS ENFORCEMENT (Stealth Execution)
            if(virtualSl > 0)
            {
               bool closeTriggered = false;
               if(type == POSITION_TYPE_BUY && bid <= virtualSl)
               {
                  closeTriggered = true;
                  PrintFormat("EA VSL Triggered: BUY #%d bid %.2f <= Virtual SL %.2f. Closing position.", ticket, bid, virtualSl);
               }
               else if(type == POSITION_TYPE_SELL && ask >= virtualSl)
               {
                  closeTriggered = true;
                  PrintFormat("EA VSL Triggered: SELL #%d ask %.2f >= Virtual SL %.2f. Closing position.", ticket, ask, virtualSl);
               }

               if(closeTriggered)
               {
                  if(trade.PositionClose(ticket))
                  {
                     GlobalVariableDel(gvName);
                     string sideStr = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
                     string msg = "🛡️ [EA Alert] position #" + string(ticket) + " (" + sideStr + ") closed by Virtual StopLoss at " + DoubleToString(type == POSITION_TYPE_BUY ? bid : ask, _Digits);
                     SendLineNotification(msg);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. DYNAMIC POSITION MANAGEMENT (Checked on EVERY tick)
   ManagePositionsOnTick();

   // 2. SIGNAL & BAR OPEN EVALUATION (Checked ONCE per bar close)
   datetime timeArr[];
   if(CopyTime(_Symbol, _Period, 0, 1, timeArr) < 1)
      return;
   datetime currentBarTime = timeArr[0];

   if(currentBarTime == lastBarTime)
      return; // Not a new bar yet

   lastBarTime = currentBarTime; // Update immediately to ensure we only evaluate once per bar!

   //--- Session Time Filter
   if(InpUseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpHourStart || dt.hour > InpHourEnd)
      {
         return;
      }
   }

   //--- Copy indicator buffers for analysis
   // Buffer 0: BufKernelMA (Midline)
   double kernelArr[];
   ArraySetAsSeries(kernelArr, true);
   if(CopyBuffer(indicatorHandle, 0, 0, 3, kernelArr) < 3)
   {
      Print("EA Error: Failed to copy kernel midline!");
      return;
   }

   // Buffer 21: BufState (+1 for Bullish breakout, -1 for Bearish breakdown)
   double stateArr[];
   ArraySetAsSeries(stateArr, true);
   if(CopyBuffer(indicatorHandle, 21, 0, 3, stateArr) < 3)
   {
      Print("EA Error: Failed to copy state buffer!");
      return;
   }

   // Buffer 2: BufUpperBand
   double upperArr[];
   ArraySetAsSeries(upperArr, true);
   if(CopyBuffer(indicatorHandle, 2, 0, 3, upperArr) < 3)
   {
      Print("EA Error: Failed to copy upper band!");
      return;
   }

   // Buffer 4: BufLowerBand
   double lowerArr[];
   ArraySetAsSeries(lowerArr, true);
   if(CopyBuffer(indicatorHandle, 4, 0, 3, lowerArr) < 3)
   {
      Print("EA Error: Failed to copy lower band!");
      return;
   }

   double closeArr[];
   ArraySetAsSeries(closeArr, true);
   if(CopyClose(_Symbol, _Period, 0, 3, closeArr) < 3)
   {
      Print("EA Error: Failed to copy close prices!");
      return;
   }

   double lowArr[];
   ArraySetAsSeries(lowArr, true);
   if(CopyLow(_Symbol, _Period, 0, 3, lowArr) < 3)
   {
      Print("EA Error: Failed to copy low prices!");
      return;
   }

   double highArr[];
   ArraySetAsSeries(highArr, true);
   if(CopyHigh(_Symbol, _Period, 0, 3, highArr) < 3)
   {
      Print("EA Error: Failed to copy high prices!");
      return;
   }

   // Copy EMA Filter if enabled
   double emaVal = 0;
   if(InpUseEmaFilter && emaHandle != INVALID_HANDLE)
   {
      double emaArr[];
      ArraySetAsSeries(emaArr, true);
      if(CopyBuffer(emaHandle, 0, 0, 2, emaArr) < 2)
      {
         Print("EA Error: Failed to copy EMA buffer!");
         return;
      }
      emaVal = emaArr[1]; // Value at the completed bar (Index 1)
   }

   // Detect Trend State transitions on the last fully closed bar (Index 1)
   double stateCur  = stateArr[1];
   double statePrev = stateArr[2];
   double closePrev = closeArr[1];

   bool isBuySignal  = false;
   bool isSellSignal = false;

   if(InpStrategyMode == STRAT_BREAKOUT)
   {
      // Breakout Strategy: open buy on bullish transition, sell on bearish transition
      isBuySignal  = (stateCur == 1.0  && statePrev != 1.0);
      isSellSignal = (stateCur == -1.0 && statePrev != -1.0);
      
      if(InpUseEmaFilter)
      {
         // Only BUY if price is above EMA 200, only SELL if price is below EMA 200
         if(isBuySignal  && closePrev < emaVal) isBuySignal  = false;
         if(isSellSignal && closePrev > emaVal) isSellSignal = false;
      }
   }
   else // STRAT_MEAN_REVERSION
   {
      // Mean Reversion Strategy: buy dips below lower band, sell rallies above upper band
      isBuySignal  = (closePrev < lowerArr[1]);
      isSellSignal = (closePrev > upperArr[1]);
      
      if(InpUseEmaFilter)
      {
         // Buy dips only if trend is bullish (close is above EMA 200 - BUY THE DIP!)
         if(isBuySignal  && closePrev < emaVal) isBuySignal  = false;
         // Sell rallies only if trend is bearish (close is below EMA 200 - SELL THE RALLY!)
         if(isSellSignal && closePrev > emaVal) isSellSignal = false;
      }
   }

   // Execute trades based on signals
   if(isBuySignal)
   {
      Print("EA Signal: BUY Signal Confirmed!");
      
      // Close active Sell positions
      ClosePositions(POSITION_TYPE_SELL);
      
      // Open new Buy position
      if(!PositionExists(POSITION_TYPE_BUY))
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double sl = 0;
         double tp = 0;
         
         if(InpStrategyMode == STRAT_BREAKOUT)
         {
            if(InpSlMode == SL_MODE_BAND)
               sl = lowerArr[1];
            else
               sl = ask - InpFixedSlPoints * _Point;

            // Verify SL sits below Ask price
            if(sl >= ask)
               sl = ask - 100 * _Point;

            double risk = ask - sl;
            tp = ask + risk * InpRiskRewardRatio;
         }
         else // STRAT_MEAN_REVERSION
         {
            // Dynamic Band Mean Reversion Exit: Exits are volatility-scaled based on the channel half-width.
            double channelHalf = (upperArr[1] - lowerArr[1]) / 2.0;
            if(channelHalf <= 0) channelHalf = 250 * _Point; // Fallback to 2.5 USD on Gold
             
            sl = ask - channelHalf;
            tp = ask + channelHalf * InpRiskRewardRatio;
             
            // Safety check: ensure SL sits below Ask price
            if(sl >= ask)
               sl = ask - 100 * _Point;
         }

         if(trade.Buy(InpLotSize, _Symbol, ask, 0, tp, "Uptrick Buy Signal"))
         {
            // Find position ticket to record Virtual SL
            ulong posTicket = 0;
            for(int k = PositionsTotal() - 1; k >= 0; k--)
            {
               ulong t = PositionGetTicket(k);
               if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
                  PositionGetString(POSITION_SYMBOL) == _Symbol &&
                  PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               {
                  if(!GlobalVariableCheck("VSL_" + string(t)))
                  {
                     posTicket = t;
                     break;
                  }
               }
            }
            if(posTicket == 0)
            {
               for(int k = PositionsTotal() - 1; k >= 0; k--)
               {
                  ulong t = PositionGetTicket(k);
                  if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
                     PositionGetString(POSITION_SYMBOL) == _Symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                  {
                     posTicket = t;
                     break;
                  }
               }
            }
            if(posTicket > 0)
            {
               GlobalVariableSet("VSL_" + string(posTicket), sl);
               PrintFormat("EA: BUY position ticket #%d. Virtual SL set to %.2f.", posTicket, sl);
            }

            string alertMsg = "🚀 [EA Stealth Alert] BUY Executed on " + _Symbol + "\r\nPrice: " + DoubleToString(ask, _Digits) + "\r\nVirtual SL (Stealth): " + DoubleToString(sl, _Digits) + "\r\nTP: " + DoubleToString(tp, _Digits);
            SendLineNotification(alertMsg);
         }
      }
   }
   else if(isSellSignal)
   {
      Print("EA Signal: SELL Signal Confirmed!");
      
      // Close active Buy positions
      ClosePositions(POSITION_TYPE_BUY);
      
      // Open new Sell position
      if(!PositionExists(POSITION_TYPE_SELL))
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double sl = 0;
         double tp = 0;

         if(InpStrategyMode == STRAT_BREAKOUT)
         {
            if(InpSlMode == SL_MODE_BAND)
               sl = upperArr[1];
            else
               sl = bid + InpFixedSlPoints * _Point;

            // Verify SL sits above Bid price
            if(sl <= bid)
               sl = bid + 100 * _Point;

            double risk = sl - bid;
            tp = bid - risk * InpRiskRewardRatio;
         }
          else // STRAT_MEAN_REVERSION
          {
             // Dynamic Band Mean Reversion Exit: Exits are volatility-scaled based on the channel half-width.
             double channelHalf = (upperArr[1] - lowerArr[1]) / 2.0;
             if(channelHalf <= 0) channelHalf = 250 * _Point; // Fallback to 2.5 USD on Gold
             
             sl = bid + channelHalf;
             tp = bid - channelHalf * InpRiskRewardRatio;
             
             // Safety check: ensure SL sits above Bid price
             if(sl <= bid)
                sl = bid + 100 * _Point;
          }

         if(trade.Sell(InpLotSize, _Symbol, bid, 0, tp, "Uptrick Sell Signal"))
         {
            // Find position ticket to record Virtual SL
            ulong posTicket = 0;
            for(int k = PositionsTotal() - 1; k >= 0; k--)
            {
               ulong t = PositionGetTicket(k);
               if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
                  PositionGetString(POSITION_SYMBOL) == _Symbol &&
                  PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               {
                  if(!GlobalVariableCheck("VSL_" + string(t)))
                  {
                     posTicket = t;
                     break;
                  }
               }
            }
            if(posTicket == 0)
            {
               for(int k = PositionsTotal() - 1; k >= 0; k--)
               {
                  ulong t = PositionGetTicket(k);
                  if(t > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && 
                     PositionGetString(POSITION_SYMBOL) == _Symbol &&
                     PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                  {
                     posTicket = t;
                     break;
                  }
               }
            }
            if(posTicket > 0)
            {
               GlobalVariableSet("VSL_" + string(posTicket), sl);
               PrintFormat("EA: SELL position ticket #%d. Virtual SL set to %.2f.", posTicket, sl);
            }

            string alertMsg = "🔥 [EA Stealth Alert] SELL Executed on " + _Symbol + "\r\nPrice: " + DoubleToString(bid, _Digits) + "\r\nVirtual SL (Stealth): " + DoubleToString(sl, _Digits) + "\r\nTP: " + DoubleToString(tp, _Digits);
            SendLineNotification(alertMsg);
         }
      }
   }
}
//+------------------------------------------------------------------+
