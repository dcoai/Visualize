defmodule Visualize.Feed.Conformance.Words do
  @moduledoc false
  # The findings of spec/08 §12.3 in words, for `Visualize.Feed.Conformance.format/1`.

  alias Visualize.Data.Schema
  alias Visualize.Feed

  @doc false
  def words({:raised, call, reason}),
    do:
      "#{call(call)} raised or exited instead of answering a value: #{Exception.format_exit(reason)}"

  def words({:timeout, call}), do: "#{call(call)} did not answer within the timeout"
  def words({:describe_error, reason}), do: "describe/1 answered {:error, #{inspect(reason)}}"

  def words({:not_described, answer}),
    do: "describe/1 answered #{inspect(answer)}, not {version, %Schema{}, supports}"

  def words({:schema_invalid, errors}),
    do:
      "the schema is not one Schema.new/1 accepts: #{Enum.map_join(errors, "; ", &Schema.format_error/1)}"

  def words({:measure, field, reason}),
    do:
      "the schema's field #{inspect(field)} names a measure the vocabulary refuses: " <>
        Schema.format_error({[field, key(reason)], reason})

  def words({:version, given, computed}) when is_binary(computed),
    do: "the version #{inspect(given)} is not the schema's content hash #{inspect(computed)}"

  def words({:unstable, first, second}),
    do:
      "a second describe answered #{inspect(second)} where the first answered #{inspect(first)}, or another schema under it"

  def words({:fetch_error, request, reason}),
    do: "#{request(request)} answered {:error, #{inspect(reason)}}"

  def words({:not_a_delivery, request, answer}),
    do: "#{request(request)} answered #{inspect(answer)}, not {:ok, %Delivery{}}"

  def words({:malformed, request, field, value}),
    do: "#{request(request)}: the delivery's #{field} is not one: #{inspect(value)}"

  def words({:version, request, named, described}),
    do:
      "#{request(request)}: the delivery names the version #{inspect(named)}, describe answered #{inspect(described)}"

  def words({:undescribed_field, request, field}),
    do: "#{request(request)}: a row holds #{inspect(field)}, which the schema does not describe"

  def words({:window_value, request, value}),
    do:
      "#{request(request)}: a row's window field holds #{inspect(value)}, not a value of its type " <>
        "(an instant for :time, a number for :number)"

  def words({:no_identity, request, field}),
    do:
      "#{request(request)}: a row has no value for #{inspect(field)}, which the schema " <>
        "declares part of its identity; every row says what it is about"

  def words({:not_an_instant, request, field, value}),
    do:
      "#{request(request)}: the :time field #{inspect(field)} holds #{inspect(value)}, not an " <>
        "instant; a count or a tick is a :number"

  def words({:no_window_field, times}),
    do:
      "the feed names :window but its schema has no window field (its :time fields: " <>
        "#{inspect(times)}); describe the field its windows are over window: true"

  def words({:outside_served, request, time, served}),
    do:
      "#{request(request)}: a row at #{inspect(time)} lies outside the served window #{inspect(served)}"

  def words({:missing, request, count, served}),
    do:
      "#{request(request)}: the delivery says it served #{inspect(served)}, but #{rows(count)} the feed holds there are missing"

  def words({:capped, request, served}),
    do:
      "#{request(request)}: capped is true, but the served window #{inspect(served)} reaches the asked from"

  def words({:uncapped, request, count}),
    do:
      "#{request(request)}: capped is false, but the feed holds #{rows(count)} in the asked window before where it served from"

  def words({:reduced_by, request, by}),
    do: "#{request(request)}: reduced_by is #{inspect(by)}, which is not true of this delivery"

  def words({:unrecorded_reduction, request, count, whole}),
    do: "#{request(request)}: served #{count} rows of #{whole} with reduced_by nil"

  def words({:resolution, request, gap, resolution}),
    do:
      "#{request(request)}: two rows of one series #{inspect(gap)} apart, finer than the resolution #{inspect(resolution)}"

  def words({:supports, supports}),
    do:
      "supports #{inspect(supports)} is not a list of distinct members of #{inspect(Feed.capabilities())}"

  def words({:no_probe, :window}),
    do: "the feed names :window, and windows: has none with a bound to probe it"

  def words({:no_probe, :budget}),
    do: "the feed names :budget, and budgets: has none to probe it"

  def words({:no_probe, :push}),
    do: "the feed names :push, and there is no push: function to make it push"

  def words({:window_served, request, served}),
    do:
      "#{request(request)}: the feed names :window and served #{inspect(served)}, not within the window asked"

  def words({:window_row, request, time}),
    do:
      "#{request(request)}: the feed names :window and served a row at #{inspect(time)}, outside the window asked"

  def words({:over_budget, {window, budget}, count}),
    do:
      "asked for at most #{budget} rows (window #{inspect(window)}), the feed names :budget and served #{count}"

  def words({:push_refused, reason}),
    do: "the feed names :push, and subscribe/2 answered {:error, #{inspect(reason)}}"

  def words({:push_undeclared, answer}),
    do: "the feed does not name :push, and subscribe/2 answered #{inspect(answer)}"

  def words({:subscribe_error, reason}), do: "subscribe/2 answered {:error, #{inspect(reason)}}"

  def words({:handshake, got}),
    do: "the first message after subscribe/2 was #{inspect(got)}, not the schema"

  def words({:schema_message, version, computed}),
    do:
      "a pushed schema's version #{inspect(version)} is not its content hash #{inspect(computed)}"

  def words({:before_schema, version}),
    do: "a delivery naming #{inspect(version)} arrived before that version's schema"

  def words({:not_a_message, message}),
    do: "a message that is neither a schema nor a delivery: #{inspect(message)}"

  def words({:no_delivery, timeout}),
    do: "push: ran and no delivery arrived within #{timeout} ms"

  def words({:not_a_value, call, answer}),
    do: "#{call(call)} answered #{inspect(answer)}, neither its success nor {:error, reason}"

  def words({:answered_down, call, answer}),
    do: "the down: feed answered #{call(call)} with #{inspect(answer)}, not an error"

  def words({:unsubscribe, answer}), do: "unsubscribe/2 answered #{inspect(answer)}, not :ok"

  def words({:pushed_after_unsubscribe, count}),
    do: "#{count} message(s) arrived after unsubscribe/2"

  def words(other), do: inspect(other)

  defp call({:fetch, window, budget}), do: "fetch(feed, #{inspect(window)}, #{inspect(budget)})"
  defp call(:describe), do: "describe/1"
  defp call(:subscribe), do: "subscribe/2"
  defp call(:unsubscribe), do: "unsubscribe/2"
  defp call(:push), do: "the push: function"
  defp call(:rows), do: "reading the rows"

  defp rows(1), do: "1 row"
  defp rows(n), do: "#{n} rows"

  defp request(:push), do: "a pushed delivery"
  defp request({window, budget}), do: "fetch(feed, #{inspect(window)}, #{inspect(budget)})"

  # The key a measure's fault is at (spec/08 §10.1).
  defp key({:unit, _code, _reason}), do: :unit
  defp key(_quantity_fault), do: :quantity
end
