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
          header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            text-align: center;
          }
          header h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
          header p { opacity: 0.9; font-size: 1.1rem; }
          main { padding: 2rem; max-width: 1400px; margin: 0 auto; }
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
        <script defer src="https://unpkg.com/phoenix_html@4.2.0/priv/static/phoenix_html.js"></script>
        <script defer src="https://unpkg.com/phoenix@1.7.21/priv/static/phoenix.min.js"></script>
        <script defer src="https://unpkg.com/phoenix_live_view@1.1.19/priv/static/phoenix_live_view.min.js"></script>
        <script>
          document.addEventListener("DOMContentLoaded", () => {
            let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
            let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
              params: { _csrf_token: csrfToken }
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
