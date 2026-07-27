# integration-test

A deliberately minimal static page for validating third-party integrations — currently **script injection**: drop a vendor `<script>` into `<head>` and confirm it actually initializes.

**Live:** <https://mendozadevcorp.github.io/integration-test/> (GitHub Pages, served from `main`)

The whole value of this page is that a check either genuinely passes or genuinely fails. Keep it light — extra assets and requests distort what you're measuring.

Whatever is installed at any given time lives in the marked block in `<head>`, with its checks in `INIT_PROBES` at the bottom of `index.html`.

## How the status panel works

Fetching a script is not the same as it initializing, so those are asserted separately. A vendor script can return `200`, fire `onload`, and still do nothing at all.

- **Fetched** — `onload` / `onerror` on the tag. Proves the file came back, nothing more.
- **Initialized** — a probe in `INIT_PROBES` asserting a side effect the script only produces on success.

Probes poll for 3s (`GRACE_MS`) before failing, so scripts injected after the `load` event still get counted. Results also go to the console via `console.log(window.checks)`.

## Adding an integration

Two edits in `index.html`.

**1.** Script tag in `<head>`, inside the marked block, with both handlers wired:

```html
<script async src="https://example.com/sdk.js"
        onload="recordCheck('sdk.js fetched', true)"
        onerror="recordCheck('sdk.js fetched', false, 'network or 404')"></script>
```

The registry that defines `recordCheck` is deliberately above this block so async handlers always have somewhere to report.

**2.** An `INIT_PROBES` entry asserting proof it actually ran — a global appearing, a method being patched, a storage write:

```js
{
    name: "sdk.js initialized",
    test: () => Boolean(window.MySdk),
    detail: "window.MySdk not defined"
}
```

Choosing that assertion is the part worth thinking about:

- **Not every script exports a global.** A self-contained IIFE may leave nothing on `window`. Look for another observable side effect — a wrapped method, a storage key, a cookie.
- **Avoid anything that can outlive the page load.** `localStorage` and `sessionStorage` survive navigation within a tab, so a bare existence check can read a leftover value from a previous load and report green on a 404. Snapshot the value *before* the script tag and assert it changed.
- **Some scripts read their config off their own tag** via `document.currentScript`, and return silently when it's null — module context, `eval`, re-execution inside a callback. The request still succeeds and `onload` still fires. This is the main failure mode to expect on unusual injection paths, and the reason fetch and init are checked separately.

## Testing it

Serve locally — `file://` restricts storage APIs and skews script behavior:

```bash
npm start        # serve on http://localhost:8765/ (detached)
npm run status   # is it up, and on which PID
npm stop
npm run restart
npm run logs     # tail the access log
```

The server runs detached so the terminal stays usable. `stop` finds its target by **port**, not by the recorded PID — a pid file goes stale after a crash, reboot, or a server started some other way, and acting on a stale PID either misses the real process or kills an unrelated one. Whatever holds the port is by definition what's in the way.

There's no dependency to install; `package.json` only exists to carry the scripts. Change the port with `-Port`:

```bash
powershell -File ./scripts/serve.ps1 -Action start -Port 9000
```

**Always test the failure path too, in the same tab as a successful load** — that's the state where a stale-data false positive shows up. Point the script at a URL that 404s:

```bash
sed 's#<script-url>#http://localhost:8765/does-not-exist.js#' index.html > _failtest.html
```

Load `_failtest.html` and wait out the 3s grace period. It's gitignored, so it won't follow you into a commit.

Every check should go red. If one stays green, it's asserting something that outlived the page load rather than something the script did.

## Files

| File | |
| --- | --- |
| `index.html` | The whole harness — markup, checks, styles |
| `favicon.png` | 180×180. Keep it small; a heavy favicon distorts load measurements |
| `scripts/serve.ps1` | Local server control. Keep it ASCII-only — Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI and mangles non-ASCII characters mid-string |
| `package.json` | Script shortcuts only. No dependencies, nothing to install |
