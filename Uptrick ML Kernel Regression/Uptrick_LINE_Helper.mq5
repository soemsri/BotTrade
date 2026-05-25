//+------------------------------------------------------------------+
//|                                     Uptrick_LINE_Helper.mq5      |
//|                                                          Uptrick |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Uptrick"
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "╔═══════ LINE Messaging API Settings ═══════╗"
input string   InpLineAccessToken = "maIdVxEOzBlYe+Rc3jwzvoTOLho8LhxOdmLaxdRibTDpZ0yZrw0A1PqF6sOs761qHbxlw74n/CJuBzzwLL3cLyCLjSXv/VBHms5jB8OTMUD8pUjkK6Wc6YEOZj7LePjdGsud9yEQ3Z/4YO0inNQTLgdB04t89/1O/w1cDnyilFU="; // Channel Access Token
input string   InpLineTargetId    = ""; // LINE Target ID (Group ID or User ID, optional)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("Uptrick LINE Helper EA Initialized. Listening for alerts...");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("Uptrick LINE Helper EA Stopped.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // No tick processing needed. Alert events are chart-driven.
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Listen for custom indicator signal event 2026
   if(id == CHARTEVENT_CUSTOM + 2026)
   {
      string message = sparam;
      Print("Uptrick LINE Helper: Alert received. Dispatching request...");
      SendLineNotification(message);
   }
}

//+------------------------------------------------------------------+
//| Send LINE Notification via WebRequest                            |
//+------------------------------------------------------------------+
void SendLineNotification(string message)
{
   if(StringLen(InpLineAccessToken) == 0)
   {
      Print("LINE Notification Error: Access Token is empty!");
      return;
   }
   
   string url = "https://api.line.me/v2/bot/message/broadcast";
   if(StringLen(InpLineTargetId) > 0)
      url = "https://api.line.me/v2/bot/message/push";

   string headers = "Content-Type: application/json\r\n" +
                    "Authorization: Bearer " + InpLineAccessToken + "\r\n";

   string body = "";
   // Format raw message inside simple JSON
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
   
   // Send POST WebRequest to LINE server (this is allowed inside EAs)
   int res = WebRequest("POST", url, headers, 3000, post_data, result_data, result_headers);
   if(res == -1)
   {
      Print("LINE Alert Error: HTTP request failed with code ", GetLastError());
   }
   else
   {
      string res_str = CharArrayToString(result_data, 0, WHOLE_ARRAY, CP_UTF8);
      Print("LINE Alert Dispatch Response: ", res_str);
   }
}
//+------------------------------------------------------------------+
