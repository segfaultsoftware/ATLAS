class ManualPageCategory < ApplicationRecord
  belongs_to :manual_page
  belongs_to :manual_category

  validates :manual_category_id, uniqueness: { scope: :manual_page_id }
end
