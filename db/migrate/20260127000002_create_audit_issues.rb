class CreateAuditIssues < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_issues do |t|
      t.references :audit, null: false, foreign_key: true
      t.string :category, null: false
      t.string :severity, null: false
      t.string :title, null: false
      t.text :description
      t.text :recommendation

      t.timestamps
    end

    add_index :audit_issues, :category
    add_index :audit_issues, :severity
    add_index :audit_issues, [:audit_id, :category]
  end
end
