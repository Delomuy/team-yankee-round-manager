# Team Yankee unit manager and round manager — project context

Godot 4 project (GDScript only) for the tabletop wargame **Team Yankee**: browse unit cards, build armies with
points, and run a battle step by step with every roll made and explained by the program.

**Read this first: test with the real Godot.** The user's Godot 4.7.2 is on this machine (console build, use it for
headless runs):
`C:\Users\Public\Documents\Unai\Aplicaciones\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
(the `.exe` in the middle is a folder name). The smoke test passes headless (5880 checks, 0 problems, exit code 0,
2026-11-12; the count varies a little with the random battle). It switches Use formations off for its run (like typed-in dice). It waits a frame between test groups: run in one frame it overflowed Godot's message queue and crashed
(signal 11) after printing "finished" - check the exit code, not only the summary line. It re-seeds the RNG before
the random battle (frames in between use random numbers; an unlucky battle floods the queue and crashes).
Its formation / card checks must not depend on formations the user fills in (the user edits those files). The random
battle draws only cards of the original unit files (`_base_pool` / `_base_nations`): the user's own cards and nations
(the user added France, 27 cards, 2026-11-12) once sent it down a path that flooded the log and crashed Godot.
Layouts have not been checked by eye. Run logs of the user's own sessions are in
`%APPDATA%\Godot\app_userdata\TY helper\logs\godot.log` - read them when the user reports a bug.

---

## 1. How to run and verify

| What | How |
|---|---|
| Open | Godot 4 (project says `config/features = "4.7", "Mobile"`), window 1600x900 |
| Main scene | `res://scenes/main.tscn` (root script `scripts/ui/main.gd`) |
| Smoke test | `res://scenes/smoke_test.tscn` (F6). Prints `=== finished: N checks, M problem(s) ===` |
| Static lint | `python3 tools/gdlint.py .` from the project root. Prints `files N problems M` (**the script is missing from `tools/` as of 2026-11-11**) |
| Regenerate unit JSON | `python tools/convert_units.py --all` (every `data/*.txt` -> `data/<name>.json`) |
| Regenerate rules JSON | `python tools/extract_special_rules.py` (needs pdfplumber and the Special Rules PDF) |

`tools/gdlint.py` checks bracket balance, that methods called on known classes exist with the right number of
arguments, and that `%` format strings have the right number of placeholders. It does **not** type-check or know the
Godot API. Passing it means little.

Headless runs (PowerShell, from the project root; `$g` = the console Godot above):

```
& $g --headless --path . --import                                         # rescan: registers new class_name files
& $g --headless --path . res://scenes/smoke_test.tscn --quit-after 3000   # smoke test
& $g --headless --path . --quit-after 200                                 # main scene starts without errors
```

**New `class_name` files must be registered** in `.godot/global_script_class_cache.cfg` before anything that uses
them compiles. Files written outside the editor are only picked up when Godot rescans; otherwise every script that
names the new class fails with "Could not find type" (this is how "armies cannot be created" happened: `Army` used
`FormationDB` / `FormationData`). After adding a class, run the `--import` line above.

## 2. Conventions

- GDScript with **tabs**, static typing everywhere (`var x: int = 0`, typed loops `for u: UnitInstance in list`).
- **All UI is built in code.** The two `.tscn` files only attach a root script. Do not add scene files for UI.
- English UI text, plain wording, British rule terms as on the cards (Armour, Stabiliser).
- Every class has a `class_name` and a `##` doc comment at the top saying what it is for.
- Helpers are static classes (`UIUtil`, `AppTheme`, `Paper`, `TYRules`, `Combat`, `RulesDB`, `ModelWeapons`,
  `ModelIcons`, `CardImages`).
- Text on the parchment must be dark (`UIUtil.INK`). White text is only for brown/red buttons and title bars.
- Rounded boxes: use `UIUtil.paper_frame(child, frame_color, radius, margin_h, margin_v, border)`.
  **Do not use `clip_children`**: nesting it made the tables disappear (see Decisions).
- Popups: the theme gives every `Window` a brown frame / title bar (`embedded_border`) and every `AcceptDialog` a
  parchment page; `main.gd` also sets the theme on the root window, so dialogs added to `get_tree().root` match.
  A popup with a scroll area calls `UIUtil.fit_popup(dlg, scroll, content, max_h)` after `popup_centered()` so it
  shrinks to its content (card windows, `CardView.popup`, `UnitEditDialog`, `ModelWeaponsDialog`).
- Keep things narrow (the screen is 1600 px): `UIUtil.narrow(option_button, width)` for drop-downs with long
  entries (formations, transports, presets), `UIUtil.small_spin(...)` for numbers in tables (a plain SpinBox is
  never narrower than ~4 characters), wrap long labels, `HFlowContainer` for rows of tick boxes.
- One scroll area per panel: step panels' model grids (`StepPanel.grid_frame`, `ShootingPanel._grid_frame`) grow
  inside the step's scroll instead of scrolling on their own.
- Rule numbers the user may want to change live as constants at the top of `scripts/rules/ty_rules.gd`.

## 3. Layout of the repository

```
project.godot                 name "TY helper"; autoloads: UnitDatabase, ArmyManager, DiceInput
scenes/main.tscn, smoke_test.tscn
data/<nation>_units.txt       source text copied from FowList (8 nations)
data/<nation>_units.json      converted cards (252 units), loaded at start
data/rules/special_rules.json 155 special rules extracted from the Special Rules PDF
data/rules/extra_rules.json   user's own rule descriptions (empty)
data/model_weapons.json       created at runtime: weapons per kind of model
data/custom/<prefix>_units.json  cards made / copied / changed in the Cards tab (override same-id cards)
data/formations/<prefix>_formation_data.json  formations per nation (only ussr: one example so far)
card_images/                  optional card pictures named <card id>.png
model_icons/                  optional model icons named <card id>.png or <type letter>.png
assets/parchment.jpg          background texture
tools/convert_units.py        FowList text / loose JSON -> units JSON
tools/extract_special_rules.py  PDF -> special_rules.json
tools/gdlint.py               the static lint
scripts/data/                 resources and battle-time objects
scripts/rules/                rules engine (no UI)
scripts/battle/battle_state.gd
scripts/ui/                   every screen, panel and widget
scripts/tests/smoke_test.gd
README.md                     user-facing manual (keep it in step with the code)
```

Shared through a **private** GitHub repository (2026-11-12, set up by the user with GitHub Desktop; Git is not
installed on the command line). `.gitignore` leaves out `.godot/`, `/export/` (Windows builds go to GitHub
Releases), `/relevant docs/` (rulebook, Quick Reference, Special Rules PDF: copyrighted, never upload) and
`/saved_army/` (the user's armies). Rule texts in `data/rules/` and the FowList copies are third-party too: keep the
repository private. The README's "How to run" section is written for people who clone it.

## 4. Architecture

### 4.1 Data layer (`scripts/data/`)

| Class | Kind | Purpose |
|---|---|---|
| `UnitData` | Resource | One card. `Category { ARMORED, GROUND, AIR }`, stats, `options`, `upgrades`, `weapons`, `special_rules`. `AUTO := -1` means unlimited / no check. Upgrades are paid three ways, `upgrade_kind(i)`: `once` (`per_model` false), `choice` (`per_model` true: player picks how many, `upgrade_limit` = "up to N/two" or models), `model` (`"per": "model"`: cost x `upgrade_units(i, option)` = models of the size, or rows whose name has `count_models`, or fixed `count`, divided by `group` rounded up). **`upgrade_cost(i, qty, option)` needs the chosen size** for `model` upgrades. `upgrade_price_text(i)` for display |
| `ArmoredUnitData`, `GroundUnitData`, `AirUnitData` | Resource | Subclasses: `armour_front/side/top`; transport ids; `aircraft_type` ("helicopter" / "jet") |
| `WeaponData` | Resource | `range_cm`, `range_cm_min`, `rof_static`, `rof_moving` (0 = cannot fire), `salvo`, `artillery`, `anti_tank`, `firepower`, `rules` |
| `UnitOption` | Resource | One purchasable size: `label`, `models`, `points`, `points_dynamic`, `composition` = `[{count, name, unit_id?}]` |
| `UnitDatabase` | autoload | Loads `data/*_units.json`, then the custom cards `data/custom/<prefix>_units.json` (`user://custom_units` exported), which replace same-id cards. `get_unit(id)`, `query(nation, category, include_attachments)`, `get_nations()`, `nation_prefix`. Card editing: `unit_to_dict(u)` (exact reverse of `_build`, smoke-tested on every card), `build_unit(d)`, `save_custom(d)`, `remove_custom(id)` (restores a main card or deletes a new one), `is_custom`, `has_original`, `free_id(id)` (TS123 -> TS123c), `transport_cards()`, `users_of_transport(id)`, signal `cards_changed(id)` (every `CardBrowser` calls `update_card`), `custom_dir_override` (smoke test) |
| `ArmyEntry` | Resource | `unit_id`, `option_index`, `upgrades` = `{upgrade index: quantity}`, `formation` (key, "" = support unit), `slot` ("hq" or slot id). `get_points()` includes upgrades. `key()` identifies identical cards |
| `Army` | Resource | `army_name`, `nation`, `points_limit`, `entries`, `use_formations`, `formations` = `[{key, formation_id}]`. `add_unit`, `groups()` / `count_of` / `remove_copies` (support units only), `total_points()` (all). Limits: `support_problem(u, n)`, `room_for`, `exclusive_clash`. Formations: `add_formation`, `remove_formation`, `slot_entry`, `slot_problem`, `set_slot`, `clear_slot`, `formation_problems`, `set_use_formations`. `list_problems()` = everything illegal (shown in the editor, blocks *Start battle*) |
| `NationDB` | static | Nations = the ones with cards + the ones added in the program, kept in `nations.json` next to the custom cards (`UnitDatabase.custom_dir()`; the smoke test redirects it with `custom_dir_override`). `all()` (used by `UnitDatabase.get_nations()`), `add(name, label, prefix, color)`, `add_problem`, `remove` (only without cards), `is_added`, `label` (fallback of `RulesDB.nation_label`), `color` (fallback of `CardTile.nation_color_for`), `prefix_for_name`; registers prefixes in `UnitDatabase.nation_prefix`. UI: `NationDialog.open(host, on_created)` |
| `CardTextImport` | static | GDScript port of `parse_text_units` / `classify_upgrade` of `tools/convert_units.py`: `parse(text, nation)` -> `{units, warnings}`; also fills `max_copies` / `exclusive_with` / `formation_only`. Card references may use 1-3 capital letters, like `REF_RE` in `convert_units.py` (fixed 2026-11-12: it used to take only `T` + one letter, so Belgian / Israeli / Swedish infantry had lost its transport link and counted its vehicles as infantry; those three JSON files were regenerated, only 7 infantry cards changed; smoke-tested). Smoke-tested against `ussr_units.txt`. UI: `CardImportDialog` (Cards > Import cards...), saved with `UnitDatabase.save_custom_many` |
| `ArmyFiles` | static | Saved armies, one file `NAME_NATION_army.json` per army in `res://saved_army` (editor) / `user://saved_army` (exported). `save(army)` (renamed army: old file removed), `load_file(path)` -> `{army, warnings, error}`, `list()`, `import_file(src)`, `delete`, `would_replace_other`, `dir_override` (smoke test). Format = `Army.to_dict()` / `Army.from_dict()` (`"format": "TY helper army"`, upgrades keys as strings, informative `card` / `size` / `points`). `Army.saved_path` + `saved_json` (= `state_key()`, no names / points) give `is_saved()` |
| `FormationData` | RefCounted | One formation: `id`, `name`, `division` ("" = none), `nation`, `hq`, `slots` = `[{id, group, compulsory, units}]`, `exclusive` = slot-id groups, `notes` (`_` fields kept on save). `full_name()` = "Division - Name" (used in every drop-down), `to_dict`, `duplicate_formation`, `new_slot_id`, `remove_slot`, `problems()` |
| `FormationDB` | static | Loads `data/formations/*_formation_data.json` on first use, then `add_hq_formations()`: every HQ card (`is_hq()`, not attachments) without a formation gets a blank one (name = `name_from_hq(card name)`, no division, no slots) and the nation file is saved (all 8 nations have files now, 67 formations). `get_formation(id)`, `for_nation(nation)`, `divisions(nation)`. Editing: `new_id`, `put`, `remove`, `save_nation(nation)` (rewrites the nation's file, keeps `_help`; res:// from the editor, `user://formations` exported, which then wins on load), `reload()`, `save_dir_override` (smoke test). File name = `UnitDatabase.nation_prefix[nation]` + `_formation_data.json`. Format documented in the `_help` list of `ussr_formation_data.json` |
| `ArmyManager` | autoload | `roster` (2 to 8 armies built in the Armies tab; a new roster starts with 2: American, Soviet = `DEFAULT_NATIONS`), `armies` (battle slot -> Army), `battle_teams`, `use_dynamic_points`, `spawn_units(slot)` |
| `UnitInstance` | RefCounted | One unit in a battle: `data`, `option`, `owner_id`, `label`, `code`, `teams` (its models), movement, `pinned`, `foxholes`, `order`, `fired_weapons`, `transport_of` |
| `TeamState` | RefCounted | **One model** on the table (see 4.3) |
| `AppSettings` | static | `user://settings.cfg`: `manual_dice()` / `set_manual_dice(on, store)`; game options `hide_hq()` (used by `CardBrowser.refresh`, HQ = `UnitData.is_hq()`; its tick box is in the **Cards tab**, not Settings), `limit_units()` (default on, used by `Army`), `no_morale()` (stored only), `use_formations()` (every army must have a formation: `Army.require_formation`, `ArmyManager.set_player_count`, `ArmyFiles.load_file` refuses, `Army.list_problems`; Settings refuses to tick it while `ArmyManager.armies_blocking_formations()` (no formation + units + not saved), then `apply_use_formations()` closes armies without one and emits `ArmyManager.roster_changed`); title picture `user://title_image.png` (`title_texture`, `set_title_image`, `clear_title_image`); `PROGRAM_NAME` |

Unit JSON shape (one entry of `"units"`):

```json
{"id": "TU102", "name": "M1A1 Abrams Tank Platoon", "nation": "American", "category": "armored",
 "unit_type": "Tank Unit", "is_hit_on": 4, "skill": 4, "courage": 4, "remount": 3, "assault": 4, "counterattack": 4,
 "armour_front": 19, "armour_side": 9, "armour_top": 2, "tactical": 35, "terrain_dash": 40, "cross_dash": 60,
 "road_dash": 70, "cross_skill": 2, "special_rules": ["Thermal Imaging", "Chobham Armour"],
 "options": [{"label": "3x M1A1", "models": 3, "points": 29, "points_dynamic": 29,
              "composition": [{"count": 3, "name": "M1A1 Abrams"}]}],
 "upgrades": [{"text": "...", "cost": 1, "per_model": false}],
 "weapons": [{"name": "120mm M256 gun", "range_cm": 100, "rof_static": 2, "rof_moving": 2, "anti_tank": 22,
              "firepower": 2, "rules": ["Advanced Stabiliser", "Laser Rangefinder"]}]}
```

The values above illustrate the shape; check the real file for a card's numbers. Every unit also has the
hand-edited army-list fields `"max_copies"` (2 artillery / AA, 1 others), `"exclusive_with": [ids]` and
`"formation_only": bool`. Upgrade payment kinds come from `classify_upgrade(text, id)` in `tools/convert_units.py`
("per tank/team/two aircraft", "for every eight", "all ... each" -> per model; "any or all" / "up to" -> choice);
cases the text cannot tell go in its `UPGRADE_FIXES` (TB105 / TB204: Milan teams from another option, count 2).
`tools/convert_units.py` keeps the army-list fields when converting again (`--update-fields` adds missing
ones with the defaults; the artillery / AA rule is `is_artillery_unit` / `is_aa_unit` there).

### 4.2 Rules engine (`scripts/rules/`, no UI)

**Every roll is a coroutine.** With Settings > "Type in every dice result myself" on, `TYRules.d6(what, needed)` and
`TYRules.dice(count, what, needed)` wait for the autoload `DiceInput` (`await DiceInput.ask(count, what, needed)`).
So `d6`, `dice`, `roll_to_hit`, `score_dice`, `roll_test`, `cross_test`, every `Combat` function that resolves
anything (`fire_*`, `resolve_hit`, `_armour_save`, `_fp_test`, `_bail`, `_resolve_allocation`, `_hit_passengers`,
`volley_dice`, `range_in`, `bombard_*`, `assault_attack`, `defensive_fire`) and the panels' `fire()`, `range_in()`,
`defensive_fire()`, `roll_hits()`, `check_over()`, `shoot_and_scoot()` must be called with **`await`**. A new rule that
rolls must use `await TYRules.d6(...)`, never `randi_range`, and pass a `what` text the user understands. Planning
functions (`plan_*`, `max_shots`, `hit_from_roll`) never roll and stay synchronous. With the setting off nothing waits.

- **`TYRules`** — dice (`d6`, `roll_test`, `roll_to_hit` returning `{"hits", "results": [{"roll","second","hit"}]}`),
  rule lookups (`weapon_has`, `unit_has`, `is_mg`, `is_aa_weapon`, `is_bombardment`), `target_eligibility`,
  `effective_rof`, `to_hit_needed` (returns `{"needed", "parts"}`), `armour_value` / `armour_rule`, `cross_number`,
  `weapons_firing_modifier`, `bombard_needed`.
- **`Combat`** — resolution. Everything writes to the event log through `state.log_line(bbcode)`.
  - `plan_shot(shooter, widx, teams_firing, target, ctx)` -> `{"ok", "w", "rof", "teams", "dice", "needed", "parts", "warnings", "notes"}` or `{"ok": false, "error"}`. `notes` = special rules applied.
  - `plan_models(shooter, models, widx, target, target_models, ctx)` and `fire_models(state, ...)` — model-to-model shooting. `ctx.shots` = shots per target model; `ctx.defensive`; `ctx.fire_smoke`.
  - `split_volley(state, shooters, weapon_name, targets, shots)`, `plan_volley(split, ctx_for)`,
    `fire_volley(state, split, ctx_for)` — a volley by models of one kind from several units at models of several
    enemy units. It is split into parts (one shooting unit x one target unit) that each go through `fire_models`;
    weapons are matched by name across cards (`weapon_index`); `ctx_for` = target unit -> ctx. Used by `ShootingPanel`.
    `volley_dice` rolls all to-hit dice at once and gives the highest to the parts with the highest to-hit number
    (passed to `fire_models` as `ctx.rolls`; `TYRules.hit_from_roll(r, needed)` scores one die, pass = `r >= needed`).
  - `fire_limit(shooter, model, widx)` — "which weapons can fire" rule.
  - `max_shots(shooter, models, widx)` — models x ROF.
  - `range_in_needed(spotter, battery)`, `range_in(state, spotter, needed, label)`, `bombard_problem(shooter)`,
    `bombard_models(state, shooter, models, widx, target, under, ctx)`, `bombard_under(...)`, `smoke_bombard(...)`.
  - `assault_attack(state, attacker, att_teams, defender, contact, needed, w, facing)`, `assault_top_weapon()`.
  - `resolve_hit` / `_armour_save` / `_fp_test` / `_bail` / `_resolve_allocation` / `_hit_passengers`.
  - Dice for the animation: `Combat.begin_rolls()` before resolving, then `Combat.roll_groups(to_hit_results)`.
  - Older unit-level functions `fire_weapon`, `bombard_group`, `defensive_fire` still exist and are only used by the smoke test's random battle.
- **`ModelWeapons`** — which weapons each *kind* of model fires. `weapons_for(card, kind)` returns weapon indexes:
  the user's override from `model_weapons.json`, else a name-matching guess. `kinds`, `ref_card`, `is_vehicle`,
  `capacity` (the N of "Passengers N"), `set_override`, `clear_override`, `save`.
- **`RulesDB`** — special rule descriptions. `find(name, nation)`, `link(...)` builds BBCode `[url=rule|Name|Nation]`,
  `summary_bbcode(unit, weapon)`, `describe_bbcode(name, nation)`. `RulePopup.connect_label(rich_text_label)`
  makes those links open the description.

Context dictionary used by shooting (`ctx`):

```gdscript
{"range_cm": 30, "facing": "front",          # "front" / "side" / "top"
 "concealed": false, "gone_to_ground": false, "out_of_command": false,
 "smoke": false, "night": false, "bulletproof": false,
 "target_stationary": true, "shots": [2, 1], "fire_smoke": false}
```

### 4.3 The model (`TeamState`)

Every unit is split into its models. Key fields:

```gdscript
var code: String            # "IA3"
var kind: String            # "M16 rifle team", "BMP-1" ...
var team_name: String       # code + kind, used in the log
var status: int             # Status.OK / BAILED_OUT / DESTROYED
var weapons: Array          # indexes into the unit's weapons this model can fire
var fired: Dictionary       # weapon index -> true, this turn
var is_vehicle, is_aircraft: bool
var capacity: int           # passengers inside
var rides_on_top_ok: bool   # an Armoured Tank Team
var carrier: TeamState      # null = on foot
var on_top: bool
var in_building: bool
var mounted_this_turn, dismounted_this_turn: bool
var move_mode, move_distance: int
var cross_failed: bool      # = Bogged Down
```

**Model codes**: type letter + unit letter + model number, e.g. `IA3`. Type letters (`BattleState.type_letter`):
`I` infantry and guns, `T` tanks, `A` artillery, `C` carriers / transports, `H` helicopters, `P` planes. With more
than two players the player number is put first (`2IA3`). Transports that have their own card are spawned as a
separate unit (`ArmyManager.spawn_units`) with `transport_of` set.

Movement is recorded per model. `UnitInstance.sync_movement()` sets the unit's `move_mode` / `move_distance` to its
fastest model. `Combat.plan_models` temporarily swaps in the movement of the firing models.

### 4.4 Battle state (`scripts/battle/battle_state.gd`)

- Signals: `log_added(bbcode)`, `state_changed()`, `phase_changed()`.
- `Phase { STARTING, MOVEMENT, SHOOTING, ARTILLERY, ASSAULT }`.
- 2 to 4 players in **teams**. A turn belongs to a team; every other team is the enemy.
  `setup(names, teams)` (from `ArmyManager.armies`) or `setup_units(names, teams, lists, colors)` (ready-made units).
- **Round 0** is the transport set-up (`in_setup()`); `next_phase()` then starts round 1.
- `friendly_living()`, `enemy_living()`, `living(player)`, `active_team()`, `team_players(team)`, `team_label`,
  `player_color(p)` (the nation colour of the player's army card), `tag(unit)`, `unit_of(model)`, `find_model(code)`.
- Transports: `passengers(carrier, on_top)`, `free_places`, `mount_problem`, `mount(model, carrier, on_top)`
  (carrier `null` = dismount), `set_in_building`.

### 4.5 UI (`scripts/ui/`)

`main.gd` opens on `MainMenu` ("TY helper" or the title picture, buttons Cards / Formations / Armies / Battle /
Test range / Settings). The sections are pages of a `TabContainer` with `tabs_visible = false`, switched by `open_section(name)`;
a navigation bar (hidden on the menu) leads back. `SettingsScreen` holds the dice-input tick box and the title picture.
`DiceInput` (autoload, `scripts/ui/dice_input.gd`) is the exclusive window that asks for dice results.
The sections:

1. **Cards** — `CardBrowser` (`card_editing = true` only here): filters plus a grid of `CardTile`, *New card...*,
   *Only my cards*. Double-click opens the full `UnitSheet` in a window with *Attach picture*, *Remove picture*,
   *Weapons per model...*, *Edit card...*, *Copy card...* and, for custom cards, *Restore original* / *Delete card*.
   `UnitEditor` (ConfirmationDialog, `Mode { NEW, EDIT, COPY }`, field `edit_mode` - `mode` clashes with Window)
   edits a unit-file dictionary: card / ratings by category / movement / rules / weapons / sizes with model rows
   (`unit_id` = transport card) / transport linking / upgrades. `finish()` fills models, transport_models, labels,
   `transport_id(s)`, the *Passengers N* rule. Transport cards link to units via `_link_units` (saved on OK).
   Ids of existing cards cannot change (armies and formations use them).
2. **Formations** — `FormationsSection`: page 1 nation cards (+ New nation), page 2 formation cards of a nation
   (+ New formation), page 3 preview = `FormationScreen.open_preview(id)` (a scratch `Army`, nothing saved; Clear
   choices, *Edit formation* -> `edit_requested`), page 4 `FormationEditor` (only from Edit / New; Back returns to
   the preview or the nation). `main.gd` calls `refresh_page()` when the section opens. In `FormationScreen` (army and
   preview) only `_featured(key, slot, choices, entry)` is a full `CardTile`; every other card is a one-line
   `CardStrip`, also with nothing chosen: chosen card > last picked in the slot (`_last_pick`) > first free card; an
   exclusive group (`_exclusive_group`, partners of partners) shows a card in one slot only: filled slot > slot last
   picked from (`_last_slot`) > first slot. `_remember_pick` is called when a card is taken.
   The Cards tab is a wrapper: `CardList` (`CardBrowser`) + `CardFormationEditor` (a second `FormationEditor`,
   shown by the browser's *Formation editing* button, `formation_mode_requested`). Both editors `reload()` when
   shown. `FormationEditor`: `open_for(nation, id)`, `start_new(nation)`, `set_back_text`, `back_requested`.
   The editor: top bar nation + formation drop-down + New / Duplicate / Delete; left a `CardBrowser` (drag_cards, payload "catalog", `obey_hide_hq = false`
   so HQ cards always show); right name, division
   (+ *Pick...*), HQ `DropZone`, one `DropZone` column per slot (group, Compulsory, `<` `>` `X`, cards = OR choices,
   *+ Selected card*), exclusive groups as tick boxes. Every change calls `FormationDB.save_nation` (typing is
   debounced 0.6 s) and emits `formations_changed`; `main.gd` then calls `ArmyBuilderScreen.formations_changed()` the
   next time Armies opens.
3. **Armies** — `ArmyBuilderScreen`: page 1 players (name, main army, points limit, + / - buttons, 2 to 8 players),
   page 2 overview (`PlayerBlock` per player), page 3 `ArmyEditor` (card selector left, army as small cards right;
   it holds the support units and greys out cards the army cannot take via `CardBrowser.set_unavailable`).
   Page 5 `SavedArmiesPage` (from *Saved armies...* on pages 1 and 2; every overview column also has *Save army*).
   Page 1 has per army "Uses a formation" (always ticked and disabled while Settings > Use formations is on) + a formation drop-down of the main army (`Army.set_main_formation`, which
   auto-fills the HQ and every compulsory slot: `Army.autofill_formation` takes the first card of an OR slot that can
   be taken - in the data, not blocked, no `army_clash`; `FormationScreen.open_army` calls it too, so empty compulsory
   slots of older armies get filled when their screen opens). Page 2 shows a FORMATION section under each block with
   *Edit formation*, opening page 4 `FormationScreen`: formation drop-down, HQ + compulsory cards on top, additional
   slots below as columns of OR choices (red OR tags), chosen = gold outline (`CardTile.set_selected`), unavailable =
   greyed (`CardTile.set_greyed`, reasons from `slot_problem` / `army_clash`). Layout copied from the FowList force
   diagram (`relevant docs/FormationHtml.txt`). The model still allows several formations; the UI uses only
   `formations[0]` (the main formation).
   Drag a card to add one copy; double-click opens `UnitEditDialog` (size radios, upgrade check boxes with points,
   copies). `xN` badge for repeated cards, *Remove selected* mode. *Start battle* asks for teams when there are more
   than two players.
4. **Battle** — `BattleScreen`: top bar, turn-order strip, left column of team blocks with `ModelTile` grids, right
   the current `StepPanel` and the event log.
5. **Test range** — `TestLab`: two configurable test units (see 4.6).

Step panels (all extend `StepPanel`, build their controls in `build()`, call `rebuild()` to redraw):

| Panel | Step | Works on |
|---|---|---|
| `DeployPanel` | round 0 | drag infantry `ModelTile`s onto carrier drop zones (top box = on top, bottom box = inside) |
| `StartingPanel` | Starting | Remount, Rally, Strike Aircraft rolls |
| `MovementPanel` | Movement | one row per model: move kind, distance **slider** capped by the move kind, Cross Check, "Where" drop-down; orders per unit |
| `ShootingPanel` | Shooting | pick shooter models (one kind, any own units), pick target models (any enemy units), shots per target with + / -, range and situation per target unit, explanation, FIRE (`Combat.fire_volley`) |
| `ArtilleryPanel` | Artillery | pick battery models, weapon, Range In, pick models under the Template, FIRE |
| `AssaultPanel` | Assault | pick assaulting and defending models, Charge, Defensive Fire, roll, Counterattack; Shoot and Scoot |

Widgets: `ModelTile` (icon, code, name, state, tooltip with to-hit and armour, optional `- xN +`), `ModelSymbol`
(drawn fallback icon), `DiceTray` (`play(results)`, `play_groups(groups)`), `DropZone` (`accepts`, `dropped(payload)`),
`UnitSheet` (the card layout copied from the FowList web page), `ModelWeaponsDialog`, `RulePopup`.

Shooting panel flow, the pattern the Artillery and Assault panels copy:

```gdscript
enum Mode { IDLE, SHOOTERS, TARGETS }
func pick_shooter(u: UnitInstance, m: TeamState) -> String   # "" or why not
func pick_target(u: UnitInstance, m: TeamState) -> String
func change_shots(m: TeamState, delta: int) -> String
func fire() -> Dictionary:
	Combat.begin_rolls()
	var res: Dictionary = Combat.fire_models(state, _shooter_unit, _shooters, _weapon, _target_unit, _targets, _ctx())
	_dice.play_groups(Combat.roll_groups(res["results"]))
```

Drag and drop: `_get_drag_data` on the tile returns a payload dictionary with a `"kind"`; `DropZone.accepts` must
equal that kind. Controls between the tile and the zone must be `MOUSE_FILTER_PASS` or the drop never arrives.

### 4.6 Test range (`TestLab`)

Two units, A and B, built from a form: preset or *Copy card* by id, then any stat, special rules (comma separated),
up to three weapons, and a starting situation (moved, Pinned Down, Foxholes, building, already shot, Bailed Out and
Bogged Down counts). `start_test(step, active_player)` builds the units with `make_unit(side)`, calls
`BattleState.setup_units`, advances to the chosen step and embeds a normal `BattleScreen`. The smoke test's
`_test_rulebook()` uses it to get deterministic units.

## 5. Rules sources and what is implemented

Order of authority: **`Rules_clean.txt`** (OCR of the rulebook, pages 28-56: Starting Step, movement, transports,
shooting, saves, Pinned Down, Smoke, Artillery) > the Special Rules PDF (special rules) > the Quick Reference
(only for assaults, which the rulebook text does not contain).

Implemented:

- Movement: Tactical and three Dash speeds per model; Cross Check, a fail = Bogged Down until the model's next turn;
  orders Blitz Move, Follow Me, Cross Here, Dig In (Foxholes), Shoot and Scoot.
- Transports: inside up to "Passengers N"; on top up to 3, Armoured Tank Teams only; cannot Mount and Dismount in the
  same turn; dismount before the transport moves; riders on top are hit with their tank; passengers of a destroyed
  transport roll a save and get out Pinned Down (destroyed in an aircraft).
- Which weapons fire: infantry one weapon per turn; tank / aircraft all MGs or one other weapon.
- To hit: Is Hit On, +1 over 40cm, +1 Concealed, +2 Concealed and Gone to Ground, +1 Out of Command, +1 Smoke,
  +1 Night, 7+ / 8+ second roll, ROF 1 against aircraft for non Dedicated AA weapons.
- Saves: armour (die + armour, +1 over 40cm) against Anti-tank then Firepower; Bailed Out, Remount when bailed again;
  Infantry Save with Firepower in Bulletproof Cover (ticked, building or Foxholes); Unarmoured and Aircraft saves.
- Pinned Down: 5 hits in one Shooting Step (8 for 12+ models); Moving ROF; no shooting if it moved.
- Firing Smoke (weapons with the Smoke rule); Smoke Bombardments.
- Artillery: who may bombard, spotter limits, worse Skill, Observer -1, three attempts, to-hit modifiers, Top armour,
  automatic Pin Down, Repeat Bombardment.
- Special rules applied and named in the log: HEAT, Brutal, Guided, Guided AA, Dedicated AA, Anti-helicopter, Radar,
  Laser Rangefinder, NLOS, Accurate, Stabiliser, Advanced Stabiliser, Slow Firing, Overworked, Pinned ROF 1,
  One Shot, Heavy Weapon, Overhead Fire, Tandem Warhead, Thermal Imaging, Scout, Hunter-Killer, Observer, MLRS,
  Passengers N, special armour against HEAT (Chobham, ERA, BDD, Bazooka Skirts, Applique, Slat).

**Known uncertain number.** The OCR lost most of the "Number of Weapons Firing" table. The code uses a
reconstruction; confirm against the printed rulebook:

```gdscript
# scripts/rules/ty_rules.gd   [most weapons, to-hit modifier]
const WEAPONS_FIRING_TABLE := [[2, 1], [4, 0], [6, -1], [9999, -2]]
```

Not implemented: Line of Sight, Concealment and range are what the user ticks or sets; Commanders and Unit Leaders;
Out of Command movement; Mistaken Target; Unit and Formation Morale; Ambushes; Reserves; Minefields; landing
Transport Aircraft; Bomblets, Minelets, Laser-Guided Projectiles; weapon rules "Assault N" on individual weapons.

## 6. Decisions and why

| Decision | Reason |
|---|---|
| One JSON file per nation, converted from FowList text | FowList's GitHub data could not be fetched; the user supplied text copies |
| UI built in code, no UI scenes | Written without the Godot editor |
| Card sheet (`UnitSheet`) copies the FowList web page layout | User request, from `American_Force.html` |
| Parchment look for the whole app (`AppTheme`, `Paper`) | User request |
| No `clip_children`; pictures rounded with a small shader (`UIUtil.round_texture`), tables kept inside a margin | Nested `clip_children` made table cells vanish for the user |
| Army editor: drag adds one copy, double-click edits size / upgrades / copies on the card | User request; replaced an earlier separate dialog |
| Picture buttons only in the Cards tab | User request |
| Same unit with different upgrades = different card (`ArmyEntry.key()`) | Needed for the `xN` grouping |
| Players 2 to 8 in the roster, 2 to 4 in a battle, grouped in teams A-D | User request; any split into at least two teams |
| A turn belongs to a team, in order A, B, C, D | Simplest reading of multi-player Team Yankee |
| Units split into models with codes; weapons assigned per *kind* of model, guessed then user-overridable | User request; cards list all weapons of the unit |
| Round 0 for transport set-up with drag and drop; later mounting in the Movement step via a drop-down | User request |
| Mount rules follow the rulebook (same-turn limit) | The rulebook file was declared authoritative. **This replaced the user's earlier wish** that infantry never remount after dismounting; ask before changing either way |
| Shooting, artillery and assault are model against model | User request |
| Shots per target with + / -, capped at models x ROF | User request |
| Shooting: same kind of model from any own units, targets from any enemy units; situation per target unit | User request. Shots go to the shooting units in pick order. Artillery and Assault panels still use one unit per side |
| `Combat.rolled` recorder feeding `DiceTray.play_groups` | User wanted save, armour and Firepower dice animated too |
| Artillery to-hit modifier table instead of re-rolls | The rulebook file uses a modifier; the older Quick Reference used re-rolls |
| Start menu "TY helper" with optional title picture; Settings section | User request |
| Unit limits in the unit JSON (`max_copies`, `exclusive_with`, `formation_only`); formations in separate per-nation files | User request. Formation units do not count towards limits; one slot = one unit, repeated slots for repeats |
| Formations chosen per army; the global Use formations setting forces one on every army | User request. Ticking it is refused while an army without a formation has unsaved units; saved / empty ones are closed |
| Saved armies: one JSON per army, `NAME_NATION_army.json` in `saved_army/`; Hide HQ units ticked in the Cards tab | User request. "Saved" = unchanged since the file was written (`state_key`, so the points switch does not count) |
| With formations, HQ cards only inside their formation; without, HQ cards are normal units | User request |
| Cards made / changed in the program go to `data/custom/`, not into the main unit files | Regenerating with `convert_units.py` must not wipe them, and a changed main card can be restored. Copies get a free id (TS123c) so ids never repeat (user request) |
| One blank formation per HQ card, made automatically; HQ cards always visible in the Formations section | User request ("each HQ unit corresponds to a different formation"). Blank = no division, no slots |
| Formations section edits the per-nation JSON files and saves on every change; formations have a `division` | User request ("BTR-60 Motor Rifle Battalion is part of the 228th Guards"). Saving at once means nothing is lost when leaving the screen; the id never changes so saved armies keep their formation |
| Formations section = nations -> formations -> preview -> editor; the editor also in the Cards tab; greyed cards folded to one line | User request. The preview reuses `FormationScreen` on a scratch army so both screens fold cards the same way |
| Cards for any nation from FowList text inside the program; nations can be added | User request. Ported `convert_units.py` to GDScript (`CardTextImport`) instead of calling Python, so it works in an exported program |
| Optional typed-in dice; rolls made awaitable instead of pre-entering dice | User request. Saves / armour / Firepower are asked one hit at a time (their count depends on earlier dice). Closing the dice window rolls the missing dice so a step never hangs half done |

## 7. Active todo list

Highest priority first.

1. **Click through it in Godot.** The smoke test passes headless; nobody has clicked through every section yet
   (Cards, Battle, Test range, Settings, the dice-input window). The Armies pages and the formation screen were
   checked on screenshots (2026-11-11). Screenshots can be taken by running a temporary scene in a window that calls
   `get_viewport().get_texture().get_image().save_png(...)`; delete it afterwards.
2. **Look at the layouts**: every section and popup was reviewed on screenshots at 1600x900 (2026-11-12): popups
   themed and fitted, Test range fits both sides, Cards filter bar on one row, step panels have one scrollbar. Not yet
   looked at: round 0 drag and drop, the Artillery and Assault panels with many models, the movement rows of a big unit.
3. **Confirm with the user**: the Number of Weapons Firing table; whether to keep the rulebook's mount rule or
   restore "never remount after dismounting".
4. Check the white-on-light text report is really fixed (flat buttons use `UIUtil.ink_text`; `ItemList` hover colour
   set in `AppTheme`).
5. Assault rules from the rulebook when the user supplies those pages; apply weapon rules "Assault N".
6. Animate the remaining rolls if wanted: Remount, Rally, Cross Check, order tests, Range In.
7. Special ammunition: Bomblets, Minelets, Laser-Guided Projectiles; Mistaken Target (3+ swap).
8. Per-model overrides of weapons (today it is per kind of model on a card).
9. Morale, Reserves, Ambushes, Commanders, Minefields. Morale must be skipped when `AppSettings.no_morale()` is on.
10. **Formations**: army building is done (per army, `Army.use_formations`), and formations are made in the
    Formations section (checked on screenshots 2026-11-11; drag and drop not clicked by hand yet). Still to do: the
    user fills the other nations' formations; TS128 (in the example) has no card yet; editing a formation that a
    roster army uses can leave army entries in slots that no longer exist (not cleaned up); Formation Command in the battle rules
    (leadership bonuses only for units of the commander's own formation: `UnitInstance.formation` is already set);
    Formation Morale. `AppSettings.use_formations()` was re-enabled 2026-11-12 (forces a formation on every army).
11. Remove dead code: `UnitSheet` option-selection code paths no longer used by the Cards tab; the unit-level
    `Combat.fire_weapon` / `bombard_group` / `defensive_fire` once the smoke test's random battle is ported to models.
12. Performance: `BattleScreen._update_teams()` rebuilds every `ModelTile` on each `state_changed`. Update in place
    if large battles feel slow.

## 8. Gotchas

- `state.touch()` emits `state_changed`, which rebuilds the left column. Do not call it from slider drags.
- After changing a model's movement call `unit.sync_movement()`.
- `UnitInstance.alive_teams()` leaves out carried models unless that would leave none.
- `TeamState.mounted()` is false when the carrier is destroyed, even if `carrier` is still set.
- `UnitData.AUTO` (-1) is used for "no Cross Check" and unlimited movement; sliders use `slider_limit()`.
- Buttons added with `AcceptDialog.add_button(text, false, "action")` arrive through `custom_action`.
- Files written at runtime go to `res://` when run from the editor and to `user://` in an exported game
  (`CardImages`, `ModelIcons`, `ModelWeapons`).
- Forgetting `await` on a rolling call does not fail with the setting off but breaks it on: the caller gets no value
  and carries on before the user answers. Grep for un-awaited calls after touching the rules.
- The smoke test switches typed-in dice off for its run (`AppSettings.set_manual_dice(false, false)`, not saved).
- The smoke test seeds the RNG (`seed(20260101)`) and builds random armies; some model tests print a "not tested"
  line when the random army lacks the unit type they need.
