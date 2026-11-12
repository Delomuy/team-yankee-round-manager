# TY helper - Team Yankee round manager (Godot 4)

## How to run

### Ready-made program (no Godot needed)

If the repository has a **Release** (on GitHub: *Releases*, on the right of the repository page), download the zip,
unpack it into a folder and run `TY helper.exe`. Your armies, cards, formations and nations are saved in your own user
folder (`%APPDATA%\Godot\app_userdata\TY helper` on Windows), not next to the program.

### From the source (with Godot)

1. Install **Godot 4.7** (the standard version, not .NET) from godotengine.org.
2. Get the project: on the repository page, **Code > Open with GitHub Desktop** (or *Download ZIP* and unpack it into
   an empty folder). Keep the folders as they are: `project.godot`, `data/`, `scripts/`, `scenes/` and `tools/` sit
   side by side.
3. Start Godot, **Import**, pick `project.godot`. The first opening takes a few seconds: Godot rebuilds its `.godot`
   cache, which is not in the repository.
4. Press **F5**. To check everything works, open `scenes/smoke_test.tscn` and press **F6**: the Output panel ends with
   `=== finished: N checks, 0 problem(s) ===`.

To get later changes, press **Fetch origin / Pull** in GitHub Desktop (or download the ZIP again).

What the repository does **not** contain: the rulebook files the program was written from (the Special Rules PDF, the
Quick Reference and the rulebook text, in `relevant docs/` on the author's computer) and the author's saved armies.
The program does not need them. The cards (`data/`), the special rule descriptions (`data/rules/`), the formations
(`data/formations/`), the cards and nations made in the program (`data/custom/`) and the card pictures
(`card_images/`) are included.

### Making a ready-made program (for the author)

In Godot: **Editor > Manage Export Templates > Download and Install** (once), then **Project > Export > Add... >
Windows Desktop**, tick *Embed PCK*, and **Export Project** into an `export/` folder (it is left out of the repository).
Zip the `.exe` and attach it to a new release on GitHub (*Releases > Draft a new release*).

## Using the program

Open `project.godot` in Godot 4.7 and press F5. The program opens on its **start menu**: the name **TY helper** (or a
picture of your own, see Settings) and one button per section: **Cards**, **Formations**, **Armies**, **Battle**,
**Test range** and **Settings**. Inside a section, the bar at the top leads back to the menu (**< Menu**) or straight
to another section.

* **Cards** - every card drawn as a real card in a wrapping grid (nation-coloured title strip, picture, key stats).
  Filter by nation, type or name. **Double-click** a card to open its full unit card in a window (click a special rule
  there to read it). That window is also where a card gets its **picture**: *Attach picture...* / *Remove picture*, or
  drag an image file onto the game window while it is open. A single click only highlights a card.
  Pictures are stored as `card_images/<card id>.png` (see below) and also appear in every card pop-up during battle.
* **Formations** - every nation's formations: look at them, try them out, edit them (see "Formations" below).
* **Armies** - build the armies in three steps (see "Building armies" below).
* **Battle** - the round manager. Each player turn runs through
  Starting -> Movement -> Shooting -> Artillery -> Assault, with every dice roll logged.
* **Test range** - two configurable test units to try any rule (see "The Test range" below).
* **Settings** - see below.

## Settings

Settings are saved at once (in `user://settings.cfg`) and kept for the next start.

* **Type in every dice result myself (roll real dice).** When ticked, every roll the program would make - to hit,
  saves, armour saves, Firepower, Remount, Rally, Strike Aircraft arrival, Cross Checks, Movement Order and Shoot and
  Scoot tests, Range In, Counterattack - stops and opens a window asking for the results. It says what the dice are for
  and what they need (for example "Each die needs 4+"). Click **1** to **6** for each die or type the digits
  (`6 5 3 1` or `6531`), then **Use these results** (or Enter). A single die is taken as soon as you click its number.
  **Roll for me** lets the program roll the dice still missing; closing the window does the same. Dice for one shot are
  asked together; saves, armour saves and Firepower tests are asked one hit at a time, in the order they are resolved.
* **Hide HQ units** has moved to the **Cards** section (a tick box above the cards). The HQ cards of every formation
  (card type "Tank Formation" / "Infantry Formation") are left out of the Cards list and of the army editor's card
  selector; the Formations section always shows them. HQ cards already in an army stay.
* **Don't use Morale.** Remembered for when Unit and Formation Morale are added; nothing changes yet.
* **Limit unit quantities** (on by default). Outside formations an army may take each artillery and AA unit at most
  twice and every other unit once, and never two units that are exclusive with each other. Units inside formations do
  not count. The numbers live in the unit files (see "Unit limits and formations in the data" below).
* **Use formations (every army must have one).** When ticked, every army has a formation: new armies get the first
  formation of their nation, *Uses a formation* on the Armies set-up page is always ticked (pick the formation beside
  it), armies without a formation cannot be loaded from the saved armies, and *Start battle* refuses one. It can only
  be ticked when no army without a formation has units that are not saved; the message names them. Save them first
  (Armies > Saved armies). When it is ticked, the armies without a formation are closed (they stay in their saved
  files) and new empty ones take their place if fewer than two players are left.

## Saving and loading armies

Every army can be saved as its own file, `NAME_NATION_army.json` (for example `Red Guard_Soviet_army.json`), in the
`saved_army` folder of the project (`user://saved_army` in an exported program). Characters a file name cannot hold
(and `_`, which separates the parts) become `-`. The file holds the name, nation, points limit, the formation (if the
army has one) and every unit with its size, upgrades and formation slot; it also lists each card's name, size and
points so it can be read.

* On the armies overview, **Save army** under each army saves it; the text beside it says *Saved as ...*,
  *Changed since it was saved* or *Not saved yet*. Saving a renamed army replaces its old file. Saving over a file of
  another army with the same name and nation asks first.
* **Saved armies...** (overview and the Players page) opens the list of saved armies: name, nation, formation,
  points, units and when it was saved. **Load** puts one into a player (or *as a new player*); loading over an army
  with unsaved changes asks first. **Delete** removes the file. **Save all** saves every player's army.
  **Import file...** copies a saved army file from anywhere into the folder; **Open folder** shows the folder.
* Cards or formations that are no longer in the data are left out when loading, and the page says which.

## Formations

On the first Armies page (*Main army of each player*) every army has a **Uses a formation** tick box. Tick it and a
drop-down appears beside it with the formations of that row's main army; pick one and press *Create armies*. The HQ
and every compulsory unit are put in at once (first size, no upgrades); where a compulsory slot offers several cards
(OR), the first one is preselected - click another card of the slot on the formation screen to swap. The same happens
when a formation screen or the Formations preview opens and a compulsory slot is still empty. Unticking removes the
formation and its units; picking another formation replaces it.

On the overview, an army with a formation has a **FORMATION** section under its block (name, points, what is still
missing) with **Edit formation**, which opens the formation screen, laid out like the FowList force diagram:

* **Top bar** - the **Formation** drop-down changes the formation (the old one's units are removed).
* **Headquarters and compulsory units** (top) - always in the formation, shown as cards. Click one to set its **size
  and upgrades**. Where a compulsory slot offers several cards, click another card to swap.
* **Additional units** (bottom) - one column per slot; the cards of a column are OR choices with a red **OR** between
  them. Click a card to take it: it gets a **gold outline**, and the other cards of its column, the cards of slots that
  are exclusive with it and cards exclusive with any unit in the army are **greyed out** (the tooltip says why).
  Click a chosen card again to change its size and upgrades, or **Remove from formation**.

Units outside the formation (support units) are still added in the army editor (click the army's block). There too,
cards the army cannot take are greyed out: units exclusive with one already in the army, units at their limit,
formation-only cards and, with a formation, HQ cards.

Every formation follows the Anatomy of a Formation:

* **HQ Unit** - every formation is led by its Headquarters unit, which commands the platoons of that formation.
* **Compulsory Units** (black tag) - must be filled to field the formation.
* **Optional Units** (grey tag) - extra combat or support platoons that scale it up.
* **Formation Command** - the commander only gives leadership bonuses to units of their own formation (not programmed
  in the battle rules yet; every battle unit already knows its formation).

With a formation, HQ cards and *formation-only* cards can only be taken inside the formation. Without one, HQ cards
are ordinary units (unless Settings hides them) and formation-only cards cannot be taken. *Start battle* refuses an
army whose list breaks these rules and says what to fix.

### Looking at, trying and changing formations (the Formations section)

**Formations** on the start menu (and in the bar on top) opens on **one card per nation**: its colour, how many
formations it has (and how many are still blank), its divisions and how many cards it has. **+ New nation** adds one.

Click a nation to see **one card per formation**: division, name, HQ card, compulsory and optional slots, and whether
it is *Ready* or something is *To check*. **+ New formation** makes one and opens the editor.

Click a formation to open its **preview**, laid out like an army's formation screen: HQ and compulsory units on top,
additional units below, the OR choices of a slot in one column. Click cards to try out a list and see the points
(*Chosen: N pts*); nothing is saved (**Clear choices** starts again). Of every choice only **one card is shown in
full**, also before anything is chosen; the others are **folded to one line**:
* in a slot with several cards (OR): the chosen card, else the card you picked there last, else the first card that
  can be taken;
* in slots that are "only one of" each other: only one of those slots shows a card - the filled one, else the one you
  picked from last, else the first - and the other slots are folded completely.
Click a folded card to take it instead, double-click it to read the card. The army's own formation screen
(Armies > Edit formation) folds cards the same way.

**Edit formation** opens the formation editor (described below); its *Back* button returns to the preview. The editor
is also in the **Cards** section: **Formation editing** puts it in place of the card list (*Back to the cards*
returns).

In the editor, on the left is the card selector with every card of every nation (the nation filter starts on the
nation picked in the top bar). HQ cards are always shown here, even with *Hide HQ units* on. On the right is the
formation being edited.

Every HQ card leads its own formation, so the program makes a **blank formation for each HQ card** that no formation
uses yet: named after the card without "HQ" (*T-80 Shock Tank Company HQ* -> *T-80 Shock Tank Company*), with that
card as its HQ, no division and no slots. Fill in the division and the slots here. This happens once, the first time
the formations are read; a new HQ card added to the unit data gets its formation the next time the program starts.
Deleting such a formation brings it back blank at the next start.

* **Top bar** - **Nation**, the **Formation** drop-down (shown as *Division - Name*, e.g. *228th Guards - BTR-60
  Motor Rifle Battalion*), **New** (an empty formation of that nation, keeping the division of the one shown),
  **Duplicate** and **Delete** (asks first; armies using it lose their formation).
* **Name** and **Division** - type them; *Pick...* offers the divisions the nation's formations already use. The id
  under them is made once and never changes, so saved armies keep finding the formation.
* **Headquarters** - drag the HQ card onto the box (or click a card on the left, then *+ Selected card*).
* **Slots** - *+ Add slot* adds a column. Drag cards onto it; two or more cards in one slot are the OR choices. Give
  it a group name (type it, or pick a common one with *v*), tick **Compulsory** for a black box (must be filled), leave
  it unticked for an additional unit. `<` `>` move the slot, `X` deletes it, *Remove* under a card takes it out.
  A unit that may be taken three times needs three slots.
* **Only one of (exclusive slots)** - *+ Add group*, then tick the slots of which only one may be filled.

Double-click a card in a slot to see the full card. Red text under the name lists anything to check (no HQ, a slot
without cards, a card id that is not in the unit data). Every change is saved at once to the nation's file in
`data/formations/` (in an exported program to `user://formations/`, which is then used instead).

## Unit limits and formations in the data

Every unit in `data/*_units.json` has three hand-editable fields:

```json
"max_copies": 2,             // times the unit may be taken outside formations (2 for artillery / AA, 1 for the rest)
"exclusive_with": ["TS102"], // ids of units that cannot be in the same army (outside formations)
"formation_only": false      // true = only inside a formation
```

They were added with `python tools/convert_units.py --update-fields` (artillery = a unit with an Artillery or Salvo
weapon; AA = a name with AA / SAM / Anti-Aircraft / Flak / Air Defence, or only Dedicated AA / Guided AA weapons;
aircraft and HQ cards are never counted as either). Converting the cards again keeps the values you edited.

Formations live in `data/formations/<prefix>_formation_data.json`, one file per nation with the same prefix as the
unit file (`us_formation_data.json`, `ussr_formation_data.json` ...). `ussr_formation_data.json` holds a complete
example (the BTR-60 Motor Rifle Battalion of the 228th Guards) and a `_help` list explaining every field: the name,
the optional `division`, the HQ card, the slots (group,
compulsory or optional, the card ids that may fill it) and `exclusive` groups of slots of which only one may be filled.
A unit that can be taken three times is three slots. Card ids that are not in the unit data yet are shown as
"no card" and cannot be chosen (TS128 BRDM-2 Recon in the example). The Formations section writes these files for
you; editing them by hand still works.
* **Start menu title.** *Choose picture...* shows a picture (PNG, JPG or WEBP) on the start menu instead of the name
  "TY helper"; *Remove picture* brings the name back. The picture is stored as `user://title_image.png`.

## Folder layout

    data/      one <nation>_units.txt (FowList copy) and one generated <nation>_units.json per nation
    data/rules special_rules.json (generated from the Special Rules PDF) and extra_rules.json (your own descriptions)
    data/custom      <nation>_units.json: the cards you made, copied or changed in the Cards tab
    data/formations  <nation>_formation_data.json: the formations (made in the Formations section)
    saved_army/      NAME_NATION_army.json: the saved armies (Armies > Saved armies)
    tools/     convert_units.py  (python tools/convert_units.py --all) and extract_special_rules.py (the rules PDF -> JSON)
    scripts/data      cards, armies, unit instances (UnitInstance = a unit on the table, with its teams)
    scripts/rules     ty_rules.gd (dice, to-hit modifiers, armour tables), combat.gd (shots, saves, bombardments, assaults)
                      and rules_db.gd (what a special rule does)
    scripts/battle    battle_state.gd (round / turn / step / log)
    scripts/ui        main, theme, card browser / sheet / tiles, the army screens (builder, player block, editor), battle screen and one panel per step
    scripts/tests     smoke_test.gd  (open scenes/smoke_test.tscn and press F6)
    assets/           parchment.jpg, the background of the cards
    card_images/      optional card pictures, one file per card id (TU102.png, TS114a.jpg ...)

## Importing cards and adding nations

In the **Cards** section, under the filters:

* **Import cards...** makes cards from text copied from FowList's list view, for any nation (also a new one). Pick the
  nation, paste the text (or **Load text file...**), press **Read the cards**: every card found is listed with what
  will happen to it (*new*, *replaces original* - a card of the original files, *Restore original* brings it back -
  or *replaces yours*) and anything the reader was unsure about. Untick what you do not want and press **Import
  ticked cards**. The reading rules are the ones of `tools/convert_units.py` (sizes with `(N points)` or
  `(14/dynamic: 13 points)`, a transport written `(TS126)` after its size line, options paid once / each / per model,
  HQs made of several stat cards ...); `data/ussr_units.txt` is a complete example. Card ids can start with any 1 to 3
  capital letters, so a new nation can have its own (e.g. FR101).
* **New nation...** adds a nation: the name the cards use, the name shown, the file prefix of its files and the colour
  of its cards. It is kept in `data/custom/nations.json` and appears in every nation list (cards, card editor, import,
  Formations, Armies). The card editor and the import window have the same button.
* **Formation editing** opens the formation editor (see the Formations section above).

## Making, changing and copying cards

In the **Cards** tab:

* **New card...** (top right) starts an empty card of the nation picked in the filter.
* Double-click a card, then **Edit card...** changes it, or **Copy card...** makes a new card from it. A copy gets a
  free id straight away (TS123 -> **TS123c**, then TS123c2 ...) and you can change it in the *Card id* box. An id
  that is already used is refused, so two cards never share an id. The copy also gets the original's picture.
* A changed card from the original files gets **Restore original** in its window (throws your changes away). A card
  you made gets **Delete card** (it warns when a formation, an army or another card still uses it).
* *Only my cards* (under the search box) shows just the cards you made or changed.

The card editor has these parts:

* **Card** - id, name, nation, **kind of unit** and card type. *Armored* has armour (tanks, APCs, SP guns), *Ground*
  is infantry and guns (Save, Rally), *Air* is helicopters and planes (aircraft type, movement Auto). Changing the kind
  shows the fields that kind has. Tick **Transport / attachment card** for a transport (BTR-60 Transport, M113 ...): it
  has no sizes or points of its own. **Passengers** is how many teams fit inside; it becomes the *Passengers N* rule.
* **Ratings** (Is hit on, Skill, Courage, Morale, Rally or Remount, Assault, Counterattack, Save, Armour) are the
  "n+" numbers of the card; 0 = the card does not have it. **Movement** in cm, -1 = Auto.
* **Special rules** and the **army list** limits (copies allowed, exclusive with, formation only), comma separated.
* **Weapons** - one row each: range, ROF halted / moving (0 = cannot fire), Salvo, Artillery, AT, FP, rules.
* **Sizes and points** - one box per size: points, dynamic points and its rows of models. A row can be linked to a
  **transport card** in its drop-down; those vehicles come into the battle as the unit's transport. The label is made
  from the rows when left empty.
* **Upgrades** - the text, the points and how they are paid: *once for the unit*, *each one picked*, or *for every
  model*. For every model you can count only models whose name has a word (e.g. *Milan*), use a fixed number (when
  the models come from another option), and charge once per group ("per two aircraft" = 2, "every eight teams" = 8).

**Linking transports.** On a unit's card, *Transport* > **Link transport card** picks a transport and **Add to every
size** puts that many vehicles into every size (adjust each size afterwards). On a transport card, *Units that ride in
this transport* lists who uses it, and **Link to unit** gives it to another unit (one vehicle per size; set the right
number in that unit's card).

Your cards are saved in `data/custom/<nation>_units.json` (in an exported program `user://custom_units`). They are
read after the original card files and replace a card with the same id, so running `tools/convert_units.py` again
never loses them.

## Card pictures

Every card can have one picture (a photo of the model, artwork, anything). Three ways to give a card its picture:

1. Double-click the card in the Cards tab -> **Attach picture...** (a normal file dialog opens).
2. Double-click the card, then **drag an image file onto the game window**.
3. Copy a file named after the card id into `card_images/`, for example `TU102.png`, `TS114a.jpg` or `TU105.webp`.
   The id is printed on every card.

Where pictures are stored:

* Running from the Godot editor: `card_images/<id>.png` inside the project (so they stay in your project and in git).
* In an exported game: the `user://card_images` folder (on Windows `%APPDATA%\Godot\app_userdata\<project name>\card_images`).
* Lookup order is `user://card_images` first, then the project's `card_images/`.

Large pictures are shrunk to 1024 px and saved as PNG; the cards in the grid use a smaller copy so hundreds of pictures
stay light. *Remove picture* deletes the file again. A picture shows on the card in the grid, in the card window and
in every other large card pop-up (also the ones opened from the Battle tab).

## Building armies

1. **Main army of each player**: name, nation (the "main army") and an optional points limit for every player. The
   **+** and **-** buttons under the list add a player to the list or remove the last one (2 to 8 players). The list
   starts with two armies: Player 1 American, Player 2 Soviet.
2. **Overview**: one block per player with the main army, number of units, points (and what is left of the limit),
   models and the split between Armored / Ground / Air. Click a block to build that army. *Start battle* is here too
   (with more than two players it asks who fights and in which team, see "Teams" below).
3. **Army editor**: the card selector (same grid and filters as the Cards tab, starting on the main army's nation)
   on the left and the army as small cards on the right.
   * Drag a card from the selector onto the army list to add one copy (the whole card follows the mouse; it is added
     with its first size and no upgrades).
   * **Double-click** a card, in the selector or in the army list, to open the full card. There you click the **size**,
     **tick the upgrades** you want (each check box shows its points) and set the **number of copies**. Options are
     paid in one of three ways, shown after their text:
     * **+1 pt** - once for the unit ("Add AT-11 Sniper missile for +1 point", "Fit up to three tanks ... +1 point").
     * **+1 pt each** - for each one you pick: a box asks how many ("Replace any or all ... +1 point each",
       "Add up to two ... +1 point each"; the most is the "up to" number or one per model).
     * **+1 pt per model** - for every model it covers in the size you chose, counted for you ("... to all T-80
       tanks for +1 point per tank": 10 tanks = 10 points; "Milan 2 ... per team": the Milan teams of that size;
       "+3 points per two aircraft"; "one Mi-8 for every eight infantry teams": 15 teams = 2).
     The price line adds it all up. The price line adds it all up. From the selector the button is *Add to army*; from the
     army list it is *Apply changes* (it replaces that card). There are no picture buttons here (they are only in the
     Cards tab). The army total, the player block, the card footer and the points lost in battle all include the upgrades.
     The same unit with different upgrades is a different card.
   * Drag a card from the army list back onto the card selector to take one copy out.
   * A unit bought several times is one card with **xN** in a black circle at its top right.
   * **Remove selected** is a mode: click cards to mark copies (a red circle at the top left shows how many; click
     again for one more, right-click for one less), then press **Accept** (it appears to the left of the button).
     Pressing the button again cancels the mode. **Clear army** empties the list (and removes the formations).
   * Points limit and name can be changed at the top.
   * With Settings > *Limit unit quantities* a card that may not be taken again is refused with the reason, and the
     copies box of the card window stops at what is still allowed. What still has to be fixed is listed in the pane.
   * With a formation, this list holds the support units; the formation itself is edited on the formation screen
     (see "Formations" above). **Clear army** then only clears the support units.

The whole interface uses the look of the card sheet: parchment pages, dark ink text, brown buttons and tabs, nation-coloured
title bars (the theme is built in `scripts/ui/app_theme.gd`).

## Teams (2 to 4 players in a battle)

With two players *Start battle* starts a normal 1v1. With more players a window asks, for every player, **Not playing**
or **Team A / B / C / D**. Players with the same team fight together, so 2v2, 3v1, 2v1, 1v1v1, 2v1v1 and everyone
against everyone are all possible (any split of 2 to 4 players into at least two teams).

A turn belongs to a **team**: all its players play each step together (their units are listed together in the step
panels, prefixed with the player's name), and every other team is the enemy that can be targeted. Teams play in the
order A, B, C, D; a round ends when every team has had its turn. The Battle tab shows the turn order with the team
playing now highlighted, and one block per team with each player's points, points lost and the state of every unit.

## Models, their codes, icons and weapons

In the Battle tab every unit is split into its **models** (each vehicle, aircraft, gun or infantry team), also when
several models are the same kind. The models are shown as a grid of small tiles: **icon, code and name**
(for example an icon, `IA3`, "M16 rifle team"). The code is:

    I A 3      I = type of unit:  I infantry, T tanks, A artillery, C carriers / transports,
                                  H helicopters, P planes
               A = which unit of that type (A, B, C ... per player)
               3 = the third model of that unit

With more than two players the player number comes first (`2IA3`). Transports that have their own card (for example
the BMP-1s of a Soviet company) are a unit of their own (`C...`), listed right after the unit they came with. Tiles
and names use the colour of the player's army card.

**Icons** are configurable. Click a unit's name in the Battle tab -> **Set icon...** to choose a picture for the models
of that card (**Remove icon** undoes it), or put pictures in the `model_icons` folder named after a card id
(`TU102.png`) or a type letter (`I.png`, `T.png`, `A.png`, `C.png`, `H.png`, `P.png`). Models without a picture show a
drawn symbol for their type.

**Which weapons a model fires.** A card lists every weapon of the unit, but each model only fires its own. The program
guesses this from the names; to specify it yourself use **Weapons per model...** (Cards tab -> double-click a card, or
Battle tab -> click a unit's name). Tick, for every kind of model, the weapons it can fire. It is saved in
`data/model_weapons.json` (`user://model_weapons.json` in an exported game) as
`{ "card id": { "kind of model": ["weapon name", ...] } }` and can also be edited by hand.

## Round 0 and transports

A battle starts with **round 0**, which only sets up who is carried. Every player has two sets, the **infantry** and
the **carriers**. Drag an infantry model onto a carrier: on the **top** box to ride on the outside (up to 3, ground
vehicles only), on the **bottom** box to ride inside (as many as "Passengers N" on the vehicle's card). Drag it back
to the infantry box to leave it on foot. Then press *Start round 1*.

## Movement, model by model

The Movement step lists every model of every unit. For each model choose the kind of move and drag the **distance
slider**: it stops at the distance the card gives for that kind of move. Cross tests are rolled per model. *All
models* sets the same kind of move for the whole unit; Movement Orders stay per unit. The unit as a whole counts as
having moved as much as its fastest model; a shot uses the movement of the models that fire.

The **Where** column of an infantry model: *On foot*, *In a building*, *Inside <vehicle>* or *On top of <vehicle>*.
A unit can move and mount, or ride with its carrier, dismount and then move on its own. As in the rulebook, a model
**cannot Mount and Dismount in the same turn** and it **dismounts before its Transport moves**. Inside: as many as
"Passengers N" on the card; on top: up to three, on Armoured Tank Teams only. Carried models cannot shoot, assault or
be shot at. Riders on top are hit every time their tank is hit; when a transport is destroyed each passenger rolls an
Infantry Save and the survivors get out Pinned Down (in an aircraft they are destroyed with it). Infantry in a
building or in Foxholes is in Bulletproof Cover automatically.

## Shooting, model against model

1. Press **1. Shoot** and click the models that fire (gold frame). The models must be of the same kind (for example
   all M1A1 Abrams) but may come from any of your units.
2. Press **2. Choose targets** and click the enemy models that are shot at (red frame), from any enemy units. Every
   click aims one shot; a chosen model shows **- xN +** on top to aim more or fewer shots at it. The shots can never be
   more than the combined ROF of the shooters (models x ROF), and each model takes the hits of the shots aimed at it.
3. Pick the weapon (only the weapons all those models have), set the range with the **slider** (it goes up to the
   weapon's range) and the situation. Range, armour facing, Concealed, Gone to Ground and Bulletproof Cover are set
   **per target unit**: when the targets belong to more than one unit, pick the unit in **Target unit** first.
4. Read the explanation: how many dice and why, what each die needs and why (one line per shooting unit and target
   unit), what the target rolls for every hit and who takes the hits.
   When the volley has different to-hit numbers (for example 3+ against one unit and 5+ against another), all dice are
   rolled together and the **highest results go to the hardest numbers first**. A roll passes when it is equal to or
   higher than the number: a 3+ is passed by a 3, 4, 5 or 6. Then **FIRE!**: the to-hit dice tumble and turn green (hit) or red (miss), followed by rows for the saves or armour saves and the Firepower tests; saves and
   results are written to the event log. Each model can fire each of its weapons once per turn.

Hovering a model shows its to-hit number (Is Hit On), its front / side / top armour (or its Save), its state and its
weapons.

## The rules the program follows

The core rules follow the rulebook text you supplied (`Rules_clean.txt`, pages 28-56): Starting Step, movement and
Movement Orders, transports, shooting, saves, Pinned Down, Smoke and Artillery. Special rules come from the Special
Rules PDF. Whenever a special rule changes a number or allows something, **its name is written** in the explanation
before the roll and in the event log ("special rule Thermal Imaging", "special rule Brutal", ...).

What is applied:

* **Movement**: Tactical and the three Dash speeds per model, Cross Checks (a fail = **Bogged Down** until the model's
  next turn: no moving, shooting or assaulting), the orders Blitz Move, Follow Me, Cross Here (Cross number -1, no
  shooting or assaulting), Dig In (Foxholes = Bulletproof Cover until the unit moves, Moving ROF, no bombardment) and
  Shoot and Scoot (button in the Assault step).
* **Which weapons fire**: an Infantry model fires one of its weapons per turn; a Tank or Aircraft model fires all its
  MGs or one other weapon; a Bombardment is fired instead of the other weapons.
* **To hit**: Is Hit On, +1 over 40cm, +1 Concealed (+2 Concealed and Gone to Ground), +1 Out of Command, +1 Smoke,
  +1 Night, 7+ and 8+ needing a 6 and a second roll, ROF 1 against Aircraft for weapons that are not Dedicated AA.
* **Saves**: Armour Save (die + armour, +1 over 40cm) against Anti-tank, then Firepower; Bailed Out and the Remount
  roll when Bailed Out again; Infantry Save with Firepower against Bulletproof Cover; Unarmoured and Aircraft Saves.
* **Pinned Down**: 5 hits in one Shooting Step (8 for units of 12 or more); Pinned Down Infantry and Unarmoured units
  shoot with Moving ROF and cannot shoot at all if they moved. **Firing Smoke** with weapons that have the Smoke rule.
* **Artillery**: who may bombard (not after Moving unless Aircraft, not while Pinned Down unless Armoured), the
  Spotting Team (one bombardment per turn, did not move or shoot; the worse Skill is used; Observer -1), three
  attempts to Range In, to hit = Is Hit On + number of weapons firing + 2nd / 3rd attempt (+1 / +2) + Gone to Ground,
  no Line of Sight from the spotter, Smoke, Night (+1 each), never better than 2+, Top armour, automatic Pin Down,
  Repeat Bombardments and Smoke Bombardments.

**One number is a reconstruction.** The scan lost most of the "Number of Weapons Firing" table; only "5 or 6", "7 or
more" and the worked example (five or six guns = -1) survive. The program uses 1-2 weapons +1, 3-4 none, 5-6 -1, 7 or
more -2. If your rulebook says otherwise, change `WEAPONS_FIRING_TABLE` at the top of `scripts/rules/ty_rules.gd`.

Not automated (do these by hand): Line of Sight, Concealment and ranges are what you tick or set; Commanders and Unit
Leaders, Out of Command movement, Mistaken Target, Formation Morale, Ambushes, Reserves, landing Transport Aircraft,
and the special ammunition Bomblets, Minelets and Laser-Guided Projectiles. The assault rules were not in the
document, so the Assault step still follows the Quick Reference.

## The Test range

The **Test range** tab lets you try any situation without building armies. It has two test units, A (yours) and B
(the enemy):

1. Fill in each unit: choose a **preset** (infantry platoon, main battle tank, IFV with Passengers, artillery battery,
   AA gun, truck, attack helicopter, strike aircraft) or type a **card id** and press *Copy card*, then change anything:
   type, number of models, Is Hit On, Save, armour, Skill, Courage, Rally / Remount, Assault, Counterattack, Cross,
   the four movement distances, the unit's special rules, and up to three weapons (range, minimum range, ROF halted /
   moving, Anti-tank, Firepower, direct fire / Artillery / Salvo, weapon rules). Special rules are typed as on the
   cards, separated by commas.
2. Set the **situation** of each unit: how it moved and how far, Pinned Down, in Foxholes, in a building, already
   shot, and how many models are Bailed Out or Bogged Down.
3. Choose the step to start at (round 0, Starting, Movement, Shooting, Artillery or Assault) and who plays, and press
   **Start the test**.

The normal round manager opens on the two units. Each panel explains its numbers before you roll and the event log
shows every roll and every special rule applied. *Test settings* returns to the form so you can change one thing and
start again. Things to try: move a tank more than 25cm and shoot with and without Stabiliser; shoot through Smoke
with and without Thermal Imaging; Pin Down the infantry and let it shoot; put B in Foxholes or a building and compare
the saves; bombard with 2, 4 and 6 guns; fire HEAT at a tank with Chobham Armour or ERA.

## Artillery and assaults, model against model

**Artillery** works like shooting. Press **1. Bombard** and click the models that fire (same kind, same unit, with an
Artillery or Salvo weapon), pick the weapon and **Range In**, then press **3. Choose targets** and click every enemy
model under the Template (they may belong to several units). The explanation shows the number of weapons firing and its
to-hit modifier, the score to hit each unit and what every hit does. **FIRE** rolls one die per model under the Template.
Smoke Bombardments need no targets.

**Assaults.** Press **1. Assaulting models** and click the models that charge (one unit), then **2. Defending models**
and click the enemy models in contact or within 20cm (one unit). Then: **3. Charge**, **4. Defensive Fire** (tick the
weapons; every chosen defender that has the weapon fires it at the assaulting models), **5. Roll** (one die per
assaulting model that is still OK, hits go on the defending models), **6. Is it over?** If the defenders pass their
Counterattack test the roles swap (the frames swap colour) and you repeat 5 and 6.

## The card sheet

The selected card (right side of the Cards tab) and the large card pop-up use the same layout as the Team Yankee
force-builder page: a nation-coloured title bar; on the left the purchase options with their points badges, then the
upgrades and notes; on the right the unit-type line, the picture, the red Courage / Skill pills with Morale, Rally or
Remount, Assault and Counterattack (not shown for aircraft and helicopters; ground units always show them, as "-" when
they have none), the Is Hit On and Save boxes (or the Front / Side / Top armour box for vehicles), the
movement table and the weapons table with the notes in italics. In a narrow window the options move under the card.
Colours: American is the web page's green; other nations use the colour of their tile (edit `CardTile.nation_color_for`).
Everything sits on the parchment picture `assets/parchment.jpg` (the sheet, the picture frame, and behind the card
grid and the pictures on the tiles); replace that file to change the look. Everything that sits on a rounded frame is
rounded to match (pictures and the parchment get a small rounding shader, tables and boxes keep a margin so their square
cells stay inside the rounded corners): see `UIUtil.round_holder` and `UIUtil.round_texture`.
The two pictures that came with the web page (TU104, TU105) are already in `card_images/`.

## Special rules: click one to read it

Every special rule on a card is a blue link: the unit's rules under its name, and the weapon rules in the *Notes*
column. Click one (in the Cards tab, in a large card pop-up, or in the *Weapon rules / Unit rules* box of the Shooting
and Artillery steps) and a window shows the rule text from the **Special Rules PDF**: the italic flavour text, the rule,
and where it comes from (general rule, or the nation's own rule, with the PDF page).

* The unit's own nation comes first; if the PDF also has a general rule with that name it is shown below it
  (for example Radar, or Bazooka Skirts).
* Card names are matched loosely: `Assault +1` / `Assault 5+` find "Assault #", `Passengers 2` finds "Passengers #",
  `ERA` finds "ERA Armour", `Infra-Red (IR)` finds "Infra-Red", `Advanced Stabiliser` finds "Advanced Stabilisers".
* Rules the PDF does not describe (Bomblets, Minelets, Krasnopol Projectile, Laser Guided Projectiles, Landing Company)
  are grey links; the window says there is no description. To add one, put it in `data/rules/extra_rules.json`
  (the note at the top of that file explains the format). Your text is shown before the PDF text for the same rule.
* The PDF prints the Soviet Army section twice (pages 10 and 11); identical rules are merged and list both pages.
* To rebuild the data from the PDF (needs `pip install pdfplumber`):
  `python tools/extract_special_rules.py "World-War-III-Complete-Special-rules.pdf"`
  The PDF does not say which book each national rule is from, so the book is left empty (only the American militia
  rules on page 6 state "Red Dawn").

## Adding a nation

1. Copy the FowList text into `data/<name>_units.txt`.
2. Add the prefix to `NATION_BY_PREFIX` in `tools/convert_units.py` (or pass `--nation`).
3. `python tools/convert_units.py --all` and read the warnings.

## What the round manager does

* **Movement** - mode (Halted / Tactical / Terrain Dash / Cross-Country Dash / Road Dash), distance in cm against the
  card's limit, Cross test (D6 vs the card's Cross rating, result shown), Movement Orders (Blitz, Follow Me!, Cross Here,
  Dig In) with their Skill / Courage tests.
* **Shooting** - choose shooter, weapon, target team, range, facing and conditions. The preview shows dice and the
  score needed. Rolls to hit (7+/8+ handled), hit allocation, Armour Saves (Anti-tank, Firepower tests, Bail Out, Remount
  if bailed again), Infantry / Aircraft Saves, Brutal, HEAT vs special armour, Tandem Warhead, Pinned Down, anti-aircraft
  restrictions and ROF 1, Guided / Laser Rangefinder / Accurate / Radar range rules, Stabiliser limits.
* **Artillery** - Range In (three attempts on the spotter's Skill), Template groups per target unit, re-rolls by number of
  weapons firing, Top armour saves, Repeat Bombardments, Smoke Bombardments, aircraft Salvo weapons.
* **Assault** - Charge, Defensive Fire (and Fall Back), roll to hit on Assault, no saves for Infantry / Unarmoured,
  Side or Top armour attacks on tanks, Test to Counterattack with role swap, Break Off.
* **Starting Step** - Remount, Rally, Strike Aircraft arrival.

## Not implemented (do these by hand)

Unit / Formation Morale, Reserves and Ambushes, Minefields, Night visibility rolls (Night is a +1 toggle), hull / turret
roll (pick the facing), special ammunition (Bomblets, Minelets, Laser-Guided), Napalm, Command Leadership re-rolls,
passenger saves when a transport is destroyed.

Rules sources: TY Quick Reference, Complete Special Rules download, Field Manual 101 (March 2024).
