// Pointer drag engine (mouse, pen and touch).
//  - drag sources: elements with [data-src] (and data-side / data-slot)
//  - drop targets: elements with [data-drop]
//  - magnetic snap toward the hovered slot, tilt from velocity, wheel adjusts the amount
//  - hovering a [data-spring] element while dragging "clicks" it (switch tabs mid-drag)

import { $, h, clamp, itemImg, sfx } from './ui.js';

const THRESHOLD = 5;
const LONG_PRESS = 450;

let cfg = null;
let press = null;      // pointer down, not yet dragging
let drag = null;       // active drag
let lastClick = { key: null, t: 0 };
let raf = 0;
let springTimer = null, springEl = null;

export function isDragging() { return !!drag; }

export function initDrag(options) {
    cfg = options;
    document.addEventListener('pointerdown', onDown, true);
    document.addEventListener('pointermove', onMove, true);
    document.addEventListener('pointerup', onUp, true);
    document.addEventListener('pointercancel', cancel, true);
    document.addEventListener('wheel', onWheel, { passive: false });
    document.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('blur', cancel);
}

function srcInfo(el) {
    return { side: el.dataset.side, slot: +el.dataset.slot, kind: el.dataset.src, el };
}

function onDown(e) {
    const el = e.target.closest('[data-src]');
    if (!el || el.classList.contains('locked')) return;
    const src = srcInfo(el);
    const item = cfg.getItem(src);
    if (!item) return;

    if (e.button === 2) {
        e.preventDefault();
        cfg.onContext(src, item, e.clientX, e.clientY);
        return;
    }
    if (e.button !== 0) return;
    press = { x: e.clientX, y: e.clientY, src, item, id: e.pointerId, t: Date.now(), touch: e.pointerType === 'touch' };
    if (press.touch) {
        press.timer = setTimeout(() => {
            if (press && !drag) { cfg.onContext(press.src, press.item, press.x, press.y); press = null; }
        }, LONG_PRESS);
    }
}

function onMove(e) {
    if (press && !drag) {
        if (Math.hypot(e.clientX - press.x, e.clientY - press.y) < THRESHOLD) return;
        clearTimeout(press.timer);
        if (cfg.canDrag && !cfg.canDrag(press.src, press.item)) { press = null; return; }
        start(press, e);
        press = null;
    }
    if (!drag) return;
    drag.tx = e.clientX;
    drag.ty = e.clientY;
    drag.vx = e.clientX - drag.lastX;
    drag.lastX = e.clientX;
    hover(e.clientX, e.clientY);
}

function start(p, e) {
    const item = p.item;
    const amount = cfg.initialAmount(item, { shift: e.shiftKey }, p.src);
    const ghost = $('#ghost');
    ghost.innerHTML = '';
    const count = h('div', { class: 'n' }, amount);
    const hint = h('div', { class: 'hint' }, item.label || '');
    ghost.append(h('div', { class: 'g' }, itemImg(item)), item.unique ? null : count, hint);
    ghost.classList.remove('hidden');
    p.src.el.classList.add('dragging');
    document.body.classList.add('is-dragging');
    drag = {
        src: p.src, item, amount, ghost, count, hint,
        x: e.clientX, y: e.clientY, tx: e.clientX, ty: e.clientY, lastX: e.clientX, vx: 0, tilt: 0,
        target: null,
    };
    cfg.onDragStart && cfg.onDragStart(drag.src, item);
    sfx('pick');
    loop();
    hover(e.clientX, e.clientY);
}

function loop() {
    cancelAnimationFrame(raf);
    const step = () => {
        if (!drag) return;
        let tx = drag.tx, ty = drag.ty;
        // magnetic snap toward the hovered slot centre
        if (drag.target && drag.target.rect) {
            const r = drag.target.rect;
            const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
            if (Math.abs(cx - tx) < r.width && Math.abs(cy - ty) < r.height) {
                tx = tx + (cx - tx) * 0.45;
                ty = ty + (cy - ty) * 0.45;
            }
        }
        drag.x += (tx - drag.x) * 0.38;
        drag.y += (ty - drag.y) * 0.38;
        drag.tilt += (clamp(drag.vx * 1.4, -18, 18) - drag.tilt) * 0.2;
        drag.vx *= 0.85;
        const w = drag.ghost.offsetWidth || 60;
        drag.ghost.style.transform = `translate(${drag.x - w / 2}px, ${drag.y - w / 2}px) rotate(${drag.tilt}deg) scale(1.06)`;
        raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
}

function hover(x, y) {
    const el = document.elementFromPoint(x, y);
    const target = el && el.closest('[data-drop]');
    const prev = drag.target && drag.target.el;
    if (prev !== target) {
        if (prev) prev.classList.remove('target', 'bad');
        drag.target = null;
        if (target) {
            const info = { el: target, kind: target.dataset.drop, side: target.dataset.side, slot: target.dataset.slot != null ? +target.dataset.slot : null };
            const verdict = cfg.canDrop(drag.src, drag.item, info);
            if (verdict !== null) {
                target.classList.add('target');
                if (verdict === false) target.classList.add('bad');
                info.rect = target.getBoundingClientRect();
                info.ok = verdict !== false;
                drag.target = info;
            }
        }
        drag.hint.textContent = drag.target ? (cfg.hint(drag.src, drag.item, drag.target) || drag.item.label) : drag.item.label;
    }
    // spring-loaded tabs
    const spring = el && el.closest('[data-spring]');
    if (spring !== springEl) {
        if (springEl) springEl.classList.remove('spring');
        clearTimeout(springTimer);
        springEl = spring;
        if (spring) {
            spring.classList.add('spring');
            springTimer = setTimeout(() => { if (drag && springEl === spring) { spring.click(); spring.classList.remove('spring'); } }, 420);
        }
    }
}

function onWheel(e) {
    if (!drag || drag.item.unique) return;
    e.preventDefault();
    const step = e.shiftKey ? 10 : 1;
    drag.amount = clamp(drag.amount + (e.deltaY < 0 ? step : -step), 1, drag.item.amount);
    drag.count.textContent = drag.amount;
    sfx('tick');
}

function onUp(e) {
    if (press) {
        clearTimeout(press.timer);
        const p = press;
        press = null;
        if (e.button === 0 || p.touch) click(p, e);
        return;
    }
    if (!drag) return;
    const d = drag;
    finish();
    if (d.target && d.target.ok) {
        const amount = e.shiftKey && !d.item.unique ? Math.max(1, Math.floor(d.item.amount / 2)) : d.amount;
        sfx('drop');
        cfg.onDrop(d.src, d.item, d.target, amount, { shift: e.shiftKey, ctrl: e.ctrlKey });
    } else if (d.target) {
        sfx('error');
        cfg.onReject && cfg.onReject(d.src, d.item, d.target);
    }
}

function click(p, e) {
    const key = `${p.src.side}:${p.src.slot}:${p.src.kind}`;
    const now = Date.now();
    if (lastClick.key === key && now - lastClick.t < 320) {
        lastClick = { key: null, t: 0 };
        cfg.onDouble && cfg.onDouble(p.src, p.item, e);
        return;
    }
    lastClick = { key, t: now };
    cfg.onClick && cfg.onClick(p.src, p.item, e);
}

function finish() {
    cancelAnimationFrame(raf);
    clearTimeout(springTimer);
    if (springEl) springEl.classList.remove('spring');
    springEl = null;
    if (!drag) return;
    if (drag.target) drag.target.el.classList.remove('target', 'bad');
    drag.src.el.classList.remove('dragging');
    drag.ghost.classList.add('hidden');
    document.body.classList.remove('is-dragging');
    cfg.onDragEnd && cfg.onDragEnd();
    drag = null;
}

export function cancel() {
    if (press) { clearTimeout(press.timer); press = null; }
    if (drag) finish();
}
