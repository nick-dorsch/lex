defmodule Lex.Library.Language do
  @moduledoc """
  ISO language normalization utilities for EPUB language values and user target language values.

  Provides functions to normalize language tags using ISO code semantics, including:
  - Normalizing casing and separators
  - Extracting base languages from region-specific tags
  - Matching region-specific tags to base language targets
  - Handling missing/blank/invalid language metadata as "unknown"
  """

  @unknown "unknown"

  @doc """
  Normalizes a language tag to lowercase with standardized separators.

  Converts underscores to hyphens and downcases the entire tag.
  Returns "unknown" for nil, empty, or whitespace-only strings.

  ## Examples

      iex> Language.normalize("es-ES")
      "es-es"

      iex> Language.normalize("es_ES")
      "es-es"

      iex> Language.normalize("ES")
      "es"

      iex> Language.normalize(nil)
      "unknown"

      iex> Language.normalize("")
      "unknown"
  """
  @spec normalize(String.t() | nil) :: String.t()
  def normalize(nil), do: @unknown

  def normalize(language) when is_binary(language) do
    language
    |> String.trim()
    |> case do
      "" ->
        @unknown

      trimmed ->
        trimmed
        |> String.downcase()
        |> String.replace("_", "-")
    end
  end

  @doc """
  Extracts the base language code from a language tag.

  Removes region/script/variant subtags, returning just the primary language code.
  Returns "unknown" for nil, empty, or whitespace-only strings.

  ## Examples

      iex> Language.base_language("es-ES")
      "es"

      iex> Language.base_language("es_ES")
      "es"

      iex> Language.base_language("zh-Hans-CN")
      "zh"

      iex> Language.base_language("en")
      "en"

      iex> Language.base_language(nil)
      "unknown"
  """
  @spec base_language(String.t() | nil) :: String.t()
  def base_language(nil), do: @unknown

  def base_language(language) when is_binary(language) do
    language
    |> normalize()
    |> case do
      @unknown ->
        @unknown

      normalized ->
        normalized
        |> String.split("-")
        |> List.first()
    end
  end

  @doc """
  Checks if a language tag matches a target language (with base language support).

  Returns true if the normalized language tag's base language matches the target.
  Supports region-specific tags matching their base (e.g., "es-ES" matches "es").

  ## Examples

      iex> Language.matches_target?("es-ES", "es")
      true

      iex> Language.matches_target?("es_MX", "es")
      true

      iex> Language.matches_target?("es", "es")
      true

      iex> Language.matches_target?("en-US", "es")
      false

      iex> Language.matches_target?(nil, "es")
      false

      iex> Language.matches_target?("es-ES", nil)
      false
  """
  @spec matches_target?(String.t() | nil, String.t() | nil) :: boolean()
  def matches_target?(nil, _target), do: false
  def matches_target?(_language, nil), do: false

  def matches_target?(language, target) when is_binary(language) and is_binary(target) do
    language_base = base_language(language)
    target_normalized = normalize(target)

    language_base != @unknown and
      target_normalized != @unknown and
      language_base == target_normalized
  end

  @doc """
  Normalizes an EPUB language value to a standardized form.

  This is the main entry point for processing language metadata from EPUB files.
  Returns the normalized language code or "unknown" for invalid values.

  ## Examples

      iex> Language.from_epub("es-ES")
      "es-es"

      iex> Language.from_epub("ES")
      "es"

      iex> Language.from_epub(nil)
      "unknown"

      iex> Language.from_epub("  ")
      "unknown"
  """
  @spec from_epub(String.t() | nil) :: String.t()
  def from_epub(language) do
    normalize(language)
  end

  @doc """
  Normalizes a user target language value to its base form.

  This is the main entry point for processing user target language preferences.
  Returns the base language code or "unknown" for invalid values.

  ## Examples

      iex> Language.from_user_target("es-ES")
      "es"

      iex> Language.from_user_target("zh-Hans")
      "zh"

      iex> Language.from_user_target("en")
      "en"

      iex> Language.from_user_target(nil)
      "unknown"
  """
  @spec from_user_target(String.t() | nil) :: String.t()
  def from_user_target(language) do
    base_language(language)
  end

  @doc """
  Returns the string used to represent unknown/invalid languages.

  ## Examples

      iex> Language.unknown()
      "unknown"
  """
  @spec unknown() :: String.t()
  def unknown, do: @unknown
end
