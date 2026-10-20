// UI state: both inventories, filters, settings, favourites and optimistic moves.

const listeners = new Set();
export function onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }
export function emit(reason) { listeners.forEach((fn) => { try { fn(reason); } catch (e) { console.error(e); } }); }

export const S = {
    open: false,
    config: {
        categories: [], rarities: {}, equip: [], hotbar: 5, maxSlots: 40,
        theme: {}, keys: { Open: 'TAB', Wheel: 'F2' },
    },
    player: { items: new Map(), slots: 40, maxweight: 120000, money: { cash: 0, bank: 0 }, name: '', id: 0 },
    other: null,
    ui: {
        search: '', category: 'all', amountMode: 'all', amountValue: 1,
        layout: 'wide', tab: 'me', gearOpen: false,
        craftTab: 'craft', recipe: null, shopSel: null, shopQty: 1, payMethod: 'cash',
        crafting: null,  // { kind, until, duration }
    },
    trade: null,         // incoming request { id, from, name }
    pendingPush: null,   // pushes that arrived while moves were in flight
};

// ───────────── settings (per viewer) ─────────────
const DEFAULTS = { scale: 1, accent: null, motion: true, sound: true, camera: true, tooltips: true };
function load(key, fallback) {
    try { const v = localStorage.getItem(key); return v ? JSON.parse(v) : fallback; } catch (e) { return fallback; }
}
function save(key, v) { try { localStorage.setItem(key, JSON.stringify(v)); } catch (e) { /* storage blocked */ } }

export const settings = { ...DEFAULTS, ...load('mz-inv-settings', {}) };
export function setSetting(k, v) { settings[k] = v; save('mz-inv-settings', settings); emit('settings'); }

export const favs = new Set(load('mz-inv-favs', []));
export function toggleFav(name) {
    if (favs.has(name)) favs.delete(name); else favs.add(name);
    save('mz-inv-favs', [...favs]);
    emit('items');
}

// ───────────── inventories ─────────────
/** Lua sends empty tables as {} — always get an array. */
export const arr = (v) => (Array.isArray(v) ? v : v && typeof v === 'object' ? Object.values(v) : []);

const toMap = (list) => {
    const m = new Map();
    for (const it of arr(list)) if (it && it.slot != null) m.set(+it.slot, it);
    return m;
};

export function setPlayer(p) {
    if (!p) return;
    S.player = { ...S.player, ...p, items: toMap(p.items) };
}
export function setOther(o) {
    S.other = o ? { ...o, items: toMap(o.items) } : null;
}

export function side(name) { return name === 'player' ? S.player : S.other; }

export function weightOf(inv) {
    let w = 0;
    if (!inv || !inv.items) return 0;
    for (const it of inv.items.values()) w += (it.weight || 0) * (it.amount || 1);
    return w;
}

export function capacity(inv) { return { slots: inv.slots || 0, maxweight: inv.maxweight || 0 }; }

export function isEquipSlot(slot) { return S.config.equip.some((e) => e.slot === +slot); }
export function equipDef(slot) { return S.config.equip.find((e) => e.slot === +slot); }

export function canEquip(item, slot) {
    const e = equipDef(slot);
    if (!e || !item) return false;
    if (item.equip === e.id) return true;
    const accepts = Array.isArray(e.accepts) ? e.accepts : Object.values(e.accepts || {});
    return accepts.includes(item.name) || accepts.includes(item.type);
}

/** Live quality: decaying items are recomputed from info.created so bars move while open. */
export function quality(item) {
    if (!item) return null;
    if (item.decay && item.info && item.info.created) {
        const q = 100 - ((Date.now() / 1000 - item.info.created) / (item.decay * 3600)) * 100;
        return Math.max(0, Math.min(100, q));
    }
    const q = item.info && item.info.quality;
    return typeof q === 'number' ? Math.max(0, Math.min(100, q)) : null;
}

/** Amount to move given the toolbar mode and modifier keys. */
export function moveAmount(item, { shift = false, ctrl = false } = {}) {
    if (!item) return 0;
    const n = item.amount || 1;
    if (shift) return Math.max(1, Math.floor(n / 2));
    if (ctrl) return 1;
    switch (S.ui.amountMode) {
        case 'one': return 1;
        case 'half': return Math.max(1, Math.floor(n / 2));
        case 'custom': return Math.max(1, Math.min(n, S.ui.amountValue || 1));
        default: return n;
    }
}

// Optimistic local move so the UI reacts instantly; the server response replaces it.
export function optimisticMove(fromSide, fromSlot, toSide, toSlot, amount) {
    const A = side(fromSide), B = side(toSide);
    if (!A || !B || !A.items) return;
    const item = A.items.get(+fromSlot);
    if (!item) return;
    const target = B.items.get(+toSlot);
    amount = Math.min(amount, item.amount);
    if (!target) {
        if (amount === item.amount) { A.items.delete(+fromSlot); B.items.set(+toSlot, { ...item, slot: +toSlot }); }
        else { item.amount -= amount; B.items.set(+toSlot, { ...item, amount, slot: +toSlot }); }
    } else if (target.name === item.name && !item.unique) {
        target.amount += amount;
        item.amount -= amount;
        if (item.amount <= 0) A.items.delete(+fromSlot);
    } else if (amount === item.amount) {
        A.items.set(+fromSlot, { ...target, slot: +fromSlot });
        B.items.set(+toSlot, { ...item, slot: +toSlot });
    }
}
