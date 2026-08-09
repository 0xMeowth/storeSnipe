#storeSnipe.ash  (v2.9)
#Snipe daily loss-leader sales from specific mall stores.
#
#An item in a scanned store is bought when ALL of these hold:
#   1. VALUE TEST:
#      - fair value known (KolItemPrices DB): price <= fairFraction x fair value
#      - fair value unknown: price <= mall floor ( max(100, 2 x autosell) ),
#        and only if storeSnipe_buyUnknownFair = true (default false: skip)
#   2. price <= unitCeiling (default 500 meat per unit)
#   3. this shop's spend cap (default 2000 meat) isn't exhausted
#Daily limits are respected when present (never over-buy a limited listing) but
#are NOT required. Unlimited listings are bought up to storeSnipe_unlimitedQty
#units (default 10) per run.
#
#Config lives in mafia properties (settings/<char>_prefs.txt), so your shop
#list stays out of the script file and can be kept private when publishing.
#Set once in the gCLI:
#   set storeSnipe_shops = 123456,654321:5000
#       (comma-separated store IDs; optional :N per-shop spend cap override)
#   set storeSnipe_unitCeiling = 500        (optional, default 500)
#   set storeSnipe_fairFraction = 0.6       (optional, default 0.6)
#   set storeSnipe_shopSpendCap = 2000      (optional, default 2000)
#   set storeSnipe_unlimitedQty = 10        (optional, default 10)
#   set storeSnipe_buyUnknownFair = false   (optional; true = speculate on floor-priced
#                                            items whose fair value is unknown)
#
#Usage (gCLI):
#   storeSnipe run          <- BUY from every shop in the config (use this in automation:
#                              an explicit argument means mafia never shows the input popup)
#   storeSnipe dry          <- preview every configured shop, buy nothing
#   storeSnipe 123456       <- preview one ad-hoc shop (dry run)
#   storeSnipe 123456 buy   <- buy from one ad-hoc shop

int unit_ceiling = 500;
float fair_fraction = 0.6;
int default_shop_cap = 2000;
int unlimited_qty = 10;
boolean buy_unknown_fair = false;
int [int] config_shops;          # shopId -> spend cap override (-1 = use default)

int [int] fair_price;            # itemId -> Irrat fair value
int [int] weekly_sales;          # itemId -> units sold in the last week (Irrat DB col 4)
boolean have_fair_db = false;

int total_spent = 0;
int total_kinds = 0;

# end-of-run report data
record Purchase { item it; int price; int qty; int fair; int wk; int mall5; int adj; };
Purchase [int, int] bought;      # shopId, seq -> purchase line
int [int] bought_n;              # shopId -> number of purchase lines
int [int] shop_spent;            # shopId -> meat spent (or would-spend in dry mode)
int [int] shop_cap_used;         # shopId -> the spend cap that governed the run
string [int] shop_owner;         # shopId -> owner player name (parsed from store page)

void record_purchase(int store_id, item it, int price, int qty, int fair, int wk) {
    int m5 = mall_price(it);                      # mafia's 5th-cheapest current listing (1 search per item)
    if (m5 < 0) m5 = 0;
    int adj = 0;                                  # adjusted FV = avg(fair, mall5), or whichever is known
    if (fair > 0 && m5 > 0) adj = (fair + m5) / 2;
    else if (fair > 0) adj = fair;
    else if (m5 > 0) adj = m5;
    int seq = bought_n[store_id];
    bought[store_id, seq].it = it;
    bought[store_id, seq].price = price;
    bought[store_id, seq].qty = qty;
    bought[store_id, seq].fair = fair;
    bought[store_id, seq].wk = wk;
    bought[store_id, seq].mall5 = m5;
    bought[store_id, seq].adj = adj;
    bought_n[store_id] = seq + 1;
}

void print_report(boolean execute) {
    if (count(shop_spent) == 0) return;
    int total_gain = 0;
    buffer h;
    h.append("<b>" + (execute ? "Purchase" : "Preview") + " report</b>");
    h.append("<table border=1 cellpadding=4 cellspacing=0>");
    h.append("<tr><td><b>Item</b></td><td><b>Qty</b></td><td><b>Unit paid</b></td><td><b>Fair/unit</b></td><td><b>Mall(5th)</b></td><td><b>Adj FV</b></td><td><b>Sold/wk</b></td><td><b>Line total</b></td><td><b>Est. gain</b></td></tr>");
    foreach sid in shop_spent {
        string who = shop_owner[sid] == "" ? ("store #" + sid) : (shop_owner[sid] + " (#" + sid + ")");
        string capnote = shop_spent[sid] + " / " + shop_cap_used[sid] + " cap";
        h.append("<tr><td colspan=9 bgcolor=\"#d0e0f0\"><b>" + who + "</b> &mdash; " + (execute ? "spent " : "would spend ") + capnote + "</td></tr>");
        if (bought_n[sid] == 0) {
            h.append("<tr><td colspan=9><i>nothing qualified</i></td></tr>");
        }
        foreach shop, seq, p in bought {
            if (shop != sid) continue;
            string fairtxt = p.fair > 0 ? "" + p.fair : "?";
            string m5txt = p.mall5 > 0 ? "" + p.mall5 : "?";
            string adjtxt = p.adj > 0 ? "" + p.adj : "?";
            string gaintxt = "?";
            if (p.adj > 0) {
                int gain = (p.adj - p.price) * p.qty;
                total_gain += gain;
                gaintxt = "" + gain;
            }
            string wktxt = p.wk >= 0 ? "" + p.wk : "?";
            h.append("<tr><td>" + p.it + "</td><td>" + p.qty + "</td><td>" + p.price + "</td><td>" + fairtxt + "</td><td>" + m5txt + "</td><td>" + adjtxt + "</td><td>" + wktxt + "</td><td>" + (p.price * p.qty) + "</td><td>" + gaintxt + "</td></tr>");
        }
    }
    h.append("<tr><td colspan=7><b>Total: " + count(shop_spent) + " shop(s), " + total_kinds + " item kind(s)</b></td><td><b>" + total_spent + "</b></td><td><b>" + total_gain + "</b></td></tr>");
    h.append("</table>");
    print_html(h.to_string());
}

boolean load_config() {
    if (get_property("storeSnipe_unitCeiling") != "") unit_ceiling = get_property("storeSnipe_unitCeiling").to_int();
    if (get_property("storeSnipe_fairFraction") != "") fair_fraction = get_property("storeSnipe_fairFraction").to_float();
    if (get_property("storeSnipe_shopSpendCap") != "") default_shop_cap = get_property("storeSnipe_shopSpendCap").to_int();
    if (get_property("storeSnipe_unlimitedQty") != "") unlimited_qty = get_property("storeSnipe_unlimitedQty").to_int();
    buy_unknown_fair = get_property("storeSnipe_buyUnknownFair") == "true";

    string shops = get_property("storeSnipe_shops");
    if (shops == "") return false;
    foreach i, tok in split_string(shops, ",") {
        string [int] p = split_string(tok.replace_string(" ", ""), ":");
        if (count(p) == 0 || !is_integer(p[0])) continue;
        int cap = -1;
        if (count(p) > 1 && is_integer(p[1])) cap = p[1].to_int();
        config_shops[p[0].to_int()] = cap;
    }
    return count(config_shops) > 0;
}

void load_fair_db() {
    buffer buf = file_to_buffer("irrats_item_prices.txt");
    if (buf.length() == 0) {
        print("KolItemPrices DB not found -- fair-value rule disabled, mall-floor rule only.", "olive");
        return;
    }
    foreach i, line in split_string(buf.to_string(), "\n") {
        string clean = line.replace_string("\r", "");
        if (clean == "" || clean.starts_with("#") || clean.starts_with("Last Updated")) continue;
        string [int] parts = split_string(clean, "\t");
        if (count(parts) < 3) continue;
        if (!is_integer(parts[0]) || !is_integer(parts[2])) continue;
        int fp = parts[2].to_int();
        if (fp <= 0) continue;
        int id = parts[0].to_int();
        fair_price[id] = fp;
        if (count(parts) >= 4 && is_integer(parts[3])) weekly_sales[id] = parts[3].to_int();
    }
    have_fair_db = count(fair_price) > 0;
}

int min_mall_price(item it) {
    return max(100, 2 * autosell_price(it));
}

# returns meat spent in this shop
int snipe_shop(int store_id, int spend_cap, boolean execute, boolean debug) {
    print("");
    print((execute ? "Sniping" : "Previewing") + " store #" + store_id + " (spend cap " + spend_cap + ")...", "blue");

    buffer page = visit_url("mallstore.php?whichstore=" + store_id);
    if (page.length() == 0 || page.contains_text("doesn't exist")) {
        print("Couldn't load store #" + store_id + ".", "red");
        return 0;
    }

    matcher own = create_matcher("showplayer\\.php\\?who=\\d+[^>]*>([^<]+)<", page);
    if (own.find()) shop_owner[store_id] = own.group(1);
    shop_cap_used[store_id] = spend_cap;

    int spent_here = 0;
    int listings = 0;
    boolean [item] seen;

    foreach idx, row in split_string(page.to_string(), "<tr") {
        matcher link = create_matcher("whichitem(?:=|[^>]{0,60}?value=\\\"?)(\\d+)\\.(\\d+)", row);
        if (!link.find()) continue;

        int item_id = link.group(1).to_int();
        int price = link.group(2).to_int();
        item it = item_id.to_item();
        if (it == $item[none] || seen contains it) continue;
        seen[it] = true;
        listings++;

        matcher striptags = create_matcher("<[^>]*>", row);
        string rowtext = striptags.replace_all(" ");
        # strip invisible/non-ASCII characters that can hide inside words
        matcher nonascii = create_matcher("[^ -~]+", rowtext);
        string rowclean = nonascii.replace_all("");
        int day_limit = 0;
        # key on "imit" so an exotic leading character can't break the match
        matcher lim = create_matcher("(?i)imit[^0-9]{0,10}([0-9,]+)", rowclean);
        if (lim.find()) day_limit = lim.group(1).replace_string(",", "").to_string().to_int();
        # rule 2 facts (computed early so debug can show them even when rule 1 fails)
        boolean at_floor = price <= min_mall_price(it);
        boolean below_fair = false;
        int fair = 0;
        if (have_fair_db && fair_price contains item_id) {
            fair = fair_price[item_id];
            below_fair = price.to_float() <= fair.to_float() * fair_fraction;
        }

        boolean value_ok = fair > 0 ? below_fair : (at_floor && buy_unknown_fair);
        if (debug) {
            string verdict = !value_ok ?
                  (fair > 0 ? "REJECT rule1: above " + fair_fraction + "x fair value"
                   : at_floor ? "REJECT rule1: fair unknown (set storeSnipe_buyUnknownFair = true to speculate)"
                   : "REJECT rule1: fair unknown and not floor-priced")
                : price > unit_ceiling ? "REJECT rule2: above unit ceiling"
                : "PASS";
            print("DBG " + it + " | price " + price + " | limit " + (day_limit < 1 ? "none" : "" + day_limit)
                + " | floor " + min_mall_price(it) + " | fair " + (fair > 0 ? "" + fair : "?")
                + " | " + verdict, verdict == "PASS" ? "green" : "red");
            string plain = rowtext;
            matcher sp = create_matcher("\\s+", plain);
            plain = sp.replace_all(" ");
            if (plain.length() > 200) plain = plain.substring(0, 200);
            print("    raw: " + plain, "gray");

        }

        if (!value_ok) continue;                           # rule 1: proven discount (or opted-in floor speculation)
        string why = fair > 0 ? ("" + price + " vs fair " + fair) : "floor price, fair unknown";

        if (price > unit_ceiling) {                        # rule 3
            print("SKIP " + it + " @ " + price + " (" + why + ", but above unit ceiling " + unit_ceiling + ")", "olive");
            continue;
        }

        int remaining = spend_cap - spent_here;            # rule 4
        int max_qty = day_limit > 0 ? day_limit : unlimited_qty;
        int n = min(max_qty, remaining / price);
        if (n < 1) {
            print("SKIP " + it + " @ " + price + " (" + why + ", shop spend cap reached)", "olive");
            continue;
        }

        print((execute ? "BUYING " : "WOULD BUY ") + n + " x " + it + " @ " + price + " [" + why + ", " + (day_limit > 0 ? "limit " + day_limit + "/day" : "no limit, capped " + unlimited_qty) + "]", "green");

        if (execute) {
            string resp = visit_url("mallstore.php?whichstore=" + store_id
                + "&buying=1&ajax=1&whichitem=" + item_id + "." + price
                + "&quantity=" + n);
            if (resp.contains_text("You acquire")) {
                spent_here += price * n;
                total_kinds++;
                record_purchase(store_id, it, price, n, fair, weekly_sales contains item_id ? weekly_sales[item_id] : -1);
            } else if (resp.contains_text("already purchased")) {
                print("  ...already hit today's limit for " + it + ".", "olive");
            } else {
                print("  ...purchase may have failed for " + it + " (check session log).", "red");
            }
        } else {
            spent_here += price * n;   # dry run: track hypothetical spend against the cap
            total_kinds++;
            record_purchase(store_id, it, price, n, fair, weekly_sales contains item_id ? weekly_sales[item_id] : -1);
        }
    }

    if (listings == 0) {
        print("WARNING: page loaded but no listings parsed for store #" + store_id + " -- unexpected page format. Run: storeSnipe " + store_id + " debug  and share the output.", "red");
    } else if (debug) {
        print("DBG store #" + store_id + ": " + listings + " listing(s) parsed.", "blue");
    }
    shop_spent[store_id] = spent_here;
    return spent_here;
}

void main(string params) {
    print("storeSnipe v2.9 (popup-free automation via run token)", "blue");
    if (!can_interact()) {
        print("You can't use the mall right now (Ronin/Hardcore).", "red");
        return;
    }
    boolean config_ok = load_config();
    load_fair_db();

    string [int] args = split_string(params, " ");
    string a0 = count(args) > 0 ? args[0] : "";

    if (a0 == "" || a0 == "run" || a0 == "go" || a0 == "dry") {
        # config-driven mode: all shops. "run"/"go"/empty = BUY (config entries are pre-approved).
        boolean execute = a0 != "dry";
        if (!config_ok || count(config_shops) == 0) {
            print("No shops configured. Set them with e.g.:", "red");
            print("  set storeSnipe_shops = 123456,654321:5000", "red");
            return;
        }
        foreach id, cap in config_shops {
            total_spent += snipe_shop(id, cap < 0 ? default_shop_cap : cap, execute, false);
        }
        print_report(execute);
        return;
    }

    if (is_integer(a0)) {
        # ad-hoc single shop: dry by default, "buy" to execute
        boolean execute = false;
        boolean debug = false;
        foreach i, a in args {
            if (a == "buy") execute = true;
            if (a == "debug") debug = true;
        }
        if (debug) execute = false;   # debug is always a dry run
        int spent = snipe_shop(a0.to_int(), default_shop_cap, execute, debug);
        print_report(execute);
        if (!execute && spent > 0) {
            print("To claim these:  storeSnipe " + a0 + " buy   -- or add " + a0 + " to storeSnipe_shops to snipe it daily.", "green");
        }
        return;
    }

    print("Usage: storeSnipe run | storeSnipe dry | storeSnipe <shopId> [buy|debug]", "red");
}
