// Serves binary releases from yznts.cc, streaming them out of private
// GitHub release assets.
//
// The projects behind these downloads are closed source, so there is no
// repository to send anyone to. The worker keeps the distribution on this
// domain: it holds a read only token, resolves a release by tag, and pipes
// the asset back. Nothing about the origin reaches the browser.
//
// Route: /dl/<project>/<version>/<file>

const PROJECTS = {
  babel: { repo: 'yznts/babel', tagPrefix: 'v' },
};

const ROUTE = /^\/dl\/([a-z0-9-]+)\/([^/]+)\/([^/]+)$/i;

// Assets are immutable once a release is published, so they cache hard.
const CACHE_CONTROL = 'public, max-age=31536000, immutable';

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405 });
    }

    const url = new URL(request.url);
    const route = url.pathname.match(ROUTE);
    if (!route) return notFound();

    const [, name, version, file] = route;
    const project = PROJECTS[name];
    if (!project) return notFound();

    // A ranged request must not be answered from a full cached body,
    // so only plain requests use the cache.
    const ranged = request.headers.has('range');
    const cache = caches.default;
    if (!ranged) {
      const hit = await cache.match(request);
      if (hit) return hit;
    }

    // Resolve the release, then the asset inside it. Looking the file up
    // rather than trusting the path keeps the worker from being turned
    // into a general proxy for the repository.
    const release = await api(`/repos/${project.repo}/releases/tags/${project.tagPrefix}${version}`, env);
    if (!release.ok) return notFound();
    const asset = (await release.json()).assets.find(a => a.name === file);
    if (!asset) return notFound();

    const headers = {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: 'application/octet-stream',
      'User-Agent': 'yznts.cc',
    };
    if (ranged) headers.Range = request.headers.get('range');

    const upstream = await fetch(
      `https://api.github.com/repos/${project.repo}/releases/assets/${asset.id}`,
      { headers, redirect: 'follow' },
    );
    if (!upstream.ok && upstream.status !== 206) {
      return new Response('Download unavailable', { status: 502 });
    }

    const response = new Response(request.method === 'HEAD' ? null : upstream.body, {
      status: upstream.status,
      headers: {
        'Content-Type': asset.content_type || 'application/octet-stream',
        'Content-Disposition': `attachment; filename="${asset.name}"`,
        'Cache-Control': CACHE_CONTROL,
        'Accept-Ranges': 'bytes',
        ...(upstream.headers.get('content-length') ? { 'Content-Length': upstream.headers.get('content-length') } : {}),
        ...(upstream.headers.get('content-range') ? { 'Content-Range': upstream.headers.get('content-range') } : {}),
      },
    });

    if (!ranged && request.method === 'GET' && response.status === 200) {
      ctx.waitUntil(cache.put(request, response.clone()));
    }
    return response;
  },
};

function api(path, env) {
  return fetch(`https://api.github.com${path}`, {
    headers: {
      Authorization: `Bearer ${env.GITHUB_TOKEN}`,
      Accept: 'application/vnd.github+json',
      'User-Agent': 'yznts.cc',
    },
  });
}

function notFound() {
  return new Response('Not found', { status: 404, headers: { 'Cache-Control': 'no-store' } });
}
