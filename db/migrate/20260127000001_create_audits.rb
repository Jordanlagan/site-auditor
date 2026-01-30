class CreateAudits < ActiveRecord::Migration[7.1]
  def change
    create_table :audits do |t|
      t.string :url, null: false
      t.string :status, null: false, default: 'pending'
      t.integer :overall_score
      t.jsonb :category_scores, default: {}
      t.jsonb :raw_results, default: {}
      t.text :summary

      t.timestamps
    end

    add_index :audits, :url
    add_index :audits, :status
    add_index :audits, :created_at
  end
end
