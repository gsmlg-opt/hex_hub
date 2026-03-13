# DuskMoon UI Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace DaisyUI with `@duskmoon-dev/core` as the Tailwind CSS plugin and upgrade `phoenix_duskmoon` to v9 for all HEEX components.

**Architecture:** Remove DaisyUI dependency entirely. Use `@duskmoon-dev/core/plugin` as Tailwind v4 plugin with MD3 color system (sunshine/moonlight themes). Upgrade `phoenix_duskmoon` hex dep from `~> 7.0` to `~> 9.0` and use its `dm_*` components where possible. Replace inline SVG icons with `dm_mdi` Material Design Icons throughout.

**Tech Stack:** Elixir/Phoenix 1.8, phoenix_duskmoon 9.x, @duskmoon-dev/core (CSS), @duskmoon-dev/elements (custom elements), Bun bundler, Tailwind CSS v4

---

## Color System Migration Reference

DaisyUI → @duskmoon-dev/core (MD3):
- `bg-base-100` → `bg-surface`
- `bg-base-200` → `bg-surface-container`
- `bg-base-300` → `bg-surface-container-high`
- `text-base-content` → `text-on-surface`
- `text-base-content/70` → `text-on-surface-variant`
- `text-base-content/60` → `text-on-surface-variant`
- `text-base-content/40` → `text-on-surface-variant`
- `text-primary-content` → `text-on-primary`
- `border-base-200` → `border-outline-variant`
- `border-base-300` → `border-outline`
- `btn-accent` → `btn-tertiary`
- `text-accent` → `text-tertiary`
- `bg-accent` → `bg-tertiary`
- `badge-ghost` → `badge-outline`
- `badge-accent` → `badge-tertiary`
- `table-zebra` → `table-striped`
- `shadow-primary-content` → `shadow-primary/20`

## Component Migration Reference

DaisyUI → @duskmoon-dev/core or dm_* component:
- `join` + `join-item` → flex group with `gap-0` and `[&>*:not(:first-child)]:rounded-l-none [&>*:not(:last-child)]:rounded-r-none`
- `stats` + `stat` → card-based layout (custom)
- `hero` + `hero-content` → flex layout (custom)
- `mockup-code` → `bg-neutral text-neutral-content rounded-lg p-4 font-mono` (custom)
- `dropdown` + `dropdown-content` → `dm_dropdown` component
- `modal` + `modal-box` → `dm_modal` component
- `collapse` + `collapse-arrow` → `dm_collapse` or `accordion` class
- `toggle` + `toggle-primary` → `switch switch-primary`
- `file-input` + `file-input-bordered` → `input` with `type="file"`
- `input-bordered` → `input` (default has border in duskmoon)
- `select-bordered` → `select` (default has border in duskmoon)
- `form-control` → `form-group`
- `label-text` → `form-label`
- `label-text-alt` → `helper-text`
- `tabs tabs-boxed` → `tabs`
- `tab-content` → panel div (manual)
- `drawer` → `dm_drawer` or `drawer` class
- `menu` → `dm_left_menu` or `nested-menu` class
- `breadcrumbs` → `dm_breadcrumb` component
- `btn-disabled` → use `disabled` attribute
- `btn-active` → keep or use active state
- `data-theme="light"` → `data-theme="sunshine"`

---

### Task 1: Update Dependencies

**Files:**
- Modify: `mix.exs`
- Modify: `package.json`

**Step 1: Update mix.exs**

Change `phoenix_duskmoon` dep from `~> 7.0` to `~> 9.0`:

```elixir
{:phoenix_duskmoon, "~> 9.0"},
```

**Step 2: Update package.json**

Replace daisyui with @duskmoon-dev packages:

```json
{
  "name": "hex_hub",
  "private": true,
  "dependencies": {
    "phoenix": "^1.7.21",
    "phoenix_html": "^4.2.1",
    "phoenix_live_view": "^1.1.3",
    "@duskmoon-dev/core": "latest",
    "@duskmoon-dev/elements": "latest"
  },
  "devDependencies": {
    "@tailwindcss/typography": "^0.5.16",
    "phoenix_duskmoon": "^9.0.0"
  }
}
```

**Step 3: Install dependencies**

Run: `mix deps.get && bun install`

**Step 4: Commit**

```
feat: update deps to duskmoon-dev/core and phoenix_duskmoon v9
```

---

### Task 2: Update CSS Files

**Files:**
- Modify: `assets/css/app.css`
- Modify: `assets/css/admin.css`

**Step 1: Update app.css**

Replace daisyui plugin with @duskmoon-dev/core plugin and theme imports:

```css
@import "tailwindcss";
@plugin "@tailwindcss/typography";
@plugin "@duskmoon-dev/core/plugin";
@import "@duskmoon-dev/core/themes/sunshine";
@import "@duskmoon-dev/core/themes/moonlight";
@import "@duskmoon-dev/core/components";

@source "../js";
@source "../../lib/hex_hub_web";
@source "../../deps/phoenix_duskmoon/lib/phoenix_duskmoon/";
```

**Step 2: Update admin.css**

Same pattern but sourcing admin web:

```css
@import "tailwindcss";
@plugin "@tailwindcss/typography";
@plugin "@duskmoon-dev/core/plugin";
@import "@duskmoon-dev/core/themes/sunshine";
@import "@duskmoon-dev/core/themes/moonlight";
@import "@duskmoon-dev/core/components";

@source "../js";
@source "../../lib/hex_hub_admin_web";
@source "../../deps/phoenix_duskmoon/lib/phoenix_duskmoon/";
```

**Step 3: Commit**

```
feat: replace daisyui with @duskmoon-dev/core in CSS
```

---

### Task 3: Update JavaScript Files

**Files:**
- Modify: `assets/js/app.js`
- Modify: `assets/js/admin.js`

**Step 1: Update app.js**

Add DuskmoonHooks and register elements:

```javascript
import { Socket } from "phoenix";
import "phoenix_html";
import { LiveSocket } from "phoenix_live_view";
import * as DuskmoonHooks from "phoenix_duskmoon/hooks";
import { registerAll } from "@duskmoon-dev/elements";

registerAll();

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...DuskmoonHooks },
});

liveSocket.connect();
window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    reloader.enableServerLogs()
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)
    window.liveReloader = reloader
  });
}
```

**Step 2: Update admin.js**

```javascript
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import * as DuskmoonHooks from "phoenix_duskmoon/hooks";
import { registerAll } from "@duskmoon-dev/elements";

registerAll();

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/admin/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...DuskmoonHooks },
})

liveSocket.connect()
window.liveSocket = liveSocket
```

**Step 3: Commit**

```
feat: add DuskmoonHooks and register custom elements in JS
```

---

### Task 4: Update Web Modules

**Files:**
- Modify: `lib/hex_hub_web.ex`
- Modify: `lib/hex_hub_admin_web.ex`

**Step 1: Update hex_hub_web.ex html_helpers**

Replace `use PhoenixDuskmoon.Fun` with `use PhoenixDuskmoon.CssArt`:

```elixir
defp html_helpers do
  quote do
    use Gettext, backend: HexHubWeb.Gettext
    import Phoenix.HTML
    use PhoenixDuskmoon.Component
    use PhoenixDuskmoon.CssArt
    alias HexHubWeb.Layouts
    alias Phoenix.LiveView.JS
    unquote(verified_routes())
  end
end
```

**Step 2: Update hex_hub_admin_web.ex html_helpers**

Same change:

```elixir
defp html_helpers do
  quote do
    use Gettext, backend: HexHubAdminWeb.Gettext
    import Phoenix.HTML
    use PhoenixDuskmoon.Component
    use PhoenixDuskmoon.CssArt
    alias HexHubAdminWeb.Layouts
    alias Phoenix.LiveView.JS
    unquote(verified_routes())
  end
end
```

**Step 3: Compile and verify**

Run: `mix compile --warnings-as-errors`

**Step 4: Commit**

```
feat: update web modules for phoenix_duskmoon v9
```

---

### Task 5: Update Root Layouts

**Files:**
- Modify: `lib/hex_hub_web/components/layouts/root.html.heex`
- Modify: `lib/hex_hub_admin_web/components/layouts/root.html.heex`

**Step 1: Update main root layout**

Change `data-theme="light"` to `data-theme="sunshine"` and `bg-base-100` to `bg-surface`:

```heex
<!DOCTYPE html>
<html lang="en" class="[scrollbar-gutter:stable]" data-theme="sunshine">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="HexHub" suffix=" · HexHub">
      {assigns[:page_title]}
    </.live_title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
    </script>
  </head>
  <body class="bg-surface antialiased">
    {@inner_content}
  </body>
</html>
```

**Step 2: Update admin root layout**

Same theme and color changes:

```heex
<!DOCTYPE html>
<html lang="en" class="[scrollbar-gutter:stable]" data-theme="sunshine">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <link rel="icon" type="image/svg+xml" href={~p"/favicon.ico"} />
    <link phx-track-static rel="stylesheet" href={~p"/assets/admin.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/admin.js"}>
    </script>
    <title>HexHub Admin</title>
  </head>
  <body class="bg-surface antialiased">
    {@inner_content}
  </body>
</html>
```

**Step 3: Commit**

```
feat: update root layouts for duskmoon theme system
```

---

### Task 6: Update Main Web App Layout

**Files:**
- Modify: `lib/hex_hub_web/components/layouts.ex`

**Step 1: Rewrite app component**

Replace `shadow-primary-content` and color classes. Keep `dm_simple_appbar`, `dm_theme_switcher`, `dm_link`, `dm_mdi`, `dm_flash_group` (these are phoenix_duskmoon components and stay):

```elixir
def app(assigns) do
  ~H"""
  <.dm_simple_appbar class={[
    "z-50 bg-primary",
    "shadow shadow-primary/20"
  ]}>
    <:logo>
      <a href="/" class="text-xl font-bold text-on-primary hover:opacity-80">HexHub</a>
    </:logo>
    <:user_profile>
      <div class="flex items-center">
        <.dm_theme_switcher />
        <.dm_link href="https://github.com/gsmlg-dev/hex_hub">
          <.dm_mdi name="github" class="w-12 h-12" color="white" />
        </.dm_link>
      </div>
    </:user_profile>
  </.dm_simple_appbar>

  <main class="p-4">
    <div class="mx-auto space-y-4">
      {render_slot(@inner_block)}
    </div>
  </main>

  <.dm_flash_group flash={@flash} />
  """
end
```

**Step 2: Commit**

```
feat: update main web app layout colors for duskmoon
```

---

### Task 7: Update Admin App Layout (Sidebar + Appbar)

**Files:**
- Modify: `lib/hex_hub_admin_web/components/layouts/app.html.heex`

**Step 1: Rewrite admin layout**

Replace DaisyUI drawer/menu with `dm_drawer` and `dm_left_menu` components. Replace all inline SVG icons with `dm_mdi` icons. Replace DaisyUI color tokens with MD3 tokens:

```heex
<.dm_simple_appbar
  title="HexHub Admin"
  class={[
    "z-50 bg-primary",
    "shadow shadow-primary/20"
  ]}
>
  <:logo></:logo>
  <:user_profile>
    <div class="flex items-center">
      <.dm_theme_switcher />
      <.dm_link href="https://github.com/gsmlg-dev/hex_hub">
        <.dm_mdi name="github" class="w-12 h-12" color="white" />
      </.dm_link>
    </div>
  </:user_profile>
</.dm_simple_appbar>

<div class="flex min-h-screen">
  <!-- Sidebar -->
  <aside class="hidden lg:block w-80 bg-surface border-r border-outline-variant">
    <nav class="p-4">
      <div class="text-xl font-bold mb-4 px-2">HexHub Admin</div>
      <ul class="nested-menu nested-menu-bordered">
        <li><a href={~p"/"} class="flex items-center gap-2 active"><.dm_mdi name="view-dashboard" class="h-5 w-5" /> Dashboard</a></li>
        <li><a href={~p"/repositories"} class="flex items-center gap-2"><.dm_mdi name="source-repository" class="h-5 w-5" /> Repositories</a></li>
        <li><a href={~p"/packages"} class="flex items-center gap-2"><.dm_mdi name="package-variant" class="h-5 w-5" /> All Packages</a></li>
        <li><a href={~p"/local-packages"} class="flex items-center gap-2"><.dm_mdi name="shield-check" class="h-5 w-5" /> Local Packages</a></li>
        <li><a href={~p"/cached-packages"} class="flex items-center gap-2"><.dm_mdi name="database" class="h-5 w-5" /> Cached Packages</a></li>
        <li><a href={~p"/packages/search"} class="flex items-center gap-2"><.dm_mdi name="magnify" class="h-5 w-5" /> Search Packages</a></li>
        <li><a href={~p"/users"} class="flex items-center gap-2"><.dm_mdi name="account-group" class="h-5 w-5" /> Users</a></li>
        <li><a href={~p"/upstream"} class="flex items-center gap-2"><.dm_mdi name="flash" class="h-5 w-5" /> Upstream</a></li>
        <li><a href={~p"/storage"} class="flex items-center gap-2"><.dm_mdi name="harddisk" class="h-5 w-5" /> Storage</a></li>
        <li><a href={~p"/publish-config"} class="flex items-center gap-2"><.dm_mdi name="wifi" class="h-5 w-5" /> Publish Config</a></li>
        <li><a href={~p"/backups"} class="flex items-center gap-2"><.dm_mdi name="backup-restore" class="h-5 w-5" /> Backups</a></li>
      </ul>
    </nav>
  </aside>
  <!-- Main content -->
  <div class="flex-1 flex flex-col">
    <main class="p-4">
      <div class="mx-auto space-y-4">
        {if assigns[:inner_content], do: @inner_content, else: render_slot(@inner_block)}
      </div>
    </main>
  </div>
</div>

<.dm_flash_group flash={@flash} />
```

**Step 2: Commit**

```
feat: replace admin sidebar with duskmoon nested-menu and mdi icons
```

---

### Task 8: Update Home Page

**Files:**
- Modify: `lib/hex_hub_web/controllers/page_html/home.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements for this file:
- `bg-base-100` → `bg-surface`
- `bg-base-200` → `bg-surface-container`
- `text-base-content` → `text-on-surface`
- `text-base-content/70` → `text-on-surface-variant`
- `card bg-base-100 shadow-xl` → `card shadow-xl`
- `btn btn-primary btn-lg` → `btn btn-primary btn-lg` (same)
- `btn btn-outline btn-lg` → `btn btn-outline btn-lg` (same)
- `badge badge-outline badge-primary` → `badge badge-outline badge-primary` (same)
- `alert alert-info` → `alert alert-info` (same)
- `stats shadow` → custom card grid layout
- `stat` / `stat-title` / `stat-value` / `stat-figure` → custom card layout
- Inline SVG icons → `dm_mdi` components
- `from-base-100 to-base-200` → `from-surface to-surface-container`

**Step 2: Verify page renders**

Run: `mix phx.server` and check http://localhost:4360

**Step 3: Commit**

```
feat: migrate home page to duskmoon UI
```

---

### Task 9: Update Public Package Index Page

**Files:**
- Modify: `lib/hex_hub_web/controllers/package_html/index.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements:
- `join` + `join-item` → flex group with button group styling
- `input input-bordered join-item` → `input`
- `tabs tabs-boxed` → `tabs`
- `tab-content` → panel div
- `card card-compact` → `card`
- `dropdown` + `dropdown-content menu` → `dm_dropdown` component
- All color tokens per migration reference
- `btn-disabled` → use `disabled` attribute on button
- `btn-active` → active styling

**Step 2: Commit**

```
feat: migrate package index page to duskmoon UI
```

---

### Task 10: Update Public Package Show Page

**Files:**
- Modify: `lib/hex_hub_web/controllers/package_html/show.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements:
- `stats shadow` → card grid
- `stat` / `stat-title` / `stat-value` → custom card layout
- `breadcrumbs` → `dm_breadcrumb` component
- `mockup-code` → custom code block styling
- `table` → `table` (same)
- `link link-primary` → `link link-primary` or use `dm_link`
- All color tokens per migration reference

**Step 2: Commit**

```
feat: migrate package show page to duskmoon UI
```

---

### Task 11: Update Package Not Found Page

**Files:**
- Modify: `lib/hex_hub_web/controllers/package_html/not_found.html.heex`

**Step 1: Replace DaisyUI hero with custom layout**

Replace `hero` / `hero-content` with flexbox center layout. Update color tokens.

**Step 2: Commit**

```
feat: migrate package not-found page to duskmoon UI
```

---

### Task 12: Update Documentation Pages (4 files)

**Files:**
- Modify: `lib/hex_hub_web/controllers/docs_html/index.html.heex`
- Modify: `lib/hex_hub_web/controllers/docs_html/getting_started.html.heex`
- Modify: `lib/hex_hub_web/controllers/docs_html/publishing.html.heex`
- Modify: `lib/hex_hub_web/controllers/docs_html/api_reference.html.heex`

**Step 1: Replace all DaisyUI classes across all 4 files**

Key replacements:
- `mockup-code` → `bg-neutral text-on-surface rounded-lg p-4 font-mono overflow-x-auto`
- `table-zebra` → `table-striped`
- `badge-ghost` → `badge-outline`
- All color tokens per migration reference
- `alert alert-info` / `alert alert-warning` → same class names (compatible)
- Keep `prose` classes (from @tailwindcss/typography)

**Step 2: Commit**

```
feat: migrate docs pages to duskmoon UI
```

---

### Task 13: Update Admin Dashboard Page

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/admin_html/dashboard.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements:
- `navbar bg-base-100` → `navbar bg-surface`
- `stat shadow bg-base-100` → card-based stat layout
- `stat-figure` / `stat-title` / `stat-value` / `stat-desc` → custom layout
- `card bg-base-100 shadow` → `card shadow`
- `btn btn-accent` → `btn btn-tertiary`
- Inline SVGs → `dm_mdi` icons
- Remove `<style>` block (drawer CSS no longer needed)
- All color tokens per migration reference

**Step 2: Commit**

```
feat: migrate admin dashboard to duskmoon UI
```

---

### Task 14: Update Admin Package Pages (5 files)

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/package_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/package_html/new.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/package_html/edit.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/package_html/show.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/package_html/search.html.heex`

**Step 1: Replace all DaisyUI classes across all 5 files**

Key replacements:
- `join` / `join-item` → button group with flex
- `form-control` → `form-group`
- `label-text` → `form-label`
- `input-bordered` → `input` (default bordered)
- `select-bordered` → `select` (default bordered)
- `mockup-code` → custom code block
- `badge-ghost` → `badge-outline`
- All color tokens per migration reference

**Step 2: Commit**

```
feat: migrate admin package pages to duskmoon UI
```

---

### Task 15: Update Admin Local & Cached Package Pages (2 files)

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/local_package_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/cached_package_html/index.html.heex`

**Step 1: Replace all DaisyUI classes**

Same patterns as Task 14. Additionally:
- `badge-info` → `badge-info` (same)
- `join` pagination → button group

**Step 2: Commit**

```
feat: migrate admin local/cached package pages to duskmoon UI
```

---

### Task 16: Update Admin User Pages (4 files)

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/user_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/user_html/new.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/user_html/edit.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/user_html/show.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements:
- `alert alert-warning` → `alert alert-warning` (same)
- `badge badge-info` → `badge badge-info` (same)
- All color tokens per migration reference

**Step 2: Commit**

```
feat: migrate admin user pages to duskmoon UI
```

---

### Task 17: Update Admin Repository Pages (3 files)

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/repository_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/repository_html/new.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/repository_html/edit.html.heex`

**Step 1: Replace all DaisyUI classes**

All color tokens per migration reference. Same patterns as other admin pages.

**Step 2: Commit**

```
feat: migrate admin repository pages to duskmoon UI
```

---

### Task 18: Update Admin Config Pages (5 files)

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/upstream_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/upstream_html/edit.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/storage_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/storage_html/edit.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/publish_config_html/index.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements:
- `form-control` → `form-group`
- `label-text` / `label-text-alt` → `form-label` / `helper-text`
- `input-bordered` → `input`
- `select-bordered` → `select`
- `radio` → `radio` (same)
- `toggle toggle-primary toggle-lg` → `switch switch-primary`
- `modal` / `modal-box` / `modal-action` / `modal-backdrop` → `dm_modal` component
- `input-group` → form layout
- All color tokens per migration reference

**Step 2: Commit**

```
feat: migrate admin config pages to duskmoon UI
```

---

### Task 19: Update Admin Backup Pages (4 files)

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/backup_html/index.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/backup_html/new.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/backup_html/show.html.heex`
- Modify: `lib/hex_hub_admin_web/controllers/backup_html/restore.html.heex`

**Step 1: Replace all DaisyUI classes**

Key replacements:
- `table-zebra` → `table-striped`
- `stats shadow` → card grid
- `stat` → custom card
- `file-input file-input-bordered` → `input` with type="file"
- `collapse collapse-arrow` → `accordion` / `dm_collapse`
- `divider` → `divider` (same)
- `tooltip` → `tooltip` (same)
- All color tokens per migration reference

**Step 2: Commit**

```
feat: migrate admin backup pages to duskmoon UI
```

---

### Task 20: Update Admin Error Pages

**Files:**
- Modify: `lib/hex_hub_admin_web/controllers/error_html/404.html.heex`

**Step 1: Replace DaisyUI classes**

- `bg-base-200` → `bg-surface-container`
- `text-primary` → `text-primary` (same)
- `text-base-content` → `text-on-surface`
- `text-base-content/70` → `text-on-surface-variant`

**Step 2: Commit**

```
feat: migrate admin 404 page to duskmoon UI
```

---

### Task 21: Build and Smoke Test

**Step 1: Build assets**

Run: `mix assets.build`

**Step 2: Run tests**

Run: `mix test`

**Step 3: Start server and manually verify**

Run: `mix phx.server`

Check:
- http://localhost:4360 (main site home, packages, docs)
- http://localhost:4361 (admin dashboard, all pages)
- Theme switching works
- All pages render without errors

**Step 4: Format and lint**

Run: `mix format && mix credo --strict`

**Step 5: Final commit**

```
chore: verify duskmoon UI refactor builds and passes tests
```
