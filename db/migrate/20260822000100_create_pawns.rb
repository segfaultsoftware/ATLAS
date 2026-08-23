class CreatePawns < ActiveRecord::Migration[8.1]
  def change
    ascii_boundary_whitespace = "char(9, 10, 11, 12, 13, 32)"

    create_table :pawns do |t|
      t.references :game,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :first_name, limit: 18, null: false
      t.string :nickname, limit: 18, null: false
      t.string :last_name, limit: 18
      t.integer :born_on_turn, null: false
      t.integer :max_health, null: false
      t.integer :current_health, null: false
      t.integer :max_stamina, null: false
      t.integer :current_stamina, null: false
      t.integer :max_vigor, null: false
      t.integer :current_vigor, null: false

      t.timestamps
    end

    add_check_constraint :pawns,
                         "first_name = trim(first_name, #{ascii_boundary_whitespace}) " \
                           "AND length(first_name) BETWEEN 1 AND 18",
                         name: "pawns_first_name_is_trimmed_and_bounded"
    add_check_constraint :pawns,
                         "nickname = trim(nickname, #{ascii_boundary_whitespace}) " \
                           "AND length(nickname) BETWEEN 1 AND 18",
                         name: "pawns_nickname_is_trimmed_and_bounded"
    add_check_constraint :pawns,
                         "last_name IS NULL OR " \
                           "(last_name = trim(last_name, #{ascii_boundary_whitespace}) " \
                           "AND length(last_name) <= 18)",
                         name: "pawns_last_name_is_trimmed_and_bounded"

    %i[
      max_health
      current_health
      max_stamina
      current_stamina
      max_vigor
      current_vigor
    ].each do |attribute|
      add_check_constraint :pawns,
                           "#{attribute} > 0",
                           name: "pawns_#{attribute}_is_positive"
    end
  end
end
