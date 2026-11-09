# Sure Bar

Your revenue, cash flow and quick expense entry in the [Omarchy](https://omarchy.org) bar, backed by your own self-hosted [Sure](https://github.com/we-promise/sure).

![Sure Bar panel with demo data](preview.png)

This is an unofficial plugin and is not affiliated with the Sure project.

## What you get

- **In the bar:** this month's revenue and how far along your goal you are, for example `2.3k 33%`. Without a goal it shows whether you are ahead of last month, for example `40k ▲`. It turns red only for a real problem: a budget that is overspent, or under three months of runway.
- **Goal:** a monthly revenue goal you choose, broken into round stages, with profit right beside it.
- **Action of the week:** one thing you control, with a counter.
- **Growth:** the comparison with last month and your best month, a ladder of lifetime milestones, your runway, and a review of last month against its goal.
- **Money:** net cash flow, six months of income and spending, budgets paced against the calendar, and recent transactions, for everything or just the business.
- **One-line entry:** type, check the preview, press Enter. Undo from the notification.

## Requirements

- Omarchy with the shell plugin system
- A recent Sure release, reachable from this machine (tested with the `stable` image)
- A Sure API key with read and write access. A read-only key works for viewing, but entries can't be saved.

## Install

```bash
omarchy plugin add https://github.com/andreiyurik/omarchy-sure-bar --enable
```

Click the widget and follow the connect screen. It opens Sure's API keys page, checks the key you paste, and saves it. Until an account exists in Sure, the panel shows demo numbers.

If Sure is not at `http://localhost:3000`, set **Sure URL** in the widget settings first.

## Adding entries

| You type | What is saved |
| --- | --- |
| `450 coffee` | Expense of 450 |
| `+1200 client #b` | Income of 1200, tagged as business |
| `1.5k lunch` | Expense of 1500 |
| `4900 server #b @cash yesterday` | Expense on the account matching "cash", dated yesterday |

`#b` is short for your business tag. Any other `#word` is saved as that tag, and missing tags are created. An entry with a name you have used before reuses that category. Russian also works: `1.5к обед #б @нал вчера`.

In the panel, Tab switches between Growth and Money, and Esc closes it.

## Goals

The same line sets your goals, and the buttons on the Growth view fill it in for you.

| You type | What it does |
| --- | --- |
| `goal 7000` | Revenue goal of 7000 a month, from this month on |
| `week 10 client offers` | This week's action: 10 client offers |
| `goal off`, `week off` | Removes it |

Russian works too: `цель 7000`, `неделя 10 предложений клиентам`.

With the entry line empty, ↑ and ↓ change the weekly count. The action carries over to the next week with a clean count. On the 1st, the race starts again and last month's result waits in a short review until you dismiss it.

A goal is in your Sure default currency, because the plugin doesn't convert. Changing a goal applies from the current month, so past reviews keep the goal they had.

### Why it works this way

The design draws on published research. None of these studies tested a finance widget, and many were run in health, education or lab settings, so treat this as informed design, not proof that it raises income.

| Choice | Research |
| --- | --- |
| One specific, hard goal | [Locke & Latham, 2002](https://doi.org/10.1037/0003-066X.57.9.705) |
| Stages, so the middle of the month doesn't sag | [Kivetz et al., 2006](https://doi.org/10.1509/jmkr.43.1.39); [Bonezzi et al., 2011](https://doi.org/10.1177/0956797611404899) |
| Percent done early, amount left after halfway | [Koo & Fishbach, 2012](https://doi.org/10.1086/663827) |
| An action you control, because revenue isn't only up to you | [Seijts & Latham, 2005](https://doi.org/10.5465/ame.2005.15841964) |
| Progress written down and visible | [Harkin et al., 2016](https://doi.org/10.1037/bul0000025) |
| A clean start each month | [Dai et al., 2014](https://doi.org/10.1287/mnsc.2014.1901) |
| No points or loot; profit next to revenue; no ceiling at 100% | [Deci et al., 1999](https://doi.org/10.1037/0033-2909.125.6.627); [Ordóñez et al., 2009](https://doi.org/10.5465/amp.2009.37007999) |
| No revenue streaks | [Silverman & Barasch, 2023](https://doi.org/10.1093/jcr/ucac029) |

## Optional hotkey

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + M", "Sure finance panel", "omarchy-shell shell toggle andreiyurik.sure-bar")
```

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Sure URL | `http://localhost:3000` | Plain origin of your Sure instance |
| Allow plain HTTP to non-local hosts | off | See [Privacy and network](#privacy-and-network) |
| Refresh in the background | on | Turn off to fetch only when you press refresh or save an entry |
| Refresh interval | 10 minutes | 1 to 120 |
| Business tag | `business` | Transactions with this tag count as business |
| Count all income as revenue | off | Ignores the tag, for people who don't separate business money |
| Default account | empty | Part of an account name. Otherwise the last used account is chosen. |
| Show demo data | off | Fake numbers, handy for screenshots |

## How the numbers work

- Revenue is income on transactions with your business tag. The goal, milestones and the race are recalculated from your transactions every time, so there is no separate game state to lose.
- Transfers between your own accounts are ignored. A refund from a supplier looks like income in Sure, so tagging one as business counts it as revenue.
- Transactions in a currency other than your Sure default are left out of business numbers, and the panel says how many.
- At most the latest 3,000 matching transactions are read. If you have more, the panel warns that lifetime revenue and milestones may be low.
- The panel warns if Sure's date differs from your computer's, which means Sure's timezone is wrong and entries can land in the wrong month.

## Privacy and network

- The plugin talks only to the Sure URL you set. It has no analytics and no other network access.
- While background refresh is on, it makes requests to Sure at the interval you set.
- Your API key is stored in `~/.config/sure-bar/api-key`, readable only by you, and never leaves for anywhere but your Sure server.
- Plain HTTP is allowed only for `localhost` and `127.x.x.x` unless you turn on the setting, because it would send your key unencrypted.
- Your goals and weekly actions are stored only in `~/.config/sure-bar/plan.json`, readable only by you.
- The eye button hides amounts in the bar and the panel, for screen sharing. The choice is remembered in `~/.config/sure-bar/hide-amounts`.
- Removing the plugin leaves `~/.config/sure-bar` in place. Delete that folder to remove the key.

## Languages

English and Russian, following your Omarchy language. Translations live in `i18n/`. Anything missing falls back to English, and new language files are welcome.

## Development

```bash
node tests/model.test.js
node tests/project.test.js
```

## License

[MIT](LICENSE)
