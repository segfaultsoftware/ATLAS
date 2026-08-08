class CreateCelestialBodiesAndCelestialTransits < ActiveRecord::Migration[8.1]
  def change
    create_table :celestial_bodies do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :celestial_bodies, :name, unique: true

    create_table :celestial_transits do |t|
      t.references :celestial_body, null: false, foreign_key: true, index: { unique: true }
      t.json :celestial_coordinates_start, null: false
      t.json :celestial_coordinates_target, null: false

      t.timestamps
    end
  end
end
