// ==UserScript==
// @name         YouTube -> NAS ytqueue
// @namespace    ytqueue
// @version      1.0
// @description  Queue YouTube URLs to NAS yt-dlp TXT queue endpoint
// @match        https://www.youtube.com/*
// @match        https://youtu.be/*
// @grant        GM_xmlhttpRequest
// @grant        GM_setValue
// @grant        GM_getValue
// @grant        GM_registerMenuCommand
// @connect      192.168.0.157
// ==/UserScript==

(function () {
  'use strict';

  const DEFAULT_ENDPOINT = 'http://192.168.0.157:9835';
  const KEY_ENDPOINT = 'ytqueue_endpoint';
  const KEY_TOKEN = 'ytqueue_token';

  function getEndpoint() {
    return GM_getValue(KEY_ENDPOINT, DEFAULT_ENDPOINT).replace(/\/+$/, '');
  }

  function getToken() {
    return GM_getValue(KEY_TOKEN, '');
  }

  function setEndpointInteractive() {
    const cur = getEndpoint();
    const next = prompt('Endpoint base URL (pl. http://192.168.0.157:9835):', cur);
    if (next && /^https?:\/\/[^ ]+$/.test(next.trim())) {
      GM_setValue(KEY_ENDPOINT, next.trim().replace(/\/+$/, ''));
      toast('Endpoint mentve.');
    } else if (next !== null) {
      toast('Érvénytelen endpoint.');
    }
  }

  function setTokenInteractive() {
    const cur = getToken();
    const next = prompt('Jelszó (X-Token), pl. 8 karakter:', cur);
    if (next && next.trim().length >= 4) {
      GM_setValue(KEY_TOKEN, next.trim());
      toast('Jelszó mentve.');
    } else if (next !== null) {
      toast('Érvénytelen jelszó.');
    }
  }

  GM_registerMenuCommand('ytqueue: Set endpoint', setEndpointInteractive);
  GM_registerMenuCommand('ytqueue: Set token', setTokenInteractive);

  function toast(msg) {
    const id = 'ytqueue_toast';
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      el.style.position = 'fixed';
      el.style.right = '16px';
      el.style.bottom = '16px';
      el.style.zIndex = '999999';
      el.style.padding = '10px 12px';
      el.style.borderRadius = '8px';
      el.style.background = 'rgba(0,0,0,0.85)';
      el.style.color = '#fff';
      el.style.fontSize = '13px';
      el.style.maxWidth = '320px';
      el.style.boxShadow = '0 6px 18px rgba(0,0,0,0.35)';
      document.documentElement.appendChild(el);
    }
    el.textContent = msg;
    el.style.opacity = '1';
    clearTimeout(el._t);
    el._t = setTimeout(() => { el.style.opacity = '0'; }, 2500);
  }

  function enqueueCurrentUrl() {
    const endpoint = getEndpoint();
    const token = getToken();

    if (!token) {
      toast('Token not set. Tampermonkey menu: "ytqueue: Set token"');
      return;
    }

    const url = location.href;

    GM_xmlhttpRequest({
      method: 'POST',
      url: endpoint + '/add',
      headers: {
        'Content-Type': 'application/json',
        'X-Token': token
      },
      data: JSON.stringify({ url }),
      timeout: 15000,
      onload: (resp) => {
        let data = null;
        try { data = JSON.parse(resp.responseText || '{}'); } catch (_) {}
        if (resp.status >= 200 && resp.status < 300 && data && data.ok) {
          const ql = typeof data.queue_len === 'number' ? data.queue_len : '?';
          toast('Queue OK. queue_len=' + ql);
        } else if (resp.status === 401) {
          toast('401 unauthorized. Wrong token (X-Token).');
        } else {
          const err = (data && (data.error || data.details)) ? (data.error + (data.details ? (': ' + data.details) : '')) : 'ismeretlen hiba';
          toast('Hiba: ' + resp.status + ' ' + err);
        }
      },
      ontimeout: () => toast('Timeout.'),
      onerror: () => toast('Network error.')
    });
  }

  function makeButton(id, text) {
    const btn = document.createElement('button');
    btn.id = id;
    btn.type = 'button';
    btn.textContent = text;
    btn.style.cursor = 'pointer';
    btn.style.padding = '8px 10px';
    btn.style.borderRadius = '18px';
    btn.style.border = '1px solid rgba(255,255,255,0.2)';
    btn.style.background = 'rgba(255,255,255,0.08)';
    btn.style.color = 'var(--yt-spec-text-primary, #fff)';
    btn.style.fontSize = '12px';
    btn.style.marginLeft = '8px';
    btn.addEventListener('click', enqueueCurrentUrl);
    return btn;
  }

  function ensureWatchPageButton() {
    const id = 'ytqueue_btn_watch';
    if (document.getElementById(id)) return;

    // Watch page gombsor: #top-level-buttons-computed
    const container =
      document.querySelector('ytd-watch-metadata #top-level-buttons-computed') ||
      document.querySelector('ytd-video-primary-info-renderer #top-level-buttons-computed');

    if (!container) return;

    const btn = makeButton(id, '💾 to NAS');
    container.appendChild(btn);
  }

  function ensureFloatingButton() {
    const id = 'ytqueue_btn_float';
    if (document.getElementById(id)) return;

    const btn = makeButton(id, '💾 to NAS');
    btn.style.position = 'fixed';
    btn.style.right = '16px';
    btn.style.bottom = '64px';
    btn.style.zIndex = '999999';
    btn.style.padding = '10px 12px';
    btn.style.borderRadius = '22px';
    btn.style.background = 'rgba(0,0,0,0.65)';
    btn.style.border = '1px solid rgba(255,255,255,0.25)';
    document.documentElement.appendChild(btn);
  }

  function refreshButtons() {
    ensureWatchPageButton();
    ensureFloatingButton();
  }

  setInterval(refreshButtons, 1500);

  const mo = new MutationObserver(() => refreshButtons());
  mo.observe(document.documentElement, { childList: true, subtree: true });

  toast('ytqueue ready. Menüben állítsd be a jelszót, ha kell.');
})();
