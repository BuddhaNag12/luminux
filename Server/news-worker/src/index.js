// Luminux news proxy. Fetches top headlines from GNews, trims them to what the app shows, and caches them per
// country so one upstream call serves every reader. The app never sees the API key and GNews never sees readers.

const CACHE_SECONDS = 15 * 60;
// English editions GNews supports; other countries get the default edition.
const ENGLISH_EDITIONS = new Set(["au", "ca", "gb", "ie", "in", "pk", "ph", "sg", "us"]);

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET") {
      return new Response("Method not allowed", { status: 405 });
    }
    if (env.NEWS_ENABLED !== "true") {
      return json({ enabled: false, articles: [] }, 300);
    }

    const country = edition(request, env);
    const cacheKey = new Request(`https://luminux-news.cache/${country}`);
    const cache = caches.default;
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const upstream = new URL("https://gnews.io/api/v4/top-headlines");
    upstream.searchParams.set("category", "general");
    upstream.searchParams.set("lang", "en");
    upstream.searchParams.set("country", country);
    upstream.searchParams.set("max", env.MAX_ARTICLES ?? "20");
    upstream.searchParams.set("apikey", env.GNEWS_API_KEY);

    const reply = await fetch(upstream);
    if (!reply.ok) {
      // A short-lived error, so the app keeps its last headlines and retries later.
      return new Response("Upstream error", { status: 502 });
    }
    const data = await reply.json();
    const articles = (data.articles ?? []).map((article) => ({
      title: article.title,
      source: article.source?.name ?? "",
      url: article.url,
      image: article.image ?? undefined,
      publishedAt: article.publishedAt ?? undefined,
    }));

    const response = json({ enabled: true, attribution: "Headlines from GNews", articles }, CACHE_SECONDS);
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};

// Cloudflare already knows the reader's country from the connection; nothing is stored.
function edition(request, env) {
  const country = (request.cf?.country ?? "").toLowerCase();
  return ENGLISH_EDITIONS.has(country) ? country : (env.DEFAULT_COUNTRY ?? "us");
}

function json(body, maxAge) {
  return new Response(JSON.stringify(body), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": `public, max-age=${maxAge}`,
    },
  });
}
