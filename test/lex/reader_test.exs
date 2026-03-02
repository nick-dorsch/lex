defmodule Lex.ReaderTest do
  use Lex.DataCase, async: true

  alias Lex.Reader
  alias Lex.Reader.ReadingPosition
  alias Lex.Reader.ReadingEvent
  alias Lex.Reader.UserSentenceState
  alias Lex.Repo

  import Ecto.Query

  # Helper function to create a user
  defp create_user(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      name: "Test User",
      email: "test#{unique_id}@example.com",
      primary_language: "en"
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Accounts.User{}
    |> Lex.Accounts.User.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a document
  defp create_document(user_id, attrs \\ %{}) do
    default_attrs = %{
      title: "Test Document",
      author: "Test Author",
      language: "es",
      status: "ready",
      source_file: "/path/to/file.epub",
      user_id: user_id
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Library.Document{}
    |> Lex.Library.Document.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a section
  defp create_section(document_id, position, attrs \\ %{}) do
    default_attrs = %{
      position: position,
      title: "Chapter #{position}",
      document_id: document_id
    }

    attrs = Map.merge(default_attrs, attrs)

    %Lex.Library.Section{}
    |> Lex.Library.Section.changeset(attrs)
    |> Repo.insert!()
  end

  # Helper function to create a sentence
  defp create_sentence(section_id, position, text \\ "Test sentence.") do
    %Lex.Text.Sentence{}
    |> Lex.Text.Sentence.changeset(%{
      position: position,
      text: text,
      char_start: 0,
      char_end: String.length(text),
      section_id: section_id
    })
    |> Repo.insert!()
  end

  # Helper function to create a token
  defp create_token(sentence_id, position, surface \\ "test") do
    %Lex.Text.Token{}
    |> Lex.Text.Token.changeset(%{
      position: position,
      surface: surface,
      normalized_surface: String.downcase(surface),
      lemma: String.downcase(surface),
      pos: "NOUN",
      is_punctuation: false,
      char_start: 0,
      char_end: String.length(surface),
      sentence_id: sentence_id
    })
    |> Repo.insert!()
  end

  describe "get_or_create_position/2" do
    test "returns existing position if one exists" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # Create an existing position
      {:ok, existing} =
        %ReadingPosition{}
        |> ReadingPosition.changeset(%{
          user_id: user.id,
          document_id: document.id,
          section_id: section.id,
          sentence_id: sentence.id
        })
        |> Repo.insert()

      # Get should return the existing position
      assert {:ok, ^existing} = Reader.get_or_create_position(user.id, document.id)
    end

    test "creates new position at document start if none exists" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # Should create a new position at the first sentence
      assert {:ok, position} = Reader.get_or_create_position(user.id, document.id)
      assert position.user_id == user.id
      assert position.document_id == document.id
      assert position.section_id == section.id
      assert position.sentence_id == sentence.id
    end

    test "returns error for invalid document_id" do
      user = create_user()

      assert {:error, :document_not_found} =
               Reader.get_or_create_position(user.id, 999_999)
    end

    test "creates position at first section when document has multiple sections" do
      user = create_user()
      document = create_document(user.id)

      # Create sections in non-sequential order
      section2 = create_section(document.id, 2, %{title: "Chapter 2"})
      section1 = create_section(document.id, 1, %{title: "Chapter 1"})

      _sentence_in_section2 = create_sentence(section2.id, 1, "Section 2 sentence.")
      sentence_in_section1 = create_sentence(section1.id, 1, "Section 1 sentence.")

      # Position should be at the first section (by position, not ID)
      assert {:ok, position} = Reader.get_or_create_position(user.id, document.id)
      assert position.section_id == section1.id
      assert position.sentence_id == sentence_in_section1.id
    end

    test "creates position with only section_id when document has no sentences" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)

      # No sentences in section
      assert {:ok, position} = Reader.get_or_create_position(user.id, document.id)
      assert position.section_id == section.id
      assert position.sentence_id == nil
    end

    test "creates position without section when document has no sections" do
      user = create_user()
      document = create_document(user.id)

      # No sections in document
      assert {:ok, position} = Reader.get_or_create_position(user.id, document.id)
      assert position.section_id == nil
      assert position.sentence_id == nil
    end
  end

  describe "set_position/4" do
    test "updates existing position correctly" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)
      sentence1 = create_sentence(section1.id, 1)
      sentence2 = create_sentence(section2.id, 1)

      # Create initial position
      {:ok, initial} =
        %ReadingPosition{}
        |> ReadingPosition.changeset(%{
          user_id: user.id,
          document_id: document.id,
          section_id: section1.id,
          sentence_id: sentence1.id
        })
        |> Repo.insert()

      # Update to new position
      assert {:ok, updated} =
               Reader.set_position(user.id, document.id, section2.id, sentence2.id)

      assert updated.id == initial.id
      assert updated.section_id == section2.id
      assert updated.sentence_id == sentence2.id
    end

    test "creates new position if none exists" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # No existing position
      assert {:ok, position} =
               Reader.set_position(user.id, document.id, section.id, sentence.id)

      assert position.user_id == user.id
      assert position.document_id == document.id
      assert position.section_id == section.id
      assert position.sentence_id == sentence.id
    end

    test "returns error for invalid document_id" do
      user = create_user()

      assert {:error, :document_not_found} =
               Reader.set_position(user.id, 999_999, 1, 1)
    end

    test "enforces unique constraint on user_id and document_id" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # Create position directly
      {:ok, _} =
        %ReadingPosition{}
        |> ReadingPosition.changeset(%{
          user_id: user.id,
          document_id: document.id,
          section_id: section.id,
          sentence_id: sentence.id
        })
        |> Repo.insert()

      # Manually try to insert another position for same user/document
      # This should fail at the database level
      result =
        %ReadingPosition{}
        |> ReadingPosition.changeset(%{
          user_id: user.id,
          document_id: document.id,
          section_id: section.id,
          sentence_id: sentence.id
        })
        |> Repo.insert()

      assert {:error, %Ecto.Changeset{} = changeset} = result
      assert changeset.errors[:user_id]
    end
  end

  describe "mark_sentence_read/2" do
    test "creates new sentence state with read status" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      assert {:ok, state} = Reader.mark_sentence_read(user.id, sentence.id)
      assert state.user_id == user.id
      assert state.sentence_id == sentence.id
      assert state.status == "read"
      assert state.read_at != nil
    end

    test "updates existing sentence state to read" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # Create an existing unread state
      {:ok, existing} =
        %UserSentenceState{}
        |> UserSentenceState.changeset(%{
          user_id: user.id,
          sentence_id: sentence.id,
          status: "unread"
        })
        |> Repo.insert()

      assert existing.status == "unread"
      assert existing.read_at == nil

      # Mark as read
      assert {:ok, updated} = Reader.mark_sentence_read(user.id, sentence.id)
      assert updated.id == existing.id
      assert updated.status == "read"
      assert updated.read_at != nil
    end

    test "is idempotent - multiple calls don't create duplicates" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      # First call creates the record
      assert {:ok, state1} = Reader.mark_sentence_read(user.id, sentence.id)

      # Second call updates the same record
      assert {:ok, state2} = Reader.mark_sentence_read(user.id, sentence.id)

      # Third call still the same record
      assert {:ok, state3} = Reader.mark_sentence_read(user.id, sentence.id)

      # All should be the same record
      assert state1.id == state2.id
      assert state2.id == state3.id

      # Verify only one record exists in database
      count =
        UserSentenceState
        |> where(user_id: ^user.id, sentence_id: ^sentence.id)
        |> Repo.aggregate(:count)

      assert count == 1
    end
  end

  describe "next_sentence/3" do
    test "navigates to next sentence within same section" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence1 = create_sentence(section.id, 1, "First sentence.")
      sentence2 = create_sentence(section.id, 2, "Second sentence.")

      assert {:ok, %{section: returned_section, sentence: returned_sentence}} =
               Reader.next_sentence(document.id, section.id, sentence1.id)

      assert returned_section.id == section.id
      assert returned_sentence.id == sentence2.id
    end

    test "navigates to first sentence of next section" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)
      sentence1 = create_sentence(section1.id, 1, "Last sentence of section 1.")
      sentence2 = create_sentence(section2.id, 1, "First sentence of section 2.")

      assert {:ok, %{section: returned_section, sentence: returned_sentence}} =
               Reader.next_sentence(document.id, section1.id, sentence1.id)

      assert returned_section.id == section2.id
      assert returned_sentence.id == sentence2.id
    end

    test "returns error at end of document" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1, "Only sentence.")

      assert {:error, :end_of_document} =
               Reader.next_sentence(document.id, section.id, sentence.id)
    end

    test "returns error when at last sentence of last section" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)
      _sentence1 = create_sentence(section1.id, 1, "Sentence in section 1.")
      sentence2 = create_sentence(section2.id, 1, "Last sentence in document.")

      assert {:error, :end_of_document} =
               Reader.next_sentence(document.id, section2.id, sentence2.id)
    end

    test "skips empty sections" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      _section2 = create_section(document.id, 2)
      section3 = create_section(document.id, 3)
      sentence1 = create_sentence(section1.id, 1, "Last sentence of section 1.")
      # section2 has no sentences
      sentence3 = create_sentence(section3.id, 1, "First sentence of section 3.")

      assert {:ok, %{section: returned_section, sentence: returned_sentence}} =
               Reader.next_sentence(document.id, section1.id, sentence1.id)

      assert returned_section.id == section3.id
      assert returned_sentence.id == sentence3.id
    end

    test "returns end_of_document when only empty sections remain" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      _section2 = create_section(document.id, 2)
      sentence = create_sentence(section1.id, 1, "Only sentence with content.")
      # section2 has no sentences

      assert {:error, :end_of_document} =
               Reader.next_sentence(document.id, section1.id, sentence.id)
    end
  end

  describe "previous_sentence/3" do
    test "navigates to previous sentence within same section" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence1 = create_sentence(section.id, 1, "First sentence.")
      sentence2 = create_sentence(section.id, 2, "Second sentence.")

      assert {:ok, %{section: returned_section, sentence: returned_sentence}} =
               Reader.previous_sentence(document.id, section.id, sentence2.id)

      assert returned_section.id == section.id
      assert returned_sentence.id == sentence1.id
    end

    test "navigates to last sentence of previous section" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)
      sentence1 = create_sentence(section1.id, 1, "Last sentence of section 1.")
      sentence2 = create_sentence(section2.id, 1, "First sentence of section 2.")

      assert {:ok, %{section: returned_section, sentence: returned_sentence}} =
               Reader.previous_sentence(document.id, section2.id, sentence2.id)

      assert returned_section.id == section1.id
      assert returned_sentence.id == sentence1.id
    end

    test "returns error at start of document" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1, "Only sentence.")

      assert {:error, :start_of_document} =
               Reader.previous_sentence(document.id, section.id, sentence.id)
    end

    test "returns error when at first sentence of first section" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)
      sentence1 = create_sentence(section1.id, 1, "First sentence in document.")
      _sentence2 = create_sentence(section2.id, 1, "Sentence in section 2.")

      assert {:error, :start_of_document} =
               Reader.previous_sentence(document.id, section1.id, sentence1.id)
    end

    test "skips empty sections when going backwards" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      _section2 = create_section(document.id, 2)
      section3 = create_section(document.id, 3)
      sentence1 = create_sentence(section1.id, 1, "Last sentence of section 1.")
      # section2 has no sentences
      sentence3 = create_sentence(section3.id, 1, "First sentence of section 3.")

      assert {:ok, %{section: returned_section, sentence: returned_sentence}} =
               Reader.previous_sentence(document.id, section3.id, sentence3.id)

      assert returned_section.id == section1.id
      assert returned_sentence.id == sentence1.id
    end

    test "returns start_of_document when only empty sections before" do
      user = create_user()
      document = create_document(user.id)
      _section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)
      # section1 has no sentences
      sentence = create_sentence(section2.id, 1, "Only sentence with content.")

      assert {:error, :start_of_document} =
               Reader.previous_sentence(document.id, section2.id, sentence.id)
    end
  end

  describe "skip_to_next_section/3" do
    test "skips to first sentence of next section" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1, %{title: "Chapter 1"})
      section2 = create_section(document.id, 2, %{title: "Chapter 2"})
      sentence1 = create_sentence(section1.id, 1, "Last sentence of chapter 1.")
      sentence2 = create_sentence(section2.id, 1, "First sentence of chapter 2.")

      assert {:ok,
              %{
                section: returned_section,
                sentence: returned_sentence,
                skipped_sentences: skipped
              }} =
               Reader.skip_to_next_section(document.id, section1.id, sentence1.id)

      assert returned_section.id == section2.id
      assert returned_sentence.id == sentence2.id
      # Skips 0 sentences because we land immediately on the next section
      # (no intermediate sections to skip)
      assert skipped == 0
    end

    test "returns error at last section" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1, %{title: "Only Chapter"})
      sentence = create_sentence(section.id, 1, "Only sentence.")

      assert {:error, :end_of_document} =
               Reader.skip_to_next_section(document.id, section.id, sentence.id)
    end

    test "skips empty sections automatically" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1, %{title: "Chapter 1"})
      _section2 = create_section(document.id, 2, %{title: "Empty Chapter"})
      section3 = create_section(document.id, 3, %{title: "Chapter 3"})
      sentence1 = create_sentence(section1.id, 1, "Sentence in chapter 1.")
      # section2 has no sentences
      sentence3 = create_sentence(section3.id, 1, "Sentence in chapter 3.")

      assert {:ok,
              %{
                section: returned_section,
                sentence: returned_sentence,
                skipped_sentences: skipped
              }} =
               Reader.skip_to_next_section(document.id, section1.id, sentence1.id)

      assert returned_section.id == section3.id
      assert returned_sentence.id == sentence3.id
      # Empty sections don't add to skipped count
      assert skipped == 0
    end

    test "skips multiple sections and counts skipped sentences" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1, %{title: "Chapter 1"})
      section2 = create_section(document.id, 2, %{title: "Chapter 2"})
      section3 = create_section(document.id, 3, %{title: "Chapter 3"})
      sentence1 = create_sentence(section1.id, 1, "Sentence 1.")
      _sentence2a = create_sentence(section2.id, 1, "Sentence 2a.")
      _sentence2b = create_sentence(section2.id, 2, "Sentence 2b.")
      sentence3 = create_sentence(section3.id, 1, "Sentence 3.")

      assert {:ok,
              %{
                section: returned_section,
                sentence: returned_sentence,
                skipped_sentences: skipped
              }} =
               Reader.skip_to_next_section(document.id, section1.id, sentence1.id)

      assert returned_section.id == section3.id
      assert returned_sentence.id == sentence3.id
      # Skips 2 sentences from section2 (the intermediate section with content)
      assert skipped == 2
    end

    test "lands on last section when it's the only one with content" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1, %{title: "Chapter 1"})
      section2 = create_section(document.id, 2, %{title: "Chapter 2"})
      sentence1 = create_sentence(section1.id, 1, "Sentence in chapter 1.")
      sentence2 = create_sentence(section2.id, 1, "Sentence in chapter 2.")

      assert {:ok,
              %{
                section: returned_section,
                sentence: returned_sentence,
                skipped_sentences: skipped
              }} =
               Reader.skip_to_next_section(document.id, section1.id, sentence1.id)

      # Cannot skip last section, so we land on it
      assert returned_section.id == section2.id
      assert returned_sentence.id == sentence2.id
      assert skipped == 1
    end
  end

  describe "log_event/3" do
    test "logs enter_sentence event" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)

      assert {:ok, event} =
               Reader.log_event(user.id, :enter_sentence, %{
                 document_id: document.id,
                 sentence_id: sentence.id
               })

      assert event.user_id == user.id
      assert event.document_id == document.id
      assert event.sentence_id == sentence.id
      assert event.event_type == "enter_sentence"
      assert event.inserted_at != nil
    end

    test "logs advance_sentence event with navigation metadata" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence1 = create_sentence(section.id, 1)
      sentence2 = create_sentence(section.id, 2)

      assert {:ok, event} =
               Reader.log_event(user.id, :advance_sentence, %{
                 document_id: document.id,
                 from_sentence_id: sentence1.id,
                 to_sentence_id: sentence2.id
               })

      assert event.user_id == user.id
      assert event.event_type == "advance_sentence"
      decoded_payload = ReadingEvent.decode_payload(event)
      assert decoded_payload["from_sentence_id"] == sentence1.id
      assert decoded_payload["to_sentence_id"] == sentence2.id
    end

    test "logs skip_range event" do
      user = create_user()
      document = create_document(user.id)
      section1 = create_section(document.id, 1)
      section2 = create_section(document.id, 2)

      assert {:ok, event} =
               Reader.log_event(user.id, :skip_range, %{
                 document_id: document.id,
                 from_section_id: section1.id,
                 to_section_id: section2.id,
                 skipped_sentences: 10
               })

      assert event.event_type == "skip_range"
      decoded_payload = ReadingEvent.decode_payload(event)
      assert decoded_payload["skipped_sentences"] == 10
    end

    test "logs mark_learning event with token reference" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      token = create_token(sentence.id, 1)

      assert {:ok, event} =
               Reader.log_event(user.id, :mark_learning, %{
                 document_id: document.id,
                 sentence_id: sentence.id,
                 token_id: token.id,
                 lexeme_id: 123
               })

      assert event.event_type == "mark_learning"
      assert event.token_id == token.id
      decoded_payload = ReadingEvent.decode_payload(event)
      assert decoded_payload["lexeme_id"] == 123
    end

    test "logs unmark_learning event" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      token = create_token(sentence.id, 1)

      assert {:ok, event} =
               Reader.log_event(user.id, :unmark_learning, %{
                 document_id: document.id,
                 sentence_id: sentence.id,
                 token_id: token.id
               })

      assert event.event_type == "unmark_learning"
      assert event.token_id == token.id
    end

    test "logs llm_help_requested event" do
      user = create_user()
      document = create_document(user.id)
      section = create_section(document.id, 1)
      sentence = create_sentence(section.id, 1)
      token = create_token(sentence.id, 1)

      assert {:ok, event} =
               Reader.log_event(user.id, :llm_help_requested, %{
                 document_id: document.id,
                 sentence_id: sentence.id,
                 token_id: token.id
               })

      assert event.event_type == "llm_help_requested"
      assert event.token_id == token.id
    end

    test "metadata is properly serialized to JSON" do
      user = create_user()
      document = create_document(user.id)

      metadata = %{
        document_id: document.id,
        custom_field: "custom_value",
        nested: %{key: "value"},
        list: [1, 2, 3]
      }

      assert {:ok, event} = Reader.log_event(user.id, :enter_sentence, metadata)

      decoded = ReadingEvent.decode_payload(event)
      assert decoded["custom_field"] == "custom_value"
      assert decoded["nested"]["key"] == "value"
      assert decoded["list"] == [1, 2, 3]
    end

    test "event has correct user_id and timestamp" do
      user = create_user()
      document = create_document(user.id)

      assert {:ok, event} =
               Reader.log_event(user.id, :enter_sentence, %{document_id: document.id})

      assert event.user_id == user.id
      assert event.inserted_at != nil

      # Verify timestamp is set and is a valid datetime
      inserted_at = DateTime.from_naive!(event.inserted_at, "Etc/UTC")
      assert %DateTime{} = inserted_at
    end

    test "returns error for invalid event type" do
      user = create_user()
      document = create_document(user.id)

      # Invalid event type should fail validation
      assert {:error, %Ecto.Changeset{} = changeset} =
               Reader.log_event(user.id, :invalid_event_type, %{document_id: document.id})

      assert changeset.errors[:event_type]
    end

    test "returns error when required fields missing" do
      user = create_user()

      # Missing document_id should fail validation
      assert {:error, %Ecto.Changeset{} = changeset} =
               Reader.log_event(user.id, :enter_sentence, %{document_id: nil})

      assert changeset.errors[:document_id]
    end

    test "empty metadata is allowed" do
      user = create_user()
      document = create_document(user.id)

      assert {:ok, event} =
               Reader.log_event(user.id, :enter_sentence, %{document_id: document.id})

      decoded = ReadingEvent.decode_payload(event)
      assert decoded == %{"document_id" => document.id}
    end
  end
end
