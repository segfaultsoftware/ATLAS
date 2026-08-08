class CreateCelestialBodiesAndCelestialTransits < ActiveRecord::Migration[8.1]
  def change
    create_table :celestial_bodies do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :celestial_bodies, :name, unique: true

    create_table :celestial_transits do |t|
      t.references :celestial_body, null: false, foreign_key: true, index: { unique: true }
      t.float :celestial_coordinates_start_x, null: false
      t.float :celestial_coordinates_start_y, null: false
      t.float :celestial_coordinates_target_x, null: false
      t.float :celestial_coordinates_target_y, null: false

      t.timestamps
    end
  end
end
