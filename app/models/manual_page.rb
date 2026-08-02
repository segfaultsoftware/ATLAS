class ManualPage < ApplicationRecord
  belongs_to :parent, class_name: "ManualPage", optional: true, inverse_of: :children
  has_many :children,
           class_name: "ManualPage",
           foreign_key: :parent_id,
           inverse_of: :parent,
           dependent: :restrict_with_exception

  has_many :manual_page_categories, dependent: :destroy
  has_many :categories, through: :manual_page_categories, source: :manual_category

  validates :title, :slug, presence: true
  validates :slug, uniqueness: true
end
