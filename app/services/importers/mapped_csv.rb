require "csv"
require "digest"

module Importers
  # Importer for CSVs whose headers do not match the canonical fixed schema.
  # Reads each row via the data_source.schema_mapping JSON, which maps a
  # canonical field name (e.g. "external_id") to the user's CSV header
  # (e.g. "Reference"). Bank rows may either provide a single signed `amount`
  # column with a `txn_type`, or two unsigned columns `amount_debit` and
  # `amount_credit`; in the latter case, net = credit - debit and txn_type
  # is derived from the sign.
  class MappedCsv < Base
    CANONICAL_REQUIRED = {
      "bank" => %w[external_id posted_date],
      "accounting" => %w[external_id invoice_number issue_date]
    }.freeze

    private

    def iter_rows(batch)
      io = batch.source_file.download
      # Use exact user-supplied headers; mapping is responsible for the
      # translation. We still strip surrounding whitespace on headers because
      # most CSV authoring tools introduce it accidentally.
      CSV.parse(io, headers: true, header_converters: ->(h) { h.to_s.strip })
        .map(&:to_h)
    end

    def import_row(batch, row, _row_number)
      validate_mapping!(batch.data_source)

      case batch.data_source.kind
      when "bank"       then import_bank_row(batch, row)
      when "accounting" then import_invoice_row(batch, row)
      else
        raise ArgumentError, "MappedCsv does not support kind=#{batch.data_source.kind.inspect}"
      end
    end

    def import_bank_row(batch, row)
      ds = batch.data_source
      workspace = ds.workspace
      mapping = ds.schema_mapping

      external_id = pick!(row, mapping, "external_id")
      external_id_hash = hash_external_id(external_id)
      raise ActiveRecord::RecordNotUnique if duplicate?(batch, external_id_hash)

      amount_cents, txn_type = bank_amount_and_type(row, mapping)
      posted_date = Date.parse(pick!(row, mapping, "posted_date"))
      currency = (pick(row, mapping, "currency").presence || ds.currency).upcase

      ReconcilableItem.transaction do
        bank_txn = BankTransaction.create!(
          workspace: workspace,
          posted_date: posted_date,
          txn_type: txn_type,
          counterparty: pick(row, mapping, "counterparty"),
          memo: pick(row, mapping, "memo"),
          check_number: pick(row, mapping, "check_number"),
          raw_payload: row
        )

        ReconcilableItem.create!(
          workspace: workspace,
          data_source: ds,
          import_batch: batch,
          item: bank_txn,
          amount_cents: amount_cents,
          amount_currency: currency,
          occurred_on: posted_date,
          description: pick(row, mapping, "description").to_s,
          external_id: external_id,
          external_id_hash: external_id_hash,
          status: "unmatched"
        )
      end
    end

    def import_invoice_row(batch, row)
      ds = batch.data_source
      workspace = ds.workspace
      mapping = ds.schema_mapping

      external_id = pick!(row, mapping, "external_id")
      external_id_hash = hash_external_id(external_id)
      raise ActiveRecord::RecordNotUnique if duplicate?(batch, external_id_hash)

      amount_cents = to_cents(pick!(row, mapping, "amount"))
      issue_date = Date.parse(pick!(row, mapping, "issue_date"))
      due_date_raw = pick(row, mapping, "due_date")
      due_date = due_date_raw.present? ? Date.parse(due_date_raw) : nil
      currency = (pick(row, mapping, "currency").presence || ds.currency).upcase

      ReconcilableItem.transaction do
        invoice = Invoice.create!(
          workspace: workspace,
          invoice_number: pick!(row, mapping, "invoice_number"),
          issue_date: issue_date,
          due_date: due_date,
          total_cents: amount_cents,
          currency: currency,
          status: pick(row, mapping, "status").presence || "open",
          payer: pick(row, mapping, "payer"),
          payer_kana: pick(row, mapping, "payer_kana"),
          notes: pick(row, mapping, "notes")
        )

        ReconcilableItem.create!(
          workspace: workspace,
          data_source: ds,
          import_batch: batch,
          item: invoice,
          amount_cents: amount_cents,
          amount_currency: currency,
          occurred_on: issue_date,
          description: pick(row, mapping, "description").to_s,
          external_id: external_id,
          external_id_hash: external_id_hash,
          status: "unmatched"
        )
      end
    end

    # Returns [amount_cents, txn_type]. Supports three layouts:
    #   Format A: single signed `amount` column, no `txn_type` mapped — sign
    #     IS the source of truth; txn_type is derived (negative -> debit).
    #     Typical for AU bank exports, Stripe payouts, etc.
    #   Format B: unsigned `amount` column + explicit `txn_type` column.
    #   Format C: two unsigned columns `amount_debit` + `amount_credit`;
    #     net = credit - debit; txn_type derived from the sign.
    def bank_amount_and_type(row, mapping)
      if mapping["amount_debit"].present? || mapping["amount_credit"].present?
        debit  = to_cents(pick(row, mapping, "amount_debit").presence || "0").abs
        credit = to_cents(pick(row, mapping, "amount_credit").presence || "0").abs
        raise ArgumentError, "row has neither debit nor credit amount" if debit.zero? && credit.zero?
        raise ArgumentError, "row has both debit and credit amount" if debit.positive? && credit.positive?

        if credit.positive?
          [ credit, "credit" ]
        else
          [ -debit, "debit" ]
        end
      elsif mapping["txn_type"].present?
        txn_type = pick!(row, mapping, "txn_type").to_s.downcase
        amount = to_cents(pick!(row, mapping, "amount")).abs
        amount = -amount if txn_type == "debit"
        [ amount, txn_type ]
      else
        amount = to_cents(pick!(row, mapping, "amount"))
        [ amount, amount.negative? ? "debit" : "credit" ]
      end
    end

    def validate_mapping!(data_source)
      mapping = data_source.schema_mapping
      raise ArgumentError, "data_source.schema_mapping is empty" if mapping.blank?

      required = CANONICAL_REQUIRED.fetch(data_source.kind) do
        raise ArgumentError, "MappedCsv does not support kind=#{data_source.kind.inspect}"
      end
      missing = required - mapping.keys
      raise ArgumentError, "schema_mapping missing required keys: #{missing.join(', ')}" if missing.any?

      if data_source.kind == "bank"
        has_amount = mapping["amount"].present?
        has_pair   = mapping["amount_debit"].present? || mapping["amount_credit"].present?
        unless has_amount || has_pair
          raise ArgumentError, "bank mapping needs amount (signed, or with txn_type) or amount_debit/amount_credit"
        end
      elsif data_source.kind == "accounting"
        raise ArgumentError, "accounting mapping needs amount" if mapping["amount"].blank?
      end
    end

    # Read a mapped field, returning nil if the canonical key is not mapped
    # or the underlying CSV header is missing/blank.
    def pick(row, mapping, canonical_key)
      header = mapping[canonical_key]
      return nil if header.blank?
      row[header]
    end

    def pick!(row, mapping, canonical_key)
      value = pick(row, mapping, canonical_key)
      raise KeyError, "missing value for #{canonical_key} (header: #{mapping[canonical_key].inspect})" if value.blank?
      value
    end

    def to_cents(value)
      str = value.to_s.strip.delete(",").delete("$")
      (BigDecimal(str) * 100).to_i
    end

    def hash_external_id(external_id)
      Digest::SHA256.hexdigest("#{@batch.data_source_id}:#{external_id}")
    end

    def duplicate?(batch, external_id_hash)
      ReconcilableItem.exists?(
        data_source: batch.data_source,
        external_id_hash: external_id_hash
      )
    end
  end
end
