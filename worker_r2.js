// ═══════════════════════════════════════════════════════════════════════
// WORKER CLOUDFLARE R2 — PagneShop
// Compatible avec StockageService._uploadBytesCloudflare (l'app Flutter).
// À coller tel quel dans un Worker, avec un binding R2 nommé "BUCKET".
// ═══════════════════════════════════════════════════════════════════════
export default {
  async fetch(request, env) {
    // Auth : le même token que _R2Config.authToken dans l'app
    const auth = request.headers.get('Authorization') || '';
    if (auth !== `Bearer ${env.AUTH_TOKEN}`) {
      return new Response('Non autorisé', { status: 401 });
    }
    const url = new URL(request.url);

    // ── UPLOAD : POST /upload?file=<chemin> (corps = octets de l'image)
    if (request.method === 'POST' && url.pathname === '/upload') {
      const chemin = url.searchParams.get('file') ||
                     request.headers.get('X-Filename');
      if (!chemin) return new Response('chemin manquant', { status: 400 });
      const contentType =
        request.headers.get('Content-Type') || 'application/octet-stream';
      await env.BUCKET.put(chemin, request.body, {
        httpMetadata: {
          contentType,
          // CDN : l'image est immuable → cache 1 an au edge Cloudflare
          // (affichages instantanés, moins d'opérations R2 facturées)
          cacheControl: 'public, max-age=31536000, immutable',
        },
      });
      return Response.json({ url: chemin });
    }

    // ── DELETE : DELETE /delete?file=<chemin>
    if (request.method === 'DELETE' && url.pathname === '/delete') {
      const chemin = url.searchParams.get('file');
      if (!chemin) return new Response('chemin manquant', { status: 400 });
      await env.BUCKET.delete(chemin);
      return Response.json({ ok: true });
    }

    return new Response('PagneShop R2 Worker', { status: 200 });
  },
};
