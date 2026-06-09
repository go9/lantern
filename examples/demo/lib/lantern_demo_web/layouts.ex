defmodule LanternDemoWeb.Layouts do
  use Phoenix.Component

  import Phoenix.Controller, only: [get_csrf_token: 0]

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Lantern Demo</title>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;600;700&family=JetBrains+Mono:wght@400;500&display=swap" />
        <link rel="stylesheet" href="/lantern/lantern.css" />
        <link rel="stylesheet" href="/livecode/livecode.css" />
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer>
        </script>
        <script type="module" src="/app.js">
        </script>
        <style>
          :root {
            color-scheme: light dark;
            --demo-coral: oklch(0.66 0.18 39);
            --demo-ember: oklch(0.56 0.15 34);
            --demo-bg: oklch(0.98 0.008 62);
            --demo-fg: oklch(0.20 0.025 39);
            --demo-muted: oklch(0.48 0.025 45);
            --demo-card: oklch(0.995 0.004 62);
            --demo-border: oklch(0.88 0.018 55);
            --demo-panel: color-mix(in srgb, var(--demo-card) 88%, transparent);
          }

          @media (prefers-color-scheme: dark) {
            :root {
              --demo-bg: oklch(0.15 0.018 39);
              --demo-fg: oklch(0.94 0.01 55);
              --demo-muted: oklch(0.72 0.018 55);
              --demo-card: oklch(0.19 0.020 39);
              --demo-border: oklch(0.32 0.028 39);
              --demo-panel: color-mix(in srgb, var(--demo-card) 91%, transparent);
            }
          }

          body {
            margin: 0;
            background: var(--demo-bg);
            color: var(--demo-fg);
            font-family: "Space Grotesk", Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          }

          .demo-shell {
            --demo-bg-local: var(--demo-bg);
            --demo-fg-local: var(--demo-fg);
            --demo-muted-local: var(--demo-muted);
            --demo-card-local: var(--demo-card);
            --demo-border-local: var(--demo-border);
            min-height: 100vh;
            padding: 2rem 1rem 3rem;
            background:
              radial-gradient(circle at top left, color-mix(in oklch, var(--demo-coral) 22%, transparent), transparent 28rem),
              linear-gradient(135deg, color-mix(in oklch, var(--demo-bg-local) 96%, var(--demo-coral)), var(--demo-bg-local));
            color: var(--demo-fg-local);
          }

          .demo-shell[data-demo-theme="light"] {
            --demo-bg-local: oklch(0.98 0.008 62);
            --demo-fg-local: oklch(0.20 0.025 39);
            --demo-muted-local: oklch(0.48 0.025 45);
            --demo-card-local: oklch(0.995 0.004 62);
            --demo-border-local: oklch(0.88 0.018 55);
          }

          .demo-shell[data-demo-theme="dark"] {
            --demo-bg-local: oklch(0.15 0.018 39);
            --demo-fg-local: oklch(0.94 0.01 55);
            --demo-muted-local: oklch(0.72 0.018 55);
            --demo-card-local: oklch(0.19 0.020 39);
            --demo-border-local: oklch(0.32 0.028 39);
          }

          .demo-shell > * {
            max-width: 1180px;
            margin-left: auto;
            margin-right: auto;
          }

          .demo-hero {
            display: grid;
            gap: 0.75rem;
            margin-bottom: 1.25rem;
          }

          .demo-eyebrow {
            margin: 0;
            color: var(--demo-coral);
            font-size: 0.78rem;
            font-weight: 760;
            letter-spacing: 0.08em;
            text-transform: uppercase;
          }

          .demo-title {
            max-width: 920px;
            margin: 0;
            font-size: clamp(2.2rem, 6vw, 4.65rem);
            line-height: 0.92;
            letter-spacing: -0.065em;
          }

          .demo-copy {
            max-width: 790px;
            margin: 0;
            color: var(--demo-muted-local);
            font-size: 1.05rem;
            line-height: 1.7;
          }

          .demo-panel {
            margin: 1rem auto 1.25rem;
            padding: 1rem;
            border: 1px solid var(--demo-border-local);
            border-radius: 1rem;
            background: color-mix(in srgb, var(--demo-card-local) 88%, transparent);
            box-shadow: 0 18px 50px color-mix(in oklch, var(--demo-fg-local) 8%, transparent);
          }

          .demo-panel code {
            font-family: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
          }

          .demo-warning {
            border-color: color-mix(in oklch, var(--demo-coral) 45%, var(--demo-border-local));
          }

          .demo-error {
            border-color: color-mix(in oklch, oklch(0.62 0.19 25) 50%, var(--demo-border-local));
          }

          .demo-controls {
            display: flex;
            flex-wrap: wrap;
            align-items: end;
            gap: 0.85rem;
          }

          .demo-controls label {
            display: grid;
            gap: 0.35rem;
            color: var(--demo-muted-local);
            font-size: 0.78rem;
            font-weight: 720;
            letter-spacing: 0.04em;
            text-transform: uppercase;
          }

          .demo-controls select,
          .demo-controls input[type="color"] {
            min-height: 2.35rem;
            border: 1px solid var(--demo-border-local);
            border-radius: 0.65rem;
            background: var(--demo-card-local);
            color: var(--demo-fg-local);
            padding: 0 0.65rem;
          }

          .demo-controls input[type="color"] {
            width: 4rem;
            padding: 0.2rem;
          }

          .demo-controls .demo-checkbox {
            display: flex;
            align-items: center;
            min-height: 2.35rem;
            flex-direction: row;
            color: var(--demo-fg-local);
            text-transform: none;
            letter-spacing: 0;
            font-weight: 640;
          }

          .demo-inline-warning {
            margin: 0.9rem auto 0;
            font-size: 0.9rem;
          }

          .demo-actions {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            margin-top: 0.9rem;
            color: var(--demo-muted-local);
          }

          .demo-actions button {
            border: 1px solid var(--demo-border-local);
            border-radius: 0.65rem;
            background: var(--demo-card-local);
            color: var(--demo-fg-local);
            padding: 0.55rem 0.8rem;
            font-weight: 680;
            cursor: pointer;
          }

          .demo-actions button:hover {
            border-color: var(--demo-coral);
          }

          .demo-btn {
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
            border: 1px solid var(--demo-border-local);
            border-radius: 0.65rem;
            background: var(--demo-card-local);
            color: var(--demo-fg-local);
            padding: 0.55rem 0.85rem;
            font-size: 0.875rem;
            font-weight: 660;
            cursor: pointer;
            transition: border-color 0.15s, background 0.15s;
          }

          .demo-btn:hover { border-color: var(--demo-coral); }

          .demo-btn-primary {
            background: var(--demo-coral);
            border-color: var(--demo-coral);
            color: #fff;
          }

          .demo-btn-primary:hover {
            background: var(--demo-ember);
            border-color: var(--demo-ember);
          }

          .demo-btn-sm { padding: 0.35rem 0.65rem; font-size: 0.8rem; }

          .demo-sandbox-bar {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 1rem;
            flex-wrap: wrap;
          }

          .demo-sandbox-desc { flex: 1; font-size: 0.9rem; }

          .demo-sandbox-actions { display: flex; gap: 0.5rem; }

          .demo-captcha-panel { text-align: center; }

          .demo-captcha-hint {
            margin: 0 0 1rem;
            color: var(--demo-muted-local);
            font-size: 0.9rem;
          }

          .demo-sandbox-active {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            flex-wrap: wrap;
            border-color: oklch(0.62 0.19 145);
          }

          .demo-sandbox-live-dot {
            width: 0.6rem;
            height: 0.6rem;
            border-radius: 50%;
            background: oklch(0.62 0.19 145);
            flex-shrink: 0;
          }

          .demo-sandbox-live-label {
            font-weight: 660;
            font-size: 0.875rem;
            color: oklch(0.62 0.19 145);
          }

          .demo-sandbox-timer {
            flex: 1;
            color: var(--demo-muted-local);
            font-size: 0.875rem;
            font-variant-numeric: tabular-nums;
          }

          .demo-spinner-label {
            color: var(--demo-muted-local);
            font-size: 0.875rem;
          }
        </style>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
