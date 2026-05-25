import re
import json

def parse_html_report(file_path):
    with open(file_path, 'r', encoding='utf-16') as f:
        content = f.read()

    metrics = {}
    
    # Updated patterns for UTF-16 format
    patterns = {
        "Total Net Profit": r'Total Net Profit:.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>',
        "Profit Factor": r'Profit Factor:.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>',
        "Expected Payoff": r'Expected Payoff:.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>',
        "Maximal Drawdown": r'Drawdown Maximal:.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>',
        "Total Trades": r'Total Trades:.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>',
        "Short Trades": r'Short Trades \(won %\):.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>',
        "Long Trades": r'Long Trades \(won %\):.*?</td>.*?<td[^>]*><b>([^<]+)</b></td>'
    }

    for name, pattern in patterns.items():
        match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)
        if match:
            metrics[name] = match.group(1).strip().replace('&nbsp;', ' ')
        else:
            # Fallback
            broad_pattern = rf'{name}.*?</td>.*?<td[^>]*><b>?([^<]+)</b>?</td>'
            broad_match = re.search(broad_pattern, content, re.IGNORECASE | re.DOTALL)
            if broad_match:
                metrics[name] = broad_match.group(1).strip().replace('&nbsp;', ' ')
            else:
                metrics[name] = "Not Found"

    return metrics

if __name__ == "__main__":
    report_path = "d:\\BotTrade\\Uptrick_Backtest_Report.html"
    results = parse_html_report(report_path)
    print(json.dumps(results, indent=4))
    
    # Save to json file
    with open("d:\\BotTrade\\parsed_metrics.json", "w") as f:
        json.dump(results, f, indent=4)
