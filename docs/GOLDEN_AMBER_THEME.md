# Golden Amber theme

Golden Amber is an optional color theme for Mastodon v4.6.5. It keeps the
default Mastodon layout, typography, and component styles while replacing the
neutral and brand color palettes with warm charcoal, ivory, and amber tones.

## How the theme is loaded

Mastodon reads the available theme names and entrypoints from
`config/themes.yml`. The Mastodon Vite plugin exposes each entry as a virtual
`themes/<name>` stylesheet, and `theme_style_tags` includes the stylesheet for
the active theme in the page layout.

The active theme is selected in this order:

1. The signed-in user's theme, when it is valid.
2. The theme selected by the administrator for the site.
3. Mastodon's `default` theme.

Golden Amber imports the default `styles/application.scss` entrypoint and then
overrides only CSS custom properties. Mastodon's error, warning, and success
colors are left unchanged so that their meanings remain distinct.

The dark scheme slightly increases separation between adjacent surfaces. High
contrast keeps container and control borders strong while using quieter row
dividers, and the light scheme uses a warm-neutral custom scrollbar.

Mastodon v4.6 stores color theme tokens under
`app/javascript/styles/mastodon/theme`. Color scheme and contrast are separate
preferences in this version. The resolved values are exposed through the
`data-color-scheme` and `data-contrast` HTML attributes, so the same Golden
Amber theme supports Auto, Light, Dark, and High contrast preferences.

## Test locally with the development container

The root `docker-compose.yml` is intended for production. Use the development
container configuration for local theme work:

```shell
docker compose -f .devcontainer/compose.yaml up -d
docker compose -f .devcontainer/compose.yaml exec app bin/setup
docker compose -f .devcontainer/compose.yaml exec app bin/dev
```

`bin/setup` is only required for the initial setup or after dependency changes.
Once the processes are ready, open <http://localhost:3000> and sign in with the
seeded administrator account:

- E-mail: `admin@localhost` or `admin@mastodon.local`, depending on the setup
- Password: `mastodonadmin`

Select the theme for an individual account under **Preferences > Appearance >
Theme**. To make it the site's theme for signed-out visitors and users without a
personal selection, use **Administration > Server settings > Design**.

`config/themes.yml` is loaded by the Rails process, so restart `bin/dev` after
adding or renaming a theme. Once the theme is registered, edits to
`golden_amber.scss` are updated by the Vite development server without an asset
precompile.

Optional sample posts for visual testing can be created inside the container:

```shell
docker compose -f .devcontainer/compose.yaml exec app bin/rails dev:populate_sample_data
```

## Visual and accessibility checklist

Test Light and Dark schemes with both Default and High contrast. Also test Auto
while switching the operating system's color scheme.

Check these surfaces at desktop and mobile widths:

- Home timeline and composer
- Posts with media, polls, and content warnings
- Notifications
- Preferences and administration pages
- Signed-out and authentication pages

Verify primary and secondary text, links, focus rings, buttons and their hover
or disabled states, errors, warnings, success messages, and highlighted
favourites. Normal text and meaningful controls should meet a WCAG AA contrast
ratio of at least 4.5:1 where the standard requires it.

## Production deployment

After deploying the theme files, compile production assets and restart all
Mastodon processes:

```shell
RAILS_ENV=production bundle exec rails assets:precompile
```

No database migration is required. After restart, confirm that signed-out
visitors receive the administrator's site theme and that existing users keep
their personal theme choices.
