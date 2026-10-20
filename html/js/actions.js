// Everything the player can do. Optimistic where safe; the newest server response always wins.

import { server, post, inFlight } from './bridge.js';
import { S, setPlayer, setOther, optimisticMove, emit, side, isEquipSlot, canEquip, arr } from './state.js';
import { toast, sfx, askAmount, pick } from './ui.js';

const ERR = {
    weight: 'Too heavy', slots: 'Not enough space', equip: 'That doesn\'t fit there',
    nest: 'Containers can\'t go inside containers', containerOpen: 'Close that container first',
    backpack: 'Empty the backpack slots first', tooFar: 'You are too far away', access: 'Not accessible',
    swapPartial: 'Can\'t swap part of a stack', full: 'That stack is full', noDrop: 'This item can\'t be dropped',
    noGive: 'This item can\'t be given away', noTrade: 'This item can\'t be traded', targetFull: 'They can\'t carry that',
    targetWeight: 'That\'s too heavy for them', target: 'No valid player nearby', stock: 'Out of stock',
    money: 'You can\'t afford this', missingIngredients: 'Missing ingredients', missingTools: 'Missing tools',
    noRepair: 'This item doesn\'t need repairs', spoiled: 'This item has spoiled', notUsable: 'You can\'t use this',
    busy: 'You are busy', tradeBusy: 'That player is busy', notLocked: 'Both players must lock first',
    changed: 'The trade changed — lock again', item: 'Unknown item',
};

let seq = 0;

export function applySnapshot(res) {
    if (!res) return;
    if (res.player) setPlayer(res.player);
    if (Object.prototype.hasOwnProperty.call(res, 'other')) setOther(res.other || null);
    emit('items');
}

export function flushPending() {
    if (inFlight > 0 || !S.pendingPush) return;
    const p = S.pendingPush;
    S.pendingPush = null;
    if (p.player) setPlayer(p.player);
    if (p.hasOther) setOther(p.other);
    emit('items');
}

/** Run a server action. optimistic() mutates local state first; the response snapshot replaces it. */
export async function call(name, arg, { optimistic, quiet } = {}) {
    const my = ++seq;
    if (optimistic) { optimistic(); emit('items'); }
    const res = (await server(name, arg)) || { ok: false };
    if (res.ok === false && !quiet) {
        const msg = ERR[res.err];
        if (msg) toast(msg, 'error');
        sfx('error');
    }
    if (my === seq) applySnapshot(res);
    flushPending();
    return res;
}

const kindOf = (s) => (s === 'player' ? 'player' : S.other && S.other.kind);
export const otherIsGrid = () => !!S.other && ['stash', 'drop', 'player', 'ground'].includes(S.other.kind);

// ───────────── moves ─────────────

export function firstFree(inv, exclude) {
    for (let i = 1; i <= inv.slots; i++) if (!inv.items.has(i) && i !== exclude) return i;
    return null;
}

export function moveItem(src, dst, amount) {
    if (src.side === dst.side && src.slot === dst.slot) return;
    const from = side(src.side);
    const item = from && from.items.get(src.slot);
    if (!item) return;
    const toGround = dst.side === 'other' && S.other && S.other.kind === 'ground';
    return call('move', {
        from: src.side, fromSlot: src.slot, to: dst.side, toSlot: dst.slot, amount, name: item.name,
    }, { optimistic: toGround ? null : () => optimisticMove(src.side, src.slot, dst.side, dst.slot, amount) });
}

export function quickMove(src, amount) {
    if (!otherIsGrid()) return;
    const item = side(src.side).items.get(src.slot);
    if (!item) return;
    return call('quickMove', { from: src.side, slot: src.slot, amount: amount ?? item.amount });
}

export async function splitItem(src) {
    const inv = side(src.side);
    const item = inv && inv.items.get(src.slot);
    if (!item || item.amount < 2) return;
    const free = firstFree(inv);
    if (!free) return toast(ERR.slots, 'error');
    const n = await askAmount({ title: `Split ${item.label}`, max: item.amount - 1, value: Math.floor(item.amount / 2), confirm: 'Split' });
    if (!n) return;
    return moveItem(src, { side: src.side, slot: free }, n);
}

export function useItem(slot) {
    sfx('tick');
    return call('use', { slot });
}

export async function dropItem(slot, amount) {
    const item = S.player.items.get(slot);
    if (!item) return;
    if (amount == null && item.amount > 1) {
        amount = await askAmount({ title: `Drop ${item.label}`, max: item.amount, value: item.amount, confirm: 'Drop', ic: 'drop' });
        if (!amount) return;
    }
    return call('drop', { slot, amount: amount ?? item.amount });
}

export async function giveItem(slot) {
    const item = S.player.items.get(slot);
    if (!item) return;
    const near = arr(await post('nearby', { range: 'give' }));
    if (!near.length) return toast('No one nearby', 'error');
    let target = near[0];
    if (near.length > 1) {
        target = await pick({ title: 'Give to', items: near.map((p) => ({ ...p, label: p.name || `Player ${p.id}`, sub: `#${p.id} · ${p.dist} m` })), ic: 'give' });
        if (!target) return;
    }
    let amount = item.amount;
    if (item.amount > 1) {
        amount = await askAmount({ title: `Give ${item.label}`, max: item.amount, value: item.amount, confirm: 'Give', ic: 'give' });
        if (!amount) return;
    }
    return call('give', { slot, amount, target: target.id });
}

export function equipItem(slot) {
    return call('equip', { slot });
}

export function bindHotbar(slot, n) {
    if (slot === n) return;
    const item = S.player.items.get(slot);
    if (!item) return;
    return moveItem({ side: 'player', slot }, { side: 'player', slot: n }, item.amount);
}

export function sortSide(which) {
    sfx('tick');
    return call('sort', { side: which });
}

/** Client-side pre-check mirroring the server rules, for drop target colouring. */
export function dropVerdict(src, item, dst) {
    if (dst.kind === 'ground') return src.side === 'player';
    if (dst.kind !== 'slot') return null;
    const to = side(dst.side);
    if (!to) return null;
    if (dst.side === 'other' && !otherIsGrid()) return null;
    if (src.kind === 'shop') return dst.side === 'player' && !isEquipSlot(dst.slot) ? true : false;
    if (isEquipSlot(dst.slot)) {
        if (kindOf(dst.side) !== 'player') return false;
        return canEquip(item, dst.slot);
    }
    const target = to.items.get(dst.slot);
    if (target && src.side === dst.side && src.slot === dst.slot) return null;
    if (target && isEquipSlot(src.slot) && !(target.name === item.name) && !canEquip(target, src.slot)) return false;
    if (dst.slot > to.slots && !(target)) return false;
    if (S.other && S.other.sub === 'container' && dst.side === 'other' && item.container) return false;
    return true;
}

// ───────────── shop ─────────────

export function purchase(slot, amount, method) {
    const item = S.other && S.other.items.get(slot);
    if (!item) return;
    sfx('buy');
    return call('purchase', { slot, amount, method, name: item.name });
}

// ───────────── crafting ─────────────

let craftTimer = null;

export async function startCraft(recipe, times) {
    const res = await call('craftStart', { recipe: recipe.id, times });
    if (!res.ok) return;
    runTimer('craft', res.duration, () => call('craftFinish', null));
}

export async function startRepair(slot) {
    const res = await call('repairStart', { slot });
    if (!res.ok) return;
    runTimer('repair', res.duration, () => call('repairFinish', null));
}

function runTimer(kind, duration, done) {
    clearTimeout(craftTimer);
    S.ui.crafting = { kind, start: Date.now(), duration };
    emit('craft');
    craftTimer = setTimeout(async () => {
        const res = await done();
        S.ui.crafting = null;
        emit('craft');
        if (res && res.ok) sfx('buy');
    }, duration + 150);
}

export function cancelCraft() {
    clearTimeout(craftTimer);
    if (!S.ui.crafting) return;
    S.ui.crafting = null;
    emit('craft');
    call('craftCancel', null, { quiet: true });
}

// ───────────── trade ─────────────

export async function requestTrade() {
    const near = arr(await post('nearby', { range: 'trade' }));
    if (!near.length) return toast('No one nearby', 'error');
    const target = near.length === 1 ? near[0] : await pick({
        title: 'Trade with', ic: 'trade',
        items: near.map((p) => ({ ...p, label: p.name || `Player ${p.id}`, sub: `#${p.id} · ${p.dist} m` })),
    });
    if (!target) return;
    return call('tradeRequest', { target: target.id });
}

export function tradeOffer(slot, amount) { return call('tradeOffer', { slot, amount }); }
export function tradeLock(lock) { return call('tradeLock', lock); }
export function tradeConfirm() { return call('tradeConfirm', null); }
export function tradeCancel() { post('tradeCancel'); }
export function tradeRespond(id, accept) { S.trade = null; emit('trade'); post('tradeRespond', { id, accept }); }
