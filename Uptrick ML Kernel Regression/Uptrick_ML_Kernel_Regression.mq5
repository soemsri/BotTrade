//+------------------------------------------------------------------+
//|                               Uptrick: ML Kernel Regression.mq5  |
//|                                                          Uptrick |
//|                                  https://creativecommons.org/    |
//+------------------------------------------------------------------+
#property copyright "Uptrick"
#property link      "https://creativecommons.org/licenses/by-sa/4.0/"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Indicator Settings                                               |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 22
#property indicator_plots   6

// Plot definitions
#property indicator_label1  "Kernel MA"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Upper Band"
#property indicator_type2   DRAW_COLOR_LINE
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Lower Band"
#property indicator_type3   DRAW_COLOR_LINE
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "Trail Bull"
#property indicator_type4   DRAW_LINE
#property indicator_style4  STYLE_SOLID
#property indicator_width4  5

#property indicator_label5  "Trail Bear"
#property indicator_type5   DRAW_LINE
#property indicator_style5  STYLE_SOLID
#property indicator_width5  5

#property indicator_label6  "Candles"
#property indicator_type6   DRAW_COLOR_CANDLES

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_THEME {
   THEME_CLASSIC,          // Classic
   THEME_CYBER_AQUA,       // Cyber Aqua
   THEME_CRIMSON_PULSE,    // Crimson Pulse
   THEME_ROYAL_PURPLE,     // Royal Purple
   THEME_EMERALD_NIGHT,    // Emerald Night
   THEME_MINIMAL_MONO,     // Minimal Mono
   THEME_CLASSIC_EMERALD   // Classic Emerald
};

enum ENUM_VISUAL {
   VIS_BANDS,              // Bands
   VIS_SINGLE_LINE,        // Single Line
   VIS_TRAIL               // Trail
};

enum ENUM_ANCHOR {
   ANCHOR_HIGH_LOW,        // High/Low
   ANCHOR_MAIN_LINE,       // Main Line
   ANCHOR_BANDS            // Bands
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
//--- Kernel Regression Settings
input group "╔═════ Kernel Regression ═════╗"
input int         InpLookback       = 30;          // Lookback Window
input double      InpBandwidth      = 8.0;         // Base Bandwidth (h)
input bool        InpAdaptive       = true;        // Adaptive Bandwidth (ATR-scaled)
input int         InpAtrLen         = 14;          // ATR Length (adaptive)
input int         InpSmooth         = 3;           // MA Output Smoothing

//--- Residual Bands Settings
input group "╔═══════ Residual Bands ═══════╗"
input double      InpBandMult       = 1.0;         // Band Multiplier (sigma)
input int         InpBandLen        = 24;          // Band Lookback (sigma)
input int         InpBandSmooth     = 5;           // Band Smoothing

//--- Visuals Settings
input group "╔═════════ Visuals ═════════╗"
input ENUM_VISUAL InpVisualMode     = VIS_BANDS;   // Visual Mode
input bool        InpShowBars       = true;        // Color Bars
input bool        InpShowTable      = true;        // Show Dashboard
input ENUM_THEME  InpTheme          = THEME_CLASSIC; // Theme
input ENUM_ANCHOR InpLabelAnchor    = ANCHOR_MAIN_LINE; // Label Anchor
input double      InpLabelOffsetMult= 0.50;        // Offset Mult (ATR)

//--- Alerts Settings
input group "╔═════════ Alerts ════════╗"
input bool        InpAlertPopup     = true;        // Alert: Show Popup Alert
input bool        InpAlertMobile    = false;       // Alert: Send Push Notification
input bool        InpAlertLine      = true;        // Alert: Send LINE Notification via Helper

//+------------------------------------------------------------------+
//| Buffers                                                          |
//+------------------------------------------------------------------+
double BufKernelMA[], ColKernelMA[];
double BufUpperBand[], ColUpperBand[];
double BufLowerBand[], ColLowerBand[];
double BufTrailBull[];
double BufTrailBear[];
double BufCandleOpen[], BufCandleHigh[], BufCandleLow[], BufCandleClose[], ColCandle[];

// Private calculations series
double BufTR[];
double BufATR[];
double BufATRNorm[];
double BufATRFactor[];
double BufNWRaw[];
double BufResidual[];
double BufSigmaRaw[];
double BufSigma[];
double BufState[];

// Global variables for themes and drawing
color themeBull, themeBear, themeBg, themeFrame, themeNeutral;

//+------------------------------------------------------------------+
//| Custom functions                                                 |
//+------------------------------------------------------------------+
void GetThemeColors(ENUM_THEME t, color &bull, color &bear, color &bg, color &frame, color &neutral)
{
   switch(t)
   {
      case THEME_CYBER_AQUA:
         bull    = C'0x00,0xE5,0xFF';
         bear    = C'0xFF,0x2E,0x63';
         bg      = C'0x06,0x0B,0x10';
         frame   = C'0x1A,0x2A,0x33';
         neutral = C'0x7F,0xAE,0xC2';
         break;
      case THEME_CRIMSON_PULSE:
         bull    = C'0x00,0xCF,0xFE';
         bear    = C'0xe0,0xf7,0x0e';
         bg      = C'0x12,0x08,0x0C';
         frame   = C'0x2A,0x0F,0x18';
         neutral = C'0x9E,0x76,0x80';
         break;
      case THEME_ROYAL_PURPLE:
         bull    = C'0xc5,0xaf,0xf5';
         bear    = C'0xD9,0x00,0xFF';
         bg      = C'0x0F,0x0B,0x1A';
         frame   = C'0x24,0x1A,0x3A';
         neutral = C'0x9C,0x8F,0xD9';
         break;
      case THEME_EMERALD_NIGHT:
         bull    = C'0x00,0xE6,0x76';
         bear    = C'0xFF,0x52,0x52';
         bg      = C'0x07,0x11,0x0B';
         frame   = C'0x15,0x33,0x22';
         neutral = C'0x7F,0xAF,0x9B';
         break;
      case THEME_MINIMAL_MONO:
         bull    = C'0xFF,0xFF,0xFF';
         bear    = C'92,92,92';
         bg      = C'0x00,0x00,0x00';
         frame   = C'0x1C,0x1C,0x1C';
         neutral = C'0x77,0x77,0x77';
         break;
      case THEME_CLASSIC_EMERALD:
         bull    = C'0,255,0';
         bear    = C'255,0,0';
         bg      = C'0x12,0x12,0x12';
         frame   = C'0x2A,0x2A,0x2A';
         neutral = C'0x9E,0x9E,0x9E';
         break;
      case THEME_CLASSIC:
      default:
         bull    = C'0x5C,0xF0,0xD7';
         bear    = C'0xB3,0x2A,0xC3';
         bg      = C'0x0D,0x0D,0x0D';
         frame   = C'0x1E,0x1E,0x2E';
         neutral = C'0x88,0x88,0x88';
         break;
   }
}

//+------------------------------------------------------------------+
//| Custom Indicator Initialization Function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set theme colors
   GetThemeColors(InpTheme, themeBull, themeBear, themeBg, themeFrame, themeNeutral);

   // Buffer mappings
   SetIndexBuffer(0, BufKernelMA, INDICATOR_DATA);
   SetIndexBuffer(1, ColKernelMA, INDICATOR_COLOR_INDEX);

   SetIndexBuffer(2, BufUpperBand, INDICATOR_DATA);
   SetIndexBuffer(3, ColUpperBand, INDICATOR_COLOR_INDEX);

   SetIndexBuffer(4, BufLowerBand, INDICATOR_DATA);
   SetIndexBuffer(5, ColLowerBand, INDICATOR_COLOR_INDEX);

   SetIndexBuffer(6, BufTrailBull, INDICATOR_DATA);
   SetIndexBuffer(7, BufTrailBear, INDICATOR_DATA);

   SetIndexBuffer(8, BufCandleOpen, INDICATOR_DATA);
   SetIndexBuffer(9, BufCandleHigh, INDICATOR_DATA);
   SetIndexBuffer(10, BufCandleLow, INDICATOR_DATA);
   SetIndexBuffer(11, BufCandleClose, INDICATOR_DATA);
   SetIndexBuffer(12, ColCandle, INDICATOR_COLOR_INDEX);

   // Calculation buffers
   SetIndexBuffer(13, BufTR, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, BufATR, INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, BufATRNorm, INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, BufATRFactor, INDICATOR_CALCULATIONS);
   SetIndexBuffer(17, BufNWRaw, INDICATOR_CALCULATIONS);
   SetIndexBuffer(18, BufResidual, INDICATOR_CALCULATIONS);
   SetIndexBuffer(19, BufSigmaRaw, INDICATOR_CALCULATIONS);
   SetIndexBuffer(20, BufSigma, INDICATOR_CALCULATIONS);
   SetIndexBuffer(21, BufState, INDICATOR_CALCULATIONS);

   // Set plot properties
   // Plot 1: Kernel MA (DRAW_COLOR_LINE)
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, themeBull);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, themeBear);
   PlotIndexSetInteger(0, PLOT_SHOW_DATA, InpVisualMode == VIS_SINGLE_LINE);

   // Plot 2: Upper Band (DRAW_COLOR_LINE)
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, themeBull);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 1, themeBear);
   PlotIndexSetInteger(1, PLOT_SHOW_DATA, InpVisualMode == VIS_BANDS);

   // Plot 3: Lower Band (DRAW_COLOR_LINE)
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0, themeBull);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 1, themeBear);
   PlotIndexSetInteger(2, PLOT_SHOW_DATA, InpVisualMode == VIS_BANDS);

   // Plot 4: Trail Bull (DRAW_LINE)
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, themeBull);
   PlotIndexSetInteger(3, PLOT_SHOW_DATA, InpVisualMode == VIS_TRAIL);

   // Plot 5: Trail Bear (DRAW_LINE)
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, themeBear);
   PlotIndexSetInteger(4, PLOT_SHOW_DATA, InpVisualMode == VIS_TRAIL);

   // Plot 6: Candles (DRAW_COLOR_CANDLES)
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, 0, themeBull);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, 1, themeBear);
   PlotIndexSetInteger(5, PLOT_SHOW_DATA, InpShowBars);

   // Make calculations and plots series (time runs backwards: index 0 is newest)
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
      // Set all buffers as series (0 = newest)
   ArraySetAsSeries(BufKernelMA, true);
   ArraySetAsSeries(ColKernelMA, true);
   ArraySetAsSeries(BufUpperBand, true);
   ArraySetAsSeries(ColUpperBand, true);
   ArraySetAsSeries(BufLowerBand, true);
   ArraySetAsSeries(ColLowerBand, true);
   ArraySetAsSeries(BufTrailBull, true);
   ArraySetAsSeries(BufTrailBear, true);
   ArraySetAsSeries(BufCandleOpen, true);
   ArraySetAsSeries(BufCandleHigh, true);
   ArraySetAsSeries(BufCandleLow, true);
   ArraySetAsSeries(BufCandleClose, true);
   ArraySetAsSeries(ColCandle, true);

   ArraySetAsSeries(BufTR, true);
   ArraySetAsSeries(BufATR, true);
   ArraySetAsSeries(BufATRNorm, true);
   ArraySetAsSeries(BufATRFactor, true);
   ArraySetAsSeries(BufNWRaw, true);
   ArraySetAsSeries(BufResidual, true);
   ArraySetAsSeries(BufSigmaRaw, true);
   ArraySetAsSeries(BufSigma, true);
   ArraySetAsSeries(BufState, true);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom Indicator Deinitialization Function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up BUY/SELL text labels from chart
   for(int i = ObjectsTotal(0, 0, OBJ_TEXT) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_TEXT);
      if(StringFind(name, "Uptrick_Label_") == 0)
         ObjectDelete(0, name);
   }

   // Clean up dashboard rectangle labels
   for(int i = ObjectsTotal(0, 0, OBJ_RECTANGLE_LABEL) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_RECTANGLE_LABEL);
      if(StringFind(name, "Uptrick_Tbl_") == 0)
         ObjectDelete(0, name);
   }

   // Clean up dashboard text labels
   for(int i = ObjectsTotal(0, 0, OBJ_LABEL) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_LABEL);
      if(StringFind(name, "Uptrick_Tbl_") == 0)
         ObjectDelete(0, name);
   }
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Dashboard Drawing                                                |
//+------------------------------------------------------------------+
void CreateCell(string name, string text, int x, int y, color textCol, color bgCol, ENUM_ANCHOR_POINT anchor, int fontSize, bool isHeader)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
      
   if(ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Courier New");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, textCol);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void DrawDashboard(double kernelMA, double upper, double lower, double sigma, double h, bool isBull, bool isAdaptive)
{
   if(!InpShowTable) return;
   
   // Clean up table elements
   for(int i = ObjectsTotal(0, 0, OBJ_LABEL) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_LABEL);
      if(StringFind(name, "Uptrick_Tbl_") == 0)
         ObjectDelete(0, name);
   }
   for(int i = ObjectsTotal(0, 0, OBJ_RECTANGLE_LABEL) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_RECTANGLE_LABEL);
      if(StringFind(name, "Uptrick_Tbl_") == 0)
         ObjectDelete(0, name);
   }

   int tableWidth = 280;
   int tableHeight = 148;
   int xStart = 20;
   int yStart = 20;
   
   // Background
   string bgName = "Uptrick_Tbl_BG";
   if(ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, xStart);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, yStart);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, tableWidth);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, tableHeight);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, themeBg);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, themeFrame);
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, bgName, OBJPROP_SELECTABLE, false);
   }
   
   // Header Background
   string hdrName = "Uptrick_Tbl_HDR_BG";
   if(ObjectCreate(0, hdrName, OBJ_RECTANGLE_LABEL, 0, 0, 0))
   {
      ObjectSetInteger(0, hdrName, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, hdrName, OBJPROP_XDISTANCE, xStart + 2);
      ObjectSetInteger(0, hdrName, OBJPROP_YDISTANCE, yStart + tableHeight - 22);
      ObjectSetInteger(0, hdrName, OBJPROP_XSIZE, tableWidth - 4);
      ObjectSetInteger(0, hdrName, OBJPROP_YSIZE, 20);
      ObjectSetInteger(0, hdrName, OBJPROP_BGCOLOR, themeFrame);
      ObjectSetInteger(0, hdrName, OBJPROP_BORDER_COLOR, themeFrame);
      ObjectSetInteger(0, hdrName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, hdrName, OBJPROP_SELECTABLE, false);
   }

   // Row 0: Headers
   int yOffset = yStart + tableHeight - 20;
   CreateCell("Uptrick_Tbl_C0_R0", "ML KERNEL MA", xStart + tableWidth - 10, yOffset, clrWhite, themeFrame, ANCHOR_LEFT, 9, true);
   CreateCell("Uptrick_Tbl_C1_R0", "VALUE", xStart + 10, yOffset, clrWhite, themeFrame, ANCHOR_RIGHT, 9, true);

   // Row 1: Signal
   yOffset -= 20;
   string sigText = isBull ? "▲  BULLISH" : "▼  BEARISH";
   color sigCol = isBull ? themeBull : themeBear;
   CreateCell("Uptrick_Tbl_C0_R1", "Signal", xStart + tableWidth - 10, yOffset, clrWhite, themeBg, ANCHOR_LEFT, 9, false);
   CreateCell("Uptrick_Tbl_C1_R1", sigText, xStart + 10, yOffset, sigCol, themeBg, ANCHOR_RIGHT, 9, false);

   // Row 2: Kernel MA
   yOffset -= 20;
   CreateCell("Uptrick_Tbl_C0_R2", "Kernel MA", xStart + tableWidth - 10, yOffset, clrWhite, themeBg, ANCHOR_LEFT, 9, false);
   CreateCell("Uptrick_Tbl_C1_R2", DoubleToString(kernelMA, _Digits), xStart + 10, yOffset, sigCol, themeBg, ANCHOR_RIGHT, 9, false);

   // Row 3: Upper Band
   yOffset -= 20;
   CreateCell("Uptrick_Tbl_C0_R3", "Upper Band", xStart + tableWidth - 10, yOffset, clrWhite, themeBg, ANCHOR_LEFT, 9, false);
   CreateCell("Uptrick_Tbl_C1_R3", DoubleToString(upper, _Digits), xStart + 10, yOffset, themeBull, themeBg, ANCHOR_RIGHT, 9, false);

   // Row 4: Lower Band
   yOffset -= 20;
   CreateCell("Uptrick_Tbl_C0_R4", "Lower Band", xStart + tableWidth - 10, yOffset, clrWhite, themeBg, ANCHOR_LEFT, 9, false);
   CreateCell("Uptrick_Tbl_C1_R4", DoubleToString(lower, _Digits), xStart + 10, yOffset, themeBear, themeBg, ANCHOR_RIGHT, 9, false);

   // Row 5: Band Width σ
   yOffset -= 20;
   CreateCell("Uptrick_Tbl_C0_R5", "Band Width o", xStart + tableWidth - 10, yOffset, clrWhite, themeBg, ANCHOR_LEFT, 9, false);
   CreateCell("Uptrick_Tbl_C1_R5", DoubleToString(sigma, _Digits), xStart + 10, yOffset, clrWhite, themeBg, ANCHOR_RIGHT, 9, false);

   // Row 6: Bandwidth h
   yOffset -= 20;
   string bwText = DoubleToString(h, 2) + (isAdaptive ? "  (adaptive)" : "");
   CreateCell("Uptrick_Tbl_C0_R6", "Bandwidth h", xStart + tableWidth - 10, yOffset, clrWhite, themeBg, ANCHOR_LEFT, 9, false);
   CreateCell("Uptrick_Tbl_C1_R6", bwText, xStart + 10, yOffset, clrWhite, themeBg, ANCHOR_RIGHT, 9, false);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| BUY/SELL label creation                                          |
//+------------------------------------------------------------------+
void CreateSignalLabel(int bar, double state, datetime barTime, double highPrice, double lowPrice, double lowerBandVal, double upperBandVal, double kernelVal)
{
   double atr = BufATR[bar] * BufCandleClose[bar]; // Re-scaling Normalized ATR to absolute price ATR
   if(atr <= 0) atr = _Point * 10;
   
   double offset = atr * InpLabelOffsetMult;

   double baseLongY = 0;
   double baseShortY = 0;

   if(InpLabelAnchor == ANCHOR_HIGH_LOW)
   {
      baseLongY = lowPrice;
      baseShortY = highPrice;
   }
   else if(InpLabelAnchor == ANCHOR_BANDS)
   {
      baseLongY = lowerBandVal;
      baseShortY = upperBandVal;
   }
   else // ANCHOR_MAIN_LINE
   {
      baseLongY = kernelVal;
      baseShortY = kernelVal;
   }

   double yPrice = (state == 1.0) ? (baseLongY - offset) : (baseShortY + offset);
   string text = (state == 1.0) ? "BUY" : "SELL";
   color col = (state == 1.0) ? themeBull : themeBear;
   
   string name = "Uptrick_Label_" + string((long)barTime);
   
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
      
   if(ObjectCreate(0, name, OBJ_TEXT, 0, barTime, yPrice))
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, "Lucida Console");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, name, OBJPROP_COLOR, col);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

//+------------------------------------------------------------------+
//| Alert / Notifications Dispatch                                   |
//+------------------------------------------------------------------+
void TriggerNotification(double state, double price)
{
   string msg = "";
   if(state == 1.0)
      msg = "🟢 Uptrick NW Kernel MA: BUY Signal (Bullish Breakout) confirmed at " + DoubleToString(price, _Digits);
   else if(state == -1.0)
      msg = "🔴 Uptrick NW Kernel MA: SELL Signal (Bearish Breakdown) confirmed at " + DoubleToString(price, _Digits);
      
   if(StringLen(msg) > 0)
   {
      // 1. Popup Alert
      if(InpAlertPopup)
         Alert(msg);
         
      // 2. Mobile Push Notification
      if(InpAlertMobile)
         SendNotification(msg);
         
      // 3. LINE Helper Dispatch (asynchronous workaround via Custom Event)
      if(InpAlertLine)
      {
         // Send Custom Event 2026 to the active chart
         EventChartCustom(0, 2026, (long)state, price, msg);
      }
   }
}

//+------------------------------------------------------------------+
//| Custom Indicator Iteration Function                              |
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
   // Validate historical bar counts
   if(rates_total < InpLookback || rates_total < InpBandLen)
      return(0);

   // Configure series arrays in Pine Script indexing direction (0 = newest)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(low, true);

   // Define limits for calculation loop
   int limit = rates_total - prev_calculated;
   if(limit < 0) limit = 0;
   if(limit > 0) limit += 2; // margins to recalculate last confirmed bars
   
   if(prev_calculated == 0)
   {
      limit = rates_total - 2;
      
      // Initialize oldest bar settings
      int oldest = rates_total - 1;
      BufTR[oldest]        = 0.0;
      BufATR[oldest]       = 0.0;
      BufATRNorm[oldest]   = 0.0;
      BufATRFactor[oldest] = 0.0;
      BufNWRaw[oldest]     = close[oldest];
      BufKernelMA[oldest]  = close[oldest];
      BufResidual[oldest]  = 0.0;
      BufSigmaRaw[oldest]  = 0.0;
      BufSigma[oldest]     = 0.0;
      BufState[oldest]     = 0.0;
      
      BufUpperBand[oldest] = close[oldest];
      BufLowerBand[oldest] = close[oldest];
      BufTrailBull[oldest] = EMPTY_VALUE;
      BufTrailBear[oldest] = EMPTY_VALUE;
      
      ColKernelMA[oldest]  = 0;
      ColUpperBand[oldest] = 0;
      ColLowerBand[oldest] = 0;
   }

   // Ensure calculation limit fits bounds
   if(limit >= rates_total - 1)
      limit = rates_total - 2;

   // Main loops: calculate series from oldest to newest (index 'bar' down to 0)
   for(int bar = limit; bar >= 0; bar--)
   {
      //--- Mapped copies for candles Plot
      BufCandleOpen[bar]  = open[bar];
      BufCandleHigh[bar]  = high[bar];
      BufCandleLow[bar]   = low[bar];
      BufCandleClose[bar] = close[bar];

      //--- Step 1: True Range (TR) & Average True Range (ATR)
      double tr = fmax(high[bar] - low[bar], fmax(MathAbs(high[bar] - close[bar+1]), MathAbs(low[bar] - close[bar+1])));
      BufTR[bar] = tr;
      
      double atr = (BufATR[bar+1] == 0) ? tr : (tr + (InpAtrLen - 1) * BufATR[bar+1]) / InpAtrLen;
      BufATR[bar] = atr;
      
      double atrNorm = (close[bar] != 0.0) ? (atr / close[bar]) : 0.0;
      BufATRNorm[bar] = atrNorm;
      
      double alphaAtr = 2.0 / (InpAtrLen + 1.0);
      double atrFactor = (BufATRFactor[bar+1] == 0) ? atrNorm : (atrNorm * alphaAtr) + (BufATRFactor[bar+1] * (1.0 - alphaAtr));
      BufATRFactor[bar] = atrFactor;

      //--- Step 2: Adaptive Bandwidth (h)
      double adaptScale = InpAdaptive ? (1.0 + atrFactor * 200.0) : 1.0;
      double h = InpBandwidth * adaptScale;

      //--- Step 3: Nadaraya-Watson Gaussian Kernel Regression Loop
      double nwSum = 0.0;
      double nwWeight = 0.0;
      for(int i = 0; i < InpLookback; i++)
      {
         if(bar + i >= rates_total) break;
         double kw = exp(-pow(i, 2) / (2.0 * pow(h, 2)));
         nwSum += kw * close[bar + i];
         nwWeight += kw;
      }
      double nwRaw = (nwWeight > 0) ? (nwSum / nwWeight) : close[bar];
      BufNWRaw[bar] = nwRaw;

      //--- Step 4: Smoothing the raw midline
      double alphaSmooth = 2.0 / (InpSmooth + 1.0);
      double kernelMA = (nwRaw * alphaSmooth) + (BufKernelMA[bar+1] * (1.0 - alphaSmooth));
      BufKernelMA[bar] = kernelMA;

      //--- Step 5: Residual & Sigma (StDev of residuals)
      double residual = close[bar] - kernelMA;
      BufResidual[bar] = residual;
      
      double rSum = 0;
      int count = 0;
      for(int k = 0; k < InpBandLen; k++)
      {
         if(bar + k >= rates_total) break;
         rSum += BufResidual[bar + k];
         count++;
      }
      double rMean = (count > 0) ? (rSum / count) : 0;
      double rSumSq = 0;
      for(int k = 0; k < InpBandLen; k++)
      {
         if(bar + k >= rates_total) break;
         rSumSq += pow(BufResidual[bar + k] - rMean, 2);
      }
      double sigmaRaw = (count > 0) ? sqrt(rSumSq / count) : 0.0;
      BufSigmaRaw[bar] = sigmaRaw;

      double alphaBand = 2.0 / (InpBandSmooth + 1.0);
      double sigma = (sigmaRaw * alphaBand) + (BufSigma[bar+1] * (1.0 - alphaBand));
      BufSigma[bar] = sigma;

      //--- Step 6: Residual bands limits
      double upper = kernelMA + InpBandMult * sigma;
      double lower = kernelMA - InpBandMult * sigma;
      
      BufUpperBand[bar] = upper;
      BufLowerBand[bar] = lower;

      //--- Step 7: State Management Engine (Confirmed / Non-repainting)
      double lastState = (bar + 1 < rates_total) ? BufState[bar+1] : 0.0;
      double currentState = lastState;
      
      if(bar > 0)
      {
         if(close[bar] > upper)
            currentState = 1.0;
         else if(close[bar] < lower)
            currentState = -1.0;
         BufState[bar] = currentState;
      }
      else
      {
         // Live bar (index 0) holds latest confirmed state from previous bar (index 1)
         currentState = lastState;
         BufState[bar] = currentState;
      }

      //--- Step 8: Visual Plots & Colors Mapping
      bool isBullTrend = (currentState == 1.0);
      ColKernelMA[bar]  = isBullTrend ? 0.0 : 1.0;
      ColUpperBand[bar] = isBullTrend ? 0.0 : 1.0;
      ColLowerBand[bar] = isBullTrend ? 0.0 : 1.0;
      ColCandle[bar]    = isBullTrend ? 0.0 : 1.0;

      // Trail mode plots
      if(InpVisualMode == VIS_TRAIL)
      {
         BufTrailBull[bar] = isBullTrend ? lower : EMPTY_VALUE;
         BufTrailBear[bar] = !isBullTrend ? upper : EMPTY_VALUE;
      }
      else
      {
         BufTrailBull[bar] = EMPTY_VALUE;
         BufTrailBear[bar] = EMPTY_VALUE;
      }

      //--- Step 9: Confirmed Transitions & BUY/SELL Labels
      if(bar > 0 && bar + 1 < rates_total)
      {
         double statePrev = BufState[bar+1];
         if(currentState != statePrev && statePrev != 0.0)
         {
            // Draw Buy/Sell text labels
            CreateSignalLabel(bar, currentState, time[bar], high[bar], low[bar], lower, upper, kernelMA);
            
            // Dispatch live notification once the newest bar is fully closed (bar == 1)
            if(bar == 1)
            {
               TriggerNotification(currentState, close[1]);
            }
         }
      }
   }

   //--- Step 10: Render Dashboard in real-time
   if(InpShowTable)
   {
      double curKernel = BufKernelMA[0];
      double curUpper  = BufUpperBand[0];
      double curLower  = BufLowerBand[0];
      double curSigma  = BufSigma[0];
      double curAtrFactor = BufATRFactor[0];
      double curH = InpBandwidth * (InpAdaptive ? (1.0 + curAtrFactor * 200.0) : 1.0);
      bool isBull = (BufState[0] == 1.0);
      
      DrawDashboard(curKernel, curUpper, curLower, curSigma, curH, isBull, InpAdaptive);
   }

   return(rates_total);
}
//+------------------------------------------------------------------+
