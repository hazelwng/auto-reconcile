module Reconciliation
  class PartyNormalizer
    HIRAGANA_START = 0x3041
    HIRAGANA_END = 0x3096
    KATAKANA_OFFSET = 0x60

    SMALL_KANA_MAP = {
      "ァ" => "ア",
      "ィ" => "イ",
      "ゥ" => "ウ",
      "ェ" => "エ",
      "ォ" => "オ",
      "ッ" => "ツ",
      "ャ" => "ヤ",
      "ュ" => "ユ",
      "ョ" => "ヨ",
      "ヮ" => "ワ",
      "ヵ" => "カ",
      "ヶ" => "ケ"
    }.freeze

    class << self
      def kana(raw)
        raw.to_s
           .unicode_normalize(:nfkc)
           .each_char
           .map { |char| hiragana_to_katakana(char) }
           .join
           .tr(SMALL_KANA_MAP.keys.join, SMALL_KANA_MAP.values.join)
           .gsub(/[[:space:][:punct:]]/, "")
      end

      def latin(raw)
        raw.to_s
           .unicode_normalize(:nfkc)
           .downcase
           .gsub(/[[:space:][:punct:]]/, "")
      end

      def strip_markers(raw, markers)
        markers.reduce(raw.to_s) do |value, marker|
          value.gsub(marker, "")
        end.strip
      end

      private

      def hiragana_to_katakana(char)
        codepoint = char.ord
        return char unless codepoint.between?(HIRAGANA_START, HIRAGANA_END)

        (codepoint + KATAKANA_OFFSET).chr(Encoding::UTF_8)
      end
    end
  end
end
