class AddPayerKanaToInvoices < ActiveRecord::Migration[8.1]
  def change
    add_column :invoices, :payer_kana, :string
  end
end
