//+------------------------------------------------------------------+
//|                                              SMC_Venom_BPR.mq5   |
//|                                  SMC Venom BPR Indicator         |
//|                        Detects FVG, BPR, Breaker Blocks          |
//|                                 with Venom Time Window Filter    |
//+------------------------------------------------------------------+
#property copyright "SMC Venom BPR"
#property link      ""
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 8
#property indicator_plots   6

//--- Plot definitions
#property indicator_label1  "Bullish FVG Up"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Bullish FVG Dn"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrLime
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Bearish FVG Up"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

#property indicator_label4  "Bearish FVG Dn"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrRed
#property indicator_style4  STYLE_SOLID
#property indicator_width4  1

#property indicator_label5  "BPR Up"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_SOLID
#property indicator_width5  2

#property indicator_label6  "BPR Dn"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrDodgerBlue
#property indicator_style6  STYLE_SOLID
#property indicator_width6  2

//--- Input parameters - General settings
input int    InpSwingLeft        = 5;       // Левое плечо для swing-поиска
input int    InpSwingRight       = 2;       // Правое плечо для swing-поиска
input int    InpMaxBarsBack      = 500;     // Глубина анализа истории

//--- Input parameters - FVG / BPR
input double InpMinFVGSize       = 0.0;     // Мин. размер FVG (в пунктах, 0 = авто)
input int    InpBPRWindow        = 10;      // Окно поиска пересечения FVG (баров)
input bool   InpShowFVG          = true;    // Показывать FVG
input bool   InpShowBPR          = true;    // Показывать BPR
input bool   InpShowBreaker      = true;    // Показывать Breaker Blocks

//--- Input parameters - Venom (время)
input int    InpVenomStartHour   = 13;      // Начало окна Venom (серверное время)
input int    InpVenomEndHour     = 16;      // Конец окна Venom
input bool   InpVenomOnly        = true;    // Сигналы ТОЛЬКО в окне Venom

//--- Input parameters - Visual
input color  InpBullFVGColor     = clrLime;
input color  InpBearFVGColor     = clrRed;
input color  InpBPRColor         = clrDodgerBlue;
input color  InpBreakerColor     = clrOrange;
input int    InpZoneOpacity      = 30;      // Прозрачность зон (0-100)

//--- Input parameters - Signals
input bool   InpAlertEnabled     = true;
input bool   InpPushEnabled      = false;
input bool   InpEmailEnabled     = false;

//--- Indicator buffers
double BullishFVG_Up[];
double BullishFVG_Dn[];
double BearishFVG_Up[];
double BearishFVG_Dn[];
double BPR_Up[];
double BPR_Dn[];
double SignalBuffer[];
double SignalTypeBuffer[];

//--- Global variables
int lastSignalBar = -1;
string zonePrefix = "SMCVenom_";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Set buffer indices
   SetIndexBuffer(0, BullishFVG_Up, INDICATOR_DATA);
   SetIndexBuffer(1, BullishFVG_Dn, INDICATOR_DATA);
   SetIndexBuffer(2, BearishFVG_Up, INDICATOR_DATA);
   SetIndexBuffer(3, BearishFVG_Dn, INDICATOR_DATA);
   SetIndexBuffer(4, BPR_Up, INDICATOR_DATA);
   SetIndexBuffer(5, BPR_Dn, INDICATOR_DATA);
   SetIndexBuffer(6, SignalBuffer, INDICATOR_DRAWING);
   SetIndexBuffer(7, SignalTypeBuffer, INDICATOR_CALCULATIONS);
   
   //--- Initialize arrays as series
   ArraySetAsSeries(BullishFVG_Up, true);
   ArraySetAsSeries(BullishFVG_Dn, true);
   ArraySetAsSeries(BearishFVG_Up, true);
   ArraySetAsSeries(BearishFVG_Dn, true);
   ArraySetAsSeries(BPR_Up, true);
   ArraySetAsSeries(BPR_Dn, true);
   ArraySetAsSeries(SignalBuffer, true);
   ArraySetAsSeries(SignalTypeBuffer, true);
   
   //--- Validate input parameters
   if(InpSwingLeft <= 0)
   {
      Print("Error: InpSwingLeft must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpSwingRight <= 0)
   {
      Print("Error: InpSwingRight must be > 0");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpVenomStartHour >= InpVenomEndHour)
   {
      Print("Error: InpVenomStartHour must be < InpVenomEndHour");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpZoneOpacity < 0 || InpZoneOpacity > 100)
   {
      Print("Error: InpZoneOpacity must be between 0 and 100");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   //--- Clear all existing objects on start
   ObjectsDeleteAll(0, zonePrefix);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Delete all graphical objects
   ObjectsDeleteAll(0, zonePrefix);
   Comment("");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
   //--- Check minimum bars
   if(rates_total < InpSwingLeft + InpSwingRight + 5)
      return(0);
   
   //--- Calculate from bar
   int limit = rates_total - prev_calculated;
   if(limit > 1)
   {
      limit = rates_total - 1;
      //--- Clear buffers on full recalculation
      ArrayInitialize(BullishFVG_Up, EMPTY_VALUE);
      ArrayInitialize(BullishFVG_Dn, EMPTY_VALUE);
      ArrayInitialize(BearishFVG_Up, EMPTY_VALUE);
      ArrayInitialize(BearishFVG_Dn, EMPTY_VALUE);
      ArrayInitialize(BPR_Up, EMPTY_VALUE);
      ArrayInitialize(BPR_Dn, EMPTY_VALUE);
      ArrayInitialize(SignalBuffer, EMPTY_VALUE);
      
      //--- Clean up old objects
      CleanupOldObjects(time[0]);
   }
   
   //--- Main calculation loop
   for(int i = limit; i >= 0 && i < rates_total - InpSwingRight; i--)
   {
      //--- Detect FVG
      DetectFVG(i, high, low, close);
      
      //--- Detect BPR
      if(InpShowBPR)
         DetectBPR(i, time, high, low);
      
      //--- Detect Breaker Blocks
      if(InpShowBreaker)
         DetectBreaker(i, time, high, low, close);
      
      //--- Check for Venom signals
      CheckVenomSignal(i, time, high, low, close);
   }
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Detect FVG (Fair Value Gap)                                      |
//+------------------------------------------------------------------+
void DetectFVG(int i, const double &high[], const double &low[], const double &close[])
{
   double minFvgSize = InpMinFVGSize;
   if(minFvgSize == 0)
      minFvgSize = _Point * 10; // Auto size
   
   //--- Bullish FVG: Low[i] > High[i+2]
   if(i + 2 < ArraySize(high))
   {
      if(low[i] > high[i+2])
      {
         double fvgSize = low[i] - high[i+2];
         if(fvgSize >= minFvgSize)
         {
            BullishFVG_Up[i] = low[i];
            BullishFVG_Dn[i] = high[i+2];
            
            //--- Draw FVG zone
            if(InpShowFVG)
               DrawZone(i, high[i+2], low[i], "BullFVG", InpBullFVGColor, InpZoneOpacity);
         }
      }
   }
   
   //--- Bearish FVG: High[i] < Low[i+2]
   if(i + 2 < ArraySize(low))
   {
      if(high[i] < low[i+2])
      {
         double fvgSize = low[i+2] - high[i];
         if(fvgSize >= minFvgSize)
         {
            BearishFVG_Up[i] = high[i];
            BearishFVG_Dn[i] = low[i+2];
            
            //--- Draw FVG zone
            if(InpShowFVG)
               DrawZone(i, high[i], low[i+2], "BearFVG", InpBearFVGColor, InpZoneOpacity);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect BPR (Balanced Price Range)                                |
//+------------------------------------------------------------------+
void DetectBPR(int i, const datetime &time[], const double &high[], const double &low[])
{
   //--- Search for overlapping Bullish and Bearish FVG within window
   for(int j = i; j < i + InpBPRWindow && j < ArraySize(high); j++)
   {
      //--- Check if we have both Bullish and Bearish FVG
      if(BullishFVG_Up[j] != EMPTY_VALUE && BearishFVG_Up[j] != EMPTY_VALUE)
      {
         double bullUp = BullishFVG_Up[j];
         double bullDn = BullishFVG_Dn[j];
         double bearUp = BearishFVG_Up[j];
         double bearDn = BearishFVG_Dn[j];
         
         //--- Calculate overlap
         double bprUpper = MathMax(bullDn, bearDn);
         double bprLower = MathMin(bullUp, bearUp);
         
         //--- Valid BPR if upper > lower
         if(bprUpper > bprLower)
         {
            BPR_Up[i] = bprUpper;
            BPR_Dn[i] = bprLower;
            
            //--- Draw BPR zone
            DrawZone(i, bprLower, bprUpper, "BPR", InpBPRColor, InpZoneOpacity + 20);
            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Breaker Block                                             |
//+------------------------------------------------------------------+
void DetectBreaker(int i, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   //--- Find swing highs and lows
   bool isSwingHigh = true;
   bool isSwingLow = true;
   
   //--- Check Swing High
   for(int k = 1; k <= InpSwingLeft; k++)
   {
      if(i + k >= ArraySize(high)) break;
      if(high[i] <= high[i-k]) { isSwingHigh = false; break; }
   }
   for(int k = 1; k <= InpSwingRight; k++)
   {
      if(i - k < 0) { isSwingHigh = false; break; }
      if(high[i] <= high[i-k]) { isSwingHigh = false; break; }
   }
   
   //--- Check Swing Low
   for(int k = 1; k <= InpSwingLeft; k++)
   {
      if(i + k >= ArraySize(low)) break;
      if(low[i] >= low[i+k]) { isSwingLow = false; break; }
   }
   for(int k = 1; k <= InpSwingRight; k++)
   {
      if(i - k < 0) { isSwingLow = false; break; }
      if(low[i] >= low[i-k]) { isSwingLow = false; break; }
   }
   
   //--- Bullish Breaker: last bearish swing before bullish impulse
   if(isSwingLow && close[i] < open[i])
   {
      //--- Check if there was a bullish breakout after this swing
      bool breakoutFound = false;
      for(int k = i - 1; k >= i - InpSwingLeft * 2 && k >= 0; k--)
      {
         if(high[k] > high[i])
         {
            breakoutFound = true;
            break;
         }
      }
      
      if(breakoutFound)
      {
         DrawZone(i, low[i], high[i], "BullBreaker", InpBreakerColor, InpZoneOpacity);
      }
   }
   
   //--- Bearish Breaker: last bullish swing before bearish impulse
   if(isSwingHigh && close[i] > open[i])
   {
      //--- Check if there was a bearish breakout after this swing
      bool breakoutFound = false;
      for(int k = i - 1; k >= i - InpSwingLeft * 2 && k >= 0; k--)
      {
         if(low[k] < low[i])
         {
            breakoutFound = true;
            break;
         }
      }
      
      if(breakoutFound)
      {
         DrawZone(i, low[i], high[i], "BearBreaker", InpBreakerColor, InpZoneOpacity);
      }
   }
}

//+------------------------------------------------------------------+
//| Check Venom Signal                                               |
//+------------------------------------------------------------------+
void CheckVenomSignal(int i, const datetime &time[], const double &high[], const double &low[], const double &close[])
{
   //--- Check time window
   MqlDateTime dt;
   TimeToStruct(time[i], dt);
   
   bool inVenomWindow = (dt.hour >= InpVenomStartHour && dt.hour < InpVenomEndHour);
   
   if(InpVenomOnly && !inVenomWindow)
      return;
   
   //--- Check if price is in BPR zone
   bool inBullishBPR = (BPR_Up[i] != EMPTY_VALUE && close[i] <= BPR_Up[i] && close[i] >= BPR_Dn[i]);
   bool inBearishBPR = (BPR_Dn[i] != EMPTY_VALUE && close[i] <= BPR_Up[i] && close[i] >= BPR_Dn[i]);
   
   //--- Simple MSS detection (Market Structure Shift)
   bool mssUp = false;
   bool mssDown = false;
   
   if(i >= 3)
   {
      //--- MSS Up: higher high after lower low
      if(high[i] > high[i-1] && low[i] > low[i-1] && close[i] > open[i])
         mssUp = true;
      
      //--- MSS Down: lower low after higher high
      if(low[i] < low[i-1] && high[i] < high[i-1] && close[i] < open[i])
         mssDown = true;
   }
   
   //--- Generate signals
   string signalType = "";
   
   if(inBullishBPR && mssUp && i != lastSignalBar)
   {
      SignalBuffer[i] = low[i] - 20 * _Point;
      SignalTypeBuffer[i] = 1; // BUY
      signalType = "BUY";
      lastSignalBar = i;
      
      SendSignal("BUY", close[i], "BPR", time[i]);
      DrawArrow(i, low[i] - 20 * _Point, 233, clrLime);
   }
   else if(inBearishBPR && mssDown && i != lastSignalBar)
   {
      SignalBuffer[i] = high[i] + 20 * _Point;
      SignalTypeBuffer[i] = -1; // SELL
      signalType = "SELL";
      lastSignalBar = i;
      
      SendSignal("SELL", close[i], "BPR", time[i]);
      DrawArrow(i, high[i] + 20 * _Point, 234, clrRed);
   }
}

//+------------------------------------------------------------------+
//| Draw Zone Rectangle                                              |
//+------------------------------------------------------------------+
void DrawZone(int barIndex, double priceLow, double priceHigh, string type, color col, int opacity)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string objName = zonePrefix + type + "_" + IntegerToString(barIndex) + "_" + IntegerToString(dt.sec);
   
   //--- Check if object already exists
   if(ObjectFind(0, objName) >= 0)
      return;
   
   datetime time1 = TimeCurrent();
   datetime time2 = TimeCurrent();
   
   //--- Create rectangle label as zone visualization
   long chartID = ChartID();
   
   //--- Use OBJ_RECTANGLE_LABEL for zone display
   ObjectCreate(chartID, objName, OBJ_RECTANGLE_LABEL, 0, time1, priceHigh, time2, priceLow);
   ObjectSetInteger(chartID, objName, OBJPROP_COLOR, col);
   ObjectSetInteger(chartID, objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(chartID, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(chartID, objName, OBJPROP_BACK, true);
   ObjectSetInteger(chartID, objName, OBJPROP_SELECTABLE, false);
   
   //--- Set opacity through color with alpha
   color colWithAlpha = ColorToAlpha(col, opacity);
   ObjectSetInteger(chartID, objName, OBJPROP_COLOR, colWithAlpha);
}

//+------------------------------------------------------------------+
//| Convert color with alpha                                         |
//+------------------------------------------------------------------+
color ColorToAlpha(color baseColor, int opacityPercent)
{
   //--- Simple opacity simulation via color blending
   //--- For full alpha support, use ARGB
   uchar r = (uchar)((GetR(baseColor) * opacityPercent) / 100);
   uchar g = (uchar)((GetG(baseColor) * opacityPercent) / 100);
   uchar b = (uchar)((GetB(baseColor) * opacityPercent) / 100);
   
   return ColorToARGB(r, g, b, 255 - (opacityPercent * 255 / 100));
}

//+------------------------------------------------------------------+
//| Draw Signal Arrow                                                |
//+------------------------------------------------------------------+
void DrawArrow(int barIndex, double price, int arrowCode, color col)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string objName = zonePrefix + "Arrow_" + IntegerToString(barIndex) + "_" + IntegerToString(dt.sec);
   
   datetime timeVal = TimeCurrent();
   
   ObjectCreate(ChartID(), objName, OBJ_ARROW, 0, timeVal, price);
   ObjectSetInteger(ChartID(), objName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(ChartID(), objName, OBJPROP_COLOR, col);
   ObjectSetInteger(ChartID(), objName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(ChartID(), objName, OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Send Signal Notification                                         |
//+------------------------------------------------------------------+
void SendSignal(string signalType, double price, string zoneType, datetime signalTime)
{
   MqlDateTime dt;
   TimeToStruct(signalTime, dt);
   
   string message = StringFormat("[SMC Venom BPR] | %s | %s | %s @ %.5f | Zone: %s | Time: %02d:%02d",
                                 Symbol(),
                                 EnumToString(Period()),
                                 signalType,
                                 price,
                                 zoneType,
                                 dt.hour,
                                 dt.min);
   
   //--- Alert
   if(InpAlertEnabled)
      Alert(message);
   
   //--- Push notification
   if(InpPushEnabled)
      SendNotification(message);
   
   //--- Email
   if(InpEmailEnabled)
      SendMail("[SMC Venom BPR]", message);
}

//+------------------------------------------------------------------+
//| Cleanup old objects                                              |
//+------------------------------------------------------------------+
void CleanupOldObjects(datetime currentTime)
{
   //--- Remove objects older than InpMaxBarsBack
   int totalObjects = ObjectsTotal(0, 0, OBJ_RECTANGLE_LABEL);
   
   for(int i = totalObjects - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, OBJ_RECTANGLE_LABEL);
      if(StringFind(name, zonePrefix) == 0)
      {
         //--- Check age of object (simplified)
         //--- In production, store creation time and compare
      }
   }
}

//+------------------------------------------------------------------+
