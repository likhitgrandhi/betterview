// CommentBridge.js — runs in an isolated WKContentWorld so page JS can't
// spoof messages to the host. Owns:
//   • comment-mode click capture
//   • pin overlay rendering (numbered badges + accent rings)
//   • selector / blockId / text-quote anchor resolution
// API exposed via `window.BV`. Host calls BV.setMode / setCommentMode / setPins
// via evaluateJavaScript(..., in: bvContentWorld).

(function () {
  if (window.BV) return;

  const OVERLAY_ID = 'bv-pin-overlay';
  let mode = 'browser'; // 'markdown' | 'browser'
  let commentMode = false;
  let pins = []; // [{ id, number, state, anchor }]

  function injectStyle() {
    if (document.getElementById('bv-style')) return;
    const s = document.createElement('style');
    s.id = 'bv-style';
    s.textContent = `
      body.bv-comment-mode, body.bv-comment-mode * { cursor: crosshair !important; }
      body.bv-comment-mode *:hover {
        outline: 1.5px solid #D97757 !important;
        outline-offset: 2px;
      }
      #${OVERLAY_ID} {
        position: fixed; inset: 0; pointer-events: none;
        z-index: 2147483646;
      }
    `;
    (document.head || document.documentElement).appendChild(s);
  }

  function ensureOverlay() {
    let el = document.getElementById(OVERLAY_ID);
    if (!el) {
      el = document.createElement('div');
      el.id = OVERLAY_ID;
      (document.body || document.documentElement).appendChild(el);
    }
    return el;
  }

  function buildSelector(el) {
    if (!el || el.nodeType !== 1) return null;
    if (el.id) return `#${CSS.escape(el.id)}`;
    const parts = [];
    let cur = el;
    while (cur && cur.nodeType === 1 && cur !== document.body) {
      const tag = cur.tagName.toLowerCase();
      const parent = cur.parentElement;
      if (!parent) break;
      const sibs = Array.from(parent.children).filter(c => c.tagName === cur.tagName);
      const idx = sibs.indexOf(cur) + 1;
      parts.unshift(`${tag}:nth-of-type(${idx})`);
      if (cur.id) { parts[0] = `#${CSS.escape(cur.id)}`; break; }
      cur = parent;
    }
    return parts.join(' > ') || el.tagName.toLowerCase();
  }

  // Walk up to the closest block-level ancestor we can address.
  function findBlockTarget(el) {
    let cur = el;
    while (cur && cur !== document.body) {
      if (cur.dataset && cur.dataset.bvId) return cur;
      cur = cur.parentElement;
    }
    return el;
  }

  function buildTextAnchor(el) {
    const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
    return {
      exact: text.slice(0, 120),
      prefix: '',
      suffix: '',
    };
  }

  function resolveAnchor(anchor) {
    if (anchor && anchor.blockId) {
      const el = document.querySelector(`[data-bv-id="${anchor.blockId}"]`);
      if (el) return el;
    }
    if (anchor && anchor.selector) {
      try {
        const el = document.querySelector(anchor.selector);
        if (el) return el;
      } catch (_) {}
    }
    if (anchor && anchor.exact) {
      const found = findByQuote(anchor.exact);
      if (found) return found;
    }
    return null;
  }

  // Best-effort text-quote resolution: scan for the first element whose
  // textContent starts with `exact`. Cheap and good enough for V1.
  function findByQuote(exact) {
    if (!exact) return null;
    const needle = exact.replace(/\s+/g, ' ').trim();
    if (!needle) return null;
    const blocks = document.querySelectorAll('p, h1, h2, h3, h4, h5, h6, li, blockquote, pre, [data-bv-id]');
    for (const el of blocks) {
      const t = (el.textContent || '').replace(/\s+/g, ' ').trim();
      if (t.startsWith(needle.slice(0, 80))) return el;
    }
    return null;
  }

  let pinScheduled = false;
  function schedulePinReposition() {
    if (pinScheduled) return;
    pinScheduled = true;
    requestAnimationFrame(() => {
      pinScheduled = false;
      repositionPins();
    });
  }

  function repositionPins() {
    const overlay = ensureOverlay();
    overlay.innerHTML = '';
    for (const pin of pins) {
      const el = resolveAnchor(pin.anchor);
      if (!el) continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      const color =
        pin.state === 'working'   ? '#D97757' :
        pin.state === 'cancelled' ? '#C0444A' :
        pin.state === 'orphaned'  ? '#D89A4C' :
        'rgba(217,119,87,0.7)'; // queued

      const ring = document.createElement('div');
      ring.style.cssText = `
        position:absolute;
        left:${r.left - 2}px; top:${r.top - 2}px;
        width:${r.width + 4}px; height:${r.height + 4}px;
        border:1px solid ${color}; border-radius:3px;
        background:${color}1A;
      `;
      overlay.appendChild(ring);

      const badge = document.createElement('div');
      badge.textContent = String(pin.number);
      badge.style.cssText = `
        position:absolute;
        left:${Math.max(2, r.right - 12)}px; top:${Math.max(2, r.top - 10)}px;
        width:20px; height:20px; border-radius:50%;
        background:${color}; color:white;
        font:500 11px -apple-system,'Inter Variable',sans-serif;
        display:flex; align-items:center; justify-content:center;
        box-shadow:0 1px 4px rgba(0,0,0,0.4);
      `;
      overlay.appendChild(badge);
    }
  }

  function onClick(e) {
    if (!commentMode) return;
    e.preventDefault();
    e.stopPropagation();
    const target = e.target;
    if (!target || target.id === OVERLAY_ID) return;

    let anchor, rectEl, snippetSrc;
    if (mode === 'markdown') {
      const blockEl = findBlockTarget(target);
      rectEl = blockEl;
      snippetSrc = blockEl;
      anchor = {
        kind: 'markdown',
        blockId: (blockEl.dataset && blockEl.dataset.bvId) || null,
        ...buildTextAnchor(blockEl),
      };
    } else {
      rectEl = target;
      snippetSrc = target;
      anchor = {
        kind: 'browser',
        selector: buildSelector(target),
        ...buildTextAnchor(target),
      };
    }
    const r = rectEl.getBoundingClientRect();
    const snippet = (snippetSrc.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 200);
    post({
      kind: 'click',
      anchor,
      snippet,
      rect: { x: r.left, y: r.top, w: r.width, h: r.height },
    });
  }

  function post(payload) {
    try {
      window.webkit.messageHandlers.bv.postMessage(payload);
    } catch (_) {}
  }

  document.addEventListener('click', onClick, true);
  window.addEventListener('scroll', schedulePinReposition, true);
  window.addEventListener('resize', schedulePinReposition);

  const mo = new MutationObserver(schedulePinReposition);
  // Lazy-attach observer once body exists.
  function attachObserver() {
    if (document.body) mo.observe(document.body, { childList: true, subtree: true, characterData: true });
    else requestAnimationFrame(attachObserver);
  }
  attachObserver();

  injectStyle();

  window.BV = {
    setMode(m) { mode = m === 'markdown' ? 'markdown' : 'browser'; },
    setCommentMode(on) {
      commentMode = !!on;
      if (document.body) {
        if (commentMode) document.body.classList.add('bv-comment-mode');
        else document.body.classList.remove('bv-comment-mode');
      }
    },
    setPins(p) {
      pins = Array.isArray(p) ? p : [];
      schedulePinReposition();
    },
    notifyClickDismissed() {
      // Future hook for the host to clear hover state after popover dismiss.
    },
  };
})();
