defmodule ExamplesWeb.RedirectController do
  @moduledoc "Routes that moved: `/high-performance` is the Scrolling series chart's page (#327)."
  use Phoenix.Controller, formats: [:html]

  def scrolling_series(conn, _params), do: redirect(conn, to: "/chart/scrolling_series")
end
