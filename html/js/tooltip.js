// Holo item card that follows the cursor (or pins on "Inspect").

import { $, h, kg, money, itemImg, icon, hexToRgba } from './ui.js';
import { S, settings, quality, favs } from './state.js';
import { isDragging } from './drag.js';

let timer = null;
let current = null;
let pinned = false;
let mouse = { x: 0, y: 0 };

const HIDDEN_INFO = new Set(['created', 'quality', 'serie', 'ammo', 'attachments', 'containerId', 'tint', 'durability']);
const LABELS = {
    citizenid: 'Citizen ID', firstname: 'First name', lastname: 'Last name', birthdate: 'Birthdate',
    nationality: 'Nationality', gender: 'Gender', type: 'Type', worth: 'Worth', uses: 'Uses',
    label: 'Label', plate: 'Plate', model: 'Model', label2: 'Note',
};

export function rarityVars(item) {
    const color = (S.config.rarities && S.config.rarities[item.rarity]) || '#8fa3b8';
    return { '--rar': color, '--rar-soft': hexToRgba(color, 0.24) };
}

function qualityLabel(item, q) {
    if (item.decay) return q <= 0 ? 'Spoiled' : q < 25 ? 'Stale' : q < 60 ? 'Aging' : 'Fresh';
    return q <= 0 ? 'Broken' : q < 25 ? 'Critical' : q < 60 ? 'Worn' : 'Good';
}

function build(item) {
    const tip = $('#tooltip');
    tip.innerHTML = '';
    tip.className = 'glass';
    for (const [k, v] of Object.entries(rarityVars(item))) tip.style.setProperty(k, v);

    const rarity = item.rarity || 'common';
    const cat = (S.config.categories || []).find((c) => c.id === item.category);
    tip.append(h('div', { class: 'tt-head' },
        h('div', { class: 'tt-img' }, itemImg(item)),
        h('div', {},
            h('div', { class: 'rar' }, `${rarity}${cat ? ' · ' + cat.label : ''}`),
            h('h4', {}, item.label, favs.has(item.name) ? ' ★' : ''),
        ),
    ));
    if (item.description) tip.append(h('div', { class: 'desc' }, item.description));

    const q = quality(item);
    if (q !== null) {
        const cls = q > 60 ? '' : q > 25 ? 'mid' : 'low';
        tip.append(h('div', { class: 'qbar' },
            h('div', { class: 'top' }, h('span', {}, item.decay ? 'Freshness' : 'Durability'), h('b', {}, `${qualityLabel(item, q)} · ${Math.floor(q)}%`)),
            h('div', { class: `progress q ${cls}` }, h('i', { style: { width: `${q}%`, background: q > 60 ? 'var(--success)' : q > 25 ? 'var(--warn)' : 'var(--danger)' } }))));
    }

    const rows = [];
    rows.push(['Weight', item.amount > 1 ? `${kg(item.weight)} · ${kg(item.weight * item.amount)}` : kg(item.weight)]);
    if (item.amount > 1) rows.push(['Amount', `x${item.amount}`]);
    if (item.price != null) rows.push(['Price', money(item.price)]);
    const info = item.info || {};
    if (info.serie) rows.push(['Serial', info.serie]);
    if (info.ammo != null) rows.push(['Ammo', info.ammo]);
    if (Array.isArray(info.attachments) && info.attachments.length) rows.push(['Attachments', info.attachments.length]);
    if (item.backpack) rows.push(['Capacity', `+${item.backpack.slots} slots · +${kg(item.backpack.weight)}`]);
    if (item.container) rows.push(['Holds', `${item.container.slots} slots · ${kg(item.container.weight)}`]);
    if (item.decay) rows.push(['Shelf life', `${item.decay} h`]);
    for (const [k, v] of Object.entries(info)) {
        if (HIDDEN_INFO.has(k) || v === null || v === '' || typeof v === 'object') continue;
        let val = v;
        if (k === 'gender') val = v === 0 || v === '0' ? 'Male' : 'Female';
        if (k === 'worth') val = money(v);
        rows.push([LABELS[k] || k, String(val)]);
    }
    if (rows.length) {
        const dl = h('dl', { class: 'stats' });
        for (const [k, v] of rows) dl.append(h('dt', {}, k), h('dd', {}, v));
        tip.append(dl);
    }

    const keys = [];
    if (item.useable || item.type === 'weapon') keys.push('Dbl-click use');
    keys.push('Ctrl+click move', 'Right-click actions');
    if (item.amount > 1) keys.push('Shift-drag split');
    tip.append(h('div', { class: 'keys' }, keys.map((k) => h('span', {}, k))));
}

function place() {
    const tip = $('#tooltip');
    if (tip.classList.contains('hidden')) return;
    const r = tip.getBoundingClientRect();
    const pad = 16;
    let x = mouse.x + 22, y = mouse.y + 18;
    if (x + r.width + pad > window.innerWidth) x = mouse.x - r.width - 22;
    if (y + r.height + pad > window.innerHeight) y = window.innerHeight - r.height - pad;
    x = Math.max(pad, x);
    y = Math.max(pad, y);
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
}

export function hideTip(force = false) {
    if (pinned && !force) return;
    pinned = false;
    clearTimeout(timer);
    current = null;
    $('#tooltip').classList.add('hidden');
    $('#tooltip').classList.remove('pinned');
}

export function pinTip(item, x, y) {
    build(item);
    pinned = true;
    mouse = { x, y };
    const tip = $('#tooltip');
    tip.classList.remove('hidden');
    tip.classList.add('pinned');
    place();
}

export function initTooltip(getItem) {
    document.addEventListener('pointermove', (e) => {
        mouse = { x: e.clientX, y: e.clientY };
        if (pinned) return;
        if (isDragging() || !settings.tooltips || e.pointerType === 'touch') { if (current) hideTip(); return; }
        const el = e.target.closest('[data-src]');
        if (!el) { if (current) hideTip(); return; }
        const key = `${el.dataset.side}:${el.dataset.slot}:${el.dataset.src}`;
        if (key === current) { place(); return; }
        hideTip();
        current = key;
        timer = setTimeout(() => {
            const item = getItem({ side: el.dataset.side, slot: +el.dataset.slot, kind: el.dataset.src });
            if (!item || current !== key) return;
            build(item);
            $('#tooltip').classList.remove('hidden');
            place();
        }, 260);
    });
    document.addEventListener('pointerdown', (e) => {
        if (pinned && !e.target.closest('#tooltip')) hideTip(true);
        else if (!pinned) hideTip();
    }, true);
}

export { icon };
