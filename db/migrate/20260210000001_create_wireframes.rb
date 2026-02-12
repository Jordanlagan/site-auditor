class CreateWireframes < ActiveRecord::Migration[7.2]
  def change
    create_table :wireframes do |t|
      t.references :audit, null: false, foreign_key: true
      t.string :title, null: false
      t.string :file_path, null: false
      t.jsonb :config_used, default: {}, null: false # Stores generation config (colors, fonts, etc.)

      t.timestamps
    end

    add_index :wireframes, :created_at
  end
end
