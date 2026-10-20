// Radial context menu: a ring of actions around the cursor.

import { $, h, icon, itemImg, clamp, sfx } from '../ui.js';
import { S } from '../state.js';

let onPick = null;
let openedAt = 0;

export function radialOpen() { return !$('#radial').classList.contains('hidden'); }

export function closeRadial() {
    const el = $('#radial');
    el.classList.add('hidden');
    el.innerHTML = '';
    onPick = null;
}

/**
 * actions: [{ id, label, icon, danger?, disabled? }]
 */
export function openRadial(x, y, item, actions, pickFn) {
    const el = $('#radial');
    el.innerHTML = '';
    el.classList.remove('hidden');
    onPick = pickFn;
    openedAt = Date.now();

    const menu = h('div', { class: 'ring-menu' });
    el.append(menu);
    const size = menu.offsetWidth || 240;
    const margin = size / 2 + 12;
    menu.style.left = `${clamp(x, margin, window.innerWidth - margin)}px`;
    menu.style.top = `${clamp(y, margin, window.innerHeight - margin)}px`;

    const n = actions.length;
    const R = 50, r = 21, gap = n > 1 ? 2.5 : 0; // viewBox units (100x100)
    const svgNS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(svgNS, 'svg');
    svg.setAttribute('viewBox', '0 0 100 100');
    const center = h('div', { class: 'center' }, itemImg(item), h('b', {}, item.label));
    const label = center.querySelector('b');

    actions.forEach((a, i) => {
        const a0 = ((i / n) * 360 - 90 + gap / 2) * (Math.PI / 180);
        const a1 = (((i + 1) / n) * 360 - 90 - gap / 2) * (Math.PI / 180);
        const large = a1 - a0 > Math.PI ? 1 : 0;
        const p = (rad, ang) => `${50 + rad * Math.cos(ang)},${50 + rad * Math.sin(ang)}`;
        const d = n === 1
            ? `M50,0 A50,50 0 1,1 49.99,0 Z M50,${50 - r} A${r},${r} 0 1,0 50.01,${50 - r} Z`
            : `M${p(R, a0)} A${R},${R} 0 ${large},1 ${p(R, a1)} L${p(r, a1)} A${r},${r} 0 ${large},0 ${p(r, a0)} Z`;
        const path = document.createElementNS(svgNS, 'path');
        path.setAttribute('d', d);
        path.setAttribute('class', `seg-path ${a.danger ? 'danger' : ''} ${a.disabled ? 'disabled' : ''}`);
        path.addEventListener('pointerenter', () => { label.textContent = a.label; if (!a.disabled) sfx('tick'); });
        path.addEventListener('pointerleave', () => { label.textContent = item.label; });
        path.addEventListener('pointerup', (e) => {
            e.stopPropagation();
            if (a.disabled || Date.now() - openedAt < 180) return;
            const fn = onPick;
            closeRadial();
            fn && fn(a.id);
        });
        svg.append(path);
        const mid = (a0 + a1) / 2;
        const ir = (R + r) / 2;
        const ic = h('div', { class: `seg-icon ${a.disabled ? 'disabled' : ''}` }, icon(a.icon));
        ic.style.left = `${50 + ir * Math.cos(mid)}%`;
        ic.style.top = `${50 + ir * Math.sin(mid)}%`;
        menu.append(ic);
    });
    menu.prepend(svg);
    menu.append(center);
    sfx('open');
}

document.addEventListener('pointerdown', (e) => {
    if (!radialOpen()) return;
    if (!e.target.closest('.ring-menu')) closeRadial();
}, true);

export { S };
