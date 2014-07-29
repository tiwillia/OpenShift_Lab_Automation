class Project < ActiveRecord::Base
  # attr_accessible :title, :body
  
  belongs_to :lab
  has_many :instances
end
