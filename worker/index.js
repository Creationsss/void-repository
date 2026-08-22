const IMMUTABLE = /\.xbps(\.sig2)?$/;

function pkgName(key) {
	const m = key.match(/^(.+?)-[^-\s]+_\d+\.[^.]+\.xbps(\.sig2)?$/);
	return m ? m[1] : "";
}

function category(key) {
	if (key.endsWith(".xbps")) return "pkg";
	if (key.endsWith(".xbps.sig2")) return "sig";
	if (key.endsWith("-repodata")) return "sync";
	return "other";
}

function record(env, key, request) {
	env.ANALYTICS.writeDataPoint({
		blobs: [key, pkgName(key), category(key), (request.cf && request.cf.country) || ""],
		indexes: [pkgName(key) || category(key)],
		doubles: [1],
	});
}

async function packageCounts(env) {
	if (!env.ANALYTICS_TOKEN || !env.CF_ACCOUNT_ID) return null;
	const sql =
		"SELECT blob2 AS p, SUM(_sample_interval) AS n FROM void_repo_hits " +
		"WHERE blob3='pkg' AND blob2!='' AND timestamp > now() - INTERVAL '90' DAY GROUP BY p";
	try {
		const r = await fetch(
			`https://api.cloudflare.com/client/v4/accounts/${env.CF_ACCOUNT_ID}/analytics_engine/sql`,
			{ method: "POST", headers: { Authorization: `Bearer ${env.ANALYTICS_TOKEN}` }, body: sql },
		);
		if (!r.ok) return null;
		const j = await r.json();
		const m = {};
		for (const row of j.data || []) m[row.p] = Math.floor(Number(row.n));
		return m;
	} catch (e) {
		return null;
	}
}

export default {
	async fetch(request, env, ctx) {
		if (request.method !== "GET" && request.method !== "HEAD") {
			return new Response("Method not allowed", { status: 405 });
		}

		const url = new URL(request.url);
		let key = decodeURIComponent(url.pathname).replace(/^\/+/, "");
		if (key === "" || key.endsWith("/")) key += "index.html";

		const wantStats =
			request.method === "GET" &&
			key === "index.html" &&
			url.searchParams.get("stats") === "true";

		if (wantStats) {
			const obj = await env.REPO.get("index.html");
			if (obj) {
				const counts = await packageCounts(env);
				const headers = new Headers();
				obj.writeHttpMetadata(headers);
				headers.set("cache-control", "public, max-age=300");
				if (env.ANALYTICS) record(env, "index.html", request);
				let resp = new Response(obj.body, { headers });
				if (counts) {
					resp = new HTMLRewriter()
						.on("span.dl", {
							element(el) {
								const p = el.getAttribute("data-pkg");
								if (!p) return;
								el.setInnerContent(`${counts[p] || 0} dl`);
							},
						})
						.transform(resp);
				}
				return resp;
			}
		}

		const rangeHeader = request.headers.get("range");
		let opts = {};
		if (rangeHeader) {
			const m = /bytes=(\d+)-(\d*)/.exec(rangeHeader);
			if (m) {
				const offset = Number(m[1]);
				opts = { range: m[2] ? { offset, length: Number(m[2]) - offset + 1 } : { offset } };
			}
		}

		let obj = await env.REPO.get(key, opts);
		if (!obj && rangeHeader) obj = await env.REPO.get(key);
		if (!obj) return new Response("Not found", { status: 404 });

		if (request.method === "GET" && env.ANALYTICS) {
			record(env, key, request);
		}

		const headers = new Headers();
		obj.writeHttpMetadata(headers);
		headers.set("etag", obj.httpEtag);
		headers.set("accept-ranges", "bytes");
		headers.set("cache-control", IMMUTABLE.test(key) ? "public, max-age=31536000, immutable" : "public, max-age=300");

		if (request.method === "HEAD") {
			headers.set("content-length", String(obj.size));
			return new Response(null, { headers });
		}

		if (obj.range) {
			const off = obj.range.offset || 0;
			const len = obj.range.length !== undefined ? obj.range.length : obj.size - off;
			headers.set("content-range", `bytes ${off}-${off + len - 1}/${obj.size}`);
			headers.set("content-length", String(len));
			return new Response(obj.body, { status: 206, headers });
		}

		return new Response(obj.body, { headers });
	},
};
