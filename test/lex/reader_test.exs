defmodule Lex.ReaderTest do
  use Lex.DataCase, async: true

  alias Lex.Reader
  alias Lex.Reader.ReadingPosition
  alias Lex.Repo

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
end
