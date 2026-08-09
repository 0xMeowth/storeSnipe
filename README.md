# storeSnipe

KoLmafia script that snipes daily loss-leader sales from specific mall stores.

Some stores sell items below fair value with a daily purchase limit. storeSnipe scans a list of store IDs you keep in mafia properties, buys anything that is provably cheap, and prints a report showing the fair value, the current 5th-cheapest mall price, and the estimated gain if you resold each item.

## Install

Run both commands in KoLmafia's gCLI (the first installs the price DB used for fair values):

```
git checkout libraryaddict/KolItemPrices master
git checkout 0xMeowth/storeSnipe release
```

## First run

1. Configure the stores to watch (comma-separated store IDs; optional `:N` per-shop spend cap):

   ```
   set storeSnipe_shops = 123456,654321:5000
   ```

2. Preview what would be bought (buys nothing):

   ```
   storeSnipe dry
   ```

3. Buy for real:

   ```
   storeSnipe run
   ```

You can also check a single store without configuring it:

```
storeSnipe 123456          <- preview one shop
storeSnipe 123456 buy      <- buy from one shop
storeSnipe 123456 debug    <- verbose dry run, shows why each listing passed/failed
```

Use `storeSnipe run` (with the explicit argument) in automation — it never triggers mafia's input popup.

## How it decides to buy

An item in a scanned store is bought only when all of these hold:

1. **Value test** — fair value known: price <= `fairFraction` x fair value. Fair value unknown: only if the price is at the mall floor (`max(100, 2 x autosell)`) *and* you opted in with `storeSnipe_buyUnknownFair`.
2. Price <= the per-unit ceiling.
3. The shop's spend cap isn't exhausted.

Daily limits are respected when present (never over-buys a limited listing) but not required; unlimited listings are bought up to `storeSnipe_unlimitedQty` units per run.

## Config

All config lives in mafia properties, so your shop list stays out of the script file. Set once in the gCLI:

| Property | Default | What it does |
|---|---|---|
| `storeSnipe_shops` | *(required)* | Store IDs to scan, e.g. `123456,654321:5000` (`:N` overrides that shop's spend cap) |
| `storeSnipe_unitCeiling` | `500` | Never pay more than this per unit |
| `storeSnipe_fairFraction` | `0.6` | Buy only at or below this fraction of fair value |
| `storeSnipe_shopSpendCap` | `2000` | Default meat spend cap per shop per run |
| `storeSnipe_unlimitedQty` | `10` | Units to buy of listings with no daily limit |
| `storeSnipe_buyUnknownFair` | `false` | `true` = speculate on floor-priced items with unknown fair value |

## The report

After each run (or dry run) you get a per-shop table:

- **Fair/unit** — Irrat DB fair value
- **Mall(5th)** — mafia's current 5th-cheapest mall listing
- **Adj FV** — average of the two (or whichever is known)
- **Est. gain** — `(Adj FV - price paid) x qty`, i.e. what you'd make reselling at fair value

## License

Public domain (Unlicense).
