import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root
  // Third-party services can't read shell.json, so the bar widget hands over its settings.
  property var widgetSettings: null
  property var payload: null
  property bool busy: false
  property bool saving: false
  property var lastAdded: null
  property var plan: Model.emptyPlan()
  property var gameSource: null
  property var cache: null
  property var snapshotRaw: null
  property bool snapshotChecked: false
  property var keyScopes: null
  property var timezoneNote: null
  property string checkedZone: ""
  property var entryAttempt: null
  property bool timedOut: false
  property real blockedUntil: 0
  property int retryAttempt: 0
  signal connected()
  property string apiKey: ""
  property bool keyChecked: false
  property bool amountsHidden: false
  property date updatedAt: new Date(0)
  property date now: new Date()

  // Why the panel shows the connect screen: "", no-key, rejected, url-invalid, url-insecure.
  property string setupReason: ""
  property string setupError: ""
  property bool connecting: false
  property string errorKey: ""
  property string errorArg: ""

  // Test seams: settings without a running shell, and no desktop notifications.
  property var overrides: null
  property bool silent: false
  property string lastNotice: ""

  property var accounts: []
  property var tags: []
  property var inflight: []
  property int generation: 0
  property string pendingNotice: ""

  readonly property int maxResponseChars: 8000000
  readonly property int maxPages: 30
  readonly property string pluginId: "andreiyurik.sure-bar"
  // Test seams for time: the defaults are what people get.
  readonly property int retryBaseMs: Number(settings.retryBaseMs) || 15000
  readonly property int retryMaxMs: Number(settings.retryMaxMs) || 300000
  readonly property int requestTimeoutMs: Number(settings.requestTimeoutMs) || 20000
  readonly property int probeSeconds: Number(settings.probeSeconds) || 8
  readonly property string configDir: (Quickshell.env("HOME") || "") + "/.config/sure-bar"

  Commons.Translations { id: catalog; directory: Qt.resolvedUrl("i18n") }
  function t(key) { return catalog.t(key) }
  function tn(key, count) { return catalog.tn(key, count) }

  readonly property var settings: overrides || widgetSettings || ({})
  readonly property bool configured: !!overrides || widgetSettings !== null
  readonly property string rawUrl: String(settings.baseUrl || "http://localhost:3000")
  readonly property var server: Model.origin(Model.normalizeServer(rawUrl), settings.allowInsecureHttp === true)
  readonly property string baseUrl: server.ok ? server.url : ""
  readonly property string businessTag: String(settings.businessTag || "business")
  readonly property bool trackAllIncome: settings.trackAllIncome === true
  readonly property string defaultAccount: String(settings.defaultAccount || "")
  readonly property bool autoRefresh: settings.autoRefresh !== false
  readonly property int refreshMinutes: Math.max(1, Math.min(120, Number(settings.refreshMinutes) || 10))
  readonly property bool forcedDemo: settings.demoMode === true

  readonly property string cacheId: Model.cacheKey(baseUrl, businessTag, trackAllIncome)
  readonly property bool readOnly: !!keyScopes && keyScopes.indexOf("read_write") < 0
  readonly property bool canRetry: Model.retryable(errorKey)
  readonly property bool hasKey: apiKey !== ""
  readonly property bool probing: probe.running
  readonly property var visibleTimezoneNote: timezoneNote && plan.dismissed.indexOf(timezoneNote.dismiss) < 0 ? timezoneNote : null
  readonly property bool isDemo: !payload || payload.status === "demo"
  readonly property bool needsSetup: setupReason !== ""
  readonly property string currency: payload ? payload.currency : "USD"
  readonly property var game: payload ? payload.game : null
  readonly property var runway: payload ? Model.runway(payload.netWorth, Model.view(payload, "all").burn) : null
  readonly property bool alarm: !isDemo && ((!!payload.budget && !!payload.budget.pace && payload.budget.pace.status === "over") || (runway !== null && runway < 3))
  readonly property string message: errorKey ? t(errorKey).replace("%1", errorArg) : ""

  // Display helpers. Every amount on screen goes through money(), so hiding amounts has one switch.
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)
  function plainMoney(value, code) { return Model.formatMoney(value, code || currency, locale.groupSeparator) }
  function money(value, code) { return amountsHidden ? "•••" : plainMoney(value, code) }
  function signed(value, code) { return amountsHidden ? "•••" : (value > 0 ? "+" : "") + plainMoney(value, code) }
  function shortMoney(value) {
    return amountsHidden ? "•••" : Model.shortMoney(value, {k: t("short.k"), m: t("short.m"), decimal: locale.decimalPoint})
  }
  function monthName(index) { return locale.standaloneMonthName(index) }
  function monthShort(index) { return locale.standaloneMonthName(index, Locale.ShortFormat).replace(/\.$/, "") }
  function monthOf(isoDate) { return monthShort(Model.monthIndex(isoDate)) }
  function number(value, decimals) { return Commons.I18n.formatNumber(value, decimals) }
  function runwayText() { return runway === null ? t("growth.runway-unknown") : t("growth.runway-value").arg(number(Math.round(runway * 10) / 10, 1)) }

  function raceText(g) {
    if (!g) return ""
    if (g.goal) {
      if (g.goal.over > 0) return t("race.goal-over").arg(money(g.goal.over))
      if (g.goal.reached) return t("race.goal-reached")
      return t("race.goal").arg(number(g.goal.percent, 0)).arg(money(g.goal.stage.remaining)).arg(money(g.goal.stage.target))
    }
    if (g.delta !== null) return (g.delta >= 0 ? t("race.ahead") : t("race.behind")).arg(number(Math.abs(g.delta), 0))
    if (!g.next) return t("race.all-done")
    if (g.next.target === 1) return t("race.first-payment")
    return t("race.to-next").arg(money(g.next.remaining))
  }
  function winTitle(win) {
    if (win.kind === "first-profit") return t("win.first-profit")
    if (win.kind === "three-months") return t("win.three-months")
    return win.target === 1 ? t("win.first-payment") : t("win.revenue").arg(money(win.target))
  }
  function barText(compact) {
    var g = game
    if (!g || needsSetup) return "◎"
    if (g.goal) {
      var progress = g.goal.reached ? "★" : number(g.goal.percent, 0) + "%"
      return compact || amountsHidden || g.current <= 0 ? progress : shortMoney(g.current) + " " + progress
    }
    var arrow = g.delta === null ? "" : g.delta >= 0 ? "▲" : "▼"
    if (compact || amountsHidden || g.current <= 0) return arrow || "◎"
    return shortMoney(g.current) + (arrow ? " " + arrow : "")
  }
  function updatedText() {
    var minutes = Math.floor((now.getTime() - updatedAt.getTime()) / 60000)
    if (updatedAt.getTime() === 0) return ""
    if (minutes < 1) return t("footer.updated-now")
    if (minutes < 60) return tn("footer.updated-min", minutes).arg(number(minutes, 0))
    var hours = Math.floor(minutes / 60)
    return tn("footer.updated-hours", hours).arg(number(hours, 0))
  }
  function previewAccount(hint) {
    var last = payload && payload.recent && payload.recent[0] ? payload.recent[0].accountId : ""
    return Model.pickAccount(accounts, hint, defaultAccount, last)
  }

  onConfiguredChanged: refresh()
  onForcedDemoChanged: refresh()
  onBaseUrlChanged: { forgetServer(); refresh() }
  Connections {
    target: Commons.I18n
    function onLanguageChanged() { if (root.isDemo) root.refresh() }
  }

  FileView {
    id: keyFile
    path: root.configDir + "/api-key"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { root.apiKey = text().trim(); root.keyChecked = true; root.refresh() }
    onLoadFailed: { root.apiKey = ""; root.keyChecked = true; root.refresh() }
  }
  FileView {
    id: snapshotFile
    path: root.configDir + "/snapshot.json"
    printErrors: false
    onLoaded: {
      try { root.snapshotRaw = JSON.parse(text()) } catch (error) { root.snapshotRaw = null }
      root.snapshotChecked = true
      root.refresh()
    }
    onLoadFailed: { root.snapshotChecked = true; root.refresh() }
  }
  FileView {
    id: prefsFile
    path: root.configDir + "/hide-amounts"
    printErrors: false
    onLoaded: root.amountsHidden = text().trim() === "1"
  }

  FileView {
    id: planFile
    path: root.configDir + "/plan.json"
    printErrors: false
    onLoaded: {
      var raw = null
      try { raw = JSON.parse(text()) } catch (error) { raw = null }
      root.plan = Model.normalizePlan(raw)
      root.rebuildGame()
    }
  }

  // Over stdin, so an API key never shows up in a process list.
  PrivateFile {
    id: keyWriter
    path: root.configDir + "/api-key"
    onSaved: function(ok) {
      root.connecting = false
      if (ok) { keyFile.reload(); root.connected() }
      else root.setupError = "setup.save-failed"
    }
  }
  PrivateFile { id: planWriter; path: root.configDir + "/plan.json" }
  PrivateFile { id: snapshotWriter; path: root.configDir + "/snapshot.json" }
  Process { id: prefsWriter }
  // Only when a connection fails: it sends no key, and names the reason the HTTP client can't.
  Process {
    id: probe
    property var report: null
    onExited: function(code) { if (report) report(Model.probeKey(code)); report = null }
  }
  Process {
    id: serverWriter
    property var finish: null
    onExited: function(code) { if (finish) finish(code === 0); finish = null }
  }
  Process {
    id: timezoneCheck
    property string zone: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.timezoneNote = Model.timezoneWarning(timezoneCheck.zone, lines[1], lines[0])
      }
    }
  }
  Process {
    id: entryNotice
    stdout: StdioCollector { onStreamFinished: if (text.trim() === "undo") root.undoLast() }
  }

  Timer { interval: root.refreshMinutes * 60000; running: root.autoRefresh; repeat: true; onTriggered: root.refresh() }
  Timer { id: retryTimer; onTriggered: root.refresh() }
  // A large jump between ticks means the machine slept, so the numbers are old.
  Timer {
    interval: Number(root.settings.tickMs) || 30000; running: true; repeat: true
    onTriggered: {
      var tick = new Date(), slept = tick.getTime() - root.now.getTime() > 120000
      root.now = tick
      if (slept && root.autoRefresh) { root.retryAttempt = 0; root.refresh() }
    }
  }
  // Sure recalculates balances in a background job after each write.
  Timer { id: settle; interval: 4000; onTriggered: root.refresh() }
  Timer {
    id: watchdog
    interval: root.requestTimeoutMs
    onTriggered: { root.timedOut = true; root.inflight.slice().forEach(function(xhr) { xhr.abort() }) }
  }

  function api(method, path, body, done, keyOverride, baseOverride) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var index = root.inflight.indexOf(xhr)
      if (index < 0) return
      root.inflight.splice(index, 1)
      if (root.inflight.length) watchdog.restart()
      else watchdog.stop()
      if (xhr.responseText && xhr.responseText.length > root.maxResponseChars) { done(false, null, -1, 0); return }
      var ok = xhr.status >= 200 && xhr.status < 300, data = null
      if (xhr.responseText) { try { data = JSON.parse(xhr.responseText) } catch (error) { ok = false } }
      done(ok, data, xhr.status, xhr.status === 429 ? parseInt(xhr.getResponseHeader("Retry-After"), 10) || 0 : 0)
    }
    xhr.open(method, (baseOverride || baseUrl) + "/api/v1" + path)
    xhr.setRequestHeader("X-Api-Key", keyOverride || apiKey)
    xhr.setRequestHeader("Accept", "application/json")
    if (body) xhr.setRequestHeader("Content-Type", "application/json")
    inflight.push(xhr)
    watchdog.restart()
    xhr.send(body ? JSON.stringify(body) : "")
  }

  function failureOf(status, data, retryAfter) { return {status: status, json: data !== null && data !== undefined, retryAfter: retryAfter || 0} }

  function fetchAll(requests, done) {
    var results = {}, left = requests.length, failure = null
    if (!left) { done(null, results); return }
    requests.forEach(function(request) {
      api("GET", request.path, null, function(ok, data, status, retryAfter) {
        if (!ok && failure === null) failure = failureOf(status, data, retryAfter)
        results[request.key] = data
        if (--left === 0) done(failure, results)
      })
    })
  }

  function errorFor(status, isJson) { return Model.failureKey(status, isJson === undefined ? true : isJson) }
  function setError(status, isJson) {
    errorKey = errorFor(status, isJson)
    errorArg = String(status)
  }

  function runProbe(url, report) {
    probe.report = report
    probe.exec(["curl", "-sS", "-o", "/dev/null", "-m", String(probeSeconds), url + "/api/v1/usage"])
  }

  function reportFailure(failure) {
    var previous = errorKey
    setError(failure.status, failure.json)
    if (errorKey === "error.rejected") setupReason = "rejected"
    if (errorKey === "error.rate-limited") {
      var wait = Model.retryDelay(retryAttempt, failure.retryAfter, retryBaseMs, retryMaxMs)
      blockedUntil = Date.now() + wait
      errorArg = String(Math.ceil(wait / 60000))
    }
    if (failure.status === 0) {
      if (timedOut) errorKey = "error.timeout"
      else {
        // Keep the last explanation on screen while checking again, so it doesn't flicker.
        if (previous !== "" && Model.retryable(previous) && previous !== "error.server" && previous !== "error.rate-limited") errorKey = previous
        runProbe(baseUrl, function(key) { if (root.errorKey !== "") root.errorKey = key })
      }
    }
    if (autoRefresh && Model.retryable(errorKey)) {
      retryTimer.interval = Model.retryDelay(retryAttempt++, failure.retryAfter, retryBaseMs, retryMaxMs)
      retryTimer.restart()
    }
  }

  // A different server means different numbers; nothing from the old one may stay on screen.
  function forgetServer() {
    payload = null
    cache = null
    gameSource = null
    keyScopes = null
    errorKey = ""
    blockedUntil = 0
    retryAttempt = 0
    retryTimer.stop()
  }

  function restoreSnapshot() {
    var snapshot = Model.readSnapshot(snapshotRaw, cacheId)
    snapshotRaw = null
    if (!snapshot || payload) return
    cache = snapshot.cache
    keyScopes = snapshot.scopes || null
    updatedAt = new Date(snapshot.savedAt)
    gameSource = {transactions: snapshot.cache.transactions, asOf: new Date(snapshot.asOf + "T00:00:00"), currency: snapshot.payload.currency}
    payload = snapshot.payload
    rebuildGame()
  }

  function saveSnapshot(asOf) {
    snapshotWriter.save(JSON.stringify({version: 1, key: cacheId, savedAt: updatedAt.getTime(), asOf: Model.iso(asOf), scopes: keyScopes, payload: payload, cache: cache}))
  }

  function loadScopes() {
    api("GET", "/usage", null, function(ok, data) {
      if (ok && data && data.api_key && Array.isArray(data.api_key.scopes)) root.keyScopes = data.api_key.scopes
    })
  }

  function checkTimezone(zone) {
    if (!zone || zone === checkedZone) return
    checkedZone = zone
    timezoneCheck.zone = zone
    timezoneCheck.exec(["sh", "-c", 'date +%z; TZ="$1" date +%z', "sh", zone])
  }

  function showDemo(reason) {
    busy = false
    errorKey = ""
    var names = {groceries: t("demo.groceries"), ads: t("demo.ads"), cafe: t("demo.cafe"), subscriptions: t("demo.subscriptions"),
      coffee: t("demo.coffee"), server: t("demo.server"), client: t("demo.client")}
    names.action = t("demo.action")
    gameSource = null
    payload = Model.demo(new Date(), reason, Commons.I18n.language.indexOf("ru") === 0 ? "RUB" : "USD", names, plan)
  }

  function refreshIfStale() {
    if (autoRefresh && !busy && (errorKey !== "" || now.getTime() - updatedAt.getTime() > 120000)) refresh()
  }

  // Closed months and old revenue come from the local cache, re-read in full once a day or on request.
  function refresh(forceFull) {
    if (!keyChecked || !configured || !snapshotChecked) return
    if (snapshotRaw && server.ok && apiKey && !forcedDemo) restoreSnapshot()
    setupReason = ""
    if (forcedDemo) { ++generation; showDemo("demo.reason.forced"); return }
    if (!server.ok) { ++generation; setupReason = server.error; showDemo("demo.reason.no-key"); return }
    if (!apiKey) { ++generation; setupReason = "no-key"; showDemo("demo.reason.no-key"); return }
    if (Date.now() < blockedUntil) return
    var token = ++generation
    busy = true
    timedOut = false
    retryTimer.stop()
    if (keyScopes === null) loadScopes()
    var full = Model.needsFullRefresh(cache, cacheId, Model.iso(new Date()), forceFull === true)
    var known = full ? null : cache
    var alive = function() { return token === generation }
    var fail = function(failure) {
      if (!alive()) return
      busy = false
      reportFailure(failure)
      flushNotice()
      if (!payload) { var key = errorKey, arg = errorArg; showDemo("demo.reason.unreachable"); errorKey = key; errorArg = arg }
    }
    fetchAll([
      {key: "accounts", path: "/accounts?per_page=100"},
      {key: "cash", path: "/cash_flow"},
      {key: "sheet", path: "/balance_sheet"},
      {key: "tags", path: "/tags"},
      {key: "recent", path: "/transactions?per_page=6"},
      {key: "budgets", path: "/budgets?per_page=6"}
    ], function(failure, base) {
      if (!alive()) return
      if (failure !== null) { fail(failure); return }
      root.accounts = (base.accounts.accounts || []).slice(0, 200)
      root.tags = (base.tags || []).slice(0, 1000)
      if (!root.accounts.length) { retryAttempt = 0; showDemo("demo.reason.no-accounts"); return }
      var months = Model.monthsBack(base.cash.month, 6)
      var requests = months.slice(0, -1).filter(function(month) { return !known || !known.months[month] })
        .map(function(month) { return {key: month, path: "/cash_flow?month=" + month} })
      var current = (base.budgets.budgets || []).filter(function(budget) { return budget.current })[0]
      if (current) {
        requests.push({key: "budget", path: "/budgets/" + encodeURIComponent(current.id)})
        requests.push({key: "budgetCategories", path: "/budget_categories?per_page=100"})
      }
      fetchAll(requests, function(failure2, detail) {
        if (!alive()) return
        if (failure2 !== null) { fail(failure2); return }
        var lines = (current && detail.budgetCategories ? detail.budgetCategories.budget_categories || [] : [])
          .filter(function(line) { return line.budget_id === current.id && line.budgeted_spending_cents > 0 })
          .sort(function(a, b) { return b.budgeted_spending_cents - a.budgeted_spending_cents })
          .slice(0, 8)
        fetchAll(lines.map(function(line) { return {key: line.id, path: "/budget_categories/" + encodeURIComponent(line.id)} }), function(failure3, categories) {
          if (!alive()) return
          if (failure3 !== null) { fail(failure3); return }
          var start = known ? Model.windowStart(base.cash.month) : ""
          loadRevenue(months, base.cash.currency, 1, [], start, known, function(revenue, failure4) {
            if (!alive()) return
            if (failure4 !== null) { fail(failure4); return }
            compose(base, detail, months, lines, categories, revenue, known)
          }, alive)
        })
      })
    })
  }

  function businessTagObject() {
    var name = businessTag.toLowerCase()
    return root.tags.filter(function(tag) { return String(tag.name).toLowerCase() === name })[0] || null
  }

  function revenueResult(fresh, months, currency, truncated, start, known) {
    var slim = fresh.map(Model.slimTransaction)
    var all = start ? Model.mergeTransactions(known.transactions, slim, start) : slim
    var result = Model.aggregateTagged(all, months, currency)
    result.transactions = all
    result.truncated = truncated || (!!start && known.truncated === true)
    result.recent = fresh.slice(0, 6).map(recentRow)
    result.start = start
    return result
  }

  // Sure lists newest first, so hitting the page cap loses the oldest history; that is reported.
  function loadRevenue(months, currency, page, collected, start, known, done, alive) {
    var tag = trackAllIncome ? null : businessTagObject()
    if (!tag && !trackAllIncome) { done(revenueResult([], months, currency, false, "", null), null); return }
    var filter = (tag ? "tag_ids%5B%5D=" + encodeURIComponent(tag.id) + "&" : "") + (start ? "start_date=" + start + "&" : "")
    api("GET", "/transactions?" + filter + "per_page=100&page=" + page, null, function(ok, data, status, retryAfter) {
      if (!alive()) return
      if (!ok) { done(null, failureOf(status, data, retryAfter)); return }
      var all = collected.concat(data.transactions || [])
      var pages = data.pagination ? data.pagination.total_pages : 1
      if (page < pages && page < root.maxPages) loadRevenue(months, currency, page + 1, all, start, known, done, alive)
      else done(revenueResult(all, months, currency, page < pages, start, known), null)
    })
  }

  function recentRow(item) {
    return {id: item.id, date: item.date, name: String(item.name || "").slice(0, 80), amount: Model.fromMinor(item.signed_amount_cents, item.currency),
      currency: item.currency, category: item.category ? String(item.category.name).slice(0, 40) : "", accountId: item.account ? item.account.id : ""}
  }

  function compose(base, detail, months, lines, categories, revenue, known) {
    var code = base.cash.currency
    var series = months.map(function(month) {
      var flow = month === base.cash.month ? base.cash : detail[month] || known.months[month]
      return {month: month, income: Model.num(flow.income), spending: Model.num(flow.spending)}
    })
    var asOf = Model.latestDay(base.cash.as_of, new Date())
    var previousGame = payload && payload.status === "ok" ? payload.game : null
    gameSource = {transactions: revenue.transactions, asOf: asOf, currency: code}
    var currentGame = Model.game(revenue.transactions, asOf, code, plan)
    var budget = null, source = detail.budget
    if (source && source.budgeted_spending_cents > 0) {
      var days = new Date(asOf.getFullYear(), asOf.getMonth() + 1, 0).getDate()
      var spent = Model.fromMinor(source.actual_spending_cents, code), total = Model.fromMinor(source.budgeted_spending_cents, code)
      budget = {spent: spent, total: total, pace: Model.pace(spent, total, asOf.getDate(), days)}
    }
    var warnings = []
    checkTimezone(base.cash.time_zone)
    if (revenue.truncated) warnings.push({key: "warn.truncated", arg: String(root.maxPages * 100)})
    busy = false
    errorKey = ""
    retryAttempt = 0
    blockedUntil = 0
    retryTimer.stop()
    updatedAt = new Date()
    now = updatedAt
    payload = {
      status: "ok", reason: "", currency: code, series: series, warnings: warnings,
      business: {series: revenue.series, skipped: revenue.skipped, recent: previousRecent(revenue)}, game: currentGame,
      netWorth: Model.num(base.sheet.net_worth.amount), budget: budget,
      categories: lines.map(function(line) {
        var item = categories[line.id] || line
        return {name: String(line.category ? line.category.name : "").slice(0, 60), total: Model.fromMinor(line.budgeted_spending_cents, code),
          spent: Model.fromMinor(item.actual_spending_cents, code)}
      }),
      recent: (base.recent.transactions || []).map(recentRow)
    }
    var closed = {}
    series.slice(0, -1).forEach(function(point) { closed[point.month] = {income: point.income, spending: point.spending} })
    cache = {key: cacheId, day: known ? known.day : Model.iso(new Date()), months: closed, transactions: revenue.transactions, truncated: revenue.truncated}
    saveSnapshot(asOf)
    announce(previousGame, currentGame)
  }

  function previousRecent(revenue) {
    var before = payload && payload.status === "ok" ? payload.business.recent : []
    return revenue.start ? Model.mergeRecent(revenue.recent, before, revenue.start, 6) : revenue.recent
  }

  function notify(title, body) {
    lastNotice = title + " | " + body
    if (!silent) Quickshell.execDetached(["notify-send", "-a", "Sure", title, body])
  }
  // Waits for the notification, so a second entry replaces the earlier undo offer.
  function notifyEntry(title, body) {
    lastNotice = title + " | " + body
    if (!silent) entryNotice.exec(["notify-send", "-a", "Sure", "-t", "8000", "-A", "undo=" + t("action.undo"), title, body])
  }
  function flushNotice() {
    if (pendingNotice) notifyEntry(t("notice.saved"), pendingNotice)
    pendingNotice = ""
  }

  function goalNotice(before, after) {
    var was = before ? before.goal : null, goal = after.goal
    if (!was || !goal || was.target !== goal.target || before.monthKey !== after.monthKey) return ""
    if (goal.reached && !was.reached) return t("notice.goal").arg(money(goal.target))
    return goal.passed > was.passed ? t("notice.stage").arg(money(goal.stages[goal.passed - 1])) : ""
  }

  // Quick entries get the race result; imports and other writes only announce real events.
  function announce(before, after) {
    var fresh = Model.freshAchievements(before, after)
    var record = !!before && after.isRecord && !before.isRecord
    var title = goalNotice(before, after) || (fresh.length ? t("notice.milestone").arg(winTitle(fresh[fresh.length - 1])) : record ? t("notice.record") : "")
    if (pendingNotice) notifyEntry(title || t("notice.saved"), pendingNotice + " · " + raceText(after))
    else if (title) notify(title, raceText(after))
    pendingNotice = ""
  }

  function ensureTags(names, index, ids, done) {
    if (index >= names.length) { done(ids); return }
    var lower = names[index].toLowerCase()
    var known = tags.filter(function(tag) { return String(tag.name).toLowerCase() === lower })[0]
    if (known) { ensureTags(names, index + 1, ids.concat([known.id]), done); return }
    api("POST", "/tags", {tag: {name: names[index]}}, function(ok, data, status) {
      if (!ok || !data || !data.id) { done(null, status); return }
      root.tags = root.tags.concat([data])
      ensureTags(names, index + 1, ids.concat([data.id]), done)
    })
  }

  function writeError(data, status) {
    if (status === 403) return t("error.read-only")
    if (data && data.message) return String(data.message).slice(0, 160)
    return t(errorFor(status, data !== null && data !== undefined)).replace("%1", String(status))
  }

  function addEntry(text, done) {
    if (saving) return
    var entry = Model.parseEntry(text, new Date(), businessTag)
    if (!entry.ok) { done(false, t("entry." + entry.error).replace("%1", entry.amount || "")); return }
    if (!payload || payload.status === "demo") { done(false, t("entry.demo")); return }
    if (readOnly) { done(false, t("entry.read-only")); return }
    var account = previewAccount(entry.account)
    if (!account) { done(false, t("entry.account-missing").replace("%1", entry.account)); return }
    saving = true
    // Pressing Enter again after a lost reply repeats this id, so Sure can't save it twice.
    if (!entryAttempt || entryAttempt.text !== text) entryAttempt = {text: text, id: Model.externalId(Date.now(), Math.random())}
    var externalId = entryAttempt.id
    api("GET", "/transactions?search=" + encodeURIComponent(entry.name) + "&per_page=25", null, function(ok, found) {
      var lower = entry.name.toLowerCase()
      var match = ok && found ? (found.transactions || []).filter(function(t) { return String(t.name).toLowerCase() === lower && t.category })[0] : null
      ensureTags(entry.tags, 0, [], function(tagIds, tagStatus) {
        if (tagIds === null) { saving = false; done(false, tagStatus === 403 ? t("error.read-only") : t("entry.tag-failed")); return }
        var transaction = {account_id: account.id, name: entry.name, date: entry.date, amount: entry.amount,
          nature: entry.nature, currency: account.currency, tag_ids: tagIds, external_id: externalId, source: "sure-bar"}
        if (match) transaction.category_id = match.category.id
        api("POST", "/transactions", {transaction: transaction}, function(saved, data, status) {
          saving = false
          if (!saved || !data || !data.id) { done(false, writeError(data, status)); return }
          entryAttempt = null
          lastAdded = {id: data.id, name: entry.name, amount: entry.amount, nature: entry.nature, date: entry.date}
          var summary = (entry.nature === "income" ? "+" : "−") + plainMoney(entry.amount, account.currency) + " · " + entry.name
          var lowerBusiness = businessTag.toLowerCase()
          var revenue = entry.nature === "income" && (trackAllIncome || entry.tags.some(function(tag) { return tag.toLowerCase() === lowerBusiness }))
          if (revenue) pendingNotice = summary
          else notifyEntry(t("notice.saved"), summary)
          refreshAfterWrite(entry.date)
          done(true, summary)
        })
      })
    })
  }

  function undoLast(done) {
    if (saving || !lastAdded) return
    saving = true
    var name = lastAdded.name, date = lastAdded.date
    api("DELETE", "/transactions/" + encodeURIComponent(lastAdded.id), null, function(ok, data, status) {
      saving = false
      if (ok) { lastAdded = null; notify(t("notice.removed"), name); refreshAfterWrite(date) }
      else setError(status, data !== null && data !== undefined)
      if (done) done(ok)
    })
  }

  // A write into a closed month makes the cached months wrong.
  function refreshAfterWrite(date) {
    refresh(!!game && String(date).slice(0, 7) !== game.monthKey)
    settle.restart()
  }

  // Verifies the server and key before storing anything, so a typo never replaces a working setup.
  function connect(rawUrl, rawKey) {
    if (connecting) return
    setupError = ""
    var target = Model.origin(Model.normalizeServer(rawUrl), settings.allowInsecureHttp === true)
    if (!target.ok) { setupError = "setup." + target.error; return }
    var typed = String(rawKey || "").trim(), key = typed || (target.url === baseUrl ? apiKey : "")
    if (!/^[\x21-\x7e]{8,512}$/.test(key)) { setupError = "setup.bad-key"; return }
    connecting = true
    timedOut = false
    var failed = function(status, data) {
      var problem = status === 401 && data ? "setup.rejected" : errorFor(status, data !== null && data !== undefined)
      errorArg = String(status)
      if (status === 0 && !timedOut) {
        runProbe(target.url, function(probed) { root.setupError = probed; root.connecting = false })
        return
      }
      setupError = status === 0 ? "error.timeout" : problem
      connecting = false
    }
    api("GET", "/usage", null, function(ok, usage, status) {
      if (!ok) { failed(status, usage); return }
      api("GET", "/cash_flow", null, function(ok2, flow, status2) {
        if (!ok2) { failed(status2, flow); return }
        saveConnection(target.url, typed, usage && usage.api_key ? usage.api_key.scopes : null)
      }, key, target.url)
    }, key, target.url)
  }

  function saveConnection(url, typedKey, scopes) {
    var storeKey = function() {
      if (url !== root.baseUrl) root.forgetServer()
      root.cache = null
      root.keyScopes = scopes
      if (root.overrides) root.overrides = Object.assign({}, root.overrides, {baseUrl: url})
      if (typedKey) keyWriter.save(typedKey + "\n")
      else { root.connecting = false; root.connected(); root.refresh(true) }
    }
    if (url === baseUrl || overrides) { storeKey(); return }
    serverWriter.finish = function(ok) {
      if (ok) storeKey()
      else { root.setupError = "setup.url-save-failed"; root.connecting = false }
    }
    serverWriter.exec(["omarchy", "bar", "set", pluginId, "baseUrl", url])
  }

  // Goals are local, so changing one redraws at once and needs no trip to Sure.
  function rebuildGame() {
    if (!payload) return
    if (payload.status === "demo") {
      var key = errorKey, arg = errorArg
      showDemo(payload.reason)
      errorKey = key
      errorArg = arg
    } else if (gameSource) {
      var next = Object.assign({}, payload)
      next.game = Model.game(gameSource.transactions, gameSource.asOf, gameSource.currency, plan)
      payload = next
    }
  }
  function savePlan(next) {
    plan = next
    planWriter.save(JSON.stringify(next))
    rebuildGame()
  }
  function runCommand(command) {
    if (!game) return
    if (command.kind === "goal") savePlan(Model.setGoal(plan, game.monthKey, command.off ? null : command.amount, currency))
    else if (command.off) savePlan(Model.clearAction(plan, game.week))
    else savePlan(Model.setAction(plan, game.week, command.target, command.text))
  }
  function bumpAction(delta) {
    if (game && game.action && !game.action.demo) savePlan(Model.bumpAction(plan, game.week, delta))
  }
  function dismissNote(id) {
    var next = Model.clone(plan)
    next.dismissed = next.dismissed.concat([id])
    savePlan(next)
  }
  function dismissReview() {
    if (!game || !game.review) return
    var next = Model.clone(plan)
    next.reviewed = game.review.key
    savePlan(next)
  }

  function toggleAmounts() {
    amountsHidden = !amountsHidden
    prefsWriter.exec(["sh", "-c", 'umask 077; mkdir -p "$1" && printf %s "$3" > "$2"', "sh", configDir, configDir + "/hide-amounts", amountsHidden ? "1" : "0"])
  }

  function openWeb(path) { if (baseUrl) Quickshell.execDetached(["omarchy-launch-webapp", baseUrl + path]) }
  function openSure() {
    if (!baseUrl) return
    var host = baseUrl.replace(/^https?:\/\//, "").replace(/:\d+$/, "")
    Quickshell.execDetached(["omarchy-launch-or-focus-webapp", "chrome-" + host + "__-Default", baseUrl])
  }
  function openImport() { openWeb("/imports") }
  function openApiKeys(rawUrl) {
    var target = Model.origin(Model.normalizeServer(rawUrl), settings.allowInsecureHttp === true)
    if (target.ok) Quickshell.execDetached(["omarchy-launch-webapp", target.url + "/settings/api_keys"])
  }
}
