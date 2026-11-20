# Tamriel Tools: Lead Filters

A provisioning-style filter sidebar for **Scryable > All Leads** and
**Scryable > Current Zone** in ESO's keyboard antiquities journal. By Handshot.

## Features

- **Text search:** the first sidebar filter matches lead, completed set, and
  zone names. Every word must match; word order does not matter. Search is
  case-insensitive and literal.
- **Type:** choose a reward type from the entries in the selected Scryable list.
  Types use ESO's own localized reward labels. Set fragments use the completed
  set's reward type when available.
- **Lead Status:** show all native groups or just In Progress, Available,
  Requires Lead, Active Leads, or Requires Scrying Skill. Membership follows
  ESO's section rules, not just whether an entry has a lead item. Permanently
  available antiquities can therefore appear under Available without a lead.
- **Difficulty:** one compact row of neutral **Advanced**, **Master** and
  **Ultimate** buttons. Selected buttons are bright; excluded buttons are
  dimmed. Hover to see the selection state, or drag the teal range handles
  for a contiguous selection. There is no passive-rank mapping. Legacy Trivial,
  Simple and Intermediate selections are removed; selections for the three
  remaining difficulties are kept. Use Reset to enable all three if needed.
  This uses ESO's reported difficulty, matching the native journal row, not a
  wiki's base tier.
- **Lead Quality:** independently toggle Green, Blue, Purple and Gold
  using coloured hexagons in ESO's native quality colours.
  Drag its separate teal range handles to select a contiguous quality range;
  toggling colours also updates those handles. Reset restores the full range.
  This matches the lead name's colour, not its difficulty. Fragments use their
  own quality, not that of the completed set. All qualities start enabled.
  White and Orange and their legacy saved selections have been removed.
- **Codex progress:** each discovered Scryable lead with lore entries displays
  an unlocked/total count, such as **1 / 3**, with ESO's native Codex styling
  at the top right of the row. This is actual lore progress, not the Found
  recovery count. Fragments show their own progress, not the completed set's.
  Leads without lore entries have no counter.
- **Sort by Zone**, **Lead Expiry (soonest first)**, or **Alphabetical**.
  Sorting applies **within each native group**. Expiry sorting puts entries
  without a positive lead timer last within their group. Zone sorting puts
  "Any zone" entries last; ties are broken by name and antiquity ID.
- A matching/total count and a reset-arrow button. Filter and sorting choices
  are remembered per character. All filters work together; Reset enables all
  difficulties and qualities, and restores all lead statuses.

ESO's native section order and localized headings are retained, including
Available, Requires Lead and separate skill-requirement headings. Empty groups
are hidden. An entry belongs to its first matching native section and appears
only once. Native grouping takes priority over expiry or alphabetical sorting
across different groups. Rows remain native ESO lead tiles: difficulty, zone,
expiry, progress, tooltips, scrying, map and codex actions still come from ESO.

The sidebar uses the same fonts, teal range styling, original hexagon artwork
and reset icon as Tamriel Tools: Provisioning Filters. Its header aligns with
the native Quest Journal title, and its footer extends to the journal's bottom.
A connected native ESO background spans the sidebar and journal without a
separate black box or doubled-dark seam. The texture's vertical fade, coordinates,
tint and alpha are preserved. Placement follows the live header/background
geometry when the UI is resized.

Only the antiquities scene's `RIGHT_BG_FRAGMENT` membership is temporarily
replaced. The native background controls are never directly hidden, resized or
recolored, and the original scene membership is restored on codex/category
changes, scene hiding, parent-driven hiding and gamepad transitions. Other
scenes and the provisioning background remain unchanged. No library dependencies
or dependency on the provisioning addon.

## Installation

For a release installation, copy this folder to
`live\AddOns\TamrielToolsLeadFilters`, enable **Tamriel Tools: Lead Filters**,
and reload the UI.

For this development workspace, `..\..\live\AddOns\TamrielToolsLeadFilters` is
a Windows directory junction to this source folder
(`programming\Tamriel-Tools-Lead-Filters`). That relative path is from this
project directory. Source changes are available through the junction without
copying; reload the UI to load changes.

## Scope and compatibility

- Only affects the two keyboard Scryable subcategories. The ordinary antiquities
  codex, gamepad journal, map and scrying minigame are unchanged.
- Keeps ESO's visibility, current-zone and section eligibility rules. Selecting
  a different sort or status does not make an otherwise unavailable lead
  scryable. In particular, the native Active Leads section remains excluded
  from Current Zone.
- Uses the game data manager's lead timers, not a separate saved expiry database.
- Difficulty and quality come directly from ESO's antiquity data. A green lead
  reported by the client as Advanced still passes the Advanced difficulty
  filter, but can independently be hidden using the Green quality button.
  No difficulty is inferred from colour or overridden using an external list.
- The sidebar's search is separate from ESO's existing journal/codex search.
  Reset does not change that search or the selected category.
- The former Recovery filter and its saved selection have been removed.
  Recovery history no longer excludes entries.
- Switching categories preserves the selected type, even if it has no matches
  in the new category. Select "All types" or reset to clear it.
- Other addons replacing keyboard antiquities list construction may conflict.
  Reproduce issues with those addons disabled before reporting them.

## Performance

Opening relies on ESO's scheduled journal refresh rather than starting an extra
list build from the addon's scene callback. Existing Codex controls are reused
and updated once per row layout. Search words are normalized once per build,
and native section visibility is checked once per section.

Acquiring a lead still queues a membership refresh, but clearing its "new"
indicator does not. Any intervening native or filter rebuild consumes the pending
addon refresh instead of rebuilding again on the next timer tick. Live lead
timers, status membership and Codex counts are still read afresh; there is no
persistent list cache. ESO still lays out all matching native tiles, so very
large lists can still cause an opening hitch.
Rebuilds restore native tooltip and action state when the previously hovered
pooled tile remains visible; hidden tiles do not regain hover state.

## Tests

Run the mocked regression tests from this directory with Lua 5.1:

```powershell
lua .\tests\runtime.lua
```

For dependency setup and measured coverage, see the
[shared setup and coverage guide](../Tamriel-Tools/tools/testing/README.md);
select `--project Tamriel-Tools-Lead-Filters`.

The tests cover filtering, independent quality/difficulty selections, quality
range handles, preferences and reset, search-first placement, native group
headings/order, status selection and updates,
within-group sorts, expiry snapshots, set fragments, Codex counts and pooled-row
refresh/cleanup,
native candidate eligibility, empty lists, saved choices, reset, deferred
initialization, scene isolation, search debounce, connected-background ownership,
responsive anchors and cleanup. Runtime integration
was checked against ESO UI API version `101051`.
Performance regressions also exercise a 600-lead list, checking one build per
opening, one Codex update per tile layout, reused controls, and pending-refresh
coalescing. These work-count tests do not measure in-game frame time.

## In-Game Verification

In-game verification is still required:

1. Open Journal > Antiquities > Scryable > All Leads. Check the filter header
   aligns with the Quest Journal title, the sidebar joins the native background without
   a gap or doubled opacity, and its footer aligns with the journal's bottom.
   Verify fonts, textures, scrolling and readable labels at your resolution/UI
   scale. Repeat at a smaller resolution and with a larger UI scale, including
   resizing while the journal is open.
2. Select types, toggle all difficulty tiers including all off, and drag both
   handles. In the separate Lead Quality row, disable Green and Blue:
   no names in those colours should remain, regardless of reported difficulty.
   Drag both quality range handles, check the selected colours follow the range,
   and confirm the difficulty selection stays unchanged. Check colour toggles,
   saved choices and Reset keep the quality slider in sync.
   Test all qualities off, Reset, and combinations with difficulty and type.
   Select Available and Requires Lead in Lead Status. Compare their membership
   and headings with the journal without the addon. Test In Progress, Active
   Leads and skill requirements where present; filtering must hide empty groups.
   Test multiple search words, names with punctuation, set
   names and zone names. Check count and empty-state behavior.
3. Sort by zone and expiry. Native groups must keep their original order.
   Within each group, urgent timed leads must precede later-expiring and
   untimed entries; headers and tiles must not overlap.
4. Hover, scry, show a dig site on the map, abandon progress and open the codex.
   Verify all native actions still refer to the displayed lead.
   Compare the Scryable row's Codex count with its normal codex entry, including
   1/1, partial 1/3 and complete 3/3 entries recovered more than three times.
   Check long titles, reward types and zones do not overlap the right-hand
   counter, and that expiry/progress icons retain their native placement.
5. Acquire, expire, recover or consume a lead while the journal is open. Verify
   membership, count, sorting and type choices update. Reload the UI and switch
   characters to check saved preferences.
   Open and close All Active Leads repeatedly using J, including after lead
   changes while closed. Check opening responsiveness and that clearing a new
   lead marker does not rebuild the whole list or reset hover/scroll.
6. Switch to Current Zone, another zone's codex, gamepad mode and other menus.
   Check panel/dropdown/focus cleanup and unchanged native codex/gamepad lists.
   Visit provisioning, inventory and the quest journal afterward: backgrounds
   must retain their native placement, tint and opacity with no lingering sidebar
   background.
7. Test a character without scrying unlocked; native unlock messages must remain.

Mocks cannot verify actual UI rendering, client data or addon coexistence.

## Artwork and license

The included DDS textures are generated from the suite's original
`Tamriel-Tools\addons\provisioning-filters\assets` PNGs. Regenerate them from this
project directory:

```powershell
foreach ($asset in @("QualityFrame", "QualityFill", "Reset")) {
    ..\Tamriel-Tools\tools\images\Convert-PngToEsoDds.ps1 -InputPath "..\Tamriel-Tools\addons\provisioning-filters\assets\$asset.png" -OutputPath ".\Icons\$asset.dds"
}
```

No third-party database or artwork is included. [MIT](LICENSE).
