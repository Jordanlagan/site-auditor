class AddTestIdsToAudits < ActiveRecord::Migration[7.2]
  def change
    add_column :audits, :test_ids, :integer, array: true, default: []
  end
end
