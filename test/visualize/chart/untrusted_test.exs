defmodule Visualize.Chart.UntrustedTest do
  @moduledoc """
  Strings and URLs from a design are untrusted input (spec/14 §10.3, #660, D-172): a font
  family and a class refuse what their contexts cannot carry, every string reaching a
  canvas or a stylesheet is escaped, and a URL is held to the application's policy, which
  a read may only make stricter; a refusal names the field and never the URL.
  """
  # The URL policy is application config, which these tests set.
  use ExUnit.Case, async: false

  alias Visualize.{Chart, Theme}
  alias Visualize.Chart.Validator

  @tiles %{
    url: "https://{s}.tile.example/{z}/{x}/{y}.png",
    attribution: "© OpenStreetMap contributors"
  }

  defp design(tiles) do
    %{
      version: 3,
      frames: %{map: %{kind: :geo, projection: %{type: :mercator}}},
      marks: [%{type: :tiles, frame: :map, tiles: Map.merge(@tiles, tiles)}]
    }
  end

  setup do
    previous = Application.get_env(:visualize, :urls)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:visualize, :urls, previous),
        else: Application.delete_env(:visualize, :urls)
    end)
  end

  defp with_urls(config, fun) do
    Application.put_env(:visualize, :urls, config)
    fun.()
  end

  defp url_fault(url, opts \\ []) do
    case Validator.validate(design(%{url: url}), :design, opts) do
      :ok -> :ok
      {:error, [{[:marks, 0, :tiles, :url], {:url, reason}}]} -> reason
    end
  end

  describe "strings" do
    test "a font family refuses markup, rule and escape characters, wherever it is written" do
      for bad <- ["Inter</text>", "a;b", "x{y}", "a/b", "a\\b", "a\nb"] do
        design = %{
          version: 3,
          frames: %{main: %{kind: :cartesian}},
          styles: %{s: %{font: %{family: bad}}}
        }

        assert Validator.validate(design) ==
                 {:error, [{[:styles, "s", :font, :family], {:unsafe, :font_family}}]}

        flat = put_in(design, [:styles, :s], %{font_family: bad})
        assert {:error, [{[:styles, "s", :font, :family], _}]} = Validator.validate(flat)

        themed = Map.put(design, :theme, %{font_family: bad}) |> Map.delete(:styles)

        assert {:error, [{[:theme, :font_family], {:unsafe, :font_family}}]} =
                 Validator.validate(themed)
      end

      ok = %{
        version: 3,
        frames: %{main: %{kind: :cartesian}},
        styles: %{s: %{font: %{family: "Inter, 'Segoe UI', sans-serif"}}}
      }

      assert Validator.validate(ok) == :ok
    end

    test "a class is CSS class names" do
      base = %{version: 3, frames: %{main: %{kind: :cartesian}}}

      for good <- ["critical", "a b-c _d", "-x"] do
        assert Validator.validate(Map.put(base, :styles, %{s: %{class: good}})) == :ok
      end

      for bad <- ["6", "a\" onload=\"x", "a;b", "a>b", ""] do
        assert Validator.validate(Map.put(base, :styles, %{s: %{class: bad}})) ==
                 {:error, [{[:styles, "s", :class], {:unsafe, :class}}]}
      end

      assert Validator.format({[:styles, "s", :class], {:unsafe, :class}}) ==
               "styles.s.class: must be CSS class names separated by spaces"
    end

    test "a canvas escapes the font it writes, and a stylesheet its values" do
      element =
        Visualize.IR.Element.text("hi", 0, 0, %{font_family: "'Segoe UI'</script>", font_size: 12})

      js = element |> Visualize.Backend.Canvas.render_element() |> IO.iodata_to_binary()
      assert js =~ ~S|ctx.font = '12px \'Segoe UI\'\x3c/script>';|
      refute js =~ "</script>"

      css = Theme.stylesheet(%{Theme.default() | font_family: "x;} body{color:red"})
      assert css =~ ~S|--vis-font-family: x\3B \7D  body\7B color:red;|
    end
  end

  describe "URLs" do
    test "https passes; javascript, file, ftp and a relative URL do not" do
      assert url_fault("https://tile.example/{z}/{x}/{y}.png") == :ok
      assert url_fault("javascript:alert(1)//{z}{x}{y}") == :scheme
      assert url_fault("file:///etc/{z}/{x}/{y}") == :scheme
      assert url_fault("ftp://host/{z}/{x}/{y}") == :scheme
      assert url_fault("/tiles/{z}/{x}/{y}.png") == :relative
      assert url_fault("tile.example/{z}/{x}/{y}.png") == :relative
    end

    test "data is an image of png, jpeg or webp, never svg" do
      assert url_fault("data:image/png;base64,{z}{x}{y}") == :ok
      assert url_fault("DATA:image/webp,{z}{x}{y}") == :ok
      assert url_fault("data:image/svg+xml,<svg onload=x>{z}{x}{y}") == :data_type
      assert url_fault("data:text/html,{z}{x}{y}") == :data_type
    end

    test "http passes only where the application allows it, and a read cannot loosen that" do
      http = "http://tile.example/{z}/{x}/{y}.png"

      assert url_fault(http) == :http
      assert url_fault(http, urls: [http: true]) == :http

      with_urls([http: true], fn ->
        assert url_fault(http) == :ok
        assert Validator.validate(design(%{url: http})) == :ok
        # A read may be stricter than the application.
        assert url_fault(http, urls: [http: false]) == :http
      end)
    end

    test "a host allowlist, its {s} checked for every subdomain, a read narrowing it" do
      url = "https://{s}.tile.example/{z}/{x}/{y}.png"

      assert url_fault(url, urls: [hosts: ["*.tile.example"]]) == :ok
      assert url_fault(url, urls: [hosts: ["a.tile.example", "b.tile.example"]]) == :host

      assert url_fault(url, urls: [hosts: ["a.tile.example", "b.tile.example", "c.tile.example"]]) ==
               :ok

      assert url_fault("https://evil.example/{z}/{x}/{y}", urls: [hosts: ["*.tile.example"]]) ==
               :host

      with_urls([hosts: ["*.tile.example"]], fn ->
        assert url_fault("https://evil.example/{z}/{x}/{y}") == :host
        # A read naming a host the application does not allow gains nothing.
        assert url_fault("https://evil.example/{z}/{x}/{y}", urls: [hosts: ["evil.example"]]) ==
                 :host
      end)
    end

    test "a refusal names the field and the reason, and never the URL" do
      url = "javascript:steal('secret-token')//{z}{x}{y}"
      assert {:error, [fault]} = Chart.from_map(design(%{url: url}))
      line = Validator.format(fault)
      assert line =~ "marks[0].tiles.url: the URL's scheme is refused"
      refute line =~ "secret-token"
      refute line =~ "javascript"

      assert {:error, [{_, {:url, :host}}]} =
               Chart.from_map(design(%{}), urls: [hosts: ["other.example"]])

      {:ok, json} = Jason.encode(design(%{}))

      assert {:error, [{_, {:url, :host}}]} =
               Chart.from_json(json, urls: [hosts: ["other.example"]])
    end
  end
end
