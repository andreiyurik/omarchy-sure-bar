// Run with: node tests/model.test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert")
const src = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(".pragma library", "")
const M = {}; vm.createContext(M)
M.Currencies = vm.runInNewContext(fs.readFileSync(path.join(__dirname, "..", "Currencies.js"), "utf8").replace(".pragma library", "") + ";({TABLE})")
vm.runInContext(src.replace('.import "Currencies.js" as Currencies', ""), M)
const plain = value => JSON.parse(JSON.stringify(value))
const today = new Date(2026, 10, 9), parse = s => plain(M.parseEntry(s, today, "business"))

// Entry parser
let e = parse("450 coffee"); assert(e.ok && e.amount === 450 && e.nature === "expense" && e.name === "coffee" && e.date === "2026-11-09" && e.offset === 0)
e = parse("+120000 salary"); assert(e.nature === "income" && e.amount === 120000)
e = parse("1 500 lunch"); assert.strictEqual(e.amount, 1500)
e = parse("1.5k lunch"); assert.strictEqual(e.amount, 1500)
e = parse("1.5к обед"); assert.strictEqual(e.amount, 1500)
e = parse("99,50 tea"); assert.strictEqual(e.amount, 99.5)
e = parse("4900 server #b #vps @cash yesterday"); assert.deepStrictEqual(e.tags, ["business", "vps"]); assert(e.account === "cash" && e.date === "2026-11-08" && e.name === "server" && e.offset === 1)
e = parse("4900 сервер #б @нал вчера"); assert.deepStrictEqual(e.tags, ["business"]); assert(e.account === "нал" && e.offset === 1)
e = parse("100 обед позавчера"); assert.strictEqual(e.date, "2026-11-07")
assert.strictEqual(M.parseEntry("100 x yesterday", new Date(2026, 10, 1), "b").date, "2026-10-31")
assert.strictEqual(parse("").error, "empty")
assert.strictEqual(parse("coffee").error, "amount-first")
assert.strictEqual(parse("0 coffee").error, "bad-amount")
assert.strictEqual(parse("450").error, "name-missing")
for (const bad of ["450 #b", "450coffee"]) assert(!parse(bad).ok, bad)

// Thousands and decimals, by what the account's currency allows
assert.strictEqual(parse("1,500 lunch").amount, 1500)
assert.strictEqual(parse("1.500 lunch").amount, 1500)
assert.strictEqual(parse("1,500,000 car").amount, 1500000)
assert.strictEqual(parse("1,234.56 x").amount, 1234.56)
assert.strictEqual(parse("1.234,56 x").amount, 1234.56)
assert.strictEqual(parse("12,5 x").amount, 12.5)
assert.strictEqual(parse("1,5к x").amount, 1500)
const places = n => () => n
assert.strictEqual(M.parseEntry("1.234 x", today, "b", places(3)).amount, 1.234)
assert.strictEqual(M.parseEntry("1,234 x", today, "b", places(3)).amount, 1.234)
assert.strictEqual(M.parseEntry("0.12345678 x", today, "b", places(8)).amount, 0.12345678)
assert.strictEqual(M.parseEntry("1.5 x", today, "b", places(0)).error, "bad-amount")
assert.strictEqual(M.parseEntry("1.5k x", today, "b", places(0)).amount, 1500)
assert.strictEqual(parse("1.2345 x").error, "bad-amount")
assert.strictEqual(M.parseEntry("5 x @kwd", today, "b", hint => { assert.strictEqual(hint, "kwd"); return 3 }).amount, 5)

// Server address: the API key must not leave the machine unencrypted by accident
assert.strictEqual(M.origin("http://localhost:3000/").url, "http://localhost:3000")
assert(M.origin("http://127.0.0.1:3000").ok)
assert(M.origin("https://sure.example.com").ok)
assert.strictEqual(M.origin("http://sure.example.com").error, "url-insecure")
assert(M.origin("http://nas.local:3000", true).ok)
for (const bad of ["", "localhost:3000", "http://x/$(id)", "http://x;rm", "https://x/path", "ftp://x"]) assert.strictEqual(M.origin(bad, true).error, "url-invalid", bad)

// Minor units come from Sure's currency table
assert.strictEqual(M.fromMinor(12345, "RUB"), 123.45)
assert.strictEqual(M.fromMinor(500, "JPY"), 500)
assert.strictEqual(M.fromMinor(1500, "KWD"), 1.5)
assert.strictEqual(M.fromMinor(50000000, "BTC"), 0.5)
assert.strictEqual(Object.keys(M.Currencies.TABLE).length >= 180, true)

// Formatting
assert.strictEqual(M.formatMoney(-1234567, "RUB"), "−1 234 567 ₽")
assert.strictEqual(M.formatMoney(1234567, "USD", ","), "$1,234,567")
assert.strictEqual(M.formatMoney(-50, "USD", ","), "−$50")
assert.strictEqual(M.formatMoney(5, "ZZZ"), "5 ZZZ")
assert.strictEqual(M.shortMoney(1250000), "1.3M")
assert.strictEqual(M.shortMoney(20000), "20k")
assert.strictEqual(M.shortMoney(1500), "1.5k")
assert.strictEqual(M.shortMoney(999), "999")
assert.strictEqual(M.shortMoney(0.5), "0.5")
assert.strictEqual(M.shortMoney(12.56), "12.6")
assert.strictEqual(M.shortMoney(9.99), "9.99")

// Amounts keep the precision that matters
assert.strictEqual(M.formatMoney(9.99, "USD", ","), "$9.99")
assert.strictEqual(M.formatMoney(9, "USD", ","), "$9")
assert.strictEqual(M.formatMoney(1234.56, "USD", ","), "$1,235")
assert.strictEqual(M.formatMoney(0.5, "BTC"), "₿0.5")
assert.strictEqual(M.formatMoney(0.12345678, "BTC"), "₿0.12345678")
assert.strictEqual(M.formatMoney(12.5, "KWD", ","), "د.ك12.5")
assert.strictEqual(M.formatMoney(1500.4, "JPY", ","), "¥1,500")
assert.strictEqual(M.formatMoney(100, "CHF"), "CHF 100")
assert.strictEqual(M.formatMoney(100, "PLN"), "100 zł")
assert.strictEqual(M.formatMoney(-0.001, "USD"), "$0")
assert.strictEqual(M.formatMoney(1234567.8, "RUB", {group: " ", decimal: ",", prefix: false}), "1 234 568 ₽")
assert.strictEqual(M.formatMoney(9.5, "USD", {group: " ", decimal: ",", prefix: false}), "9,50 $")
assert.strictEqual(M.formatMoney(7000, "USD", {group: ".", prefix: true, spaced: true}), "$ 7.000")
assert.strictEqual(M.shortMoney(1500, {k: "%1к", m: "%1М", decimal: ","}), "1,5к")

// Budget, months, burn
assert.strictEqual(M.pace(62, 100, 9, 30).status, "warn")
assert.strictEqual(M.pace(30, 100, 9, 30).status, "ok")
assert.strictEqual(M.pace(100, 100, 9, 30).status, "over")
assert.strictEqual(M.pace(10, 0, 9, 30), null)
assert.deepStrictEqual(plain(M.monthsBack("2026-02-01", 3)), ["2025-12-01", "2026-01-01", "2026-02-01"])
assert.strictEqual(M.burn([{spending: 0}, {spending: 100}, {spending: 300}, {spending: 5}]), 200)
assert.strictEqual(M.runway(-5, 10), null)

// Aggregation skips transfers and foreign currency
const a = M.aggregateTagged([
  {date: "2026-11-02", amount_cents: 10000, currency: "RUB", classification: "expense"},
  {date: "2026-11-03", amount_cents: 50000, currency: "RUB", classification: "income"},
  {date: "2026-11-03", amount_cents: 900000, currency: "RUB", classification: "income", transfer: {id: "t"}},
  {date: "2026-11-03", amount_cents: 100, currency: "USD", classification: "expense"}], ["2026-10-01", "2026-11-01"], "RUB")
assert(a.series[1].spending === 100 && a.series[1].income === 500 && a.skipped === 1)

// Choosing an account
const accounts = [
  {id: "1", name: "Aaa loan", account_type: "loan", status: "active"},
  {id: "2", name: "Cash", account_type: "depository", status: "active"},
  {id: "3", name: "Old card", account_type: "depository", status: "disabled"},
  {id: "4", name: "Tinkoff", account_type: "depository", status: "active"}]
const pick = (...args) => { const found = M.pickAccount(accounts, ...args); return found ? found.id : null }
assert.strictEqual(pick("", "", ""), "2")
assert.strictEqual(pick("tink", "", ""), "4")
assert.strictEqual(pick("old", "", ""), null)
assert.strictEqual(pick("nope", "Cash", "4"), null)
assert.strictEqual(pick("", "tink", "2"), "4")
assert.strictEqual(pick("", "", "4"), "4")
assert.strictEqual(pick("", "", "3"), "2")

// Revenue race and milestones
const asOf = new Date(2026, 10, 9), tx = (date, amount, c) => ({date, amount_cents: amount * 100, currency: "RUB", classification: c || "income"})
const keys = g => plain(g.achieved).map(item => item.key)
let g = M.game([], asOf, "RUB"); assert(g.next.target === 1 && g.delta === null && g.achieved.length === 0 && g.ladder.length === 9)
g = M.game([tx("2026-11-02", 4000)], asOf, "RUB")
assert(g.achieved.length === 1 && g.achieved[0].kind === "revenue" && g.achieved[0].target === 1 && g.next.target === 10000 && g.next.remaining === 6000 && g.next.percent === 40 && g.ladder[0].done && !g.ladder[1].done)
g = M.game([tx("2026-10-03", 10000), tx("2026-10-20", 90000), tx("2026-11-04", 11400)], asOf, "RUB")
assert(g.prevSame === 10000 && g.delta === 14 && g.deltaAmount === 1400 && g.record.amount === 100000 && !g.isRecord && g.monthIndex === 10 && g.prevMonthIndex === 9)
g = M.game([tx("2026-10-03", 10000), tx("2026-11-04", 5000)], asOf, "RUB"); assert(g.delta === -50)
g = M.game([tx("2026-10-03", 1000), tx("2026-11-04", 2000)], asOf, "RUB"); assert(g.isRecord)
g = M.game([tx("2026-11-20", 500)], asOf, "RUB"); assert.strictEqual(g.total, 0)
g = M.game([Object.assign(tx("2026-11-02", 50000), {transfer: {id: "t"}})], asOf, "RUB"); assert.strictEqual(g.total, 0)
g = M.game([tx("2026-09-03", 500), tx("2026-09-04", 100, "expense"), tx("2026-10-03", 500), tx("2026-11-03", 500)], asOf, "RUB")
assert(keys(g).includes("first-profit") && keys(g).includes("three-months"))
g = M.game([tx("2026-07-03", 500), tx("2026-09-03", 500), tx("2026-11-03", 500)], asOf, "RUB"); assert(!keys(g).includes("three-months"))
g = M.game([tx("2026-11-02", 30000)], asOf, "RUB"); assert.strictEqual(g.next.segment, 0.5)
g = M.game([tx("2026-11-02", 10000000)], asOf, "RUB"); assert(g.next === null && g.ladder.every(step => step.done))
const before = M.game([tx("2026-11-02", 4000)], asOf, "RUB"), after = M.game([tx("2026-11-02", 4000), tx("2026-11-03", 7000)], asOf, "RUB")
assert(M.freshAchievements(before, after).length === 1 && M.freshAchievements(null, after).length === 0)

// Reaching a server
assert.strictEqual(M.normalizeServer(" sure.example.com "), "https://sure.example.com")
assert.strictEqual(M.normalizeServer("localhost:3000"), "http://localhost:3000")
assert.strictEqual(M.normalizeServer("127.0.0.1:3000"), "http://127.0.0.1:3000")
assert.strictEqual(M.normalizeServer("http://nas:3000"), "http://nas:3000")
assert.strictEqual(M.normalizeServer("localhost.evil.com"), "https://localhost.evil.com")
assert.strictEqual(M.normalizeServer(""), "")

// Telling failures apart
for (const [status, json, key] of [[0, false, "unreachable"], [-1, false, "too-large"], [429, true, "rate-limited"], [401, true, "rejected"], [401, false, "proxy"], [403, true, "forbidden"], [403, false, "proxy"],
  [404, true, "not-found"], [404, false, "not-sure"], [500, true, "server"], [502, false, "server"], [200, false, "not-sure"], [418, false, "http"]]) {
  assert.strictEqual(M.failureKey(status, json), "error." + key, status + " " + json)
}
for (const [code, key] of [[6, "dns"], [7, "refused"], [28, "timeout"], [60, "tls"], [51, "tls"], [35, "unreachable"], [0, "unreachable"], [127, "unreachable"]]) assert.strictEqual(M.probeKey(code), "error." + key, String(code))
assert(M.retryable("error.dns") && M.retryable("error.server") && M.retryable("error.rate-limited"))
for (const key of ["error.rejected", "error.proxy", "error.not-sure", "error.not-found", "error.too-large"]) assert(!M.retryable(key), key)
assert.deepStrictEqual([0, 1, 2, 20].map(n => M.retryDelay(n, 0, 15000, 300000)), [15000, 30000, 60000, 300000])
assert.strictEqual(M.retryDelay(5, 42, 15000, 300000), 42000)
assert.strictEqual(M.retryDelay(0, 999999, 15000, 300000), 3600000)
assert.notStrictEqual(M.externalId(1000, 0.1), M.externalId(1000, 0.2))

// A server behind or ahead of this computer
assert.strictEqual(M.iso(M.latestDay("2026-11-09", new Date(2026, 10, 10, 4))), "2026-11-10")
assert.strictEqual(M.iso(M.latestDay("2026-11-11", new Date(2026, 10, 10, 4))), "2026-11-11")

// Local cache
assert.strictEqual(M.windowStart("2026-11-01"), "2026-10-01")
assert.strictEqual(M.windowStart("2026-01-01"), "2025-12-01")
const ck = M.cacheKey("https://a", "Biz", false); assert.strictEqual(ck, M.cacheKey("https://a", "biz", false)); assert.notStrictEqual(ck, M.cacheKey("https://b", "biz", false)); assert.notStrictEqual(ck, M.cacheKey("https://a", "biz", true))
assert(M.needsFullRefresh(null, ck, "2026-11-09") && M.needsFullRefresh({key: ck, day: "2026-11-09"}, ck, "2026-11-09", true) && M.needsFullRefresh({key: ck, day: "2026-11-08"}, ck, "2026-11-09") && M.needsFullRefresh({key: "x", day: "2026-11-09"}, ck, "2026-11-09"))
assert(!M.needsFullRefresh({key: ck, day: "2026-11-09"}, ck, "2026-11-09"))
const slim = plain(M.slimTransaction({date: "2026-11-02T00:00:00Z", amount_cents: 5, currency: "USD", classification: "income", name: "secret", transfer: {id: 1}}))
assert.deepStrictEqual(slim, {date: "2026-11-02", amount_cents: 5, currency: "USD", classification: "income", transfer: true})
assert.deepStrictEqual(plain(M.mergeTransactions([{date: "2026-09-30"}, {date: "2026-10-01", stale: true}], [{date: "2026-10-05"}], "2026-10-01")), [{date: "2026-09-30"}, {date: "2026-10-05"}])
assert.deepStrictEqual(plain(M.mergeRecent([{id: 1, date: "2026-11-01"}], [{id: 1, date: "2026-11-01"}, {id: 2, date: "2026-11-02"}, {id: 3, date: "2026-09-01"}], "2026-10-01", 6)).map(r => r.id), [1, 3])
const snap = {version: 1, key: ck, savedAt: 5, cache: {transactions: []}, payload: {status: "ok", series: [], game: {}, business: {}, recent: []}}
assert(M.readSnapshot(snap, ck)); assert.strictEqual(M.readSnapshot(snap, "other"), null); assert.strictEqual(M.readSnapshot(null, ck), null)
for (const broken of [{version: 2}, {payload: null}, {cache: {}}, {payload: {status: "demo"}}, {savedAt: 0}]) assert.strictEqual(M.readSnapshot(Object.assign({}, snap, broken), ck), null)
assert.strictEqual(M.timezoneWarning("Etc/UTC", "+0000", "+0000"), null)
assert.strictEqual(M.timezoneWarning("Etc/UTC", "", "+0800"), null)
const tzw = plain(M.timezoneWarning("Etc/UTC", "+0000", "+0800")); assert(tzw.arg === "Etc/UTC (UTC+0000)" && tzw.arg2 === "UTC+0800" && tzw.dismiss === "tz:Etc/UTC|+0800")

// Commands
const cmd = s => plain(M.parseCommand(s))
assert.strictEqual(M.parseCommand("450 coffee"), null)
assert.strictEqual(M.parseCommand("goalie 5"), null)
assert.strictEqual(cmd("goal 7000").amount, 7000)
assert.strictEqual(cmd("Цель 7к").amount, 7000)
assert.strictEqual(cmd("goal 1 500").amount, 1500)
assert.strictEqual(cmd("goal").error, "goal-format")
assert.strictEqual(cmd("goal abc").error, "goal-format")
assert(cmd("goal off").off && cmd("цель 0").off && cmd("week off").off)
let c = cmd("week 10 client offers"); assert(c.ok && c.kind === "action" && c.target === 10 && c.text === "client offers")
assert.strictEqual(cmd("неделя 5 звонков").text, "звонков")
for (const bad of ["week", "week offers", "week 0 offers", "week 10"]) assert.strictEqual(cmd(bad).error, "action-format", bad)

assert.strictEqual(cmd("goal 7,000").amount, 7000)
let gc = cmd("goal 7000 usd"); assert(gc.ok && gc.amount === 7000 && gc.currency === "USD")
gc = cmd("goal $7000"); assert(gc.amount === 7000 && gc.currency === "USD")
gc = cmd("цель 7к ₽"); assert(gc.amount === 7000 && gc.currency === "RUB")
gc = cmd("goal 500 KZT"); assert(gc.amount === 500 && gc.currency === "KZT")
assert.strictEqual(cmd("goal 7000").currency, "")
assert.strictEqual(cmd("goal 7000 nope").error, "goal-format")
assert.strictEqual(cmd("goal $7000 eur").error, "goal-format")
let rc = cmd("rate USD 92"); assert(rc.ok && rc.kind === "rate" && rc.currency === "USD" && rc.value === 92)
assert.strictEqual(cmd("курс usd 92,5").value, 92.5)
assert.strictEqual(cmd("rate $ 0.011").value, 0.011)
rc = cmd("rate usd off"); assert(rc.ok && rc.off && rc.currency === "USD")
for (const bad of ["rate", "rate usd", "rate 92", "rate off", "rate nope 5", "rate usd abc", "rate usd -1"]) assert.strictEqual(cmd(bad).error, "rate-format", bad)

// Rates: nothing is guessed, and a rate applies only to the currency it was entered against
const usd = (date, amount, c) => ({date, amount_cents: amount * 100, currency: "USD", classification: c || "income"})
let rp = M.emptyPlan()
g = M.game([usd("2026-11-02", 100), tx("2026-11-03", 50)], asOf, "RUB", rp)
assert(g.current === 50 && g.unconverted.length === 1 && g.unconverted[0].currency === "USD" && g.unconverted[0].count === 1 && g.unconverted[0].amount === 100 && g.ratesUsed.length === 0)
rp = M.setRate(rp, "USD", 92, "RUB")
g = M.game([usd("2026-11-02", 100), tx("2026-11-03", 50), usd("2026-11-03", 10, "expense")], asOf, "RUB", rp)
assert(g.current === 9250 && g.profit === 8330 && g.unconverted.length === 0 && g.ratesUsed[0].currency === "USD" && g.ratesUsed[0].value === 92)
assert.strictEqual(M.rateFor(rp, "USD", "EUR"), null)
assert.strictEqual(M.convertAmount(rp, 5, "USD", "EUR"), null)
assert.strictEqual(M.convertAmount(M.clearRate(rp, "USD"), 5, "USD", "RUB"), null)
const ag = M.aggregateTagged([usd("2026-11-03", 10)], ["2026-11-01"], "RUB", rp); assert(ag.series[0].income === 920 && ag.skipped === 0)
const jpy = M.game([{date: "2026-11-02", amount_cents: 1000, currency: "JPY", classification: "income"}], asOf, "RUB", M.setRate(M.emptyPlan(), "JPY", 0.6, "RUB")); assert.strictEqual(jpy.current, 600)

// A goal in another currency
let gp = M.setGoal(M.emptyPlan(), "2026-11", 7000, "USD")
g = M.game([tx("2026-11-02", 64400)], asOf, "RUB", gp); assert(g.goal === null && g.goalCurrency === "USD")
gp = M.setRate(gp, "USD", 92, "RUB")
g = M.game([tx("2026-11-02", 64400)], asOf, "RUB", gp)
assert(g.goal.target === 644000 && g.goal.percent === 10 && g.goal.original.amount === 7000 && g.goal.original.currency === "USD" && g.goalCurrency === "" && g.ratesUsed[0].currency === "USD")
assert.strictEqual(M.game([], asOf, "USD", M.setGoal(M.emptyPlan(), "2026-11", 7000, "USD")).goal.original, null)
assert.strictEqual(M.game([], asOf, "RUB", M.setGoal(M.emptyPlan(), "2026-10", 7000, "USD")).review, null)
g = M.game([tx("2026-10-02", 92000)], asOf, "RUB", M.setRate(M.setGoal(M.emptyPlan(), "2026-10", 2000, "USD"), "USD", 92, "RUB")); assert(g.review.target === 184000 && g.review.percent === 50)

// Goal stages stay round and end at the goal
assert.deepStrictEqual(plain(M.goalStages(7000)), [2000, 4000, 6000, 7000])
assert.deepStrictEqual(plain(M.goalStages(10000)), [2500, 5000, 7500, 10000])
assert.deepStrictEqual(plain(M.goalStages(3000)), [750, 1500, 2250, 3000])
assert.deepStrictEqual(plain(M.goalStages(150000)), [40000, 80000, 120000, 150000])
assert.deepStrictEqual(plain(M.goalStages(1000)), [250, 500, 750, 1000])
assert.deepStrictEqual(plain(M.goalStages(2)), [2])
for (const n of [4, 7, 99, 101, 999, 1001, 12345, 777777, 5e9]) {
  const stages = plain(M.goalStages(n)); assert(stages.length >= 2 && stages.length <= 5 && stages[stages.length - 1] === n, String(n))
  stages.reduce((a, b) => { assert(b > a, String(n)); return b }, 0)
}

// Goal progress
let plan = M.setGoal(M.emptyPlan(), "2026-11", 7000, "RUB")
g = M.game([tx("2026-11-02", 2340), tx("2026-11-03", 500, "expense")], asOf, "RUB", plan)
assert(g.goal.percent === 33 && !g.goal.halfway && !g.goal.reached && g.goal.stage.target === 4000 && g.goal.stage.remaining === 1660 && g.goal.passed === 1 && g.goal.paceAmount === 2100 && g.profit === 1840)
g = M.game([tx("2026-11-02", 5000)], asOf, "RUB", plan); assert(g.goal.halfway && g.goal.remaining === 2000)
g = M.game([tx("2026-11-02", 7300)], asOf, "RUB", plan); assert(g.goal.reached && g.goal.over === 300 && g.goal.stage === null && g.goal.percent === 104)
assert.strictEqual(M.game([], asOf, "RUB").goal, null)

// A goal lasts until changed and never rewrites the past
plan = M.setGoal(plan, "2026-12", 9000, "RUB")
assert(M.goalFor(plan, "2026-10") === null && M.goalFor(plan, "2026-11").amount === 7000 && M.goalFor(plan, "2027-03").amount === 9000)
assert.strictEqual(M.goalFor(M.setGoal(plan, "2027-01", null), "2027-02"), null)

// A goal in another currency is not silently compared with these numbers
g = M.game([tx("2026-11-02", 7000)], asOf, "USD", M.setGoal(M.emptyPlan(), "2026-11", 7000, "RUB"))
assert(g.goal === null && g.goalCurrency === "RUB")

// The lifetime ladder follows the goal, and changing the goal announces nothing
plan = M.setGoal(M.emptyPlan(), "2026-11", 7000, "RUB")
g = M.game([tx("2026-11-02", 4000)], asOf, "RUB", plan)
assert.deepStrictEqual(plain(g.ladder).map(step => step.target), [1, 3500, 7000, 21000, 42000, 84000, 168000, 420000, 840000])
assert.strictEqual(g.ladder.length, 9)
assert.strictEqual(M.freshAchievements(M.game([tx("2026-11-02", 4000)], asOf, "RUB"), g).length, 0)

// Weekly action
assert.strictEqual(M.weekStart(new Date(2026, 10, 9)), "2026-11-09")
assert.strictEqual(M.weekStart(new Date(2026, 10, 15)), "2026-11-09")
assert.strictEqual(M.weekStart(new Date(2026, 10, 1)), "2026-10-26")
let p2 = M.setAction(M.emptyPlan(), "2026-11-02", 10, "offers")
p2 = M.bumpAction(M.bumpAction(p2, "2026-11-02", 1), "2026-11-02", 1)
assert.strictEqual(M.actionFor(p2, "2026-11-02").done, 2)
assert.strictEqual(M.bumpAction(M.emptyPlan(), "2026-11-02", 1).actions.length, 0)
assert.strictEqual(M.actionFor(M.bumpAction(p2, "2026-11-02", -9), "2026-11-02").done, 0)
const carried = M.actionFor(p2, "2026-11-09"); assert(carried.carried && carried.done === 0 && carried.target === 10 && carried.text === "offers")
assert.strictEqual(M.actionFor(p2, "2026-10-26"), null)
assert.strictEqual(M.actionFor(M.setAction(p2, "2026-11-02", 12, "offers"), "2026-11-02").done, 2)
assert.strictEqual(M.actionFor(M.setAction(p2, "2026-11-02", 5, "calls"), "2026-11-02").done, 0)
assert.strictEqual(M.actionFor(M.clearAction(p2, "2026-11-09"), "2026-11-16"), null)

// Month review
let p3 = M.setGoal(M.emptyPlan(), "2026-10", 1000, "RUB")
p3 = M.setAction(p3, "2026-10-05", 2, "offers"); p3 = M.bumpAction(M.bumpAction(p3, "2026-10-05", 1), "2026-10-05", 1)
g = M.game([tx("2026-09-03", 400), tx("2026-10-03", 800), tx("2026-10-04", 100, "expense")], asOf, "RUB", p3)
assert(g.review.key === "2026-10" && g.review.target === 1000 && g.review.percent === 80 && !g.review.reached && g.review.best && g.review.profit === 700 && g.review.monthIndex === 9)
assert(g.review.weeks.total === 4 && g.review.weeks.done === 1)
p3.reviewed = "2026-10"; assert.strictEqual(M.game([], asOf, "RUB", p3).review, null)
assert.strictEqual(M.game([], asOf, "RUB", M.setGoal(M.emptyPlan(), "2026-11", 1000, "RUB")).review, null)

// A damaged plan file is ignored, not fatal
assert.deepStrictEqual(plain(M.normalizePlan(null)), plain(M.emptyPlan()))
let dirty = plain(M.normalizePlan({goals: {"2026-11": {amount: "x", currency: "USD"}, bad: {amount: 1, currency: "USD"}, "2026-12": {amount: 5, currency: "USD"}, "2027-01": null},
  actions: [{week: "2026-11-09", text: "a", target: 2000, done: -4}, {week: "nope", text: "a", target: 1}, 5, {week: "2026-11-02", off: true}], reviewed: "x"}))
assert.deepStrictEqual(Object.keys(dirty.goals), ["2026-12", "2027-01"])
const badRates = plain(M.normalizePlan({rates: {USD: {value: 92, base: "RUB"}, EUR: {value: -1, base: "RUB"}, NOPE: {value: 1, base: "RUB"}, GBP: {value: 1}}}))
assert.deepStrictEqual(badRates.rates, {USD: {value: 92, base: "RUB"}})
assert(dirty.actions.length === 2 && dirty.actions[0].off && dirty.actions[1].target === 999 && dirty.actions[1].done === 0 && dirty.reviewed === "")

// Demo data
const v = M.view(M.demo(today), "business"); assert(v.series.length === 6 && v.month.income === 100000)
assert.strictEqual(M.view(null, "all").series.length, 0)
assert(M.demo(today).game.achieved.length > 0)
assert.strictEqual(M.demo(today, "", "RUB").currency, "RUB")
assert(M.demo(today).game.goal.target === 150000 && M.demo(today).game.action.demo && M.demo(today).game.review === null)
assert.strictEqual(M.demo(today, "", "USD", undefined, M.setGoal(M.emptyPlan(), "2026-11", 7000, "USD")).game.goal.target, 7000)
assert.strictEqual(M.demo(today, "", "USD", undefined, M.setGoal(M.emptyPlan(), "2026-11", 7000, "USD")).game.goal.percent, M.demo(today).game.goal.percent)

console.log("model tests passed")
