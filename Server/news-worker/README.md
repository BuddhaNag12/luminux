# Luminux news proxy

A Cloudflare Worker that serves the hub's news panel. Every 20 minutes it fetches top headlines from GNews for each
English edition (au, ca, gb, ie, in, pk, ph, sg, us) into Workers KV, and readers are served from KV. GNews usage is
fixed at 648 requests a day however many people read, the key stays off the phone, GNews never sees readers, and
nothing is logged.

## Response

```json
{
  "enabled": true,
  "attribution": "Headlines from GNews",
  "articles": [
    { "title": "…", "source": "…", "url": "https://…", "image": "https://…", "publishedAt": "2026-10-08T09:30:00Z" }
  ]
}
```

`enabled: false` hides the panel in the app on its next refresh (set `NEWS_ENABLED = "false"` and deploy).

Readers get their country's English edition when GNews has one (Cloudflare supplies the country from the connection);
everyone else gets `DEFAULT_COUNTRY`.

## Deploy

1. A GNews plan that allows commercial use (gnews.io; the entry plan's 1,000 requests a day is enough) and a free
   Cloudflare account.
2. `cd Server/news-worker`, then `npx wrangler login` (opens Cloudflare in the browser).
3. `npx wrangler kv namespace create HEADLINES` and paste the printed id into `wrangler.toml`.
4. `npx wrangler secret put GNEWS_API_KEY` and paste the key when asked.
5. `npx wrangler deploy`. It prints the URL, e.g. `https://luminux-news.<account>.workers.dev`. Headlines appear after
   the first scheduled run (within 20 minutes), or straight away for the first reader of each edition.
6. Put that URL in `LuminuxNewsURL` in `project.yml`, run `xcodegen generate` and rebuild.
