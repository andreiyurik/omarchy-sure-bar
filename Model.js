.pragma library

// Pure logic only: no QML, no network, no user-facing text. Anything shown to
// a person is returned as a key or as data and translated by the caller.

var SYMBOLS = {RUB: "₽", USD: "$", EUR: "€", GBP: "£", JPY: "¥", KZT: "₸", UAH: "₴", INR: "₹", CNY: "¥", KRW: "₩", TRY: "₺"}
var PREFIXED = {USD: true, GBP: true, JPY: true, INR: true, CNY: true, KRW: true}
var BUSINESS_ALIASES = ["б", "b", "биз", "biz"]
var ONE_DAY_AGO = ["вчера", "yesterday"]
var TWO_DAYS_AGO = ["позавчера"]
var LADDER = [1, 10000, 50000, 100000, 300000, 500000, 1000000, 3000000, 10000000]
// With a goal, lifetime milestones read as months of that goal, after the first payment.
var GOAL_LADDER = [0.5, 1, 3, 6, 12, 24, 60, 120]
var NICE_STEPS = [1, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10]
var OFF_WORDS = ["off", "0", "нет", "убрать"]
var MAX_ACTIONS = 60

// Sure's config/currencies.yml; every currency not listed here uses 100.
var MINOR_UNITS = {}
;[[1, "JPY BYR XBC PYG RWF XBD XDR XOF XPD XPF XPT XTS GBX UGX VND VUV XAF XAG XAU XBA XBB CLP DJF BIF KMF KRW GNF HUF ISK"],
  [5, "MGA MRU"], [1000, "OMR TND BHD KWD LYD IQD JOD"], [10000, "CLF"], [100000000, "BTC DOGE"]
].forEach(function(group) { group[1].split(" ").forEach(function(code) { MINOR_UNITS[code] = group[0] }) })

function pad(n) { return n < 10 ? "0" + n : String(n) }
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
function symbol(currency) { return SYMBOLS[currency] || String(currency || "") }
function num(value) { var n = Number(value); return isFinite(n) ? n : 0 }
function fromMinor(value, currency) { return num(value) / (MINOR_UNITS[currency] || 100) }

// A plain origin or nothing: the value reaches a shell eval in omarchy-launch-webapp.
// Plain HTTP would expose the API key, so it is limited to this machine unless allowed.
function origin(raw, allowInsecure) {
  var m = String(raw || "").trim().replace(/\/+$/, "").match(/^(https?):\/\/([A-Za-z0-9.-]+)(:\d{1,5})?$/)
  if (!m) return {ok: false, error: "url-invalid"}
  var local = /^(localhost|127(\.\d{1,3}){3})$/i.test(m[2])
  if (m[1] === "http" && !local && allowInsecure !== true) return {ok: false, error: "url-insecure"}
  return {ok: true, url: m[0]}
}

function amountFrom(whole, fraction, thousands) {
  return parseFloat(whole.replace(/ /g, "") + (fraction ? "." + fraction : "")) * (thousands ? 1000 : 1)
}

// People paste "sure.example.com"; only this machine defaults to plain HTTP.
function normalizeServer(raw) {
  var text = String(raw || "").trim()
  if (!text || /^[a-z][a-z0-9+.-]*:\/\//i.test(text)) return text
  return (/^(localhost|127(\.\d{1,3}){3})([:/]|$)/i.test(text) ? "http://" : "https://") + text
}

// What went wrong, from what came back. A non-JSON answer was not written by Sure.
function failureKey(status, isJson) {
  if (status === -1) return "error.too-large"
  if (status === 0) return "error.unreachable"
  if (status === 429) return "error.rate-limited"
  if (status === 401 || status === 403) return !isJson ? "error.proxy" : status === 401 ? "error.rejected" : "error.forbidden"
  if (status === 404) return isJson ? "error.not-found" : "error.not-sure"
  if (status >= 500) return "error.server"
  if (status >= 200 && status < 300) return "error.not-sure"
  return "error.http"
}

// Exit codes from `curl`, used to explain a connection the HTTP client only reports as failed.
function probeKey(exitCode) {
  if (exitCode === 6) return "error.dns"
  if (exitCode === 7) return "error.refused"
  if (exitCode === 28) return "error.timeout"
  return [51, 58, 60, 77, 80, 83, 90, 91].indexOf(exitCode) >= 0 ? "error.tls" : "error.unreachable"
}

function retryable(key) {
  return ["error.unreachable", "error.dns", "error.refused", "error.timeout", "error.tls", "error.server", "error.rate-limited"].indexOf(key) >= 0
}

function retryDelay(attempt, retryAfterSeconds, baseMs, maxMs) {
  if (retryAfterSeconds > 0) return Math.min(retryAfterSeconds, 3600) * 1000
  return Math.min(maxMs, baseMs * Math.pow(2, Math.min(attempt, 16)))
}

// A server in another timezone can be a day behind, and then today's entries look like the future.
function latestDay(serverDay, localDate) {
  var local = iso(localDate), server = String(serverDay).slice(0, 10)
  return new Date((server > local ? server : local) + "T00:00:00")
}

function externalId(nowMs, random) {
  return "sure-bar-" + Math.floor(nowMs).toString(36) + "-" + Math.floor(random * 1e12).toString(36)
}

// Revenue before this date is taken from the local cache: last month onward can still change.
function windowStart(currentMonth) { return monthsBack(currentMonth, 2)[0] }

function cacheKey(baseUrl, businessTag, trackAll) { return [baseUrl, String(businessTag).toLowerCase(), trackAll === true].join("|") }

function needsFullRefresh(cache, key, today, forced) { return forced === true || !cache || cache.key !== key || cache.day !== today }

function slimTransaction(t) {
  return {date: String(t.date).slice(0, 10), amount_cents: num(t.amount_cents), currency: String(t.currency), classification: String(t.classification), transfer: !!t.transfer}
}

function mergeTransactions(cached, fresh, start) {
  return (cached || []).filter(function(t) { return t.date < start }).concat(fresh)
}

// A short window can hold fewer rows than the list shows, so older known ones fill the rest.
function mergeRecent(fresh, previous, start, limit) {
  var known = {}
  fresh.forEach(function(row) { known[row.id] = true })
  return fresh.concat((previous || []).filter(function(row) { return !known[row.id] && String(row.date) < start })).slice(0, limit)
}

function readSnapshot(raw, key) {
  if (!raw || raw.version !== 1 || raw.key !== key || !(raw.savedAt > 0) || !raw.cache || !Array.isArray(raw.cache.transactions)) return null
  var p = raw.payload
  if (!p || p.status !== "ok" || !Array.isArray(p.series) || !p.game || !p.business || !Array.isArray(p.recent)) return null
  return raw
}

function timezoneWarning(zone, remoteOffset, localOffset) {
  if (!zone || !remoteOffset || !localOffset || remoteOffset === localOffset) return null
  return {key: "warn.timezone", arg: zone + " (UTC" + remoteOffset + ")", arg2: "UTC" + localOffset, dismiss: "tz:" + zone + "|" + localOffset}
}

// "450 coffee", "+1200 client #b", "1.5k lunch #b @cash yesterday"
function parseEntry(raw, today, businessTag) {
  var text = String(raw || "").trim()
  if (!text) return {ok: false, error: "empty"}
  var m = text.match(/^(\+?)\s*(\d{1,3}(?: \d{3})+|\d+)(?:[.,](\d{1,2}))?\s*([кkКK])?(?:\s+|$)(.*)$/)
  if (!m) return {ok: false, error: "amount-first"}
  var amount = amountFrom(m[2], m[3], m[4])
  if (!(amount > 0) || amount > 1e12) return {ok: false, error: "bad-amount"}
  var tags = [], account = "", offset = 0, words = []
  m[5].split(/\s+/).forEach(function(word) {
    if (!word) return
    var lower = word.toLowerCase()
    if (word.length > 1 && word[0] === "#") {
      var tag = word.slice(1)
      if (BUSINESS_ALIASES.indexOf(tag.toLowerCase()) >= 0) tag = businessTag
      if (tags.indexOf(tag) < 0) tags.push(tag)
    } else if (word.length > 1 && word[0] === "@") account = word.slice(1)
    else if (ONE_DAY_AGO.indexOf(lower) >= 0) offset = 1
    else if (TWO_DAYS_AGO.indexOf(lower) >= 0) offset = 2
    else words.push(word)
  })
  var name = words.join(" ").slice(0, 120)
  if (!name) return {ok: false, error: "name-missing", amount: m[2]}
  var date = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset)
  return {ok: true, amount: amount, nature: m[1] === "+" ? "income" : "expense", name: name,
    tags: tags, account: account, date: iso(date), offset: offset}
}

// "goal 7000", "week 10 client offers". Entries start with an amount, so these can't collide.
function parseCommand(raw) {
  var m = String(raw || "").trim().match(/^(goal|цель|week|неделя)(?:\s+(.*))?$/i)
  if (!m) return null
  var kind = /^(goal|цель)$/i.test(m[1]) ? "goal" : "action"
  var rest = (m[2] || "").trim()
  if (OFF_WORDS.indexOf(rest.toLowerCase()) >= 0) return {ok: true, kind: kind, off: true}
  if (kind === "goal") {
    var a = rest.match(/^(\d{1,3}(?: \d{3})+|\d+)(?:[.,](\d{1,2}))?\s*([кkКK])?$/)
    var amount = a ? amountFrom(a[1], a[2], a[3]) : 0
    return amount > 0 && amount <= 1e12 ? {ok: true, kind: kind, off: false, amount: amount} : {ok: false, kind: kind, error: "goal-format"}
  }
  var w = rest.match(/^(\d{1,3})\s+(.+)$/), target = w ? parseInt(w[1], 10) : 0
  return target > 0 ? {ok: true, kind: kind, off: false, target: target, text: w[2].slice(0, 80)} : {ok: false, kind: kind, error: "action-format"}
}

function clone(value) { return JSON.parse(JSON.stringify(value)) }
function emptyPlan() { return {goals: {}, actions: [], reviewed: "", dismissed: []} }

// The plan file can be edited by hand, so nothing in it is trusted.
function normalizePlan(raw) {
  var plan = emptyPlan()
  if (!raw || typeof raw !== "object") return plan
  var goals = raw.goals && typeof raw.goals === "object" ? raw.goals : {}
  Object.keys(goals).forEach(function(key) {
    if (!/^\d{4}-\d{2}$/.test(key)) return
    var goal = goals[key]
    if (goal === null) plan.goals[key] = null
    else if (goal && num(goal.amount) > 0 && typeof goal.currency === "string") plan.goals[key] = {amount: num(goal.amount), currency: goal.currency.slice(0, 12)}
  })
  var isWeek = function(week) { return /^\d{4}-\d{2}-\d{2}$/.test(week) }
  plan.actions = (Array.isArray(raw.actions) ? raw.actions : []).filter(function(a) {
    return a && isWeek(a.week) && (a.off === true || (typeof a.text === "string" && num(a.target) >= 1))
  }).map(function(a) {
    return a.off === true ? {week: a.week, off: true}
      : {week: a.week, text: a.text.slice(0, 80), target: Math.min(999, Math.floor(num(a.target))), done: Math.max(0, Math.floor(num(a.done)))}
  }).sort(byWeek).slice(-MAX_ACTIONS)
  if (/^\d{4}-\d{2}$/.test(raw.reviewed)) plan.reviewed = raw.reviewed
  if (Array.isArray(raw.dismissed)) plan.dismissed = raw.dismissed.filter(function(id) { return typeof id === "string" }).slice(-20)
  return plan
}

function byWeek(a, b) { return a.week < b.week ? -1 : a.week > b.week ? 1 : 0 }

// A goal stays in force until changed, so changing it never rewrites past months.
function goalFor(plan, month) {
  var keys = Object.keys(plan.goals).filter(function(key) { return key <= month }).sort()
  return keys.length ? plan.goals[keys[keys.length - 1]] : null
}

function setGoal(plan, month, amount, currency) {
  var next = clone(plan)
  next.goals[month] = amount ? {amount: amount, currency: currency} : null
  return next
}

function weekStart(date) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  d.setDate(d.getDate() - (d.getDay() + 6) % 7)
  return iso(d)
}

// Last week's action carries over with a clean count, so a new week needs no typing.
function actionFor(plan, week) {
  var past = plan.actions.filter(function(a) { return a.week <= week })
  var last = past.length ? past[past.length - 1] : null
  if (!last || last.off) return null
  if (last.week === week) return clone(last)
  return {week: week, text: last.text, target: last.target, done: 0, carried: true}
}

function withAction(plan, action) {
  var next = clone(plan)
  next.actions = next.actions.filter(function(a) { return a.week !== action.week }).concat([action]).sort(byWeek).slice(-MAX_ACTIONS)
  return next
}

function setAction(plan, week, target, text) {
  var current = actionFor(plan, week)
  var done = current && current.text === text ? current.done : 0
  return withAction(plan, {week: week, text: text, target: target, done: done})
}

function clearAction(plan, week) { return withAction(plan, {week: week, off: true}) }

function bumpAction(plan, week, delta) {
  var current = actionFor(plan, week)
  if (!current || current.demo) return plan
  return withAction(plan, {week: week, text: current.text, target: current.target, done: Math.min(9999, Math.max(0, current.done + delta))})
}

// A week belongs to the month its Monday falls in.
function actionWeeks(plan, month) {
  var year = parseInt(month.slice(0, 4), 10), index = parseInt(month.slice(5, 7), 10) - 1
  var last = new Date(year, index + 1, 0).getDate(), total = 0, done = 0
  for (var day = 1; day <= last; ++day) {
    var date = new Date(year, index, day)
    if (date.getDay() !== 1) continue
    var action = actionFor(plan, iso(date))
    if (!action) continue
    total++
    if (action.done >= action.target) done++
  }
  return {total: total, done: done}
}

// Round stages on the way to a goal, for example 2000, 4000, 6000, 7000.
function goalStages(target) {
  if (!(target >= 4)) return [target]
  var raw = target / 4, magnitude = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10 + 1e-9))
  var nice = NICE_STEPS.filter(function(n) { return n * magnitude >= raw - 1e-9 })[0]
  var step = nice * magnitude, stages = []
  for (var value = step; value < target - 1e-6; value += step) stages.push(Math.round(value * 100) / 100)
  return stages.concat([target])
}

function goalProgress(target, current, day, daysInMonth) {
  var stages = goalStages(target)
  var ahead = stages.filter(function(stage) { return stage > current })
  return {target: target, current: current, stages: stages, passed: stages.length - ahead.length,
    percent: Math.floor(current / target * 100), reached: current >= target, halfway: current >= target / 2,
    over: Math.max(0, current - target), remaining: Math.max(0, target - current),
    stage: ahead.length ? {target: ahead[0], remaining: ahead[0] - current} : null,
    paceAmount: target * day / daysInMonth}
}

function pace(spent, budget, day, daysInMonth) {
  if (!(budget > 0) || !(daysInMonth > 0)) return null
  var percent = Math.round(spent / budget * 100)
  var elapsed = Math.round(day / daysInMonth * 100)
  return {percent: percent, elapsed: elapsed,
    status: percent >= 100 ? "over" : percent > elapsed + 10 ? "warn" : "ok"}
}

function formatMoney(value, currency, separator) {
  var n = Math.round(num(value)), digits = String(Math.abs(n)), out = ""
  var gap = separator === undefined ? " " : separator
  while (digits.length > 3) { out = gap + digits.slice(-3) + out; digits = digits.slice(0, -3) }
  var sign = n < 0 ? "−" : "", sym = symbol(currency)
  return PREFIXED[currency] ? sign + sym + digits + out : sign + digits + out + " " + sym
}

function shortMoney(value, format) {
  var f = format || {k: "%1k", m: "%1M", decimal: "."}
  var n = Math.abs(num(value)), sign = num(value) < 0 ? "−" : ""
  var text = function(x) { return String(x).replace(".", f.decimal) }
  if (n >= 1e6) return sign + f.m.replace("%1", text(Math.round(n / 1e5) / 10))
  if (n >= 1e4) return sign + f.k.replace("%1", text(Math.round(n / 1e3)))
  if (n >= 1e3) return sign + f.k.replace("%1", text(Math.round(n / 100) / 10))
  return sign + String(Math.round(n))
}

// Oldest first, ending with currentMonth ("YYYY-MM-01").
function monthsBack(currentMonth, count) {
  var year = parseInt(currentMonth.slice(0, 4), 10), month = parseInt(currentMonth.slice(5, 7), 10) - 1
  var out = []
  for (var i = count - 1; i >= 0; --i) {
    var d = new Date(year, month - i, 1)
    out.push(d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-01")
  }
  return out
}

function monthIndex(month) { return parseInt(String(month).slice(5, 7), 10) - 1 }

function burn(series) {
  var full = series.slice(0, -1).filter(function(m) { return m.spending > 0 }).slice(-3)
  if (!full.length) return series.length ? series[series.length - 1].spending : 0
  return full.reduce(function(sum, m) { return sum + m.spending }, 0) / full.length
}

function runway(netWorth, monthlyBurn) {
  return netWorth > 0 && monthlyBurn > 0 ? netWorth / monthlyBurn : null
}

function monthSummary(point) {
  var net = point.income - point.spending
  return {income: point.income, spending: point.spending, net: net,
    rate: point.income > 0 ? net / point.income * 100 : null}
}

// Moving money between your own accounts is neither revenue nor spending.
function counted(transaction) { return !transaction.transfer }

// Sum tagged transactions per month; other currencies are counted, not converted.
function aggregateTagged(transactions, months, currency) {
  var byMonth = {}, skipped = 0
  months.forEach(function(month) { byMonth[month.slice(0, 7)] = {month: month, income: 0, spending: 0} })
  transactions.forEach(function(t) {
    var bucket = byMonth[String(t.date).slice(0, 7)]
    if (!bucket || !counted(t)) return
    if (t.currency !== currency) { skipped++; return }
    var amount = fromMinor(t.amount_cents, currency)
    if (t.classification === "income") bucket.income += amount
    else bucket.spending += amount
  })
  return {series: months.map(function(month) { return byMonth[month.slice(0, 7)] }), skipped: skipped}
}

function view(payload, mode) {
  var empty = {series: [], month: monthSummary({income: 0, spending: 0}), burn: 0, skipped: 0}
  if (!payload) return empty
  var source = mode === "business" ? payload.business : payload
  if (!source || !source.series || !source.series.length) return empty
  return {series: source.series, month: monthSummary(source.series[source.series.length - 1]),
    burn: burn(source.series), skipped: source.skipped || 0}
}

// Hint wins outright; otherwise the setting, the last used account, then an everyday account.
function pickAccount(accounts, hint, preferred, lastId) {
  var usable = accounts.filter(function(a) { return !a.status || a.status === "active" })
  var named = function(text) {
    var needle = String(text).toLowerCase()
    return usable.filter(function(a) { return String(a.name).toLowerCase().indexOf(needle) >= 0 })[0] || null
  }
  if (hint) return named(hint)
  return (preferred ? named(preferred) : null)
    || usable.filter(function(a) { return a.id === lastId })[0]
    || usable.filter(function(a) { return a.account_type === "depository" })[0]
    || usable[0] || null
}

// Everything is derived from transactions, so there is no game state to keep or lose.
function game(transactions, asOf, currency, plan) {
  var y = asOf.getFullYear(), mo = asOf.getMonth(), day = asOf.getDate(), today = iso(asOf)
  var curKey = today.slice(0, 7), prevDate = new Date(y, mo - 1, 1)
  var prevKey = iso(prevDate).slice(0, 7), prevDays = new Date(y, mo, 0).getDate()
  var limitDay = Math.min(day, prevDays), months = {}, incomes = [], prevSame = 0
  transactions.forEach(function(t) {
    var date = String(t.date).slice(0, 10)
    if (!counted(t) || t.currency !== currency || date > today) return
    var key = date.slice(0, 7), amount = fromMinor(t.amount_cents, currency)
    var bucket = months[key] || (months[key] = {income: 0, spending: 0})
    if (t.classification === "income") {
      bucket.income += amount
      incomes.push({date: date, amount: amount})
      if (key === prevKey && parseInt(date.slice(8, 10), 10) <= limitDay) prevSame += amount
    } else bucket.spending += amount
  })
  incomes.sort(function(a, b) { return a.date < b.date ? -1 : a.date > b.date ? 1 : 0 })

  var activePlan = plan || emptyPlan(), setGoalValue = goalFor(activePlan, curKey)
  var usableGoal = setGoalValue && setGoalValue.currency === currency ? setGoalValue : null
  var ladderBase = usableGoal && usableGoal.amount >= 4 ? usableGoal.amount : 0
  var targets = ladderBase ? [1].concat(GOAL_LADDER.map(function(times) { return Math.round(ladderBase * times) })) : LADDER

  var achieved = [], total = 0, step = 0
  var ladder = targets.map(function(target) { return {target: target, done: false, date: ""} })
  incomes.forEach(function(item) {
    total += item.amount
    while (step < targets.length && total >= targets[step]) {
      ladder[step].done = true
      ladder[step].date = item.date
      achieved.push({key: "rev-" + targets[step], kind: "revenue", target: targets[step], date: item.date})
      step++
    }
  })
  var next = null
  if (step < targets.length) {
    var floor = step > 0 ? targets[step - 1] : 0
    next = {target: targets[step], index: step, remaining: targets[step] - total,
      percent: Math.min(99, Math.floor(total / targets[step] * 100)),
      segment: Math.max(0, Math.min(1, (total - floor) / (targets[step] - floor)))}
  }

  var keys = Object.keys(months).sort(), record = null, profit = false, run = 0, lastIndex = null, three = false
  keys.forEach(function(key) {
    var bucket = months[key], index = parseInt(key.slice(0, 4), 10) * 12 + parseInt(key.slice(5, 7), 10)
    if (key < curKey && bucket.income > 0 && (!record || bucket.income > record.amount)) record = {month: key + "-01", amount: bucket.income}
    if (key < curKey && !profit && bucket.income > 0 && bucket.income > bucket.spending) {
      profit = true
      achieved.push({key: "first-profit", kind: "first-profit", date: key + "-28"})
    }
    if (bucket.income > 0) {
      run = lastIndex !== null && index === lastIndex + 1 ? run + 1 : 1
      lastIndex = index
      if (run === 3 && !three) {
        three = true
        achieved.push({key: "three-months", kind: "three-months", date: key + "-28"})
      }
    }
  })
  achieved.sort(function(a, b) { return a.date < b.date ? -1 : a.date > b.date ? 1 : 0 })

  var current = months[curKey] ? months[curKey].income : 0
  var delta = prevSame > 0 ? Math.round((current - prevSame) / prevSame * 100) : null
  var daysInMonth = new Date(y, mo + 1, 0).getDate()
  return {
    monthKey: curKey, week: weekStart(asOf), ladderBase: ladderBase,
    goal: usableGoal ? goalProgress(usableGoal.amount, current, day, daysInMonth) : null,
    goalCurrency: setGoalValue && !usableGoal ? setGoalValue.currency : "",
    action: actionFor(activePlan, weekStart(asOf)),
    review: monthReview(activePlan, prevKey, months, currency),
    profit: months[curKey] ? months[curKey].income - months[curKey].spending : 0,
    day: day, daysInMonth: daysInMonth, monthIndex: mo, prevMonthIndex: prevDate.getMonth(),
    total: total, current: current, prevSame: prevSame, delta: delta, deltaAmount: current - prevSame,
    record: record, isRecord: !!record && current > record.amount, next: next, ladder: ladder, achieved: achieved
  }
}

// Last month against the goal it had, until dismissed. No goal then, nothing to review.
function monthReview(plan, month, months, currency) {
  if (plan.reviewed >= month) return null
  var goal = goalFor(plan, month)
  if (!goal || goal.currency !== currency) return null
  var bucket = months[month] || {income: 0, spending: 0}, best = 0
  Object.keys(months).forEach(function(key) { if (key < month) best = Math.max(best, months[key].income) })
  return {key: month, monthIndex: monthIndex(month + "-01"), target: goal.amount, income: bucket.income, profit: bucket.income - bucket.spending,
    percent: Math.floor(bucket.income / goal.amount * 100), reached: bucket.income >= goal.amount,
    best: bucket.income > 0 && bucket.income > best, weeks: actionWeeks(plan, month)}
}

function freshAchievements(before, after) {
  if (!before || !after || before.ladderBase !== after.ladderBase) return []
  var known = {}
  before.achieved.forEach(function(item) { known[item.key] = true })
  return after.achieved.filter(function(item) { return !known[item.key] })
}

var DEMO_NAMES = {groceries: "Groceries", ads: "Ads", cafe: "Cafes", subscriptions: "Subscriptions",
  coffee: "Coffee", server: "Server", client: "Client payment", action: "client offers"}

// Demo numbers fill in only what the person hasn't set themselves.
function demoPlan(today, plan, currency, names) {
  var out = clone(plan || emptyPlan()), month = iso(today).slice(0, 7), week = weekStart(today)
  var goal = goalFor(out, month)
  if (!goal || goal.currency !== currency) out.goals[month] = {amount: 150000, currency: currency}
  if (!actionFor(out, week)) out.actions.push({week: week, text: names.action, target: 10, done: 4, demo: true})
  out.reviewed = iso(new Date(today.getFullYear(), today.getMonth(), 0)).slice(0, 7)
  return out
}

function demo(today, reason, currency, names, plan) {
  var code = currency || "USD", n = names || DEMO_NAMES
  var months = monthsBack(iso(new Date(today.getFullYear(), today.getMonth(), 1)), 6)
  var income = [180000, 180000, 210000, 180000, 240000, 180000]
  var spending = [132000, 148000, 121000, 167000, 139000, 74000]
  var bizIn = [60000, 40000, 90000, 70000, 60000, 100000]
  var bizOut = [41000, 52000, 38000, 66000, 47000, 21000]
  var make = function(a, b) { return months.map(function(month, i) { return {month: month, income: a[i], spending: b[i]} }) }
  var days = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate()
  var cats = [[n.groceries, 28000, 31000], [n.ads, 20000, 14500], [n.cafe, 12000, 9800], [n.subscriptions, 8000, 3200]]
  // Fake revenue follows a real goal, so the demo never claims it is already beaten.
  var effectivePlan = demoPlan(today, plan, code, n), scale = goalFor(effectivePlan, iso(today).slice(0, 7)).amount / 150000
  var taggedDemo = []
  months.forEach(function(month, i) {
    [[3, 0.4], [12, 0.35], [22, 0.25]].forEach(function(p) {
      taggedDemo.push({date: month.slice(0, 8) + pad(p[0]), amount_cents: bizIn[i] * p[1] * 100 * scale, currency: code, classification: "income"})
    })
  })
  return {status: "demo", reason: reason || "", currency: code, series: make(income, spending), warnings: [],
    game: game(taggedDemo, today, code, effectivePlan),
    business: {series: make(bizIn, bizOut), skipped: 0, recent: [
      {id: "demo-3", date: iso(today), name: n.client, amount: 50000, category: "", currency: code},
      {id: "demo-2", date: iso(today), name: n.server, amount: -4900, category: n.subscriptions, currency: code}]},
    netWorth: 1250000,
    budget: {spent: 74000, total: 120000, pace: pace(74000, 120000, today.getDate(), days)},
    categories: cats.map(function(c) { return {name: c[0], total: c[1], spent: c[2]} }),
    recent: [
      {id: "demo-1", date: iso(today), name: n.coffee, amount: -450, category: n.cafe, currency: code},
      {id: "demo-2", date: iso(today), name: n.server, amount: -4900, category: n.subscriptions, currency: code},
      {id: "demo-3", date: iso(today), name: n.client, amount: 50000, category: "", currency: code}
    ]}
}
