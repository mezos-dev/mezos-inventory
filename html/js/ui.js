// DOM helpers, icons, formatting, sounds, toasts and modals.

export function h(tag, attrs = {}, ...children) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
        if (v === undefined || v === null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'style' && typeof v === 'object') {
            for (const [sk, sv] of Object.entries(v)) {
                if (sk.startsWith('--')) el.style.setProperty(sk, sv); else el.style[sk] = sv;
            }
        }
        else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2).toLowerCase(), v);
        else if (k === 'html') el.innerHTML = v;
        else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of children.flat(Infinity)) {
        if (c === null || c === undefined || c === false) continue;
        el.append(c instanceof Node ? c : document.createTextNode(String(c)));
    }
    return el;
}

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
export const money = (n) => '$' + Math.round(n || 0).toLocaleString('en-US');
export const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function kg(grams) {
    const v = (grams || 0) / 1000;
    return (v >= 100 ? v.toFixed(0) : v.toFixed(1)) + ' kg';
}

export function hexToRgba(hex, a) {
    const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '');
    if (!m) return `rgba(143,163,184,${a})`;
    return `rgba(${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)},${a})`;
}
export function hexToRgb(hex) {
    const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '');
    return m ? `${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}` : '34, 228, 255';
}

// ───────────── icons (24px stroke set) ─────────────
const P = {
    logo: '<path d="M12 2l8.5 5v10L12 22l-8.5-5V7z"/><path d="M12 7l4.3 2.5v5L12 17l-4.3-2.5v-5z"/>',
    box: '<path d="M3 7l9-4 9 4v10l-9 4-9-4z"/><path d="M3 7l9 4 9-4M12 11v10"/>',
    backpack: '<path d="M6 9a6 6 0 0 1 12 0v11H6z"/><path d="M9 4.5V3h6v1.5M9 13h6v4H9z"/>',
    shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>',
    phone: '<rect x="7" y="2.5" width="10" height="19" rx="2.2"/><path d="M11 18.5h2"/>',
    radio: '<rect x="4" y="8" width="16" height="13" rx="2"/><path d="M8 8l9-5M8 13h3M8 16h3"/><circle cx="16" cy="14.5" r="2.5"/>',
    rifle: '<path d="M2 12h14l2-2h4v3h-4l-1 1H9l-1 4H5l1-4H2z"/>',
    pistol: '<path d="M3 7h16v4H11l-1 2H8l-1 6H3l1.5-8H3z"/>',
    weapon: '<path d="M2 12h14l2-2h4v3h-4l-1 1H9l-1 4H5l1-4H2z"/>',
    ammo: '<path d="M7 21V9l2-5 2 5v12zM13 21V9l2-5 2 5v12z"/>',
    food: '<path d="M4 11h16a8 8 0 0 1-16 0z"/><path d="M8 7c0-2 2-2 2-4M12 7c0-2 2-2 2-4"/>',
    drink: '<path d="M7 3h10l-1.5 18h-7z"/><path d="M7.5 9h9"/>',
    medical: '<rect x="3" y="6" width="18" height="14" rx="2"/><path d="M12 10v6M9 13h6M9 6V4h6v2"/>',
    tool: '<path d="M14.5 5.5a4 4 0 0 0 4.9 4.9L21 12l-9 9-3-3 9-9-1.6-1.6a4 4 0 0 0-4.9-4.9z"/><path d="M5 19l-2 2"/>',
    drug: '<rect x="4" y="9" width="16" height="6" rx="3" transform="rotate(-35 12 12)"/><path d="M10 7.5l4 9"/>',
    valuable: '<path d="M6 3h12l3 6-9 12L3 9z"/><path d="M3 9h18M9 3l3 6 3-6"/>',
    misc: '<circle cx="12" cy="12" r="9"/><path d="M12 8v5M12 16h.01"/>',
    cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="3"/>',
    bank: '<path d="M3 10l9-6 9 6M5 10v8M9 10v8M15 10v8M19 10v8M3 21h18"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
    sort: '<path d="M7 4v16M3 16l4 4 4-4M17 20V4M13 8l4-4 4 4"/>',
    settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
    x: '<path d="M6 6l12 12M18 6L6 18"/>',
    check: '<path d="M4 12l5 5L20 6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    hand: '<path d="M7 11V5.5a1.5 1.5 0 0 1 3 0V10V4a1.5 1.5 0 0 1 3 0v6V5.5a1.5 1.5 0 0 1 3 0V12V8.5a1.5 1.5 0 0 1 3 0V15a6 6 0 0 1-6 6h-1.5a6 6 0 0 1-4.6-2.2L4 14.5a1.6 1.6 0 0 1 2.4-2.1z"/>',
    give: '<path d="M2 15l4-1 5 2 6-2a2 2 0 0 1 1 3.8L11 21l-9-2"/><path d="M14 4a3 3 0 1 1 0 6 3 3 0 0 1 0-6z"/>',
    trade: '<path d="M7 7h13l-4-4M17 17H4l4 4"/>',
    drop: '<path d="M12 3v12M7 10l5 5 5-5M4 21h16"/>',
    split: '<path d="M12 21v-7l-6-6M12 14l6-6M6 3v5h5M18 3v5h-5"/>',
    use: '<path d="M5 12l5 5L20 7"/><circle cx="12" cy="12" r="10"/>',
    equip: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
    unequip: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12h6"/>',
    star: '<path d="M12 3l2.8 5.8 6.2.9-4.5 4.4 1 6.2L12 17.4 6.5 20.3l1-6.2L3 9.7l6.2-.9z"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    move: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    attach: '<circle cx="12" cy="12" r="3"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>',
    hotkey: '<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h.01M11 10h.01M15 10h.01M8 14h8"/>',
    open: '<path d="M3 7h6l2 2h10v10H3z"/><path d="M3 7V5h6l2 2"/>',
    ground: '<path d="M3 20h18"/><path d="M7 20l2-8h6l2 8"/><path d="M10 12V8h4v4"/>',
    trunk: '<path d="M3 13l2-6h14l2 6v5H3z"/><path d="M3 13h18M7 18v2M17 18v2"/>',
    glovebox: '<rect x="3" y="7" width="18" height="11" rx="2"/><path d="M10 11h4"/>',
    store: '<path d="M3 9l2-5h14l2 5"/><path d="M4 9v11h16V9M3 9h18"/><path d="M9 20v-6h6v6"/>',
    craft: '<path d="M14.5 5.5a4 4 0 0 0 4.9 4.9L21 12l-9 9-3-3 9-9-1.6-1.6a4 4 0 0 0-4.9-4.9z"/><path d="M3 21l3-3"/>',
    repair: '<path d="M14.5 5.5a4 4 0 0 0 4.9 4.9L21 12l-9 9-3-3 9-9-1.6-1.6a4 4 0 0 0-4.9-4.9z"/><path d="M3 3l6 6"/>',
    user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 3.6-7 8-7s8 3 8 7"/>',
    users: '<circle cx="9" cy="8" r="3.5"/><path d="M2 20c0-3.5 3-6 7-6s7 2.5 7 6"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14c2.5.7 4 3 4 6"/>',
    lock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    unlock: '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.01"/>',
    alert: '<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.01"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    weight: '<path d="M6 8h12l2 13H4z"/><circle cx="12" cy="5" r="2"/>',
    grid: '<rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>',
    stash: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M10 14h4"/>',
    container: '<path d="M4 8h16v12H4z"/><path d="M8 8V5h8v3M4 12h16"/>',
    wheel: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3"/><path d="M12 3v6M12 15v6M3 12h6M15 12h6"/>',
    layers: '<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>',
};

export function icon(name, cls = '') {
    const span = document.createElement('span');
    span.innerHTML = `<svg class="i ${cls}" viewBox="0 0 24 24">${P[name] || P.misc}</svg>`;
    return span.firstChild;
}
export function hasIcon(name) { return !!P[name]; }

// ───────────── item image with fallback ─────────────
export function itemImg(item) {
    const img = new Image();
    img.draggable = false;
    img.alt = '';
    img.src = `images/${item.image || 'placeholder.png'}`;
    img.onerror = () => {
        const fallback = icon(item.category && P[item.category] ? item.category : (item.type === 'weapon' ? 'weapon' : 'box'));
        img.replaceWith(fallback);
    };
    return img;
}

// ───────────── sounds ─────────────
let audio = null;
let soundOn = true;
export function setSound(on) { soundOn = on; }
export function sfx(kind = 'tick') {
    if (!soundOn) return;
    try {
        audio = audio || new (window.AudioContext || window.webkitAudioContext)();
        const o = audio.createOscillator();
        const g = audio.createGain();
        const t = audio.currentTime;
        const presets = {
            tick: [880, 0.03, 0.025, 'sine'],
            pick: [520, 0.05, 0.05, 'triangle'],
            drop: [340, 0.06, 0.06, 'triangle'],
            error: [160, 0.1, 0.12, 'sawtooth'],
            open: [660, 0.05, 0.12, 'sine'],
            buy: [990, 0.05, 0.1, 'sine'],
        };
        const [f, v, d, type] = presets[kind] || presets.tick;
        o.type = type;
        o.frequency.setValueAtTime(f, t);
        if (kind === 'open') o.frequency.exponentialRampToValueAtTime(f * 1.6, t + d);
        if (kind === 'error') o.frequency.exponentialRampToValueAtTime(f * 0.6, t + d);
        g.gain.setValueAtTime(v, t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + d);
        o.connect(g).connect(audio.destination);
        o.start(t);
        o.stop(t + d + 0.02);
    } catch (e) { /* audio blocked */ }
}

// ───────────── toasts ─────────────
export function toast(text, type = 'info', ms = 2600) {
    const root = $('#toasts');
    if (!root || !text) return;
    while (root.children.length >= 4) root.firstChild.remove();
    const ic = type === 'error' ? 'alert' : type === 'success' ? 'check' : 'info';
    const el = h('div', { class: `toast glass ${type}` }, icon(ic), h('span', {}, text));
    root.append(el);
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 320); }, ms);
}

// ───────────── modals ─────────────
let modalStack = [];
export function modalOpen() { return modalStack.length > 0; }

export function modal(build, { onClose } = {}) {
    const root = $('#modal-root');
    let closed = false;
    const close = (val) => {
        if (closed) return;
        closed = true;
        backdrop.remove();
        modalStack = modalStack.filter((m) => m !== entry);
        onClose && onClose(val);
    };
    const box = h('div', { class: 'modal glass' });
    const backdrop = h('div', { class: 'backdrop', onpointerdown: (e) => { if (e.target === backdrop) close(null); } }, box);
    const entry = { close };
    modalStack.push(entry);
    build(box, close);
    root.append(backdrop);
    const first = box.querySelector('input, button.primary');
    if (first) setTimeout(() => first.focus(), 30);
    return close;
}

export function closeTopModal() {
    const top = modalStack[modalStack.length - 1];
    if (top) { top.close(null); return true; }
    return false;
}

/** Ask for an amount with a slider + input. Resolves to a number or null. */
export function askAmount({ title, max, value, label = 'Amount', confirm = 'Confirm', ic = 'split' }) {
    return new Promise((resolve) => {
        modal((box, close) => {
            let v = clamp(Math.round(value || 1), 1, max);
            const out = h('div', { class: 'bigval' }, v);
            const input = h('input', { type: 'number', min: 1, max, value: v, class: 'num', style: { width: '5em', height: '2.2em', textAlign: 'center', border: '1px solid var(--line)', background: 'rgba(0,0,0,.3)', borderRadius: '.35em', outline: '0' } });
            const range = h('input', { type: 'range', min: 1, max, value: v });
            const set = (n) => { v = clamp(Math.round(+n || 1), 1, max); out.textContent = v; input.value = v; range.value = v; };
            range.addEventListener('input', () => set(range.value));
            input.addEventListener('input', () => set(input.value));
            input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { close(v); } });
            box.append(
                h('h3', {}, icon(ic), title),
                h('div', { class: 'row' }, h('span', { style: { color: 'var(--muted)', minWidth: '4em' } }, label), range, out),
                h('div', { class: 'row' },
                    h('button', { class: 'btn sm ghost', onclick: () => set(1) }, '1'),
                    h('button', { class: 'btn sm ghost', onclick: () => set(Math.floor(max / 2) || 1) }, '½'),
                    h('button', { class: 'btn sm ghost', onclick: () => set(max) }, 'All'),
                    h('span', { style: { flex: 1 } }), input),
                h('div', { class: 'row end' },
                    h('button', { class: 'btn ghost', onclick: () => close(null) }, 'Cancel'),
                    h('button', { class: 'btn primary', onclick: () => close(v) }, confirm)),
            );
        }, { onClose: (val) => resolve(val ?? null) });
    });
}

/** Pick one entry from a list. items: [{ id, label, sub }] */
export function pick({ title, items, ic = 'users', empty = 'Nobody nearby' }) {
    return new Promise((resolve) => {
        modal((box, close) => {
            box.append(h('h3', {}, icon(ic), title));
            if (!items.length) box.append(h('p', {}, empty));
            box.append(h('div', { class: 'plist' }, items.map((it) =>
                h('button', { onclick: () => close(it) }, icon('user'), h('b', {}, it.label), h('small', {}, it.sub || '')))));
            box.append(h('div', { class: 'row end' }, h('button', { class: 'btn ghost', onclick: () => close(null) }, 'Cancel')));
        }, { onClose: (v) => resolve(v ?? null) });
    });
}

export function throttle(fn, ms = 40) {
    let last = 0, timer = null, args = null;
    return (...a) => {
        args = a;
        const now = Date.now();
        const fire = () => { last = Date.now(); timer = null; fn(...args); };
        if (now - last >= ms) fire();
        else if (!timer) timer = setTimeout(fire, ms - (now - last));
    };
}
