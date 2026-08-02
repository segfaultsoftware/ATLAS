class ManualCategory < ApplicationRecord
  has_many :manual_page_categories, dependent: :destroy
  has_many :manual_pages, through: :manual_page_categories

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
end
