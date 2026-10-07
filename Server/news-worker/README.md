# Luminux news proxy

A Cloudflare Worker that serves the hub's news panel. It keeps the GNews key off the phone, caches headlines for
15 minutes per country (so one GNews call serves every reader), and stores nothing about who asked.

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

## Deploy

1. Buy a GNews plan that allows commercial use (gnews.io).
2. `npm install -g wrangler` (or use `npx wrangler`), then `wrangler login`.
3. `cd Server/news-worker && npx wrangler secret put GNEWS_API_KEY`
4. `npx wrangler deploy`; it prints the URL, e.g. `https://luminux-news.<account>.workers.dev`.
5. Put that URL in `LuminuxNewsURL` in `project.yml`, run `xcodegen generate` and rebuild.

Readers get their own country's English edition when GNews has one (Cloudflare supplies the country from the
connection); everyone else gets `DEFAULT_COUNTRY`.
