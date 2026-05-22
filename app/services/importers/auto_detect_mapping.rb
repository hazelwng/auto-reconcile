require "set"

module Importers
  # Suggests a schema_mapping for a CSV by matching its headers against
  # keyword patterns for each canonical field of the given data_source kind.
  #
  # Output shape mirrors what MappedCsv expects in data_source.schema_mapping:
  #   { canonical_field => csv_header }
  #
  # Returns an AutoDetectMapping::Result with:
  #   - mapping:          Hash of canonical_field => header
  #   - low_confidence:   Array of canonical_fields whose match came from the
  #                       fuzzy fallback pass and should be highlighted in the
  #                       UI for user confirmation
  #   - unmapped_headers: Array of CSV headers no canonical field claimed
  #
  # Algorithm — two passes:
  #   1. High-confidence pass: match each canonical against its precise
  #      patterns (e.g. "Counterparty" -> counterparty).
  #   2. Low-confidence fallback: for any canonical still unmatched, try its
  #      fuzzy patterns (e.g. "Description" -> counterparty when no explicit
  #      counterparty header exists). Matches in this pass are flagged.
  #
  # First-match-wins within each pass; a header that matched cannot match
  # again. Patterns are listed in specificity order so a generic regex
  # doesn't steal a header from a more precise field.
  class AutoDetectMapping
    Result = Struct.new(:mapping, :low_confidence, :unmapped_headers, keyword_init: true)

    PATTERNS = {
      "bank" => [
        { canonical: "external_id",
          high: [ /transaction.?id/i, /\btxn.?id\b/i, /\bref(erence)?\b/i, /^id$/i ] },
        { canonical: "posted_date",
          high: [ /posted.?date/i, /posting.?date/i, /transaction.?date/i, /trans.?date/i, /^date$/i ] },
        { canonical: "amount_debit",
          high: [ /^debit(s|.?amount)?$/i, /withdrawal/i ] },
        { canonical: "amount_credit",
          high: [ /^credit(s|.?amount)?$/i, /deposit/i ] },
        { canonical: "amount",
          high: [ /^amount$/i, /^amt$/i, /^value$/i, /net.?amount/i ] },
        { canonical: "txn_type",
          high: [ /^txn.?type$/i, /transaction.?type/i, /^type$/i, /direction/i ] },
        { canonical: "currency",
          high: [ /^currency$/i, /\bccy\b/i, /^curr$/i, /iso.?currency/i ] },
        { canonical: "check_number",
          high: [ /check.?(no|number)/i, /cheque.?(no|number)/i ] },
        { canonical: "counterparty",
          high: [ /counterparty/i, /^payee$/i, /^payer$/i, /^party$/i ],
          low:  [ /^description$/i, /narrative/i, /details/i, /narration/i ] },
        { canonical: "memo",
          high: [ /^memo$/i, /^notes?$/i ],
          low:  [ /particulars/i ] }
      ],
      "accounting" => [
        { canonical: "invoice_number",
          high: [ /invoice.?(number|no|#)/i, /^number$/i ] },
        { canonical: "external_id",
          high: [ /invoice.?id/i, /\bref(erence)?\b/i, /^id$/i ] },
        { canonical: "due_date",
          high: [ /due.?date/i, /payment.?due/i ] },
        { canonical: "issue_date",
          high: [ /issue.?date/i, /invoice.?date/i, /^date$/i ] },
        { canonical: "amount",
          high: [ /^amount$/i, /^total$/i, /total.?amount/i, /grand.?total/i, /^value$/i ] },
        { canonical: "currency",
          high: [ /^currency$/i, /\bccy\b/i, /^curr$/i ] },
        { canonical: "status",
          high: [ /^status$/i, /^state$/i, /^paid$/i ] },
        { canonical: "payer",
          high: [ /^payer$/i, /^customer$/i, /^client$/i, /^debtor$/i ],
          low:  [ /account.?name/i, /\bbill.?to\b/i ] },
        { canonical: "notes",
          high: [ /^notes?$/i, /^memo$/i, /^comment(s)?$/i ],
          low:  [ /^description$/i, /^details$/i, /line.?item/i ] }
      ]
    }.freeze

    def initialize(headers:, kind:)
      @headers = headers.map { |h| h.to_s.strip }.reject(&:empty?)
      @kind = kind.to_s
      unless PATTERNS.key?(@kind)
        raise ArgumentError, "AutoDetectMapping does not support kind=#{@kind.inspect}"
      end
    end

    def call
      mapping = {}
      low_confidence = []
      used = Set.new
      specs = PATTERNS.fetch(@kind)

      specs.each do |spec|
        next if mapping.key?(spec[:canonical])
        match = first_unused_match(spec[:high], used)
        next unless match
        mapping[spec[:canonical]] = match
        used << match
      end

      specs.each do |spec|
        next if mapping.key?(spec[:canonical])
        fuzzy = spec[:low] or next
        match = first_unused_match(fuzzy, used)
        next unless match
        mapping[spec[:canonical]] = match
        used << match
        low_confidence << spec[:canonical]
      end

      Result.new(
        mapping: mapping,
        low_confidence: low_confidence,
        unmapped_headers: @headers - used.to_a
      )
    end

    private

    def first_unused_match(patterns, used)
      return nil if patterns.nil? || patterns.empty?
      @headers.find { |h| !used.include?(h) && patterns.any? { |re| h.match?(re) } }
    end
  end
end
