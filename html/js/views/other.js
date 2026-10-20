// Right-hand panel: whatever you're looking at (ground, stash, trunk, drop, player, shop, bench, trade).

import { h, icon, kg, money, itemImg, clamp } from '../ui.js';
import { S, emit, weightOf, arr, quality } from '../state.js';
import { renderGrid, ring, setRing } from './inventory.js';
import { makeSlot } from './slot.js';
import { sortSide, purchase, startCraft, startRepair, cancelCraft, tradeLock, tradeConfirm, tradeCancel, tradeRespond } from '../actions.js';

const KIND = {
    ground: ['ground', 'Ground'], drop: ['drop', 'Drop'], player: ['user', 'Player'], shop: ['store', 'Shop'],
    crafting: ['craft', 'Workbench'], trade: ['trade', 'Trade'], stash: ['stash', 'Storage'],
};
const SUB = { trunk: ['trunk', 'Trunk'], glovebox: ['glovebox', 'Glovebox'], container: ['container', 'Container'] };

const isGrid = (o) => o && ['ground', 'drop', 'player', 'stash'].includes(o.kind);

// ───────────── header & footer ─────────────

let headRing = null;

export function otherHeader(head, foot) {
    const o = S.other;
    head.innerHTML = '';
    foot.innerHTML = '';
    if (!o) {
        head.append(h('div', { class: 'head-row' }, h('div', { class: 'avatar' }, icon('layers')), h('div', { class: 'head-title' }, h('div', { class: 'eyebrow' }, 'Nothing open'), h('h2', {}, '—'))));
        return;
    }
    const [ic, kindLabel] = SUB[o.sub] || KIND[o.kind] || ['box', 'Inventory'];
    let title = o.label || kindLabel;
    if (o.kind === 'trade' && o.trade) title = o.trade.partner && o.trade.partner.name || 'Trade';
    if (o.kind === 'crafting' && o.bench) title = o.bench.label || title;
    const row = h('div', { class: 'head-row' },
        h('div', { class: 'avatar' }, icon(ic)),
        h('div', { class: 'head-title' }, h('div', { class: 'eyebrow' }, kindLabel), h('h2', {}, title)));
    if (isGrid(o)) {
        headRing = headRing || ring();
        const w = weightOf(o);
        row.append(h('div', { class: 'meter' }, h('b', {}, kg(w)), h('span', {}, `of ${kg(o.maxweight)}`)), headRing);
        setRing(headRing, w, o.maxweight);
    }
    head.append(row);
    if (o.kind === 'stash' || o.kind === 'drop') {
        head.append(h('div', { class: 'tools' },
            h('span', { style: { flex: 1, color: 'var(--muted)', fontSize: '.8em' } }, o.kind === 'drop' ? 'Items on the ground despawn after a while' : ''),
            h('button', { class: 'icon-btn', title: 'Sort & stack', onclick: () => sortSide('other') }, icon('sort'))));
    }
    if (isGrid(o)) {
        let used = 0;
        for (const s of o.items.keys()) if (s <= 100) used++;
        foot.append(icon('grid'), h('span', {}, `${used} / ${o.slots} slots`), h('span', { class: 'grow' }), h('span', {}, 'Ctrl+click to move'));
    } else if (o.kind === 'shop') {
        foot.append(icon('cash'), h('span', {}, 'Click or drag to your pockets to buy'));
    } else if (o.kind === 'crafting') {
        foot.append(icon('clock'), h('span', {}, 'Stay near the bench while crafting'));
    } else if (o.kind === 'trade') {
        foot.append(icon('lock'), h('span', {}, 'Nothing moves until both sides lock and confirm'));
    }
}

// ───────────── body ─────────────

export function renderOther(body) {
    const o = S.other;
    const kind = o ? o.kind : null;
    if (body._kind !== kind || body._id !== (o && o.id)) {
        body.innerHTML = '';
        body._kind = kind;
        body._id = o && o.id;
        body._grid = null;
    }
    if (S.trade && kind !== 'trade') renderTradeBanner(body);
    else body.querySelector('.trade-banner')?.remove();

    if (!o) {
        if (!body.querySelector('.empty-note')) body.append(h('div', { class: 'empty-note' }, icon('layers'), 'Nothing nearby'));
        return;
    }
    if (isGrid(o)) {
        if (!body._grid) {
            if (kind === 'ground') body.append(h('div', { class: 'ground-hint' }, icon('drop'), 'Drag items here to drop them on the ground'));
            body._grid = h('div', { class: 'grid' });
            body.append(body._grid);
        }
        renderGrid(body._grid, o, 'other', { filter: false });
        return;
    }
    if (kind === 'shop') return renderShop(body);
    if (kind === 'crafting') return renderCrafting(body);
    if (kind === 'trade') return renderTrade(body);
}

function renderTradeBanner(body) {
    let b = body.querySelector('.trade-banner');
    if (b && b._id === S.trade.id) return;
    if (b) b.remove();
    b = h('div', { class: 'trade-banner' },
        icon('trade'),
        h('span', { class: 'grow' }, h('b', {}, S.trade.name || `Player ${S.trade.from}`), ' wants to trade'),
        h('button', { class: 'btn sm success', onclick: () => tradeRespond(S.trade.id, true) }, 'Accept'),
        h('button', { class: 'btn sm ghost', onclick: () => tradeRespond(S.trade.id, false) }, 'Decline'));
    b._id = S.trade.id;
    body.prepend(b);
}

// ───────────── shop ─────────────

function renderShop(body) {
    const o = S.other;
    body.querySelectorAll('.shop-list, .buybox').forEach((n) => n.remove());
    const list = h('div', { class: 'shop-list' });
    for (const [slot, it] of [...o.items.entries()].sort((a, b) => a[0] - b[0])) {
        const card = h('div', {
            class: `product ${S.ui.shopSel === slot ? 'sel' : ''} ${it.amount <= 0 ? 'out' : ''}`,
            'data-src': 'shop', 'data-side': 'other', 'data-slot': slot,
            onclick: () => { S.ui.shopSel = slot; S.ui.shopQty = 1; emit('ui'); },
        }, h('span', { class: 's' }, `${it.amount} left`), itemImg(it), h('div', { class: 'n' }, it.label), h('div', { class: 'p' }, money(it.price)));
        card.style.setProperty('--rar', (S.config.rarities || {})[it.rarity] || '#8fa3b8');
        list.append(card);
    }
    body.append(list);

    const sel = S.ui.shopSel && o.items.get(S.ui.shopSel);
    if (!sel) return;
    const max = clamp(sel.amount, 1, sel.unique ? 10 : 999);
    S.ui.shopQty = clamp(S.ui.shopQty, 1, max);
    const payments = arr(o.payments).length ? arr(o.payments) : ['cash'];
    if (!payments.includes(S.ui.payMethod)) S.ui.payMethod = payments[0];
    const qtyIn = h('input', { type: 'number', value: S.ui.shopQty, min: 1, max });
    const total = h('span', { class: 'total' }, money(sel.price * S.ui.shopQty));
    const setQty = (n) => { S.ui.shopQty = clamp(Math.floor(+n || 1), 1, max); qtyIn.value = S.ui.shopQty; total.textContent = money(sel.price * S.ui.shopQty); };
    qtyIn.addEventListener('input', () => setQty(qtyIn.value));
    const bal = S.player.money || {};
    body.append(h('div', { class: 'buybox' },
        h('div', { class: 'row' }, itemImg(sel), h('div', {}, h('b', {}, sel.label), h('div', { style: { color: 'var(--muted)', fontSize: '.8em' } }, `${money(sel.price)} each · ${kg(sel.weight)}`)), total),
        h('div', { class: 'row' },
            h('div', { class: 'stepper' },
                h('button', { onclick: () => setQty(S.ui.shopQty - 1) }, icon('minus')), qtyIn,
                h('button', { onclick: () => setQty(S.ui.shopQty + 1) }, icon('plus'))),
            h('button', { class: 'btn sm ghost', onclick: () => setQty(max) }, 'Max')),
        h('div', { class: 'pay' }, payments.map((m) => h('button', {
            class: S.ui.payMethod === m ? 'active' : '', onclick: () => { S.ui.payMethod = m; emit('ui'); },
        }, icon(m === 'bank' ? 'bank' : 'cash'), m, h('small', {}, money(bal[m]))))),
        h('button', { class: 'btn primary block', onclick: () => purchase(S.ui.shopSel, S.ui.shopQty, S.ui.payMethod) }, icon('check'), 'Buy'),
    ));
}

// ───────────── crafting ─────────────

function have(name) {
    let c = 0;
    for (const it of S.player.items.values()) if (it.name === name) c += it.amount;
    return c;
}

function maxCrafts(r) {
    let m = 50;
    for (const ing of arr(r.ingredients)) m = Math.min(m, Math.floor(have(ing.name) / Math.max(1, ing.amount)));
    for (const t of arr(r.tools)) if (have(t.name) < 1) m = 0;
    return m;
}

function ingChip(ing, mult = 1, tool = false) {
    const ok = have(ing.name) >= ing.amount * mult;
    return h('span', { class: `ing ${ok ? 'ok' : 'miss'} ${tool ? 'tool' : ''}` }, itemImg(ing), tool ? ing.label : `${ing.amount * mult}× ${ing.label}`);
}

function renderCrafting(body) {
    const bench = S.other.bench;
    body.innerHTML = '';
    body._grid = null;
    if (!bench) return;
    const busy = S.ui.crafting;
    body.append(h('div', { class: 'seg', style: { marginBottom: 'var(--pad)' } },
        h('button', { class: S.ui.craftTab === 'craft' ? 'active' : '', onclick: () => { S.ui.craftTab = 'craft'; emit('ui'); } }, 'Craft'),
        bench.repair ? h('button', { class: S.ui.craftTab === 'repair' ? 'active' : '', onclick: () => { S.ui.craftTab = 'repair'; emit('ui'); } }, 'Repair') : null));

    if (busy) {
        const bar = h('i', { style: { width: '0%' } });
        const left = h('b', {}, '');
        body.append(h('div', { class: 'craft-card' },
            h('div', { class: 'top' }, icon(busy.kind === 'repair' ? 'repair' : 'craft'), h('div', {}, h('b', {}, busy.kind === 'repair' ? 'Repairing…' : 'Crafting…'), h('small', {}, 'Stay close to the bench')), left),
            h('div', { class: 'progress' }, bar),
            h('button', { class: 'btn danger block', onclick: () => cancelCraft() }, icon('x'), 'Cancel')));
        const tick = () => {
            if (!S.ui.crafting || !bar.isConnected) return;
            const p = Math.min(1, (Date.now() - busy.start) / busy.duration);
            bar.style.width = `${p * 100}%`;
            left.textContent = `${Math.max(0, Math.ceil((busy.duration - (Date.now() - busy.start)) / 1000))}s`;
            requestAnimationFrame(tick);
        };
        tick();
        return;
    }

    if (S.ui.craftTab === 'repair' && bench.repair) return renderRepair(body, bench);

    const recipes = arr(bench.recipes);
    if (!recipes.length) return body.append(h('div', { class: 'empty-note' }, icon('craft'), 'No recipes here'));
    if (!S.ui.recipe || !recipes.find((r) => r.id === S.ui.recipe)) S.ui.recipe = recipes[0].id;
    const list = h('div', { class: 'recipes' });
    for (const r of recipes) {
        const can = maxCrafts(r) > 0;
        list.append(h('div', { class: `recipe ${S.ui.recipe === r.id ? 'sel' : ''} ${can ? '' : 'cant'}`, onclick: () => { S.ui.recipe = r.id; S.ui.craftQty = 1; emit('ui'); } },
            itemImg(r), h('div', { class: 't' }, h('b', {}, `${r.label}${r.amount > 1 ? ` ×${r.amount}` : ''}`), h('small', {}, `${r.time}s · ${arr(r.ingredients).length} ingredients`)),
            h('span', { class: 'ok' }, can ? 'Ready' : 'Missing')));
    }
    body.append(list);

    const r = recipes.find((x) => x.id === S.ui.recipe);
    const max = Math.max(1, maxCrafts(r));
    S.ui.craftQty = clamp(S.ui.craftQty || 1, 1, max);
    const qtyIn = h('input', { type: 'number', value: S.ui.craftQty, min: 1, max });
    const setQty = (n) => { S.ui.craftQty = clamp(Math.floor(+n || 1), 1, max); emit('ui'); };
    qtyIn.addEventListener('change', () => setQty(qtyIn.value));
    body.append(h('div', { class: 'craft-card' },
        h('div', { class: 'top' }, itemImg(r), h('div', {}, h('b', {}, r.label), h('small', {}, r.description || '')), h('span', { style: { marginLeft: 'auto', color: 'var(--muted)' } }, `${r.time * S.ui.craftQty}s`)),
        h('div', { class: 'ings' }, arr(r.ingredients).map((i) => ingChip(i, S.ui.craftQty)), arr(r.tools).map((t) => ingChip(t, 1, true))),
        h('div', { class: 'row', style: { display: 'flex', gap: '.6em', alignItems: 'center' } },
            h('div', { class: 'stepper' },
                h('button', { onclick: () => setQty(S.ui.craftQty - 1) }, icon('minus')), qtyIn,
                h('button', { onclick: () => setQty(S.ui.craftQty + 1) }, icon('plus'))),
            h('span', { style: { color: 'var(--muted)', fontSize: '.85em' } }, `= ${r.amount * S.ui.craftQty}× ${r.label}`)),
        h('button', { class: 'btn primary block', disabled: maxCrafts(r) < S.ui.craftQty, onclick: () => startCraft(r, S.ui.craftQty) }, icon('craft'), 'Craft')));
}

function renderRepair(body, bench) {
    const items = [...S.player.items.values()].filter((it) => {
        const q = quality(it);
        return !it.decay && q !== null && q < 100;
    });
    const sel = S.ui.repairSlot && S.player.items.get(S.ui.repairSlot);
    const socket = makeSlot({ side: 'repair', slot: 0, src: 'view', item: sel || null, placeholder: 'repair' });
    socket.dataset.drop = 'socket';
    body.append(h('div', { class: 'socket' }, socket),
        h('p', { class: 'empty-note', style: { padding: '.6em 0' } }, sel ? `${sel.label} · ${Math.floor(quality(sel))}%` : 'Drop a worn item in the socket, or pick one below'));
    if (items.length) {
        body.append(h('div', { class: 'recipes' }, items.map((it) =>
            h('div', { class: `recipe ${S.ui.repairSlot === it.slot ? 'sel' : ''}`, onclick: () => { S.ui.repairSlot = it.slot; emit('ui'); } },
                itemImg(it), h('div', { class: 't' }, h('b', {}, it.label), h('small', {}, `Quality ${Math.floor(quality(it))}%`))))));
    }
    const cost = arr(bench.repairCost);
    const can = sel && cost.every((c) => have(c.name) >= c.amount);
    body.append(h('div', { class: 'craft-card' },
        h('div', { class: 'ings' }, cost.map((c) => ingChip(c))),
        h('button', { class: 'btn primary block', disabled: !can, onclick: () => startRepair(S.ui.repairSlot) }, icon('repair'), `Repair (${bench.repairTime || 5}s)`)));
}

// ───────────── trade ─────────────

function renderTrade(body) {
    const t = S.other.trade;
    body.innerHTML = '';
    body._grid = null;
    if (!t) return;
    const mineItems = arr(t.mine), theirItems = arr(t.theirs);
    const mineGrid = h('div', { class: 'grid', 'data-drop': 'trade', 'data-side': 'trade-mine' });
    for (const it of mineItems) mineGrid.append(makeSlot({ side: 'trade-mine', slot: it.slot, src: 'trade', item: it }));
    if (!mineItems.length) mineGrid.append(h('div', { class: 'empty-note', style: { gridColumn: '1 / -1', padding: '.8em' } }, 'Drag items here to offer them'));
    const theirGrid = h('div', { class: 'grid' });
    for (const it of theirItems) theirGrid.append(makeSlot({ side: 'trade-theirs', slot: it.slot, src: 'peek', item: it }));
    if (!theirItems.length) theirGrid.append(h('div', { class: 'empty-note', style: { gridColumn: '1 / -1', padding: '.8em' } }, 'Nothing offered yet'));

    const both = t.myLock && t.theirLock;
    body.append(h('div', { class: 'trade' },
        h('div', { class: `trade-side mine ${t.myLock ? 'locked' : ''}` },
            h('h4', {}, icon('user'), 'Your offer', h('span', { class: `st ${t.myLock ? 'on' : ''}` }, t.myConfirm ? 'Confirmed' : t.myLock ? 'Locked' : 'Editing')),
            mineGrid),
        h('div', { class: `trade-side ${t.theirLock ? 'locked' : ''}` },
            h('h4', {}, icon('users'), (t.partner && t.partner.name) || 'Them', h('span', { class: `st ${t.theirLock ? 'on' : ''}` }, t.theirConfirm ? 'Confirmed' : t.theirLock ? 'Locked' : 'Editing')),
            theirGrid),
        h('div', { class: 'trade-actions' },
            h('button', { class: `btn ${t.myLock ? 'ghost' : 'primary'}`, style: { flex: 1 }, onclick: () => tradeLock(!t.myLock) }, icon(t.myLock ? 'unlock' : 'lock'), t.myLock ? 'Unlock' : 'Lock offer'),
            h('button', { class: 'btn success', style: { flex: 1 }, disabled: !both || t.myConfirm, onclick: () => tradeConfirm() }, icon('check'), t.myConfirm ? 'Waiting…' : 'Confirm'),
            h('button', { class: 'btn danger', onclick: () => tradeCancel() }, icon('x'))),
    ));
}
