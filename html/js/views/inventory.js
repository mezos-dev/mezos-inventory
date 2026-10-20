// The deck: pockets (left), live character + equipment (centre), secondary inventory (right).

import { $, h, icon, kg, money, throttle } from '../ui.js';
import { S, settings, onChange, emit, weightOf, quality, isEquipSlot } from '../state.js';
import { post } from '../bridge.js';
import { makeSlot, updateSlot } from './slot.js';
import { renderOther, otherHeader } from './other.js';
import { sortSide, requestTrade } from '../actions.js';
import { openSettings } from './settings.js';
import { isDragging } from '../drag.js';

let root = null;
const refs = {};

// ───────────── weight ring ─────────────
const R = 15.5, CIRC = 2 * Math.PI * R;
export function ring() {
    const bar = h('circle', {});
    const wrap = h('div', { class: 'ring' });
    wrap.innerHTML = `<svg viewBox="0 0 36 36"><circle class="track" cx="18" cy="18" r="${R}"/><circle class="bar" cx="18" cy="18" r="${R}" stroke-dasharray="${CIRC}" stroke-dashoffset="${CIRC}"/></svg><b>0%</b>`;
    wrap._bar = wrap.querySelector('.bar');
    wrap._txt = wrap.querySelector('b');
    return wrap;
}
export function setRing(el, used, max) {
    const pct = max > 0 ? Math.min(1, used / max) : 0;
    el._bar.setAttribute('stroke-dashoffset', String(CIRC * (1 - pct)));
    el._txt.textContent = `${Math.round(pct * 100)}%`;
    el.classList.toggle('hot', pct >= 0.8 && pct < 0.98);
    el.classList.toggle('full', pct >= 0.98);
}

// ───────────── filters ─────────────
function matches(item) {
    if (S.ui.category !== 'all' && item.category !== S.ui.category) return false;
    const q = S.ui.search.trim().toLowerCase();
    if (!q) return true;
    const hay = `${item.label} ${item.name} ${item.category} ${item.rarity} ${(item.info && item.info.serie) || ''}`.toLowerCase();
    // loose fuzzy: every character in order
    if (hay.includes(q)) return true;
    let i = 0;
    for (const ch of hay) if (ch === q[i]) i++;
    return i === q.length;
}
const filtering = () => S.ui.category !== 'all' || S.ui.search.trim() !== '';

// ───────────── grids ─────────────

/** Patch a slot grid in place. inv: { items: Map, slots }, sideName: 'player' | 'other' */
export function renderGrid(container, inv, sideName, { hotbar = false, filter = false, src = 'grid' } = {}) {
    let highest = 0;
    for (const s of inv.items.keys()) if (s <= 100 && s > highest) highest = s;
    const count = Math.max(inv.slots || 0, highest);
    if (!container._slots || container._slots.length !== count) {
        container.innerHTML = '';
        container._slots = [];
        for (let i = 1; i <= count; i++) {
            const el = makeSlot({ side: sideName, slot: i, src, drop: true });
            container._slots.push(el);
            container.append(el);
        }
    }
    const active = filter && filtering();
    for (let i = 1; i <= count; i++) {
        const item = inv.items.get(i);
        const ok = item ? matches(item) : true;
        updateSlot(container._slots[i - 1], item, {
            side: sideName, slot: i, src, drop: true,
            key: hotbar && i <= S.config.hotbar ? i : null,
            dim: active && (!item || !ok),
            match: active && item && ok && S.ui.search.trim() !== '',
            overflow: i > inv.slots,
        });
    }
}

// ───────────── shell ─────────────

export function mount() {
    root = $('#app');
    root.innerHTML = '';
    root.append(h('div', { class: 'vignette' }));
    root.insertAdjacentHTML('beforeend', `<svg width="0" height="0" style="position:absolute"><defs><linearGradient id="ringGrad" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(--accent)"/><stop offset="1" stop-color="var(--accent2)"/></linearGradient></defs></svg>`);

    // top bar
    refs.cash = h('span', {});
    refs.bank = h('span', {});
    refs.tradeBtn = h('button', { class: 'icon-btn', title: 'Trade', onclick: () => requestTrade() }, icon('trade'));
    refs.gearBtn = h('button', { class: 'icon-btn gear-toggle', title: 'Gear', onclick: () => { S.ui.gearOpen = !S.ui.gearOpen; applyLayout(); } }, icon('shield'));
    root.append(h('header', { class: 'topbar' },
        h('div', { class: 'brand' },
            h('div', { class: 'logo' }, icon('logo')),
            h('div', {}, h('h1', {}, (S.config.theme && S.config.theme.serverName) || 'MEZOS'), h('small', {}, 'Inventory'))),
        h('div', { class: 'spacer' }),
        h('div', { class: 'pill' }, icon('cash'), refs.cash),
        h('div', { class: 'pill bank' }, icon('bank'), refs.bank),
        refs.gearBtn,
        refs.tradeBtn,
        h('button', { class: 'icon-btn', title: 'Settings', onclick: () => openSettings() }, icon('settings')),
        h('button', { class: 'icon-btn close', title: 'Close (Esc)', onclick: () => emit('requestClose') }, icon('x')),
    ));

    // deck
    refs.left = buildPlayerPanel();
    refs.core = buildCore();
    refs.right = h('section', { class: 'panel right glass' }, h('div', { class: 'sweep' }));
    refs.otherHead = h('div', { class: 'panel-head' });
    refs.otherBody = h('div', { class: 'panel-body' });
    refs.otherFoot = h('div', { class: 'panel-foot' });
    refs.right.append(refs.otherHead, refs.otherBody, refs.otherFoot);
    refs.gear = h('section', { class: 'gear-host panel glass gear-drawer' });
    root.append(h('main', { class: 'deck' }, refs.left, refs.core, refs.right, refs.gear));

    // narrow-layout tabs
    refs.tabs = h('nav', { class: 'tabs' });
    root.append(refs.tabs);

    root.append(h('footer', { class: 'hints' },
        h('span', {}, h('kbd', {}, 'Drag'), 'Move'),
        h('span', {}, h('kbd', {}, 'Shift'), 'Split half'),
        h('span', {}, h('kbd', {}, 'Wheel'), 'Amount while dragging'),
        h('span', {}, h('kbd', {}, 'Ctrl'), '+ click quick move'),
        h('span', { class: 'wide-only' }, h('kbd', {}, '1-5'), 'Bind hovered'),
        h('span', {}, h('kbd', {}, 'Esc'), 'Close'),
    ));
    applyLayout();
}

function buildPlayerPanel() {
    const p = h('section', { class: 'panel left glass' }, h('div', { class: 'sweep' }));
    refs.pRing = ring();
    refs.pName = h('h2', {});
    refs.pEyebrow = h('div', { class: 'eyebrow' });
    refs.pMeter = h('div', { class: 'meter' });
    refs.avatar = h('div', { class: 'avatar' });
    refs.search = h('input', { placeholder: 'Search items…', spellcheck: 'false' });
    refs.search.addEventListener('input', () => { S.ui.search = refs.search.value; emit('filter'); });
    refs.chips = h('div', { class: 'chips' });
    refs.amountBar = buildAmountBar();
    refs.pGrid = h('div', { class: 'grid' });
    refs.pFoot = h('div', { class: 'panel-foot' });
    p.append(
        h('div', { class: 'panel-head' },
            h('div', { class: 'head-row' }, refs.avatar, h('div', { class: 'head-title' }, refs.pEyebrow, refs.pName), refs.pMeter, refs.pRing),
            h('div', { class: 'tools' },
                h('label', { class: 'search' }, icon('search'), refs.search),
                h('button', { class: 'icon-btn', title: 'Sort & stack', onclick: () => sortSide('player') }, icon('sort'))),
            refs.chips,
            refs.amountBar,
        ),
        h('div', { class: 'panel-body' }, refs.pGrid),
        refs.pFoot,
    );
    return p;
}

function buildAmountBar() {
    const bar = h('div', { class: 'amount-bar' }, h('span', { class: 'lbl' }, 'Move'));
    const modes = [['all', 'All'], ['half', '½'], ['one', '1']];
    const input = h('input', { type: 'number', min: 1, placeholder: '#', title: 'Custom amount' });
    const chips = modes.map(([id, label]) => h('button', { class: 'chip', 'data-mode': id, onclick: () => { S.ui.amountMode = id; input.value = ''; paint(); } }, label));
    input.addEventListener('input', () => {
        const v = Math.max(1, Math.floor(+input.value || 0));
        if (input.value === '') { S.ui.amountMode = 'all'; } else { S.ui.amountMode = 'custom'; S.ui.amountValue = v; }
        paint();
    });
    const paint = () => chips.forEach((c) => c.classList.toggle('active', c.dataset.mode === S.ui.amountMode));
    bar.append(...chips, input);
    paint();
    return bar;
}

function buildCore() {
    const core = h('section', { class: 'core' });
    refs.who = h('div', { class: 'who' });
    refs.links = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    refs.links.setAttribute('class', 'links');
    refs.eqL = h('div', { class: 'equip-col l' });
    refs.eqR = h('div', { class: 'equip-col r' });
    refs.dropzone = h('div', { class: 'dropzone', 'data-drop': 'ground' }, icon('drop'), 'Release to drop on ground');
    const rot = h('div', { class: 'rotate-zone' });
    let rotating = null;
    const send = throttle((d) => post('camera', { rotate: d }), 30);
    rot.addEventListener('pointerdown', (e) => { if (e.button === 0) { rotating = e.clientX; rot.setPointerCapture(e.pointerId); } });
    rot.addEventListener('pointermove', (e) => { if (rotating === null) return; const d = e.clientX - rotating; rotating = e.clientX; send(d * 0.6); });
    rot.addEventListener('pointerup', () => { rotating = null; });
    core.append(rot, refs.links, refs.who, refs.eqL, refs.eqR, refs.dropzone);
    return core;
}

// ───────────── equipment ─────────────

function equipNode(e) {
    const item = S.player.items.get(e.slot);
    const slot = makeSlot({ side: 'player', slot: e.slot, src: 'equip', drop: true, placeholder: e.icon, item });
    const sub = item ? (item.backpack ? `+${item.backpack.slots} slots` : item.label) : 'Empty';
    const node = h('div', { class: 'equip' }, slot, h('div', { class: 'meta' }, h('b', {}, e.label), h('span', {}, sub)));
    node._slot = slot;
    return node;
}

function renderEquip() {
    const eq = S.config.equip || [];
    const half = Math.ceil(eq.length / 2);
    refs.eqL.innerHTML = '';
    refs.eqR.innerHTML = '';
    eq.forEach((e, i) => (i < half ? refs.eqL : refs.eqR).append(equipNode(e)));
    requestAnimationFrame(drawLinks);

    // gear drawer (mid / narrow)
    refs.gear.innerHTML = '';
    const bpItem = S.player.items.get((eq.find((e) => e.id === 'backpack') || {}).slot);
    refs.gear.append(
        h('div', { class: 'panel-head' }, h('div', { class: 'head-row' },
            h('div', { class: 'avatar' }, icon('shield')),
            h('div', { class: 'head-title' }, h('div', { class: 'eyebrow' }, 'Loadout'), h('h2', {}, 'Equipment')),
            S.ui.layout === 'mid' ? h('button', { class: 'icon-btn', onclick: () => { S.ui.gearOpen = false; applyLayout(); } }, icon('x')) : null)),
        h('div', { class: 'panel-body' },
            h('div', { class: 'gear-grid' }, eq.map(equipNode)),
            bpItem && bpItem.backpack ? h('div', { class: 'ground-hint' }, icon('backpack'), `${bpItem.label}: +${bpItem.backpack.slots} slots, +${kg(bpItem.backpack.weight)}`) : null),
    );
}

function drawLinks() {
    const svg = refs.links;
    if (!svg || S.ui.layout !== 'wide') return;
    const box = refs.core.getBoundingClientRect();
    if (!box.width) return;
    const cx = box.width / 2;
    const anchors = [0.28, 0.45, 0.62]; // head/shoulder, torso, hands (fractions of height)
    let out = '';
    const nodes = [...refs.eqL.children, ...refs.eqR.children];
    nodes.forEach((n) => {
        const r = n._slot.getBoundingClientRect();
        const left = n.parentElement === refs.eqL;
        const x1 = left ? r.right - box.left + 6 : r.left - box.left - 6;
        const y1 = r.top - box.top + r.height / 2;
        const idx = [...n.parentElement.children].indexOf(n);
        const y2 = box.height * (anchors[idx] || 0.5);
        const x2 = cx + (left ? -box.width * 0.07 : box.width * 0.07);
        const mx = (x1 + x2) / 2;
        out += `<path d="M${x1},${y1} C${mx},${y1} ${mx},${y2} ${x2},${y2}"/><circle cx="${x2}" cy="${y2}" r="2.5"/>`;
    });
    svg.innerHTML = out;
}

// ───────────── layout ─────────────

export function applyLayout() {
    if (!root) return;
    const w = window.innerWidth, hgt = window.innerHeight;
    // same formula as --slot in app.css (measuring would feed back into the layout choice)
    const slot = Math.min(Math.max(50, Math.min(w * 0.0415, hgt * 0.074)), 116) * (settings.scale || 1);
    const panelW = slot * 5.78 + 8;
    let layout = 'wide';
    if (w < panelW * 2 + 60 || hgt > w * 1.15) layout = 'narrow';
    else if (w < panelW * 2 + Math.max(320, slot * 4.6)) layout = 'mid';
    S.ui.layout = layout;
    root.dataset.layout = layout;
    root.dataset.tab = S.ui.tab;
    root.classList.toggle('gear-open', layout === 'mid' && S.ui.gearOpen);
    if (refs.gearBtn) {
        refs.gearBtn.classList.toggle('hidden', layout === 'wide');
        refs.gearBtn.classList.toggle('active', S.ui.gearOpen);
    }
    post('camera', { enabled: layout === 'wide' && settings.camera });
    renderTabs();
    requestAnimationFrame(drawLinks);
}

function renderTabs() {
    if (!refs.tabs) return;
    const o = S.other;
    const otherLabel = o ? (o.kind === 'ground' ? 'Ground' : o.label || 'Other') : 'Other';
    const tab = (id, label, ic) => h('button', {
        class: S.ui.tab === id ? 'active' : '', 'data-spring': '',
        onclick: () => { S.ui.tab = id; root.dataset.tab = id; renderTabs(); },
    }, icon(ic), h('span', {}, label));
    refs.tabs.innerHTML = '';
    refs.tabs.append(tab('me', 'Pockets', 'backpack'), tab('gear', 'Gear', 'shield'), tab('other', otherLabel, 'layers'));
}

// ───────────── render ─────────────

export function render(reason) {
    if (!root || !S.open) return;
    if (isDragging() && reason === 'items') { root._dirty = true; return; }
    root._dirty = false;
    const p = S.player;
    refs.cash.textContent = money(p.money && p.money.cash);
    refs.bank.textContent = money(p.money && p.money.bank);
    const initials = (p.name || '?').split(' ').map((s) => s[0]).join('').slice(0, 2).toUpperCase();
    refs.avatar.textContent = initials;
    refs.pEyebrow.textContent = `Pockets · ID ${p.id || ''}`;
    refs.pName.textContent = p.name || 'Unknown';
    const w = weightOf(p);
    setRing(refs.pRing, w, p.maxweight);
    refs.pMeter.innerHTML = '';
    refs.pMeter.append(h('b', {}, kg(w)), h('span', {}, `of ${kg(p.maxweight)}`));

    // category chips with counts
    const counts = {};
    let total = 0;
    for (const [slot, it] of p.items) { if (slot > 100) continue; counts[it.category] = (counts[it.category] || 0) + 1; total++; }
    refs.chips.innerHTML = '';
    const chip = (id, label, n) => h('button', { class: `chip ${S.ui.category === id ? 'active' : ''}`, onclick: () => { S.ui.category = S.ui.category === id && id !== 'all' ? 'all' : id; emit('filter'); } }, label, n ? h('span', { class: 'n' }, n) : null);
    refs.chips.append(chip('all', 'All', total));
    for (const c of S.config.categories || []) if (counts[c.id]) refs.chips.append(chip(c.id, c.label, counts[c.id]));

    renderGrid(refs.pGrid, p, 'player', { hotbar: true, filter: true });
    let used = 0;
    for (const s of p.items.keys()) if (s <= 100) used++;
    refs.pFoot.innerHTML = '';
    refs.pFoot.append(icon('grid'), h('span', {}, `${used} / ${p.slots} slots`), h('span', { class: 'grow' }), h('span', {}, 'Right-click for actions'));

    // centre
    refs.who.innerHTML = '';
    refs.who.append(h('h3', {}, p.name || ''), h('small', {}, `ID ${p.id || ''} · ${kg(w)}`));
    renderEquip();
    refs.dropzone.classList.toggle('armed', true);

    // secondary
    otherHeader(refs.otherHead, refs.otherFoot);
    renderOther(refs.otherBody);
    renderTabs();
}

export function focusSearch() {
    if (refs.search) { refs.search.focus(); refs.search.select(); }
}

window.addEventListener('resize', () => { applyLayout(); });
onChange((reason) => {
    if (reason === 'settings') applyLayout();
    if (reason === 'dragEnd' && root && root._dirty) render('items');
});
