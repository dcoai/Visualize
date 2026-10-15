defmodule Visualize.Chart.Urls do
  @moduledoc false
  # The URL policy of spec/14 §10.3 (#660, D-172): a design is untrusted input, so every
  # field that holds a URL — today a `:tiles` mark's `url` template — is checked when the
  # design is validated. `https:` passes; `http:` only when the policy allows it; `data:`
  # only as a PNG, JPEG or WebP image; every other scheme and a relative URL are refused;
  # an optional list of hosts narrows the rest. The policy is the application's
  # (`config :visualize, urls: [...]`), and a read may make it stricter, never looser.

  @data_types ~w(image/png image/jpeg image/webp)

  @typedoc "Whether `http:` is allowed, and the hosts allowed (`:any`, or a list)."
  @type policy :: %{http: boolean(), hosts: :any | [String.t()]}

  @typedoc "Why a URL is refused."
  @type reason :: :relative | :scheme | :http | :data_type | :host

  @doc false
  # The application's policy, made stricter by a read's `urls:` option: `http` only when
  # both allow it, the hosts the read lists that the application allows too.
  @spec policy(keyword() | map()) :: policy()
  def policy(read \\ []) do
    app = Map.new(Application.get_env(:visualize, :urls, []))
    read = Map.new(read)
    http = Map.get(app, :http, false) == true and Map.get(read, :http, true) == true

    %{http: http, hosts: narrow(Map.get(app, :hosts, :any), Map.get(read, :hosts, :any))}
  end

  defp narrow(:any, read), do: read
  defp narrow(app, :any), do: app
  defp narrow(app, read) when is_list(app) and is_list(read), do: Enum.filter(read, &(&1 in app))

  @doc false
  # `:ok`, or `{:error, reason}` for a URL the policy refuses. A template's `{s}` host is
  # checked once for each subdomain it rotates over.
  @spec check(String.t(), policy(), [String.t()]) :: :ok | {:error, reason()}
  def check(url, policy, subdomains \\ []) when is_binary(url) do
    case scheme(url) do
      nil -> {:error, :relative}
      "https" -> hosts(url, policy, subdomains)
      "http" -> if policy.http, do: hosts(url, policy, subdomains), else: {:error, :http}
      "data" -> data(url)
      _other -> {:error, :scheme}
    end
  end

  # The scheme as RFC 3986 spells it — a letter, then letters, digits, `+`, `-` or `.`,
  # then `:` — lower-cased; `nil` for a URL without one.
  defp scheme(url) do
    case Regex.run(~r/\A([A-Za-z][A-Za-z0-9+.\-]*):/, url) do
      [_, scheme] -> String.downcase(scheme)
      nil -> nil
    end
  end

  defp data(url) do
    type = url |> String.split(":", parts: 2) |> List.last() |> String.split([";", ","]) |> hd()
    if String.downcase(type) in @data_types, do: :ok, else: {:error, :data_type}
  end

  defp hosts(_url, %{hosts: :any}, _subdomains), do: :ok

  defp hosts(url, %{hosts: allowed}, subdomains) do
    host =
      url |> String.split("//", parts: 2) |> List.last() |> String.split(["/", "?", "#"]) |> hd()

    host =
      host |> String.split("@") |> List.last() |> String.split(":") |> hd() |> String.downcase()

    candidates =
      if String.contains?(host, "{s}"),
        do: Enum.map(subdomains, &String.replace(host, "{s}", &1)),
        else: [host]

    if candidates != [] and Enum.all?(candidates, &allowed?(&1, allowed)),
      do: :ok,
      else: {:error, :host}
  end

  defp allowed?(host, allowed) do
    Enum.any?(allowed, fn
      "*." <> domain -> String.ends_with?(host, "." <> String.downcase(domain))
      entry -> host == String.downcase(entry)
    end)
  end
end
