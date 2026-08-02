# Mombasafish iSeafood Hub — Order Tracker

Customer-facing order tracking page for Mombasafish.
**Live:** https://mombasafishteam.netlify.app

Quality · Delivery · Freshness · Traceable to the source

## How it works

A customer enters their **order number** and **tracking code** (both printed on
their receipt). Both must match for an order to display. They then see the
cold-chain stage their catch has reached — Imethibitishwa → Baharini →
Imefungwa → Njiani → Imefika.

## Structure

```
index.html          The whole page — markup, styles, order data, logic
img/                Hero photograph (webp + jpg fallback)
netlify.toml        Publish settings, cache and security headers
```

## Updating orders

Order data currently lives in the `ORDERS` array inside `index.html`.
Edit it, commit, push — Netlify redeploys automatically.

```js
{ord:"NRB-AUG 008", code:"MFM-5X3BW", name:"Mohammed", stage:1,
 dest:"South C, Nairobi", items:"Kibua 5kg", date:"2 Aug 2026"}
```

| stage | Meaning        |
|-------|----------------|
| 1     | Imethibitishwa |
| 2     | Baharini       |
| 3     | Imefungwa      |
| 4     | Njiani         |
| 5     | Imefika        |
| -1    | Imesitishwa (cancelled) |

## Never put in this repo

This is a **public** page — anything in `index.html` is readable by anyone
who views source.

- No customer phone numbers
- No street addresses
- No prices, costs, or profit figures
- No API tokens or keys (those go in Netlify → Environment variables)

## Deploying

Pushing to `main` triggers a deploy. No build step.

## Next step

Replace the hardcoded `ORDERS` array with a Netlify Function that reads the
Notion **Fish Orders** database, so orders update without editing this file.
