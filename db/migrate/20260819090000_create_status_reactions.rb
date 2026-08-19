# frozen_string_literal: true

class CreateStatusReactions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    create_table :status_reactions do |t|
      t.references :status, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :custom_emoji, null: true, foreign_key: { on_delete: :nullify }, index: false
      t.references :favourite, null: true, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.string :activity_uri
      t.integer :activity_type, null: false, default: 0
      t.timestamps
    end

    add_index :status_reactions, [:status_id, :account_id], unique: true
    add_index :status_reactions, [:status_id, :custom_emoji_id, :name], name: :index_status_reactions_for_aggregation
    add_index :status_reactions, :activity_uri, unique: true, where: 'activity_uri IS NOT NULL'
    add_index :status_reactions, :custom_emoji_id
    add_index :status_reactions, :favourite_id

    create_table :reaction_domain_capabilities, id: :string, primary_key: :domain do |t|
      t.boolean :supports_like_reactions, null: false, default: false
      t.boolean :supports_emoji_react, null: false, default: false
      t.datetime :last_observed_at, null: false
      t.timestamps
    end

    add_column :notifications, :status_reaction_id, :bigint
    add_index :notifications, :status_reaction_id, algorithm: :concurrently
    add_foreign_key :notifications, :status_reactions, column: :status_reaction_id, on_delete: :cascade, validate: false
    validate_foreign_key :notifications, :status_reactions
  end

  def down
    remove_foreign_key :notifications, column: :status_reaction_id
    remove_index :notifications, :status_reaction_id
    remove_column :notifications, :status_reaction_id
    drop_table :reaction_domain_capabilities
    drop_table :status_reactions
  end
end
