// NUI <-> Lua bridge. In a normal browser (dev) calls are answered by dev.js mocks.

export const IS_GAME = typeof window.GetParentResourceName === 'function';
const RESOURCE = IS_GAME ? window.GetParentResourceName() : 'mezos-inventory';

let mock = null;
export function setMock(fn) { mock = fn; }

export async function post(name, data = {}) {
    if (!IS_GAME) return mock ? mock(name, data) : {};
    try {
        const res = await fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data),
        });
        const text = await res.text();
        return text ? JSON.parse(text) : {};
    } catch (e) {
        return {};
    }
}

// Server callbacks are serialized: qb-core keys pending callbacks by name, and
// ordering matters for optimistic moves (each response is the newest truth).
let chain = Promise.resolve();
export let inFlight = 0;
export function server(name, ...args) {
    inFlight++;
    const run = () => post('server', { name, args });
    const p = chain.then(run, run).finally(() => { inFlight--; });
    chain = p.catch(() => {});
    return p;
}

export function throttled(name, ms = 40) {
    let last = 0, timer = null, pending = null;
    return (data) => {
        pending = data;
        const now = Date.now();
        const fire = () => { last = Date.now(); timer = null; post(name, pending); };
        if (now - last >= ms) fire();
        else if (!timer) timer = setTimeout(fire, ms - (now - last));
    };
}
