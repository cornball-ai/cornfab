# cornfab 0.0.3

Ported onto glinty's protocol v3 component vocabulary. The UI is a
component tree rather than HTML tags, so it travels the wire as
structure and a frontend that is not a browser renders the same app
with real widgets.

- `app_ui()` and every `render_ui()` in the server build components:
  `row`, `column`, `panel`, `txt`, `button`, `collapse`, `image`,
  `link`, `audio_output`. `glinty::div/span/p` and the old `tag()`
  signature are gone from glinty and gone from here.
- `R/icons.R` is deleted. glinty draws all seven shapes cornfab used,
  and validates the name against a set, so a typo now fails where it
  is written instead of rendering an invisible span.
- The generated audio is an `audio_output` slot fed by
  `render_audio()`, and the value carries its media type. A browser
  sniffs the bytes; a native client hands the source to a platform
  player that asks.
- History rows are two buttons rather than a clickable card carrying
  a nested delete button. v3 has no clickable container, and a button
  inside a button was never valid markup. Each carries its entry id
  as the event's value, so one observer still serves every row.
- The two `<details>` sections are `collapse()`; the three-column
  shell is `row`/`column`/`panel` with `grow` and `width`.
- The stylesheet went from 660 lines to 330: what remains is brand,
  hooked on ids and `[data-g-target]`. A test asserts no rule targets
  something the page never renders, because CSS fails silently by
  design.

**Renumbered.** This was 0.2.0. cornfab has never been released, has
no users, and is still changing with glinty underneath it, so the
version now says so: 0.0.1 was the Shiny app, 0.0.2 the move to
glinty, and this is 0.0.3.

# cornfab 0.0.2

Migrated from Shiny to glinty (protocol 2), dropping the Shiny,
bslib and htmltools dependencies for `jsonlite` and `digest`.

# cornfab 0.0.1

Initial Shiny app for text-to-speech: enter text, pick a voice and
backend, generate audio.
