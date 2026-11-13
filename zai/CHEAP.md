# The 3K setup — cheapest way to run Levi

Measured cost: **$0.00061 per message** at 3K context, peak. Half that off-peak.
That is **$0.44/day** even if you send a message every 2 minutes for 24 hours.
$1.75 lasts **4 days** at that absurd rate, **~75 days** at normal use.

## Start it

```sh
curl -fsSL https://raw.githubusercontent.com/AmbitiousBoyII14/opencode-termux/main/zai/cheap.sh -o ~/zai/cheap.sh
sh ~/zai/cheap.sh
```

That does three things:

1. caps `max_tokens` at **512** (output is $1.20/M — the expensive line)
2. logs exact spend to `~/zai/levi-usage.log`
3. keeps NVIDIA as fallback if DeepSeek fails

## The one habit that saves the most

**Type `/new` every ~25 messages.**

| context | cost/msg | 24h @720 msgs |
|---|---|---|
| **3K** | **$0.00061** | **$0.44** |
| 10K | $0.00078 | $0.56 |
| 25K | $0.00113 | $0.81 |
| 50K | $0.00172 | $1.24 |
| 85K | $0.00255 | $1.84 |

Going 3K -> 85K is **4.2x** more expensive per message. Context is the whole game.

## Run after midday

Off-peak is exactly **half price**: everything except **Mon-Fri 03:00-06:00
and 08:00-12:00 SAST**. A 24h run started at 12:00 is mostly off-peak.

## Check spend anytime

```sh
python3 ~/zai/burn.py
```

Reads real token usage from the proxy log, so the number is measured, not
estimated.

## Free option

Set `LEVI_MAX_TOKENS=512` and put only the `nvidia=` key in `keys.txt` — then
`/health` shows `["nvidia"]` and you spend **$0.00**. Slower and weaker on
diagnosis, but free forever.
