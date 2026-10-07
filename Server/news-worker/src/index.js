// Luminux news proxy. A schedule fetches top headlines from GNews for each English edition into KV, and readers are
// served from KV, so GNews usage is fixed (editions × runs per day) however many people read. The app never sees the
// API key and GNews never sees readers.

// English editions GNews supports; other countries get the default edition.
const ENGLISH_EDITIONS = ["au", "ca", "gb", "ie", "in", "pk", "ph", "sg", "us"];
// Matches the app's own refresh interval.
const CLIENT_CACHE_SECONDS = 15 * 60;

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET") {
      return new Response("Method not allowed", { status: 405 });
    }
    if (env.NEWS_ENABLED !== "true") {
      return json({ enabled: false, articles: [] }, 300);
    }

    const country = edition(request, env);
    let stored = await env.HEADLINES.get(country, "json");
    if (!stored) {
      // Only before the first scheduled run has filled this edition.
      stored = await refreshEdition(country, env);
    }
    if (!stored) {
      return new Response("Upstream error", { status: 502 });
    }
    return json({ enabled: true, attribution: "Headlines from GNews", articles: stored.articles }, CLIENT_CACHE_SECONDS);
  },

  async scheduled(event, env, ctx) {
    for (const country of ENGLISH_EDITIONS) {
      await refreshEdition(country, env);
    }
  },
};

async function refreshEdition(country, env) {
  const upstream = new URL("https://gnews.io/api/v4/top-headlines");
  upstream.searchParams.set("category", "general");
  upstream.searchParams.set("lang", "en");
  upstream.searchParams.set("country", country);
  upstream.searchParams.set("max", env.MAX_ARTICLES ?? "20");
  upstream.searchParams.set("apikey", env.GNEWS_API_KEY);

  const reply = await fetch(upstream);
  if (!reply.ok) return null;
  const data = await reply.json();
  const stored = {
    fetchedAt: new Date().toISOString(),
    articles: (data.articles ?? []).map((article) => ({
      title: article.title,
      source: article.source?.name ?? "",
      url: article.url,
      image: article.image ?? undefined,
      publishedAt: article.publishedAt ?? undefined,
    })),
  };
  await env.HEADLINES.put(country, JSON.stringify(stored));
  return stored;
}

// Cloudflare already knows the reader's country from the connection; nothing is stored.
function edition(request, env) {
  const country = (request.cf?.country ?? "").toLowerCase();
  return ENGLISH_EDITIONS.includes(country) ? country : (env.DEFAULT_COUNTRY ?? "us");
}

function json(body, maxAge) {
  return new Response(JSON.stringify(body), {
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": `public, max-age=${maxAge}`,
    },
  });
}
