defmodule LexWeb.StatsLive.Index do
  @moduledoc """
  LiveView dashboard for user reading and vocabulary stats.
  """
  use LexWeb, :live_view

  import Ecto.Query

  alias Lex.Accounts.User
  alias Lex.Library.Document
  alias Lex.Library.Section
  alias Lex.Reader.UserSentenceState
  alias Lex.Repo
  alias Lex.Text.Sentence
  alias Lex.Vocab
  alias Lex.Vocab.UserLexemeState

  @chart_width 820
  @chart_height 260
  @chart_padding_left 56
  @chart_padding_right 16
  @chart_padding_top 16
  @chart_padding_bottom 32

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_user_id(socket)

    counts =
      if user_id, do: Vocab.get_status_counts(user_id), else: %{read: 0, learning: 0, known: 0}

    timeline = if user_id, do: load_timeline(user_id), else: []
    books = if user_id, do: load_book_progress(user_id), else: %{in_progress: [], completed: []}

    chart = build_chart_series(timeline)

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:counts, counts)
     |> assign(:timeline, timeline)
     |> assign(:chart, chart)
     |> assign(:books_in_progress, books.in_progress)
     |> assign(:books_completed, books.completed)}
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} -> user_id
      _ -> first_user_id()
    end
  end

  defp first_user_id,
    do: Repo.one(from(u in User, order_by: [asc: u.id], limit: 1, select: u.id))

  defp load_timeline(user_id) do
    read_by_hour = count_lexemes_per_hour(user_id, :first_seen_at)
    learning_by_hour = count_lexemes_per_hour(user_id, :learning_since)
    known_by_hour = count_lexemes_per_hour(user_id, :known_at)

    all_hours =
      (Map.keys(read_by_hour) ++ Map.keys(learning_by_hour) ++ Map.keys(known_by_hour))
      |> Enum.uniq()
      |> Enum.sort()

    {timeline, _running} =
      Enum.reduce(all_hours, {[], %{read: 0, learning: 0, known: 0}}, fn hour, {acc, running} ->
        next = %{
          read: running.read + Map.get(read_by_hour, hour, 0),
          learning: running.learning + Map.get(learning_by_hour, hour, 0),
          known: running.known + Map.get(known_by_hour, hour, 0)
        }

        point = %{hour: hour, read: next.read, learning: next.learning, known: next.known}
        {[point | acc], next}
      end)

    Enum.reverse(timeline)
  end

  defp count_lexemes_per_hour(user_id, timestamp_field) do
    UserLexemeState
    |> where([s], s.user_id == ^user_id)
    |> where([s], not is_nil(field(s, ^timestamp_field)))
    |> group_by([s], fragment("strftime('%Y-%m-%d %H:00:00', ?)", field(s, ^timestamp_field)))
    |> select(
      [
        s
      ],
      {fragment("strftime('%Y-%m-%d %H:00:00', ?)", field(s, ^timestamp_field)), count(s.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp load_book_progress(user_id) do
    documents =
      Document
      |> where([d], d.user_id == ^user_id and d.status == "ready")
      |> order_by([d], asc: d.title)
      |> select([d], %{id: d.id, title: d.title, author: d.author})
      |> Repo.all()

    document_ids = Enum.map(documents, & &1.id)

    total_by_document = total_sentences_by_document(document_ids)
    read_by_document = read_sentences_by_document(user_id, document_ids)

    books =
      Enum.map(documents, fn doc ->
        total = Map.get(total_by_document, doc.id, 0)
        read = Map.get(read_by_document, doc.id, 0)
        progress = if total > 0, do: round(read / total * 100), else: 0

        %{
          id: doc.id,
          title: doc.title,
          author: doc.author || "Unknown",
          total_sentences: total,
          read_sentences: read,
          progress: progress
        }
      end)

    %{
      in_progress:
        Enum.filter(books, fn book ->
          book.read_sentences > 0 and book.read_sentences < book.total_sentences
        end),
      completed:
        Enum.filter(books, fn book ->
          book.total_sentences > 0 and book.read_sentences == book.total_sentences
        end)
    }
  end

  defp total_sentences_by_document([]), do: %{}

  defp total_sentences_by_document(document_ids) do
    Sentence
    |> join(:inner, [s], sec in Section, on: s.section_id == sec.id)
    |> where([_s, sec], sec.document_id in ^document_ids)
    |> group_by([_s, sec], sec.document_id)
    |> select([s, sec], {sec.document_id, count(s.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp read_sentences_by_document(_user_id, []), do: %{}

  defp read_sentences_by_document(user_id, document_ids) do
    UserSentenceState
    |> join(:inner, [uss], s in Sentence, on: uss.sentence_id == s.id)
    |> join(:inner, [_uss, s], sec in Section, on: s.section_id == sec.id)
    |> where([uss, _s, sec], uss.user_id == ^user_id and uss.status == "read")
    |> where([_uss, _s, sec], sec.document_id in ^document_ids)
    |> group_by([_uss, _s, sec], sec.document_id)
    |> select([uss, _s, sec], {sec.document_id, count(uss.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp build_chart_series([]) do
    %{grid_lines: [], read: "", learning: "", known: "", labels: %{start: "", end: ""}}
  end

  defp build_chart_series(timeline) do
    values =
      timeline
      |> Enum.flat_map(fn point -> [point.read, point.learning, point.known] end)

    max_value = Enum.max([1 | values])
    width = @chart_width - @chart_padding_left - @chart_padding_right
    height = @chart_height - @chart_padding_top - @chart_padding_bottom

    read_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point_x(index, length(timeline), width), point_y(point.read, max_value, height)}
      end)

    learning_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point_x(index, length(timeline), width), point_y(point.learning, max_value, height)}
      end)

    known_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point_x(index, length(timeline), width), point_y(point.known, max_value, height)}
      end)

    %{grid_lines: grid_lines(max_value, height), labels: edge_labels(timeline)}
    |> Map.put(:read, as_svg_points(read_points))
    |> Map.put(:learning, as_svg_points(learning_points))
    |> Map.put(:known, as_svg_points(known_points))
  end

  defp point_x(_index, 1, _width), do: @chart_padding_left

  defp point_x(index, size, width) do
    @chart_padding_left + index * width / (size - 1)
  end

  defp point_y(value, max_value, height) do
    @chart_padding_top + (height - value / max_value * height)
  end

  defp as_svg_points(points) do
    points
    |> Enum.map_join(" ", fn {x, y} ->
      "#{round_svg_coord(x)},#{round_svg_coord(y)}"
    end)
  end

  defp round_svg_coord(value) when is_integer(value), do: (value * 1.0) |> Float.round(2)
  defp round_svg_coord(value) when is_float(value), do: Float.round(value, 2)

  defp grid_lines(max_value, height) do
    for step <- 0..4 do
      ratio = step / 4
      value = round(max_value * ratio)
      y = @chart_padding_top + (height - ratio * height)
      %{value: value, y: Float.round(y, 2)}
    end
  end

  defp edge_labels(timeline) do
    %{
      start: format_date_label(List.first(timeline).hour),
      end: format_date_label(List.last(timeline).hour)
    }
  end

  defp format_date_label(hourly_bucket) do
    date = hourly_bucket |> String.split(" ", parts: 2) |> List.first()

    case String.split(date, "-") do
      [year, month, day] -> "#{month}/#{day}/#{year}"
      _ -> hourly_bucket
    end
  end
end
