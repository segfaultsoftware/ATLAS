class CreateGames < ActiveRecord::Migration[8.1]
  def change
    create_table :games do |t|
      t.references :profile, null: false, foreign_key: true
      t.string :name, null: false, limit: 64
      t.integer :randomization_seed, null: false

      t.timestamps
    end

    add_check_constraint :games,
                         "name = trim(name) AND length(name) BETWEEN 1 AND 64",
                         name: "games_name_is_trimmed_and_bounded"
    add_check_constraint :games,
                         "randomization_seed BETWEEN 0 AND 4294967295",
                         name: "games_randomization_seed_is_unsigned_32_bit"
  end
end
