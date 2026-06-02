require "test_helper"

module Reconciliation
  class PartyNormalizerTest < ActiveSupport::TestCase
    test "kana bridges half-width zengin style names and invoice readings" do
      assert_equal PartyNormalizer.kana("ﾔﾏﾀﾞｼﾖｳｼﾞ"), PartyNormalizer.kana("ヤマダショウジ")
    end

    test "kana converts hiragana to katakana and folds small kana" do
      assert_equal "ヤマダシヨウジ", PartyNormalizer.kana("やまだしょうじ")
    end

    test "kana composes dakuten" do
      assert_equal "ダ", PartyNormalizer.kana("ﾀﾞ")
    end

    test "latin downcases and strips spaces" do
      assert_equal "acmeptyltd", PartyNormalizer.latin("Acme Pty Ltd")
    end

    test "latin strips punctuation" do
      assert_equal "acmeinc", PartyNormalizer.latin("ACME, INC.")
    end

    test "strip_markers removes supplied corporate markers" do
      assert_equal "山田商事", PartyNormalizer.strip_markers("株式会社山田商事", [ "株式会社" ])
    end

    test "normalizers are nil safe" do
      assert_equal "", PartyNormalizer.kana(nil)
      assert_equal "", PartyNormalizer.latin(nil)
    end

    test "kana does not invent readings from kanji" do
      assert_equal "株式会社山田商事", PartyNormalizer.kana("株式会社山田商事")
    end
  end
end
