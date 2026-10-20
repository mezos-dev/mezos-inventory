// Entry point: message router, gestures → actions, keyboard, heartbeat.

import { IS_GAME, post, inFlight } from './bridge.js';
import { $, h, icon, toast, sfx, modal, closeTopModal, modalOpen, pick, itemImg } from './ui.js';
import { S, settings, onChange, emit, setPlayer, setOther, side, moveAmount, isEquipSlot, canEquip, quality, favs, toggleFav, arr } from './state.js';
import { initDrag, cancel as cancelDrag, isDragging } from './drag.js';
import { initTooltip, hideTip, pinTip } from './tooltip.js';
import { mount, render, applyLayout, focusSearch } from './views/inventory.js';
import { openRadial, closeRadial, radialOpen } from './views/radial.js';
import { hotbar, hotbarPulse, itembox, required, wheel, wheelOpen } from './views/overlays.js';
import { applySettings } from './views/settings.js';
import * as A from './actions.js';

// ───────────── item lookup for any UI source ─────────────

function getItem(src) {
    if (!src) return null;
    if (src.side === 'player') return S.player.items.get(src.slot) || null;
    if (src.side === 'other') return S.other && S.other.items ? S.other.items.get(src.slot) || null : null;
    if (src.side === 'trade-mine' || src.side === 'trade-theirs') {
        const t = S.other && S.other.trade;
        const list = t ? arr(src.side === 'trade-mine' ? t.mine : t.theirs) : [];
        return list.find((it) => +it.slot === +src.slot) || null;
    }
    if (src.side === 'repair') return S.player.items.get(S.ui.repairSlot) || null;
    return null;
}

const tradeActive = () => S.other && S.other.kind === 'trade';

// ───────────── context menu ─────────────

function contextActions(src, item) {
    const acts = [];
    if (src.kind === 'shop') {
        acts.push({ id: 'buy1', label: 'Buy 1', icon: 'cash', disabled: item.amount <= 0 });
        acts.push({ id: 'buyx', label: 'Buy…', icon: 'plus', disabled: item.amount <= 0 });
        acts.push({ id: 'inspect', label: 'Inspect', icon: 'eye' });
        return acts;
    }
    if (src.kind === 'trade') {
        acts.push({ id: 'unoffer', label: 'Remove', icon: 'x', danger: true });
        acts.push({ id: 'inspect', label: 'Inspect', icon: 'eye' });
        return acts;
    }
    if (src.side === 'other') {
        acts.push({ id: 'take', label: 'Take', icon: 'move' });
        if (!item.unique && item.amount > 1) acts.push({ id: 'split', label: 'Split', icon: 'split' });
        acts.push({ id: 'inspect', label: 'Inspect', icon: 'eye' });
        return acts;
    }
    // own pockets / equipment
    const equipped = isEquipSlot(src.slot);
    const usable = item.useable || item.type === 'weapon' || item.container || item.backpack;
    if (item.container) acts.push({ id: 'use', label: 'Open', icon: 'open' });
    else if (usable && !item.backpack) acts.push({ id: 'use', label: item.type === 'weapon' ? 'Equip weapon' : 'Use', icon: 'use', disabled: quality(item) === 0 && !!item.decay });
    const equipable = equipped || (S.config.equip || []).some((e) => canEquip(item, e.slot));
    if (equipable) acts.push({ id: 'equip', label: equipped ? 'Unequip' : 'Equip', icon: equipped ? 'unequip' : 'equip' });
    if (tradeActive()) acts.push({ id: 'offer', label: 'Offer', icon: 'trade', disabled: item.noTrade });
    else if (A.otherIsGrid() && S.other.kind !== 'ground') acts.push({ id: 'move', label: 'Move', icon: 'move' });
    acts.push({ id: 'give', label: 'Give', icon: 'give', disabled: item.noGive });
    if (!item.unique && item.amount > 1) acts.push({ id: 'split', label: 'Split', icon: 'split' });
    acts.push({ id: 'drop', label: 'Drop', icon: 'drop', danger: true, disabled: item.noDrop });
    if (item.type === 'weapon') acts.push({ id: 'attach', label: 'Attachments', icon: 'attach' });
    if (!equipped) acts.push({ id: 'bind', label: 'Hotbar', icon: 'hotkey' });
    acts.push({ id: 'fav', label: favs.has(item.name) ? 'Unfavourite' : 'Favourite', icon: 'star' });
    acts.push({ id: 'inspect', label: 'Inspect', icon: 'eye' });
    return acts.slice(0, 10);
}

async function runAction(id, src, item, x, y) {
    switch (id) {
        case 'use': return A.useItem(src.slot);
        case 'equip': return A.equipItem(src.slot);
        case 'give': return A.giveItem(src.slot);
        case 'split': return A.splitItem(src);
        case 'drop': return A.dropItem(src.slot);
        case 'move':
        case 'take': return A.quickMove(src, moveAmount(item));
        case 'offer': return A.tradeOffer(src.slot, moveAmount(item));
        case 'unoffer': return A.tradeOffer(src.slot, 0);
        case 'fav': return toggleFav(item.name);
        case 'inspect': return pinTip(item, x, y);
        case 'attach': return attachments(src.slot);
        case 'bind': {
            const n = await pick({ title: 'Bind to hotbar', ic: 'hotkey', items: Array.from({ length: S.config.hotbar || 5 }, (_, i) => ({ id: i + 1, label: `Slot ${i + 1}`, sub: (S.player.items.get(i + 1) || {}).label || 'Empty' })) });
            if (n) A.bindHotbar(src.slot, n.id);
            return;
        }
        case 'buy1': return A.purchase(src.slot, 1, S.ui.payMethod);
        case 'buyx': S.ui.shopSel = src.slot; S.ui.shopQty = 1; return emit('ui');
    }
}

// ───────────── weapon attachments ─────────────

async function attachments(slot) {
    const res = await post('attachments', { slot });
    if (!res || !res.ok) return toast('No attachment data', 'error');
    modal((box, close) => {
        const draw = (list) => {
            box.innerHTML = '';
            const item = S.player.items.get(slot);
            box.append(h('h3', {}, icon('attach'), `${item ? item.label : 'Weapon'} attachments`));
            const l = arr(list);
            if (!res.available) box.append(h('p', {}, 'qb-weapons is not running.'));
            else if (!l.length) box.append(h('p', {}, 'No attachments installed.'));
            box.append(h('div', { class: 'att-list' }, l.map((a) => h('div', { class: 'att' }, itemImg(a), h('b', {}, a.label),
                h('button', {
                    class: 'btn sm danger', onclick: async () => {
                        const r = await post('removeAttachment', { slot, attachment: a.attachment });
                        if (r && r.ok) { sfx('drop'); draw(r.list); } else toast('Could not remove attachment', 'error');
                    },
                }, 'Remove')))));
            box.append(h('div', { class: 'row end' }, h('button', { class: 'btn primary', onclick: () => close() }, 'Done')));
        };
        draw(res.list);
    });
}

// ───────────── drag wiring ─────────────

initDrag({
    getItem,
    canDrag: (src, item) => ['grid', 'equip', 'shop', 'trade'].includes(src.kind) && !(src.kind === 'shop' && item.amount <= 0),
    initialAmount: (item, mods, src) => (src && src.kind === 'shop' ? 1 : moveAmount(item, mods)),
    canDrop: (src, item, dst) => {
        if (dst.kind === 'trade') return src.side === 'player' && src.kind !== 'trade' ? !item.noTrade : null;
        if (dst.kind === 'socket') return src.side === 'player' ? (quality(item) !== null && !item.decay) : null;
        if (dst.kind === 'ground') return src.side === 'player' && src.kind !== 'trade' ? !item.noDrop : null;
        if (src.kind === 'trade') return dst.side === 'player' ? true : null;
        if (src.kind === 'shop') return dst.side === 'player' && !isEquipSlot(dst.slot) ? true : null;
        return A.dropVerdict(src, item, dst);
    },
    hint: (src, item, dst) => {
        if (dst.kind === 'ground') return 'Drop on ground';
        if (dst.kind === 'trade') return 'Offer';
        if (dst.kind === 'socket') return 'Repair';
        if (src.kind === 'shop') return 'Buy';
        if (dst.kind === 'slot' && isEquipSlot(dst.slot)) return 'Equip';
        const t = side(dst.side) && side(dst.side).items && side(dst.side).items.get(dst.slot);
        if (t && t.name === item.name && !item.unique) return 'Stack';
        if (t) return 'Swap';
        return null;
    },
    onDrop: (src, item, dst, amount) => {
        if (dst.kind === 'ground') return A.dropItem(src.slot, amount);
        if (dst.kind === 'trade') return A.tradeOffer(src.slot, amount);
        if (dst.kind === 'socket') { S.ui.repairSlot = src.slot; return emit('ui'); }
        if (src.kind === 'trade') return A.tradeOffer(src.slot, 0);
        if (src.kind === 'shop') return A.purchase(src.slot, amount, S.ui.payMethod);
        return A.moveItem({ side: src.side, slot: src.slot }, { side: dst.side, slot: dst.slot }, amount);
    },
    onReject: () => post('sound', { name: 'fail' }),
    onClick: (src, item, e) => {
        if (e.ctrlKey) {
            if (tradeActive() && src.side === 'player') return A.tradeOffer(src.slot, moveAmount(item));
            if (src.kind === 'grid' || src.kind === 'equip') return A.quickMove(src, moveAmount(item));
        }
        if (e.altKey && src.side === 'player') return A.useItem(src.slot);
        if (e.shiftKey && (src.kind === 'grid')) return A.splitItem(src);
        if (src.kind === 'trade') return A.tradeOffer(src.slot, 0);
    },
    onDouble: (src, item) => {
        if (src.side === 'player' && (src.kind === 'grid' || src.kind === 'equip')) {
            if (item.backpack || (isEquipSlot(src.slot) && !item.useable && item.type !== 'weapon')) return A.equipItem(src.slot);
            return A.useItem(src.slot);
        }
        if (src.side === 'other' && src.kind === 'grid') return A.quickMove(src, moveAmount(item));
        if (src.kind === 'shop') return A.purchase(src.slot, 1, S.ui.payMethod);
    },
    onContext: (src, item, x, y) => {
        hideTip(true);
        openRadial(x, y, item, contextActions(src, item), (id) => runAction(id, src, item, x, y));
    },
    onDragStart: () => { hideTip(true); closeRadial(); },
    onDragEnd: () => emit('dragEnd'),
});
initTooltip(getItem);

// ───────────── open / close ─────────────

function openInventory(msg) {
    S.config = { ...S.config, ...(msg.config || {}) };
    applySettings(S.config.theme || {});
    setPlayer(msg.player);
    setOther(msg.other || null);
    S.trade = msg.trade || null;
    S.pendingPush = null;
    S.ui.crafting = null;
    S.ui.shopSel = null;
    S.ui.repairSlot = null;
    S.ui.tab = msg.other && msg.other.kind !== 'ground' ? (S.ui.layout === 'narrow' ? 'other' : 'me') : 'me';
    const first = !S.open;
    S.open = true;
    $('#app').classList.remove('hidden');
    $('#hotbar').classList.add('hidden');
    if (first) mount();
    applyLayout();
    render('open');
    if (first) sfx('open');
}

function closeInventory(notify) {
    if (!S.open) return;
    S.open = false;
    cancelDrag();
    closeRadial();
    hideTip(true);
    while (closeTopModal()) { /* close all */ }
    $('#app').classList.add('hidden');
    S.ui.crafting = null;
    S.ui.search = '';
    if (notify) post('close');
}

onChange((reason) => {
    if (reason === 'requestClose') return closeInventory(true);
    if (reason === 'trade' && S.open) return render('trade');
    if (S.open) render(reason);
});

// ───────────── messages from Lua ─────────────

const handlers = {
    open: openInventory,
    close: () => closeInventory(false),
    player: (m) => {
        if (inFlight > 0 || isDragging()) { S.pendingPush = { ...(S.pendingPush || {}), player: m.player }; return; }
        setPlayer(m.player);
        emit('items');
    },
    other: (m) => {
        if (inFlight > 0 || isDragging()) { S.pendingPush = { ...(S.pendingPush || {}), other: m.other, hasOther: true }; return; }
        setOther(m.other || null);
        if (S.ui.layout === 'narrow' && m.other && m.other.kind !== 'ground' && S.ui.tab === 'me' && m.other.kind === 'trade') S.ui.tab = 'other';
        emit('items');
    },
    toast: (m) => toast(m.text, m.type === 'primary' ? 'info' : m.type),
    itembox: (m) => itembox(m.item, m.type, m.amount),
    hotbar: (m) => { if (!S.open) hotbar(m.show, m.items); },
    hotbarPulse: (m) => { if (!S.open) hotbarPulse(m.slot, m.items); },
    required: (m) => required(m.items, m.show),
    wheel: (m) => {
        if (m.config) S.config = { ...S.config, ...m.config };
        if (m.show) applySettings(S.config.theme || {});
        wheel(m.show, m.player);
    },
    tradeIncoming: (m) => { S.trade = m.trade || null; emit('trade'); },
};

window.addEventListener('message', (e) => {
    const m = e.data;
    if (!m || typeof m !== 'object' || !handlers[m.action]) return;
    try { handlers[m.action](m); } catch (err) { console.error('[mezos-inventory]', m.action, err); }
});

// pushes that arrived during a drag get applied when it ends
onChange((reason) => { if (reason === 'dragEnd') A.flushPending(); });

// ───────────── keyboard ─────────────

let hovered = null;
document.addEventListener('pointerover', (e) => {
    const el = e.target.closest('[data-src]');
    hovered = el ? { side: el.dataset.side, slot: +el.dataset.slot, kind: el.dataset.src } : null;
});

document.addEventListener('keydown', (e) => {
    const typing = e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA');
    if (wheelOpen()) {
        if (e.key === 'Escape' || e.key === (S.config.keys && S.config.keys.Wheel)) { e.preventDefault(); post('wheelClose'); wheel(false); }
        return;
    }
    if (!S.open) return;
    if (e.key === 'Escape') {
        e.preventDefault();
        if (isDragging()) return cancelDrag();
        if (radialOpen()) return closeRadial();
        if (modalOpen()) return closeTopModal();
        if (!$('#tooltip').classList.contains('hidden')) hideTip(true);
        return closeInventory(true);
    }
    if (e.key === 'Tab' || (!typing && (e.key || '').toUpperCase() === (S.config.keys && S.config.keys.Open || 'TAB'))) {
        e.preventDefault();
        if (!modalOpen()) closeInventory(true);
        return;
    }
    if ((e.ctrlKey || e.metaKey) && (e.key === 'f' || e.key === 'F')) { e.preventDefault(); return focusSearch(); }
    if (typing) return;
    const n = parseInt(e.key, 10);
    if (n >= 1 && n <= (S.config.hotbar || 5) && hovered && hovered.side === 'player' && hovered.kind === 'grid') {
        e.preventDefault();
        return A.bindHotbar(hovered.slot, n);
    }
});

// ───────────── heartbeat (lets Lua release focus if the UI ever dies) ─────────────

setInterval(() => { if (S.open || wheelOpen()) post('alive'); }, 2000);
window.addEventListener('error', (e) => console.error('[mezos-inventory] ui error', e.message));

// ───────────── dev mode ─────────────
if (!IS_GAME) {
    document.body.classList.add('dev');
    import('./dev.js');
}
