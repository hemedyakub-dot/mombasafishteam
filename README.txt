MOMBASAFISH — UPLOAD THESE 6 FILES TO GITHUB (mombasafish-lab)
Netlify auto-deploys on push. All go in the repo root, same as before.

FILES:
  index.html       — customer tracker (3-stage honest basket, view-only)  + fixes Josh's broken link
  staff.html       — dispatch app (item taps work, dispatch locks until all packed)
  refund.html      — refund policy + claim form
  counter.html     — NEW: walk-in shop POS (3-tap sale, weight keypad, void, cash-up, offline queue)
  shop-admin.html  — NEW: shop control panel (products, prices, stock intake, sales history)
  netlify.toml     — cache settings

LIVE URLS AFTER UPLOAD:
  Tracker :  mombasafishteam.netlify.app/
  Staff   :  mombasafishteam.netlify.app/staff.html
  Refund  :  mombasafishteam.netlify.app/refund.html
  Counter :  mombasafishteam.netlify.app/counter.html
  Admin   :  mombasafishteam.netlify.app/shop-admin.html

LOGIN: existing staff accounts (same as dispatch) work everywhere.

FIRST-DAY CHECKLIST:
  1. Upload all 6 files
  2. Open each URL once, confirm it loads
  3. Admin: tap + on each fish, enter today's chiller stock
  4. Do ONE test counter sale -> void it -> run a cash-up (see the full loop)
  5. Open a tracking link, tick a fish through the 3 stages on staff app
  6. Hand counter to shop staff; watch the first hour
