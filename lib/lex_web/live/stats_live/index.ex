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
  @chart_height 260
  @chart_padding_left 56
  @chart_padding_right 16
  @chart_padding_top 16
  @chart_padding_bottom 32

  @impl true
  def mount(_params, _session, socket) do
    user_id = get_user_id(socket)

    counts =
      if user_id do
        user_id
        |> Vocab.get_status_counts()
        |> Map.put(:words_read, load_words_read_count(user_id))
      else
        %{words_read: 0, read: 0, learning: 0, known: 0}
      end

    timeline = if user_id, do: load_timeline(user_id), else: []
    learning_lexemes = if user_id, do: load_learning_lexemes(user_id), else: []
    books = if user_id, do: load_book_progress(user_id), else: %{in_progress: [], completed: []}

    chart = build_chart_series(timeline)

    {:ok,
     socket
     |> assign(:user_id, user_id)
     |> assign(:expanded_learning_lexeme_id, nil)
     |> assign(:counts, counts)
     |> assign(:timeline, timeline)
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

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} -> user_id
      _ -> first_user_id()
    end
  end

  defp first_user_id,
    do: Repo.one(from(u in User, order_by: [asc: u.id], limit: 1, select: u.id))

  defp load_timeline(user_id) do
    read_by_bucket = count_lexemes_per_twenty_minutes(user_id, :first_seen_at)
    learning_by_bucket = count_lexemes_per_twenty_minutes(user_id, :learning_since)
    known_by_bucket = count_lexemes_per_twenty_minutes(user_id, :known_at)

    all_buckets =
      (Map.keys(read_by_bucket) ++
         Map.keys(learning_by_bucket) ++ Map.keys(known_by_bucket))
      |> all_twenty_minute_buckets()

    {timeline, _running} =
      Enum.reduce(all_buckets, {[], %{read: 0, learning: 0, known: 0}}, fn bucket,
                                                                           {acc, running} ->
        next = %{
          read: running.read + Map.get(read_by_bucket, bucket, 0),
          learning: running.learning + Map.get(learning_by_bucket, bucket, 0),
          known: running.known + Map.get(known_by_bucket, bucket, 0)
        }

        point = %{
          bucket: bucket,
          read: next.read + next.learning + next.known,
          learning: next.learning,
          known: next.known
        }

        {[point | acc], next}
      end)

    timeline
    |> Enum.reverse()
    |> prepend_zero_start()
  end

  defp all_twenty_minute_buckets([]), do: []

  defp all_twenty_minute_buckets(bucket_strings) do
    bucket_datetimes = Enum.map(bucket_strings, &parse_bucket!/1)
    start_bucket = Enum.min(bucket_datetimes, NaiveDateTime)
    end_bucket = Enum.max(bucket_datetimes, NaiveDateTime)

    Stream.iterate(start_bucket, &NaiveDateTime.add(&1, 1200, :second))
    |> Enum.take_while(&(NaiveDateTime.compare(&1, end_bucket) != :gt))
    |> Enum.map(&format_bucket/1)
  end

  defp prepend_zero_start([]), do: []

  defp prepend_zero_start([first_point | _] = timeline) do
    [
      %{bucket: previous_twenty_minute_bucket(first_point.bucket), read: 0, learning: 0, known: 0}
      | timeline
    ]
  end

  defp previous_twenty_minute_bucket(twenty_minute_bucket) do
    twenty_minute_bucket
    |> parse_bucket!()
    |> NaiveDateTime.add(-1200, :second)
    |> format_bucket()
  end

  defp parse_bucket!(bucket) do
    bucket
    |> String.replace(" ", "T")
    |> NaiveDateTime.from_iso8601!()
  end

  defp format_bucket(naive_datetime) do
    Calendar.strftime(naive_datetime, "%Y-%m-%d %H:%M:00")
  end

  defp count_lexemes_per_twenty_minutes(user_id, timestamp_field) do
    UserLexemeState
    |> where([s], s.user_id == ^user_id)
    |> where([s], not is_nil(field(s, ^timestamp_field)))
    |> group_by(
      [s],
      fragment(
        "strftime('%Y-%m-%d %H:', ?) || printf('%02d:00', (cast(strftime('%M', ?) as integer) / 20) * 20)",
        field(s, ^timestamp_field),
        field(s, ^timestamp_field)
      )
    )
    |> select(
      [
        s
      ],
      {
        fragment(
          "strftime('%Y-%m-%d %H:', ?) || printf('%02d:00', (cast(strftime('%M', ?) as integer) / 20) * 20)",
          field(s, ^timestamp_field),
          field(s, ^timestamp_field)
        ),
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
        first_seen_at: uls.first_seen_at
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

  defp build_chart_series([]) do
    %{
      grid_lines: [],
      read: "",
      learning: "",
      known: "",
      read_area: "",
      known_area: "",
      learning_area: "",
      labels: %{start: "", end: ""}
    }
  end

  defp build_chart_series(timeline) do
    values =
      timeline
      |> Enum.flat_map(fn point -> [point.read, point.learning, point.known] end)

    max_value = Enum.max([1 | values])
    y_axis = y_axis_scale(max_value)
    width = @chart_width - @chart_padding_left - @chart_padding_right
    height = @chart_height - @chart_padding_top - @chart_padding_bottom

    read_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point_x(index, length(timeline), width), point_y(point.read, y_axis.max, height)}
      end)

    learning_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point_x(index, length(timeline), width), point_y(point.learning, y_axis.max, height)}
      end)

    known_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {point, index} ->
        {point_x(index, length(timeline), width), point_y(point.known, y_axis.max, height)}
      end)

    baseline_points =
      timeline
      |> Enum.with_index()
      |> Enum.map(fn {_point, index} ->
        {point_x(index, length(timeline), width), point_y(0, y_axis.max, height)}
      end)

    %{
      grid_lines: grid_lines(y_axis, height),
      labels: edge_labels(timeline),
      read: as_svg_points(read_points),
      learning: as_svg_points(learning_points),
      known: as_svg_points(known_points),
      learning_area: as_svg_area_between(learning_points, baseline_points),
      known_area: as_svg_area_between(known_points, learning_points),
      read_area: as_svg_area_between(read_points, known_points)
    }
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

  defp edge_labels(timeline) do
    %{
      start: format_date_label(List.first(timeline).bucket),
      end: format_date_label(List.last(timeline).bucket)
    }
  end

  defp format_date_label(bucket) do
    with {:ok, naive_datetime} <-
           bucket |> String.replace(" ", "T") |> NaiveDateTime.from_iso8601() do
      Calendar.strftime(naive_datetime, "%m/%d/%Y")
    else
      _ -> bucket
    end
  end
end
