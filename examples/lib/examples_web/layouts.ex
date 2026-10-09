defmodule ExamplesWeb.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <title>Visualize Examples - D3-style Charts in Elixir</title>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: #f5f5f5;
            color: #333;
            line-height: 1.6;
          }
          /* One header on every page, at half its former height, with the tab bar (#329) */
          header.site-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1rem 2rem 0;
            text-align: center;
          }
          header.site-header h1 { font-size: 1.25rem; margin-bottom: 0.15rem; }
          header.site-header p { opacity: 0.9; font-size: 0.85rem; margin-bottom: 0.6rem; }
          .site-tabs { display: flex; justify-content: center; gap: 0.25rem; }
          .site-tab {
            display: inline-flex; align-items: center; gap: 0.4rem;
            padding: 0.45rem 0.9rem; border-radius: 6px 6px 0 0;
            color: rgba(255,255,255,0.85); text-decoration: none; font-size: 0.9rem; font-weight: 500;
          }
          .site-tab:hover { background: rgba(255,255,255,0.12); color: #fff; }
          .site-tab[aria-current="page"] { background: #f5f5f5; color: #4c3fa0; font-weight: 600; }
          .site-tab svg { width: 16px; height: 16px; }
          .site-tab-icon { display: inline-flex; }
          .page-intro { margin-bottom: 1rem; }
          .page-intro h2 { font-size: 1.4rem; margin-bottom: 0.25rem; }
          .page-intro p { color: #666; }
          .builder-notice { margin: 1rem auto 0; max-width: 1400px; padding: 0.6rem 1rem; background: #fff8e1; border-left: 4px solid #f59e0b; color: #5c4400; font-size: 0.95rem; }
          .tab-pages { color: #666; margin: 0.5rem 0 1rem; }
          .tab-pages a { color: #667eea; font-weight: 500; }
          body > main { padding: 2rem; max-width: 1400px; margin: 0 auto; }
          body > main.main-wide { max-width: none; }
          .gallery-note {
            max-width: 60rem;
            margin: 0 auto 1.25rem;
            color: #555;
            font-size: 0.95rem;
            line-height: 1.5;
          }

          .gallery {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 1.5rem;
          }
          .chart-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            overflow: hidden;
            transition: transform 0.2s, box-shadow 0.2s;
          }
          .chart-card:hover {
            transform: translateY(-4px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
          }
          .chart-card a { text-decoration: none; color: inherit; display: block; }
          .chart-preview {
            background: white;
            padding: 1rem;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 250px;
            border-bottom: 1px solid #eee;
          }
          .chart-preview svg { max-width: 100%; height: auto; }
          .chart-preview-pending { width: 320px; max-width: 100%; height: 220px; border-radius: 6px; background: linear-gradient(90deg, #f3f4f6 25%, #e5e7eb 50%, #f3f4f6 75%); background-size: 200% 100%; animation: preview-pending 1.2s linear infinite; }
          @keyframes preview-pending { from { background-position: 200% 0; } to { background-position: -200% 0; } }
          .chart-info { padding: 1rem 1.5rem; }
          .chart-info h3 { font-size: 1.1rem; color: #333; margin-bottom: 0.25rem; }
          .chart-info p { font-size: 0.85rem; color: #666; }
          .back-link {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            color: #667eea;
            text-decoration: none;
            margin-bottom: 1.5rem;
            font-weight: 500;
          }
          .back-link:hover { text-decoration: underline; }
          .chart-detail { background: white; border-radius: 12px; padding: 2rem; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
          .chart-detail h2 { margin-bottom: 1rem; color: #333; }
          .chart-detail .chart-container { margin: 1rem 0; display: flex; justify-content: center; }
          .chart-detail svg { max-width: 100%; height: auto; }
          /* One demo, one panel: its heading, explanation and chart together (#505) */
          .panels { display: flex; flex-direction: column; gap: 1.5rem; }
          .panel { background: white; border: 1px solid #e5e7eb; border-radius: 12px; padding: 1.5rem 2rem; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
          .panel-title { margin-bottom: 0.75rem; color: #333; }
          h2.panel-title { font-size: 1.35rem; }
          h3.panel-title { font-size: 0.95rem; margin-bottom: 0.25rem; }
          .panel-note { color: #666; margin-bottom: 1rem; }
          .panel .chart-container { margin: 1rem 0; display: flex; justify-content: center; }
          .panel svg { max-width: 100%; height: auto; }
          .panel pre { margin-top: 0; }
          .panel .panel { box-shadow: none; padding: 0.75rem 1rem; border-radius: 8px; }
          /* A row of demos, each as wide as its chart (#513); the code panel takes a row */
          .panels-row { flex-direction: row; flex-wrap: wrap; align-items: flex-start; }
          .panels-row > .panel { flex: 0 0 auto; box-sizing: border-box; width: calc(var(--chart-w) + 4rem + 2px); max-width: 100%; }
          .panels-row > .panel.panel-wide { flex-basis: 100%; width: 100%; }
          pre {
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 1rem;
            border-radius: 8px;
            overflow-x: auto;
            font-size: 0.85rem;
            line-height: 1.5;
            margin-top: 1.5rem;
          }
          code { font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace; }
        </style>
        <%!-- The colours of every code block, ExamplesWeb.Highlight.code/1 (#506) --%>
        <style><%= Phoenix.HTML.raw(ExamplesWeb.Highlight.css()) %></style>
        <script defer src="https://unpkg.com/phoenix_html@4.2.0/priv/static/phoenix_html.js"></script>
        <script defer src="https://unpkg.com/phoenix@1.7.21/priv/static/phoenix.min.js"></script>
        <script defer src="https://unpkg.com/phoenix_live_view@1.1.19/priv/static/phoenix_live_view.min.js"></script>
        <script type="module">
          // The library's own hooks, generated by Visualize.Hooks.js_code/0 and served by
          // ExamplesWeb.HooksController.
          //
          // This import must stay STATIC. A static import is resolved before the module body
          // runs, and a module body runs before DOMContentLoaded, which is the ordering the
          // LiveSocket below depends on. A dynamic import() is a promise and loses that race:
          // the socket is built with no hooks, and every phx-click still works while every
          // hook silently does not — which is exactly how it presents.
          import VisualizeHooks from "/hooks/visualize_hooks.js";
          window.VisualizeHooks = VisualizeHooks;
        </script>
        <script>
          // The canvas hooks are the library's, from the module above (spec/10 §7–§9): a page
          // that redefined them here carried a decoder frozen before D-73's f32 records and
          // drew nothing while its counters ran (#270). No hook is defined in this layout.

          document.addEventListener("DOMContentLoaded", () => {
            // An empty spread is how a failed import used to disappear; say so instead.
            if (!window.VisualizeHooks) {
              console.error("visualize: the hooks module did not load, so no library hook is registered");
            }
            let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
            let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
              params: { _csrf_token: csrfToken },
              hooks: { ...(window.VisualizeHooks || {}) },
              // Every keyup says whether focus was in a form field and whether a modifier was
              // held, so a page's phx-window-keyup can leave a slider's or a caret's arrow
              // keys, and the browser's Alt+arrow, alone (#484). The page decides; this only
              // reports what the server cannot see.
              metadata: {
                keyup: (e) => ({
                  field: !!(e.target && e.target.closest && e.target.closest("input, select, textarea, [contenteditable]")),
                  modified: e.altKey || e.ctrlKey || e.metaKey || e.shiftKey
                })
              }
            });
            liveSocket.connect();
            window.liveSocket = liveSocket;
          });
        </script>
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
      </head>
      <body>
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <%= @inner_content %>
    """
  end
end
