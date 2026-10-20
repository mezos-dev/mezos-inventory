# mezos-inventory

mezos-inventory is a full replacement for `qb-inventory` 2.2.x. It has the same exports, events, hooks and player methods, and it reads and writes the same database data. Every qb resource on the server keeps working unchanged.

## Install
1. Put the resource in `resources/[Mezos]/mezos-inventory`. The old inventory lives in `resources/[disabled]/qb-inventory-legacy`. Never rename it back, because it would clash with `provide 'qb-inventory'`.
2. In `server.cfg`, add `ensure mezos-inventory` directly after `ensure qb-core` and `ensure mezos-clothing`, before `ensure [qb]`.
3. Make sure the `inventories` table exists (`sql/install.sql`). It is the same table qb-inventory used.
4. Item images go in `html/images/`, which already holds every qb image. Other resources should load them from `nui://mezos-inventory/html/images/`.

## Features
- **Holo-deck UI.** Your pockets are on the left. The middle shows your live character, framed by a camera that you rotate by dragging, with equipment nodes around it. Whatever you're looking at is on the right.
- **Responsive layout.**
  - Three columns on wide screens.
  - Two columns with a gear drawer on medium screens.
  - A single panel with tabs on narrow or portrait screens. While dragging, hover a tab and it switches.
  - Everything scales with the viewport, and each player can set the size in Settings.
- **Drag and drop.** Dragging snaps to slots, the drag preview tilts as you move, and the scroll wheel changes the amount mid-drag.
  - Shift-drag splits the stack in half.
  - Ctrl-click quick-moves an item to the other side.
  - Double-click uses an item.
  - Alt-click uses an item.
  - Hover an item and press 1-5 to bind it to the hotbar.
  - On touch screens, a long press opens the action menu.
- **Radial action menu** (right-click): use, equip, give, split, drop, move, offer, attachments, hotbar, favourite, inspect.
- **Search, sorting and filters.** Search is fuzzy. There are category chips and rarity glow. The sort button merges stacks and sorts by category; the hotbar slots stay where they are.
- **Equipment.** There are slots for backpack, armor, phone, radio, primary weapon and secondary weapon.
  - Equipped items live in slots 101-106, so `HasItem` and similar calls still find them.
  - A backpack adds slots and carry weight. You can't unequip it while its extra slots still hold items.
- **Containers.** Using a wallet or duffel bag opens its own inventory, and the contents stay with the bag when it's given away. Containers can't be put inside containers.
- **Durability.** Food, drinks and drugs lose freshness over time; set the rate with `decay` in `config/items.lua`. Spoiled items can't be used. Weapons and tools can be repaired at benches.
- **Crafting benches.** Configure them in `config/crafting.lua`.
  - A bench can be limited to a job or gang.
  - Recipes can need tools.
  - The crafting timer is enforced by the server.
- **Secure trading.** Offers stay in place until both players lock and confirm, and any change resets the locks.
  - The final swap re-checks everything and happens in one step for both players.
  - Walking away, dying or disconnecting cancels the trade.
- **Shops and vending machines.** These use the qb `CreateShop`/`OpenShop` API, with a cart, quantity stepper, and payment by cash or bank.
- **Ground drops** are managed by the server, and each player spawns the bag props locally. Dropping an item next to an existing drop adds it to that drop. Press TAB or E near a drop to open it.
- **Overlays:** a hotbar (Z, or keys 1-5), item received/removed pop-ups, a required-items strip, and a quick-use wheel (F2).

## Anti-dupe and safety
- The server makes every decision. The UI only sends what the player wants to do, and every response carries the real inventory state.
- Each move works on copies of the inventories, is validated, and is then saved in one go. Nothing waits in the middle of a move.
- An inventory can only be open for one person at a time. It closes automatically if you walk away, die, are cuffed, or lose the container.
- Rate limits apply to moves, uses, gives, purchases, crafting and trades.
- Amounts must be positive whole numbers, which blocks negative, fractional and NaN values. Slot numbers are checked and must still hold the expected item.
- Changed stashes are saved every 5 minutes, when they are closed, when the resource stops, and when txAdmin shuts the server down.
- If the UI ever stops responding, a heartbeat watchdog hands mouse and keyboard control back to the game.

## Adding items
Define items in `qb-core/shared/items.lua` as usual. To add behaviour (`category`, `rarity`, `decay`, `stack`, `equip`, `backpack`, `container`, `repair`, `noGive`, `noDrop`, `noTrade`), add an entry in `config/items.lua`.

## API
Every qb-inventory export is available under both `exports['qb-inventory']` and `exports['mezos-inventory']`:

`AddItem, RemoveItem, CanAddItem, HasItem, GetItemByName, GetItemsByName, GetItemBySlot, GetItemCount, GetSlots, GetSlotsByItem, GetFirstSlotByItem, GetTotalWeight, GetFreeWeight, SetInventory, SetItemData, ClearInventory, LoadInventory, SaveInventory, UseItem, OpenInventory, OpenInventoryById, CloseInventory, CreateInventory, GetInventory, RemoveInventory, ClearStash, CreateShop, OpenShop, AddHook, RemoveHook, AddListener, RemoveListener`

Extra exports: `OpenContainer(src, slot)`, `GetCapacity(src)`, `CreateDrop(coords, items, bucket)`. On the client: `HasItem`, `IsOpen`, `GetPlayerItems`.

## Commands
`/giveitem`, `/clearinv`, `/randomitems`, `/openstash <name>` (admin). `/tradeaccept` and `/tradedecline` answer a trade request.

## UI development
Open `html/index.html` in a browser, served over http, for example with `npx http-server html`. Use `?mode=stash|trunk|shop|crafting|trade|player|ground`. In the browser console, `devHotbar()`, `devWheel()` and `devRequired()` show the overlays.
