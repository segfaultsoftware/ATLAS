class CreateGameInitializations < ActiveRecord::Migration[8.1]
  def change
    create_table :game_initializations do |t|
      t.references :game,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: { unique: true }
      t.integer :remaining_budget, null: false, default: 5000

      t.timestamps
    end

    add_check_constraint :game_initializations,
                         "remaining_budget >= 0",
                         name: "game_initializations_remaining_budget_is_nonnegative"
  end
end
