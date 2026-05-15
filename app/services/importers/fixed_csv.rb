require "csv"
require "digest"

module Importers
  class FixedCsv < Base
    private

    def iter_rows(batch)
      io = batch.source_file.download
      CSV.parse(io, headers: true).map { |r| r.to_h.transform_keys { |k| k.to_s.strip.downcase } }
    end

    def import_row(batch, row, row_number)
      case batch.data_source.kind
      when "bank"            then import_bank_row(batch, row)
      when "accounting"      then import_invoice_row(batch, row)
      else
        raise ArgumentError, "FixedCsv does not support kind=#{batch.data_source.kind.inspect}"
      end
    end

    def import_bank_row(batch, row)
      workspace = batch.data_source.workspace
      external_id = row.fetch("external_id")
      external_id_hash = hash_external_id(external_id)
      amount_cents = to_cents(row.fetch("amount"))
      currency = (row["currency"].presence || batch.data_source.currency).upcase
      raise ActiveRecord::RecordNotUnique if duplicate?(batch, external_id_hash)

      ReconcilableItem.transaction do
        bank_txn = BankTransaction.create!(
          workspace: workspace,
          posted_date: Date.parse(row.fetch("posted_date")),
          txn_type: row.fetch("txn_type").to_s.downcase,
          counterparty: row["counterparty"],
          memo: row["memo"],
          check_number: row["check_number"],
          raw_payload: row
        )

        ReconcilableItem.create!(
          workspace: workspace,
          data_source: batch.data_source,
          import_batch: batch,
          item: bank_txn,
          amount_cents: amount_cents,
          amount_currency: currency,
          occurred_on: bank_txn.posted_date,
          description: row["description"].to_s,
          external_id: external_id,
          external_id_hash: external_id_hash,
          status: "unmatched"
        )
      end
    end

    def import_invoice_row(batch, row)
      workspace = batch.data_source.workspace
      external_id = row.fetch("external_id")
      external_id_hash = hash_external_id(external_id)
      amount_cents = to_cents(row.fetch("amount"))
      currency = (row["currency"].presence || batch.data_source.currency).upcase
      issue_date = Date.parse(row.fetch("issue_date"))
      raise ActiveRecord::RecordNotUnique if duplicate?(batch, external_id_hash)

      ReconcilableItem.transaction do
        invoice = Invoice.create!(
          workspace: workspace,
          invoice_number: row.fetch("invoice_number"),
          issue_date: issue_date,
          due_date: row["due_date"].present? ? Date.parse(row["due_date"]) : nil,
          total_cents: amount_cents,
          currency: currency,
          status: row["status"].presence || "open",
          payer: row["payer"],
          notes: row["notes"]
        )

        ReconcilableItem.create!(
          workspace: workspace,
          data_source: batch.data_source,
          import_batch: batch,
          item: invoice,
          amount_cents: amount_cents,
          amount_currency: currency,
          occurred_on: issue_date,
          description: row["description"].to_s,
          external_id: external_id,
          external_id_hash: external_id_hash,
          status: "unmatched"
        )
      end
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
