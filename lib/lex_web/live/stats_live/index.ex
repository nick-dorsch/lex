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
  alias Lex.Text.Token
  alias Lex.Text.Sentence
  alias Lex.Vocab
  alias Lex.Vocab.LlmHelpRequest
  alias Lex.Vocab.UserLexemeState

  @chart_width 820
  @chart_height 312
  @chart_padding_left 56
  @chart_padding_right 16
  @chart_padding_top 16
  @chart_padding_bottom 32
  @max_x_ticks 6

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_user_id(socket)
    visible_series = default_visible_series()

    counts =
      if user_id do
        status_counts = Vocab.get_status_counts(user_id)

        status_counts
        |> Map.put(:read, status_counts.learning + status_counts.known)
        |> Map.put(:words_read, load_words_read_count(user_id))
      else
        %{words_read: 0, read: 0, learning: 0, known: 0}
      end

    timeline = if user_id, do: load_timeline(user_id), else: []
    learning_lexemes = if user_id, do: load_learning_lexemes(user_id), else: []
    books = if user_id, do: load_book_progress(user_id), else: %{in_progress: [], completed: []}

    chart = build_chart_series(timeline, visible_series)

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:expanded_learning_lexeme_id, nil)
     |> assign(:counts, counts)
     |> assign(:timeline, timeline)
     |> assign(:visible_series, visible_series)
     |> assign(:learning_lexemes, learning_lexemes)
     |> assign(:chart, chart)
     |> assign(:books_in_progress, books.in_progress)
     |> assign(:books_completed, books.completed)}
  end

  @impl true
  def handle_event("toggle_learning_row", %{"lexeme-id" => lexeme_id}, socket) do
    lexeme_id = String.to_integer(lexeme_id)

    expanded_learning_lexeme_id =
      if socket.assigns.expanded_learning_lexeme_id == lexeme_id do
        nil
      else
        lexeme_id
      end

    {:noreply, assign(socket, :expanded_learning_lexeme_id, expanded_learning_lexeme_id)}
  end

  @impl true
  def handle_event("toggle_chart_series", %{"series" => series}, socket) do
    visible_series = toggle_series_visibility(socket.assigns.visible_series, series)
    chart = build_chart_series(socket.assigns.timeline, visible_series)

    {:noreply,
     socket
     |> assign(:visible_series, visible_series)
     |> assign(:chart, chart)}
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
    read_by_bucket = count_lexemes_per_hour(user_id, :first_seen_at)
    known_by_bucket = count_lexemes_per_hour(user_id, :known_at)
    words_read_by_bucket = count_words_read_per_hour(user_id)

    all_buckets =
      (Map.keys(read_by_bucket) ++ Map.keys(known_by_bucket) ++ Map.keys(words_read_by_bucket))
      |> all_hourly_buckets()

    {timeline, _running} =
      Enum.reduce(all_buckets, {[], %{seen: 0, known: 0, words_read: 0}}, fn bucket,
                                                                             {acc, running} ->
        next = %{
          seen: running.seen + Map.get(read_by_bucket, bucket, 0),
          known: running.known + Map.get(known_by_bucket, bucket, 0),
          words_read: running.words_read + Map.get(words_read_by_bucket, bucket, 0)
        }

        learning = max(next.seen - next.known, 0)

        point = %{
          bucket: bucket,
          learning: learning,
          known: next.known,
          words_read: next.words_read
        }

        {[point | acc], next}
      end)

    timeline
    |> Enum.reverse()
    |> prepend_zero_start()
  end

  defp all_hourly_buckets([]), do: []

  defp all_hourly_buckets(bucket_strings) do
    bucket_datetimes = Enum.map(bucket_strings, &parse_bucket!/1)
    start_bucket = Enum.min(bucket_datetimes, NaiveDateTime)
    end_bucket = Enum.max(bucket_datetimes, NaiveDateTime)

    Stream.iterate(start_bucket, &NaiveDateTime.add(&1, 3600, :second))
    |> Enum.take_while(&(NaiveDateTime.compare(&1, end_bucket) != :gt))
    |> Enum.map(&format_bucket/1)
  end

  defp prepend_zero_start([]), do: []

  defp prepend_zero_start([first_point | _] = timeline) do
    [
      %{
        bucket: previous_hourly_bucket(first_point.bucket),
        learning: 0,
        known: 0,
        words_read: 0
      }
      | timeline
    ]
  end

  defp previous_hourly_bucket(hourly_bucket) do
    hourly_bucket
    |> parse_bucket!()
    |> NaiveDateTime.add(-3600, :second)
    |> format_bucket()
  end

  defp parse_bucket!(bucket) do
    bucket
    |> String.replace(" ", "T")
    |> NaiveDateTime.from_iso8601!()
  end

  defp format_bucket(naive_datetime) do
    Calendar.strftime(naive_datetime, "%Y-%m-%d %H:00:00")
  end

  defp count_lexemes_per_hour(user_id, timestamp_field) do
    UserLexemeState
    |> where([s], s.user_id == ^user_id)
    |> where([s], not is_nil(field(s, ^timestamp_field)))
    |> group_by(
      [s],
      fragment("strftime('%Y-%m-%d %H:00:00', ?)", field(s, ^timestamp_field))
    )
    |> select(
      [
        s
      ],
      {
        fragment("strftime('%Y-%m-%d %H:00:00', ?)", field(s, ^timestamp_field)),
        count(s.id)
      }
    )
    |> Repo.all()
    |> Map.new()
  end

  defp load_learning_lexemes(user_id) do
    learning_states =
      UserLexemeState
      |> join(:inner, [uls], lex in assoc(uls, :lexeme))
      |> where([uls, _lex], uls.user_id == ^user_id and uls.status == "learning")
      |> order_by([uls, _lex], desc: uls.seen_count, desc: uls.id)
      |> limit(100)
      |> select([uls, lex], %{
        lexeme_id: uls.lexeme_id,
        normalized_lemma: lex.normalized_lemma,
        seen_count: uls.seen_count,
        first_seen_at: uls.first_seen_at,
        last_seen_at: uls.last_seen_at
      })
      |> Repo.all()

    recent_sentence_by_lexeme =
      learning_states
      |> Enum.map(& &1.lexeme_id)
      |> recent_sentence_by_lexeme(user_id)

    llm_response_by_token_sentence =
      recent_sentence_by_lexeme
      |> Map.values()
      |> llm_response_by_token_sentence(user_id)

    Enum.map(learning_states, fn state ->
      state =
        Map.merge(state, %{
          recent_document_title: nil,
          recent_sentence: nil,
          recent_token_surface: nil,
          llm_response_text: nil
        })

      case Map.get(recent_sentence_by_lexeme, state.lexeme_id) do
        nil ->
          state

        %{
          sentence: sentence,
          token_surface: token_surface,
          sentence_id: sentence_id,
          token_id: token_id,
          document_title: document_title
        } ->
          state
          |> Map.put(:recent_document_title, document_title)
          |> Map.put(:recent_sentence, sentence)
          |> Map.put(:recent_token_surface, token_surface)
          |> Map.put(
            :llm_response_text,
            Map.get(llm_response_by_token_sentence, {sentence_id, token_id})
          )
      end
    end)
  end

  defp load_words_read_count(user_id) do
    UserSentenceState
    |> join(:inner, [uss], t in Token, on: t.sentence_id == uss.sentence_id)
    |> where(
      [uss, t],
      uss.user_id == ^user_id and uss.status == "read" and t.is_punctuation == false
    )
    |> select([_uss, t], count(t.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp count_words_read_per_hour(user_id) do
    UserSentenceState
    |> join(:inner, [uss], t in Token, on: t.sentence_id == uss.sentence_id)
    |> where(
      [uss, t],
      uss.user_id == ^user_id and uss.status == "read" and not is_nil(uss.read_at) and
        t.is_punctuation == false
    )
    |> group_by(
      [uss, _t],
      fragment("strftime('%Y-%m-%d %H:00:00', ?)", uss.read_at)
    )
    |> select(
      [uss, t],
      {
        fragment("strftime('%Y-%m-%d %H:00:00', ?)", uss.read_at),
        count(t.id)
      }
    )
    |> Repo.all()
    |> Map.new()
  end

  defp recent_sentence_by_lexeme([], _user_id), do: %{}

  defp recent_sentence_by_lexeme(lexeme_ids, user_id) do
    Token
    |> join(:inner, [t], uss in UserSentenceState, on: uss.sentence_id == t.sentence_id)
    |> join(:inner, [t, _uss], s in Sentence, on: s.id == t.sentence_id)
    |> join(:inner, [_t, _uss, s], sec in Section, on: sec.id == s.section_id)
    |> join(:inner, [_t, _uss, _s, sec], doc in Document, on: doc.id == sec.document_id)
    |> where(
      [t, uss, _s, _sec, _doc],
      uss.user_id == ^user_id and uss.status == "read" and t.lexeme_id in ^lexeme_ids
    )
    |> order_by([_t, uss, s, _sec, _doc], desc: uss.read_at, desc: s.id)
    |> select([t, _uss, s, _sec, doc], {t.lexeme_id, s.id, s.text, t.id, t.surface, doc.title})
    |> Repo.all()
    |> Enum.reduce(%{}, fn
      {lexeme_id, sentence_id, sentence_text, token_id, token_surface, document_title}, acc ->
        Map.put_new(acc, lexeme_id, %{
          sentence_id: sentence_id,
          sentence: sentence_text,
          token_id: token_id,
          token_surface: token_surface,
          document_title: document_title
        })
    end)
  end

  defp llm_response_by_token_sentence([], _user_id), do: %{}

  defp llm_response_by_token_sentence(recent_entries, user_id) do
    token_ids = Enum.map(recent_entries, & &1.token_id)

    LlmHelpRequest
    |> where(
      [r],
      r.user_id == ^user_id and r.token_id in ^token_ids and not is_nil(r.response_text)
    )
    |> order_by([r], desc: r.inserted_at)
    |> select([r], {r.sentence_id, r.token_id, r.response_text})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {sentence_id, token_id, response_text}, acc ->
      Map.put_new(acc, {sentence_id, token_id}, response_text)
    end)
  end

  defp highlight_sentence_token(nil, _token_surface), do: "-"
  defp highlight_sentence_token(sentence, nil), do: sentence
  defp highlight_sentence_token(sentence, ""), do: sentence

  defp highlight_sentence_token(sentence, token_surface) do
    regex = ~r/#{Regex.escape(token_surface)}/i

    case Regex.run(regex, sentence, return: :index) do
      [{start, length}] ->
        prefix = binary_part(sentence, 0, start)
        token = binary_part(sentence, start, length)
        suffix = binary_part(sentence, start + length, byte_size(sentence) - start - length)

        escaped_prefix = prefix |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        escaped_token = token |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        escaped_suffix = suffix |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

        Phoenix.HTML.raw(
          escaped_prefix <>
            "<span class=\"lemma-highlight\">" <>
            escaped_token <>
            "</span>" <>
            escaped_suffix
        )

      _ ->
        sentence
    end
  end

  defp render_markdown_html(content) when content in [nil, ""], do: ""

  defp render_markdown_html(content) when is_binary(content) do
    content
    |> Earmark.as_html!()
    |> HtmlSanitizeEx.basic_html()
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

  defp build_chart_series([], _visible_series) do
    %{
      grid_lines: [],
      learning: "",
      known: "",
      words_read: "",
      known_area: "",
      learning_area: "",
      x_ticks: []
    }
  end

  defp build_chart_series(timeline, visible_series) do
    values = visible_series_values(timeline, visible_series)

    max_value = Enum.max([1 | values])
    y_axis = y_axis_scale(max_value)
    width = @chart_width - @chart_padding_left - @chart_padding_right
    height = @chart_height - @chart_padding_top - @chart_padding_bottom

    learning_points =
      if visible_series.learning do
        timeline
        |> Enum.with_index()
        |> Enum.map(fn {point, index} ->
          stacked_learning = point.known + point.learning
          {point_x(index, length(timeline), width), point_y(stacked_learning, y_axis.max, height)}
        end)
      else
        []
      end

    known_points =
      if visible_series.known do
        timeline
        |> Enum.with_index()
        |> Enum.map(fn {point, index} ->
          {point_x(index, length(timeline), width), point_y(point.known, y_axis.max, height)}
        end)
      else
        []
      end

    words_read_points =
      if visible_series.words_read do
        timeline
        |> Enum.with_index()
        |> Enum.map(fn {point, index} ->
          {point_x(index, length(timeline), width), point_y(point.words_read, y_axis.max, height)}
        end)
      else
        []
      end

    baseline_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {_point, index} ->
        {point_x(index, length(timeline), width), point_y(0, y_axis.max, height)}
      end)

    %{
      grid_lines: grid_lines(y_axis, height),
      x_ticks: x_axis_ticks(timeline, width),
      learning: as_svg_points(learning_points),
      known: as_svg_points(known_points),
      words_read: as_svg_points(words_read_points),
      known_area:
        if(visible_series.known,
          do: as_svg_area_between(known_points, baseline_points),
          else: ""
        ),
      learning_area:
        if(visible_series.learning and visible_series.known,
          do: as_svg_area_between(learning_points, known_points),
          else: ""
        )
    }
  end

  defp default_visible_series do
    %{learning: true, known: true, words_read: true}
  end

  defp visible_series_values(timeline, visible_series) do
    timeline
    |> Enum.flat_map(fn point ->
      []
      |> maybe_append_value(visible_series.learning, point.known + point.learning)
      |> maybe_append_value(visible_series.known, point.known)
      |> maybe_append_value(visible_series.words_read, point.words_read)
    end)
  end

  defp maybe_append_value(values, true, value), do: [value | values]
  defp maybe_append_value(values, false, _value), do: values

  defp toggle_series_visibility(visible_series, "learning") do
    visible_series
  end

  defp toggle_series_visibility(visible_series, "known") do
    visible_series
  end

  defp toggle_series_visibility(visible_series, "words-read") do
    %{visible_series | words_read: !visible_series.words_read}
  end

  defp toggle_series_visibility(visible_series, _unknown_series), do: visible_series

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

  defp as_svg_area_between(upper_points, lower_points) do
    upper_points
    |> Kernel.++(Enum.reverse(lower_points))
    |> as_svg_points()
  end

  defp round_svg_coord(value) when is_integer(value), do: (value * 1.0) |> Float.round(2)
  defp round_svg_coord(value) when is_float(value), do: Float.round(value, 2)

  defp grid_lines(y_axis, height) do
    for value <- y_axis.max..0//-y_axis.step do
      ratio = value / y_axis.max
      y = @chart_padding_top + (height - ratio * height)
      %{value: value, y: Float.round(y, 2)}
    end
  end

  defp y_axis_scale(max_value) do
    step = dynamic_tick_step(max_value)
    %{step: step, max: round_up(max_value, step)}
  end

  defp dynamic_tick_step(max_value) when max_value <= 10, do: 1

  defp dynamic_tick_step(max_value) do
    desired_tick_count = 6
    raw_step = max_value / (desired_tick_count - 1)
    nice_step(raw_step)
  end

  defp nice_step(value) do
    magnitude = :math.pow(10, :math.floor(:math.log10(value)))
    normalized = value / magnitude

    multiplier =
      cond do
        normalized <= 1 -> 1
        normalized <= 2 -> 2
        normalized <= 5 -> 5
        true -> 10
      end

    round(multiplier * magnitude)
  end

  defp round_up(value, modulus) do
    remainder = rem(value, modulus)

    if remainder == 0 do
      value
    else
      value + modulus - remainder
    end
  end

  defp x_axis_ticks(timeline, width) do
    granularity = x_tick_granularity(timeline)
    size = length(timeline)

    {ticks, _last_key} =
      timeline
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {point, index}, {acc, last_key} ->
        datetime = parse_bucket!(point.bucket)
        key = x_tick_key(datetime, granularity)

        if key == last_key do
          {acc, last_key}
        else
          {[%{index: index, datetime: datetime} | acc], key}
        end
      end)

    ticks = Enum.reverse(ticks)

    ticks
    |> Enum.uniq_by(& &1.index)
    |> downsample_ticks_evenly(@max_x_ticks)
    |> Enum.map(fn %{index: index, datetime: datetime} ->
      %{
        x: round_svg_coord(point_x(index, size, width)),
        label: format_x_tick_label(datetime, granularity),
        anchor: x_tick_anchor(index, size)
      }
    end)
  end

  defp x_tick_granularity(timeline) do
    first_datetime = timeline |> List.first() |> Map.fetch!(:bucket) |> parse_bucket!()
    last_datetime = timeline |> List.last() |> Map.fetch!(:bucket) |> parse_bucket!()
    days = NaiveDateTime.diff(last_datetime, first_datetime, :second) / 86_400

    cond do
      days <= 45 -> :day
      days <= 360 -> :week
      true -> :month
    end
  end

  defp x_tick_key(datetime, :day), do: NaiveDateTime.to_date(datetime)

  defp x_tick_key(datetime, :week) do
    date = NaiveDateTime.to_date(datetime)
    {year, week} = :calendar.iso_week_number({date.year, date.month, date.day})
    {year, week}
  end

  defp x_tick_key(datetime, :month), do: {datetime.year, datetime.month}

  defp format_x_tick_label(datetime, :day), do: Calendar.strftime(datetime, "%d/%m")
  defp format_x_tick_label(datetime, :week), do: Calendar.strftime(datetime, "%d/%m")
  defp format_x_tick_label(datetime, :month), do: Calendar.strftime(datetime, "%b %Y")

  defp x_tick_anchor(0, _size), do: "start"
  defp x_tick_anchor(index, size) when index == size - 1, do: "end"
  defp x_tick_anchor(_index, _size), do: "middle"

  defp downsample_ticks_evenly(ticks, max_ticks) when length(ticks) <= max_ticks, do: ticks

  defp downsample_ticks_evenly(ticks, max_ticks) do
    tick_count = length(ticks)

    0..(max_ticks - 1)
    |> Enum.map(fn step ->
      round(step * (tick_count - 1) / (max_ticks - 1))
    end)
    |> Enum.uniq()
    |> Enum.map(&Enum.at(ticks, &1))
  end
end
