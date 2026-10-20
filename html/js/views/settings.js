// Per-viewer settings (saved in this browser only).

import { h, icon, modal, setSound, hexToRgb } from '../ui.js';
import { S, settings, setSetting } from '../state.js';

const SWATCHES = ['#22e4ff', '#a855ff', '#2bffb1', '#ffb02e', '#ff3d71', '#4d8bff'];

export function applySettings(theme = {}) {
    const root = document.documentElement;
    root.style.setProperty('--scale', String(settings.scale || 1));
    const accent = settings.accent || theme.accent;
    if (accent) {
        root.style.setProperty('--accent', accent);
        root.style.setProperty('--accent-rgb', hexToRgb(accent));
    }
    if (theme.accent2) {
        root.style.setProperty('--accent2', theme.accent2);
        root.style.setProperty('--accent2-rgb', hexToRgb(theme.accent2));
    }
    if (theme.danger) root.style.setProperty('--danger', theme.danger);
    if (theme.success) root.style.setProperty('--success', theme.success);
    document.body.classList.toggle('reduce-motion', !settings.motion);
    setSound(settings.sound !== false && theme.sounds !== false);
}

export function openSettings(theme) {
    theme = theme || S.config.theme || {};
    modal((box, close) => {
        const toggle = (key) => {
            const t = h('button', { class: `toggle ${settings[key] ? 'on' : ''}` });
            t.addEventListener('click', () => { setSetting(key, !settings[key]); t.classList.toggle('on', settings[key]); applySettings(theme); });
            return t;
        };
        const scale = h('input', { type: 'range', min: 0.75, max: 1.35, step: 0.05, value: settings.scale || 1 });
        const scaleVal = h('b', {}, `${Math.round((settings.scale || 1) * 100)}%`);
        scale.addEventListener('input', () => {
            setSetting('scale', +scale.value);
            scaleVal.textContent = `${Math.round(+scale.value * 100)}%`;
            applySettings(theme);
        });
        const sw = h('div', { class: 'swatches' }, SWATCHES.map((c) => {
            const b = h('button', { class: (settings.accent || '#22e4ff') === c ? 'active' : '', style: { background: c, color: c } });
            b.addEventListener('click', () => {
                setSetting('accent', c);
                sw.querySelectorAll('button').forEach((x) => x.classList.remove('active'));
                b.classList.add('active');
                applySettings(theme);
            });
            return b;
        }));
        box.append(
            h('h3', {}, icon('settings'), 'Inventory settings'),
            h('div', { class: 'set-row' }, h('span', {}, 'Size', h('small', {}, 'Slot and text size')), scale, scaleVal),
            h('div', { class: 'set-row' }, h('span', {}, 'Accent', h('small', {}, 'Highlight colour')), sw),
            h('div', { class: 'set-row' }, h('span', {}, 'Animations', h('small', {}, 'Turn off for less motion')), toggle('motion')),
            h('div', { class: 'set-row' }, h('span', {}, 'Sounds', h('small', {}, 'Subtle UI ticks')), toggle('sound')),
            h('div', { class: 'set-row' }, h('span', {}, 'Character camera', h('small', {}, 'Frame your character while open')), toggle('camera')),
            h('div', { class: 'set-row' }, h('span', {}, 'Item tooltips', h('small', {}, 'Hover cards with details')), toggle('tooltips')),
            h('div', { class: 'row end' },
                h('button', { class: 'btn ghost', onclick: () => { for (const k of ['scale', 'accent', 'motion', 'sound', 'camera', 'tooltips']) setSetting(k, { scale: 1, accent: null, motion: true, sound: true, camera: true, tooltips: true }[k]); applySettings(theme); close(); } }, 'Reset'),
                h('button', { class: 'btn primary', onclick: () => close() }, 'Done')),
        );
    });
}
