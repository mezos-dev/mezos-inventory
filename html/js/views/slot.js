// A single slot. Slots are reused between renders and only patched when their item changes.

import { h, icon, itemImg, money } from '../ui.js';
import { quality, favs } from '../state.js';
import { rarityVars } from '../tooltip.js';

function signature(item, extra) {
    if (!item) return 'empty' + (extra || '');
    const q = quality(item);
    return [item.name, item.amount, item.slot, q === null ? '' : Math.floor(q), item.price, item.label, favs.has(item.name) ? 1 : 0, extra || ''].join('|');
}

/**
 * opts: { side, slot, src ('grid'|'equip'|'shop'|'trade'|'view'), drop (bool), key (hotbar number),
 *         placeholder (icon name), price (bool), dim, match, overflow, extra (signature salt) }
 */
export function makeSlot(opts) {
    const el = h('div', { class: 'slot' });
    el._sig = null;
    updateSlot(el, opts.item, opts);
    return el;
}

export function updateSlot(el, item, opts) {
    const sig = signature(item, `${opts.key || ''}${opts.placeholder || ''}${opts.src}${opts.drop ? 'd' : ''}`);
    el.dataset.side = opts.side;
    el.dataset.slot = opts.slot;
    if (opts.drop) el.dataset.drop = 'slot'; else delete el.dataset.drop;
    if (item && opts.src !== 'view') el.dataset.src = opts.src; else delete el.dataset.src;

    el.classList.toggle('filled', !!item);
    el.classList.toggle('dim', !!opts.dim);
    el.classList.toggle('match', !!opts.match);
    el.classList.toggle('overflow', !!opts.overflow);
    el.classList.toggle('locked', !!opts.locked);
    if (el._sig === sig) return el;
    el._sig = sig;

    el.innerHTML = '';
    el.classList.remove('spoiled', 'has-q', 'soldout');
    if (opts.key) el.append(h('span', { class: 'key' }, opts.key));
    if (!item) {
        if (opts.placeholder) el.append(h('div', { class: 'ph' }, icon(opts.placeholder)));
        el.style.removeProperty('--rar');
        el.style.removeProperty('--rar-soft');
        return el;
    }
    for (const [k, v] of Object.entries(rarityVars(item))) el.style.setProperty(k, v);
    el.append(h('div', { class: 'img' }, itemImg(item)));
    if (opts.price) {
        el.append(h('span', { class: 'price-tag' }, money(item.price)));
        el.append(h('span', { class: 'amt' }, item.amount > 0 ? `x${item.amount}` : 'SOLD'));
        if (item.amount <= 0) el.classList.add('soldout');
    } else if (!item.unique || item.amount > 1) {
        el.append(h('span', { class: 'amt' }, `x${item.amount}`));
    }
    el.append(h('span', { class: 'lbl' }, item.label));
    const q = quality(item);
    if (q !== null) {
        el.classList.add('has-q');
        el.append(h('div', { class: `q ${q > 60 ? '' : q > 25 ? 'mid' : 'low'}` }, h('i', { style: { width: `${Math.max(2, q)}%` } })));
        if (q <= 0) el.classList.add('spoiled');
    }
    if (favs.has(item.name)) el.append(h('span', { class: 'fav' }, icon('star')));
    if (item.container && !opts.key) el.append(h('span', { class: 'tag' }, 'bag'));
    return el;
}
