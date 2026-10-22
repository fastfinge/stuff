// Replies, likes and reposts of a post's Bluesky announcement, read in the
// reader's browser from Bluesky's public AppView -- the same model as
// fediverse-comments.js, written here rather than taken from a package so the
// markup is something a screen reader can navigate: one article per reply,
// nested under the one it answers, with counts in words and line breaks kept.
//
// Each container names the post by its bsky.app URL, as announce.ps1 writes it
// into the Bluesky: front matter key:
//
//   <div data-bsky-replies="https://bsky.app/profile/HANDLE/post/RKEY"></div>
//   <div data-bsky-likes="..."></div>
//   <div data-bsky-reposts="..."></div>
"use strict";
(() => {
  const api = "https://public.api.bsky.app/xrpc";

  const getJson = async (method, params) => {
    const response = await fetch(`${api}/${method}?${new URLSearchParams(params)}`);
    if (!response.ok) throw new Error(`${method}: HTTP ${response.status}`);
    return response.json();
  };

  // bsky.app URL -> AT-URI. One lookup per URL, however many containers use it.
  const uris = new Map();
  const resolve = (url) => {
    if (!uris.has(url)) {
      uris.set(url, (async () => {
        const match = /^https:\/\/bsky\.app\/profile\/([^/]+)\/post\/([^/?#]+)/.exec(url);
        if (!match) throw new Error(`Not a Bluesky post URL: ${url}`);
        let [, actor, rkey] = match;
        if (!actor.startsWith("did:")) {
          actor = (await getJson("com.atproto.identity.resolveHandle", { handle: actor })).did;
        }
        return `at://${actor}/app.bsky.feed.post/${rkey}`;
      })());
    }
    return uris.get(url);
  };

  const el = (tag, attributes = {}, ...children) => {
    const node = document.createElement(tag);
    for (const [name, value] of Object.entries(attributes)) {
      if (name === "class") node.className = value;
      else node.setAttribute(name, value);
    }
    node.append(...children.filter((child) => child != null));
    return node;
  };

  const profileUrl = (actor) => `https://bsky.app/profile/${encodeURIComponent(actor.handle)}`;
  const postUrl = (post) =>
    `${profileUrl(post.author)}/post/${encodeURIComponent(post.uri.split("/").pop())}`;

  // Avatar inside the name link, with empty alt: the name already says who it
  // is, and a separate avatar link would read the same person twice.
  const accountLink = (actor) =>
    el(
      "a",
      { href: profileUrl(actor), rel: "external nofollow", class: "bsky-account" },
      actor.avatar ? el("img", { src: actor.avatar, alt: "", class: "bsky-avatar", loading: "lazy" }) : null,
      el("span", { class: "bsky-display-name" }, actor.displayName || actor.handle)
    );

  const plural = (count, one, many) => `${count} ${count === 1 ? one : many}`;

  // Post text with its facets (links, mentions, hashtags) as links. Facet
  // offsets count UTF-8 bytes, so slice the encoded text. Returns runs of
  // { text, href } and "\n" tokens.
  const tokens = (record) => {
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const bytes = encoder.encode(record.text || "");
    const runs = [];
    let at = 0;
    const plain = (end) => {
      if (end > at) runs.push({ text: decoder.decode(bytes.slice(at, end)) });
    };
    const facets = [...(record.facets || [])].sort((a, b) => a.index.byteStart - b.index.byteStart);
    for (const facet of facets) {
      const { byteStart, byteEnd } = facet.index;
      if (byteStart < at || byteEnd > bytes.length) continue;
      const feature = (facet.features || [])[0] || {};
      let href = null;
      if (feature.$type === "app.bsky.richtext.facet#link") href = feature.uri;
      else if (feature.$type === "app.bsky.richtext.facet#mention") href = `https://bsky.app/profile/${feature.did}`;
      else if (feature.$type === "app.bsky.richtext.facet#tag") href = `https://bsky.app/hashtag/${encodeURIComponent(feature.tag)}`;
      if (!href || !/^https?:/i.test(href)) continue;
      plain(byteStart);
      runs.push({ text: decoder.decode(bytes.slice(byteStart, byteEnd)), href });
      at = byteEnd;
    }
    plain(bytes.length);

    return runs.flatMap((run) =>
      run.text.split("\n").flatMap((piece, i) => [...(i > 0 ? ["\n"] : []), ...(piece ? [{ ...run, text: piece }] : [])])
    );
  };

  // A blank line starts a new paragraph; a single line break is a <br>.
  const body = (record) => {
    const container = el("div", { class: "bsky-comment-content" });
    let paragraph = null;
    let newlines = 0;
    for (const token of tokens(record)) {
      if (token === "\n") {
        newlines++;
        continue;
      }
      if (!paragraph || newlines >= 2) {
        paragraph = el("p");
        container.append(paragraph);
      } else if (newlines === 1) {
        paragraph.append(el("br"));
      }
      newlines = 0;
      paragraph.append(token.href ? el("a", { href: token.href, rel: "external nofollow" }, token.text) : token.text);
    }
    return container;
  };

  const byDate = (a, b) => new Date(a.post.indexedAt) - new Date(b.post.indexedAt);

  // The thread can hold placeholders for deleted or blocked replies; those have
  // no post and are left out.
  const visible = (replies) => (replies || []).filter((reply) => reply.post && reply.post.author).sort(byDate);

  const comment = (thread) => {
    const { post } = thread;
    const counts = [
      post.likeCount > 0 ? plural(post.likeCount, "like", "likes") : null,
      post.repostCount > 0 ? plural(post.repostCount, "repost", "reposts") : null,
    ].filter(Boolean);
    const date = new Date(post.record.createdAt || post.indexedAt);
    const replies = visible(thread.replies);

    return el(
      "article",
      { class: "bsky-comment", id: `bsky-${post.uri.split("/").pop()}` },
      el(
        "header",
        { class: "bsky-comment-header" },
        accountLink(post.author),
        " ",
        el("span", { class: "bsky-handle" }, `@${post.author.handle}`)
      ),
      body(post.record),
      el(
        "footer",
        { class: "bsky-comment-footer" },
        el(
          "a",
          { href: postUrl(post), rel: "external nofollow" },
          el("time", { datetime: date.toISOString() }, date.toLocaleString(undefined, { dateStyle: "long", timeStyle: "short" }))
        ),
        counts.length ? `, ${counts.join(", ")}` : null
      ),
      replies.length ? el("div", { class: "bsky-replies" }, ...replies.map(comment)) : null
    );
  };

  const showReplies = async (container) => {
    const uri = await resolve(container.dataset.bskyReplies);
    const { thread } = await getJson("app.bsky.feed.getPostThread", { uri, depth: 10, parentHeight: 0 });
    const replies = visible(thread && thread.replies);
    container.append(...(replies.length ? replies.map(comment) : [el("p", {}, "No replies yet.")]));
  };

  // getLikes wraps each account as { actor }; getRepostedBy lists them bare.
  const showAccounts = async (container, url, method, key, none) => {
    const uri = await resolve(url);
    const accounts = ((await getJson(method, { uri, limit: 100 }))[key] || []).map((item) => item.actor || item);
    container.append(
      accounts.length
        ? el("ul", { class: "bsky-accounts" }, ...accounts.map((actor) => el("li", {}, accountLink(actor))))
        : el("p", {}, none)
    );
  };

  // A failure says so in place, rather than leaving an empty section under its
  // heading.
  const run = (container, what, show) =>
    show().catch((error) => {
      console.warn("bsky-comments:", error);
      container.append(el("p", {}, `Could not load ${what} from Bluesky.`));
    });

  document.addEventListener("DOMContentLoaded", () => {
    for (const c of document.querySelectorAll("[data-bsky-replies]")) {
      run(c, "replies", () => showReplies(c));
    }
    for (const c of document.querySelectorAll("[data-bsky-likes]")) {
      run(c, "likes", () => showAccounts(c, c.dataset.bskyLikes, "app.bsky.feed.getLikes", "likes", "No likes yet."));
    }
    for (const c of document.querySelectorAll("[data-bsky-reposts]")) {
      run(c, "reposts", () =>
        showAccounts(c, c.dataset.bskyReposts, "app.bsky.feed.getRepostedBy", "repostedBy", "No reposts yet."));
    }
  });
})();
