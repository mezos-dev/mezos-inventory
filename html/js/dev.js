// Browser-only mock so the UI can be developed without the game.
// Open html/index.html?mode=stash | shop | crafting | trade | player | ground

import { setMock } from './bridge.js';

const params = new URLSearchParams(location.search);
const mode = params.get('mode') || 'stash';

const cfg = {
    theme: { accent: '#22e4ff', accent2: '#a855ff', serverName: 'MEZOS', sounds: true },
    categories: [
        { id: 'weapon', label: 'Weapons' }, { id: 'ammo', label: 'Ammo' }, { id: 'food', label: 'Food' },
        { id: 'drink', label: 'Drinks' }, { id: 'medical', label: 'Medical' }, { id: 'tool', label: 'Tools' },
        { id: 'drug', label: 'Drugs' }, { id: 'valuable', label: 'Valuables' }, { id: 'misc', label: 'Misc' },
    ],
    rarities: { common: '#8fa3b8', uncommon: '#2bffb1', rare: '#22a8ff', epic: '#a855ff', legendary: '#ffb02e' },
    equip: [
        { id: 'backpack', slot: 101, label: 'Backpack', icon: 'backpack', accepts: [] },
        { id: 'armor', slot: 102, label: 'Armor', icon: 'shield', accepts: ['armor', 'heavyarmor'] },
        { id: 'phone', slot: 103, label: 'Phone', icon: 'phone', accepts: ['phone'] },
        { id: 'radio', slot: 104, label: 'Radio', icon: 'radio', accepts: ['radio'] },
        { id: 'primary', slot: 105, label: 'Primary', icon: 'rifle', accepts: ['weapon'] },
        { id: 'secondary', slot: 106, label: 'Secondary', icon: 'pistol', accepts: ['weapon'] },
    ],
    hotbar: 5, maxSlots: 40, camera: true, keys: { Open: 'TAB', Hotbar: 'Z', Wheel: 'F2' },
};

const now = Date.now() / 1000;
const D = {
    water_bottle: { label: 'Bottle of Water', weight: 500, image: 'water_bottle.png', category: 'drink', rarity: 'common', useable: true, decay: 720 },
    sandwich: { label: 'Sandwich', weight: 200, image: 'sandwich.png', category: 'food', rarity: 'common', useable: true, decay: 72 },
    weapon_pistol: { label: 'Walther P99', weight: 1000, image: 'weapon_pistol.png', category: 'weapon', rarity: 'uncommon', unique: true, type: 'weapon' },
    weapon_assaultrifle: { label: 'Assault Rifle', weight: 1000, image: 'weapon_assaultrifle.png', category: 'weapon', rarity: 'rare', unique: true, type: 'weapon' },
    lockpick: { label: 'Lockpick', weight: 300, image: 'lockpick.png', category: 'tool', rarity: 'common', useable: true },
    phone: { label: 'Phone', weight: 700, image: 'phone.png', category: 'tool', rarity: 'common', unique: true, equip: 'phone' },
    radio: { label: 'Radio', weight: 2000, image: 'radio.png', category: 'tool', rarity: 'common', unique: true, useable: true, equip: 'radio' },
    armor: { label: 'Armor', weight: 5000, image: 'armor.png', category: 'medical', rarity: 'common', useable: true, equip: 'armor' },
    bandage: { label: 'Bandage', weight: 100, image: 'bandage.png', category: 'medical', rarity: 'common', useable: true },
    goldbar: { label: 'Gold Bar', weight: 7000, image: 'goldbar.png', category: 'valuable', rarity: 'legendary' },
    pistol_ammo: { label: 'Pistol ammo', weight: 200, image: 'pistol_ammo.png', category: 'ammo', rarity: 'common', useable: true },
    id_card: { label: 'ID Card', weight: 0, image: 'id_card.png', category: 'misc', rarity: 'common', unique: true, useable: true, noTrade: true },
    metalscrap: { label: 'Metal Scrap', weight: 100, image: 'metalscrap.png', category: 'misc', rarity: 'common' },
    plastic: { label: 'Plastic', weight: 100, image: 'plastic.png', category: 'misc', rarity: 'common' },
    rubber: { label: 'Rubber', weight: 100, image: 'rubber.png', category: 'misc', rarity: 'common' },
    rolex: { label: 'Golden Watch', weight: 1500, image: 'rolex.png', category: 'valuable', rarity: 'rare' },
    markedbills: { label: 'Marked Money', weight: 1000, image: 'markedbills.png', category: 'valuable', rarity: 'uncommon', unique: true },
    coffee: { label: 'Coffee', weight: 200, image: 'coffee.png', category: 'drink', rarity: 'common', useable: true, decay: 48 },
    backpack_small: { label: 'Small Backpack', weight: 1200, image: 'backpack_small.svg', category: 'misc', rarity: 'uncommon', unique: true, equip: 'backpack', backpack: { slots: 10, weight: 25000 } },
    wallet: { label: 'Wallet', weight: 150, image: 'wallet.svg', category: 'valuable', rarity: 'common', unique: true, container: { slots: 6, weight: 2000 } },
    mz_repairkit: { label: 'Field Repair Kit', weight: 1500, image: 'mz_repairkit.svg', category: 'tool', rarity: 'rare' },
};

const mk = (name, amount, slot, info = {}) => ({ name, amount, slot, info, description: 'Mock description for ' + D[name].label, type: 'item', ...D[name] });

const player = {
    name: 'Mezo Rider', id: 7, money: { cash: 4250, bank: 186400 }, slots: 50, maxweight: 145000,
    items: [
        mk('weapon_pistol', 1, 1, { serie: '12ABC3DE456FGHI', quality: 86, ammo: 24 }),
        mk('water_bottle', 6, 2, { created: now - 3600 * 200 }),
        mk('sandwich', 3, 3, { created: now - 3600 * 60 }),
        mk('bandage', 10, 4),
        mk('lockpick', 4, 5),
        mk('pistol_ammo', 12, 7),
        mk('goldbar', 2, 9),
        mk('rolex', 1, 12),
        mk('metalscrap', 40, 14), mk('plastic', 35, 15), mk('rubber', 12, 16),
        mk('id_card', 1, 18, { citizenid: 'ABC12345', firstname: 'Mezo', lastname: 'Rider', birthdate: '1995-04-12', nationality: 'LS', gender: 0 }),
        mk('markedbills', 1, 20, { worth: 8200 }),
        mk('coffee', 2, 22, { created: now - 3600 * 46 }),
        mk('wallet', 1, 23),
        mk('mz_repairkit', 2, 24),
        mk('weapon_assaultrifle', 1, 105, { serie: '88XYZ1AB222CDEF', quality: 41, ammo: 60 }),
        mk('phone', 1, 103),
        mk('backpack_small', 1, 101),
        mk('armor', 2, 102),
    ],
};

let other;
if (mode === 'shop') {
    other = {
        kind: 'shop', id: 'shop-247', label: '24/7 Supermarket', slots: 6, payments: ['cash', 'bank'],
        items: ['water_bottle', 'sandwich', 'coffee', 'bandage', 'lockpick', 'wallet'].map((n, i) => ({ ...mk(n, 25 - i * 4, i + 1), price: [4, 6, 3, 12, 80, 45][i] })),
    };
} else if (mode === 'crafting') {
    const ing = (name, amount) => ({ name, amount, label: D[name].label, image: D[name].image });
    other = {
        kind: 'crafting', id: 'bench-1', label: 'Public Workbench',
        bench: {
            index: 1, label: 'Public Workbench', repair: true, repairTime: 6, repairCost: [ing('mz_repairkit', 1)],
            recipes: [
                { id: 'lockpick', item: 'lockpick', label: 'Lockpick', image: 'lockpick.png', amount: 2, time: 5, ingredients: [ing('metalscrap', 6), ing('plastic', 4)], tools: [] },
                { id: 'bandage', item: 'bandage', label: 'Bandage', image: 'bandage.png', amount: 3, time: 4, ingredients: [ing('plastic', 2), ing('rubber', 1)], tools: [] },
                { id: 'backpack_small', item: 'backpack_small', label: 'Small Backpack', image: 'backpack_small.svg', amount: 1, time: 12, ingredients: [ing('rubber', 10), ing('plastic', 12)], tools: [ing('lockpick', 1)] },
                { id: 'goldbar', item: 'goldbar', label: 'Gold Bar', image: 'goldbar.png', amount: 1, time: 30, ingredients: [ing('rolex', 4)], tools: [] },
            ],
        },
    };
} else if (mode === 'trade') {
    other = {
        kind: 'trade', id: 'trade-T1', label: 'Trade',
        trade: { id: 'T1', state: 'active', partner: { id: 12, name: 'Nova Kade' }, mine: [mk('goldbar', 1, 9)], theirs: [mk('weapon_assaultrifle', 1, 3, { serie: 'ZZ1', quality: 99 }), mk('pistol_ammo', 50, 4)], myLock: false, theirLock: true },
    };
} else if (mode === 'player') {
    other = { kind: 'player', id: 'otherplayer-12', label: 'Nova Kade', slots: 40, maxweight: 120000, items: [mk('radio', 1, 1), mk('lockpick', 2, 2), mk('bandage', 3, 6)] };
} else if (mode === 'ground') {
    other = { kind: 'ground', id: 'ground', label: 'Ground', slots: 50, maxweight: 1000000, items: [] };
} else {
    other = { kind: 'stash', sub: mode === 'trunk' ? 'trunk' : null, id: 'trunk-MZ123', label: mode === 'trunk' ? 'Trunk' : 'Apartment Stash', slots: 35, maxweight: 60000, items: [mk('water_bottle', 12, 1), mk('goldbar', 1, 2), mk('weapon_pistol', 1, 5, { serie: 'AA11', quality: 100 })] };
}

// ───────────── tiny server simulation ─────────────
const clone = (o) => JSON.parse(JSON.stringify(o));
const inv = (s) => (s === 'player' ? player : other);
const find = (i, slot) => i.items.find((it) => it.slot === slot);
const remove = (i, slot) => { i.items = i.items.filter((it) => it.slot !== slot); };
const snap = (ok = true, err) => ({ ok, err, player: clone(player), other: clone(other) });

function move({ from, fromSlot, to, toSlot, amount }) {
    const A = inv(from), B = inv(to);
    if (B.kind === 'ground') {
        const item = find(A, fromSlot);
        if (!item) return snap(false, 'missing');
        other = { kind: 'drop', id: 'drop-1', label: 'Drop', slots: 50, maxweight: 1000000, items: [{ ...clone(item), amount, slot: 1 }] };
        item.amount -= amount;
        if (item.amount <= 0) remove(A, fromSlot);
        return snap();
    }
    const item = find(A, fromSlot);
    if (!item) return snap(false, 'missing');
    amount = Math.min(amount || item.amount, item.amount);
    const target = find(B, toSlot);
    if (!target) {
        if (amount === item.amount) { remove(A, fromSlot); B.items.push({ ...item, slot: toSlot }); }
        else { item.amount -= amount; B.items.push({ ...clone(item), amount, slot: toSlot }); }
    } else if (target.name === item.name && !item.unique) {
        target.amount += amount; item.amount -= amount; if (item.amount <= 0) remove(A, fromSlot);
    } else {
        if (amount !== item.amount) return snap(false, 'swapPartial');
        target.slot = fromSlot; item.slot = toSlot;
        remove(A, fromSlot); remove(B, toSlot); A.items.push(target); B.items.push(item);
    }
    return snap();
}

setMock(async (name, data) => {
    await new Promise((r) => setTimeout(r, 60));
    if (name === 'nearby') return [{ id: 12, name: 'Nova Kade', dist: 1.4 }, { id: 31, name: 'Jax', dist: 2.6 }];
    if (name === 'attachments') return { ok: true, available: true, list: [{ attachment: 'suppressor_attachment', label: 'Suppressor', image: 'suppressor_attachment.png' }] };
    if (name === 'removeAttachment') return { ok: true, list: [] };
    if (name !== 'server') return {};
    const [arg] = data.args || [];
    switch (data.name) {
        case 'move': return move(arg);
        case 'quickMove': {
            const to = arg.from === 'player' ? 'other' : 'player';
            const B = inv(to);
            let slot = 1; while (find(B, slot)) slot++;
            return move({ from: arg.from, fromSlot: arg.slot, to, toSlot: slot, amount: arg.amount });
        }
        case 'use': {
            const it = find(player, arg.slot);
            if (it && !it.unique) { it.amount -= 1; if (it.amount <= 0) remove(player, arg.slot); }
            window.postMessage({ action: 'itembox', item: it, type: 'use' }, '*');
            return snap();
        }
        case 'drop': return move({ from: 'player', fromSlot: arg.slot, to: 'other', toSlot: 1, amount: arg.amount, ground: true });
        case 'purchase': {
            const it = find(other, arg.slot);
            let slot = 1; while (find(player, slot)) slot++;
            player.items.push({ ...clone(it), amount: arg.amount, slot, price: undefined });
            it.amount -= arg.amount;
            window.postMessage({ action: 'itembox', item: it, type: 'add', amount: arg.amount }, '*');
            return snap();
        }
        case 'craftStart': return { ok: true, duration: 2500 };
        case 'repairStart': return { ok: true, duration: 2000 };
        case 'craftFinish': case 'repairFinish': return snap();
        case 'tradeOffer': {
            const it = find(player, arg.slot);
            const t = other.trade;
            t.mine = t.mine.filter((m) => m.slot !== arg.slot);
            if (arg.amount > 0 && it) t.mine.push({ ...clone(it), amount: arg.amount });
            t.myLock = false; t.theirLock = false;
            return snap();
        }
        case 'tradeLock': other.trade.myLock = arg; setTimeout(() => { other.trade.theirLock = true; window.postMessage({ action: 'other', other: clone(other) }, '*'); }, 600); return snap();
        default: return snap();
    }
});

setTimeout(() => {
    window.postMessage({ action: 'open', config: cfg, player: clone(player), other: clone(other), trade: mode === 'stash' ? { id: 'T9', from: 31, name: 'Jax' } : null }, '*');
}, 50);

window.devHotbar = () => window.postMessage({ action: 'hotbar', show: true, items: [player.items[0], player.items[1], false, player.items[3], player.items[4]] }, '*');
window.devWheel = () => window.postMessage({ action: 'wheel', show: true, player: clone(player), config: cfg }, '*');
window.devRequired = () => window.postMessage({ action: 'required', show: true, items: [{ name: 'lockpick', label: 'Lockpick', image: 'lockpick.png', have: true }, { name: 'drill', label: 'Drill', image: 'drill.png', have: false }] }, '*');
