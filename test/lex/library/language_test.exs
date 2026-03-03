defmodule Lex.Library.LanguageTest do
  use ExUnit.Case, async: true

  alias Lex.Library.Language

  describe "normalize/1" do
    test "normalizes language tags to lowercase" do
      assert Language.normalize("ES") == "es"
      assert Language.normalize("en") == "en"
      assert Language.normalize("FR") == "fr"
    end

    test "converts underscores to hyphens" do
      assert Language.normalize("es_ES") == "es-es"
      assert Language.normalize("en_US") == "en-us"
      assert Language.normalize("pt_BR") == "pt-br"
    end

    test "preserves existing hyphens" do
      assert Language.normalize("es-ES") == "es-es"
      assert Language.normalize("zh-Hans") == "zh-hans"
      assert Language.normalize("zh-Hans-CN") == "zh-hans-cn"
    end

    test "handles mixed separators and casing" do
      assert Language.normalize("ES_es") == "es-es"
      assert Language.normalize("EN-US") == "en-us"
    end

    test "returns 'unknown' for nil" do
      assert Language.normalize(nil) == "unknown"
    end

    test "returns 'unknown' for empty string" do
      assert Language.normalize("") == "unknown"
    end

    test "returns 'unknown' for whitespace-only string" do
      assert Language.normalize("   ") == "unknown"
      assert Language.normalize("\t\n") == "unknown"
    end

    test "trims whitespace before normalizing" do
      assert Language.normalize("  es  ") == "es"
      assert Language.normalize("\tes-ES\n") == "es-es"
    end

    test "handles single-character language codes" do
      assert Language.normalize("C") == "c"
    end

    test "handles complex language tags" do
      assert Language.normalize("zh-Hans-CN") == "zh-hans-cn"
      assert Language.normalize("sr-Latn-RS") == "sr-latn-rs"
    end
  end

  describe "base_language/1" do
    test "extracts base language from region-specific tags" do
      assert Language.base_language("es-ES") == "es"
      assert Language.base_language("es-MX") == "es"
      assert Language.base_language("en-US") == "en"
      assert Language.base_language("en-GB") == "en"
    end

    test "extracts base language from underscore-separated tags" do
      assert Language.base_language("es_ES") == "es"
      assert Language.base_language("pt_BR") == "pt"
    end

    test "handles uppercase input" do
      assert Language.base_language("ES-ES") == "es"
      assert Language.base_language("EN_US") == "en"
    end

    test "returns base language for script-specific tags" do
      assert Language.base_language("zh-Hans") == "zh"
      assert Language.base_language("zh-Hant") == "zh"
      assert Language.base_language("sr-Latn") == "sr"
    end

    test "returns base language for complex tags" do
      assert Language.base_language("zh-Hans-CN") == "zh"
      assert Language.base_language("sr-Latn-RS") == "sr"
    end

    test "returns the language code for base-only tags" do
      assert Language.base_language("es") == "es"
      assert Language.base_language("en") == "en"
      assert Language.base_language("fr") == "fr"
    end

    test "returns 'unknown' for nil" do
      assert Language.base_language(nil) == "unknown"
    end

    test "returns 'unknown' for empty string" do
      assert Language.base_language("") == "unknown"
    end

    test "returns 'unknown' for whitespace-only string" do
      assert Language.base_language("   ") == "unknown"
    end
  end

  describe "matches_target?/2" do
    test "returns true when region-specific tag matches base target" do
      assert Language.matches_target?("es-ES", "es") == true
      assert Language.matches_target?("es-MX", "es") == true
      assert Language.matches_target?("es_ES", "es") == true
      assert Language.matches_target?("en-US", "en") == true
      assert Language.matches_target?("en-GB", "en") == true
    end

    test "returns true when base tag matches base target" do
      assert Language.matches_target?("es", "es") == true
      assert Language.matches_target?("en", "en") == true
      assert Language.matches_target?("fr", "fr") == true
    end

    test "returns true for case-insensitive matches" do
      assert Language.matches_target?("ES-ES", "es") == true
      assert Language.matches_target?("es-es", "ES") == true
      assert Language.matches_target?("ES", "es") == true
    end

    test "returns false when languages don't match" do
      assert Language.matches_target?("es-ES", "en") == false
      assert Language.matches_target?("en-US", "es") == false
      assert Language.matches_target?("fr-FR", "de") == false
    end

    test "returns false when language is nil" do
      assert Language.matches_target?(nil, "es") == false
      assert Language.matches_target?(nil, nil) == false
    end

    test "returns false when target is nil" do
      assert Language.matches_target?("es-ES", nil) == false
    end

    test "handles script-specific tags" do
      assert Language.matches_target?("zh-Hans", "zh") == true
      assert Language.matches_target?("zh-Hant", "zh") == true
      assert Language.matches_target?("zh-Hans", "en") == false
    end

    test "handles complex language tags" do
      assert Language.matches_target?("zh-Hans-CN", "zh") == true
      assert Language.matches_target?("sr-Latn-RS", "sr") == true
    end
  end

  describe "from_epub/1" do
    test "normalizes EPUB language values" do
      assert Language.from_epub("es-ES") == "es-es"
      assert Language.from_epub("ES") == "es"
      assert Language.from_epub("en_US") == "en-us"
    end

    test "returns 'unknown' for invalid EPUB language values" do
      assert Language.from_epub(nil) == "unknown"
      assert Language.from_epub("") == "unknown"
      assert Language.from_epub("  ") == "unknown"
    end
  end

  describe "from_user_target/1" do
    test "extracts base language from user target values" do
      assert Language.from_user_target("es-ES") == "es"
      assert Language.from_user_target("zh-Hans") == "zh"
      assert Language.from_user_target("en") == "en"
    end

    test "returns 'unknown' for invalid user target values" do
      assert Language.from_user_target(nil) == "unknown"
      assert Language.from_user_target("") == "unknown"
      assert Language.from_user_target("  ") == "unknown"
    end

    test "handles mixed separators and casing" do
      assert Language.from_user_target("ES_ES") == "es"
      assert Language.from_user_target("zh-Hans-CN") == "zh"
    end
  end

  describe "unknown/0" do
    test "returns the unknown language constant" do
      assert Language.unknown() == "unknown"
    end
  end
end
