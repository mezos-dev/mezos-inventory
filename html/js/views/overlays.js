// Overlays that also work with the inventory closed: hotbar, item popups, required items, quick-wheel.

import { $, h, icon, itemImg } from '../ui.js';
import { S, arr, favs } from '../state.js';
import { post } from '../bridge.js';
import { makeSlot } from './slot.js';
import { rarityVars } from '../tooltip.js';

// ───────────── hotbar ─────────────
let hotbarShown = false;
let hotbarTimer = null;

function drawHotbar(items, used) {
    const el = $('#hotbar');
    el.innerHTML = '';
    arr(items).forEach((it, i) => {
        const slot = makeSlot({ side: 'hotbar', slot: i + 1, src: 'view', key: i + 1, item: it || null });
        if (used === i + 1) slot.classList.add('used');
        el.append(slot);
    });
}

export function hotbar(show, items) {
    hotbarShown = !!show;
    clearTimeout(hotbarTimer);
    if (!show) return $('#hotbar').classList.add('hidden');
    drawHotbar(items);
    $('#hotbar').classList.remove('hidden');
}

export function hotbarPulse(slot, items) {
    drawHotbar(items, slot);
    const el = $('#hotbar');
    el.classList.remove('hidden');
    clearTimeout(hotbarTimer);
    if (!hotbarShown) hotbarTimer = setTimeout(() => el.classList.add('hidden'), 1800);
}

// ───────────── item popups ─────────────
const LABEL = { add: 'Received', remove: 'Removed', use: 'Used' };

export function itembox(item, type, amount) {
    if (!item) return;
    const root = $('#itembox');
    while (root.children.length >= 5) root.firstChild.remove();
    const box = h('div', { class: `ibox glass ${type}`, style: rarityVars(item) },
        h('div', { class: 'im' }, itemImg(item)),
        h('div', { class: 't' }, h('small', {}, LABEL[type] || type), h('b', {}, item.label || item.name)),
        type !== 'use' ? h('span', { class: 'x' }, `${type === 'remove' ? '−' : '+'}${amount || 1}`) : null);
    root.append(box);
    setTimeout(() => { box.classList.add('out'); setTimeout(() => box.remove(), 380); }, 3200);
}

// ───────────── required items ─────────────
export function required(items, show) {
    const el = $('#required');
    el.innerHTML = '';
    const list = arr(items);
    if (!show || !list.length) return el.classList.add('hidden');
    for (const it of list) {
        el.append(h('div', { class: `req glass ${it.have === false ? 'miss' : ''}` },
            h('small', {}, it.have === false ? 'Missing' : 'Required'), itemImg(it), h('span', {}, it.label)));
    }
    el.classList.remove('hidden');
}

// ───────────── quick wheel ─────────────
export function wheelOpen() { return !$('#wheel').classList.contains('hidden'); }

export function wheel(show, player) {
    const el = $('#wheel');
    el.innerHTML = '';
    if (!show) return el.classList.add('hidden');
    const items = new Map(arr(player && player.items).map((it) => [+it.slot, it]));
    const picks = [];
    const used = new Set();
    const add = (it) => { if (it && !used.has(it.slot) && picks.length < 8) { picks.push(it); used.add(it.slot); } };
    for (let i = 1; i <= (S.config.hotbar || 5); i++) add(items.get(i));
    for (const e of S.config.equip || []) if (e.id === 'primary' || e.id === 'secondary') add(items.get(e.slot));
    for (const it of items.values()) if (favs.has(it.name)) add(it);

    const hubLabel = h('b', {}, 'Quick use');
    const hub = h('div', { class: 'hub' }, hubLabel, h('small', {}, 'Esc to close'));
    const wheelEl = h('div', { class: 'wheel' }, hub);
    const n = Math.max(picks.length, 1);
    picks.forEach((it, i) => {
        const ang = (i / n) * Math.PI * 2 - Math.PI / 2;
        const slot = makeSlot({ side: 'wheel', slot: it.slot, src: 'view', item: it });
        slot.addEventListener('pointerenter', () => { hubLabel.textContent = it.label; });
        slot.addEventListener('pointerleave', () => { hubLabel.textContent = 'Quick use'; });
        slot.addEventListener('click', () => { post('wheelUse', { slot: it.slot }); el.classList.add('hidden'); });
        const w = h('div', { class: 'wslot' }, slot);
        w.style.left = `${50 + 38 * Math.cos(ang)}%`;
        w.style.top = `${50 + 38 * Math.sin(ang)}%`;
        wheelEl.append(w);
    });
    if (!picks.length) hub.append(h('small', { style: { display: 'block', marginTop: '.5em' } }, 'Put items in slots 1-5 or favourite them'));
    el.append(wheelEl);
    el.classList.remove('hidden');
    el.onpointerdown = (e) => { if (e.target === el) { post('wheelClose'); el.classList.add('hidden'); } };
}

export { icon };
