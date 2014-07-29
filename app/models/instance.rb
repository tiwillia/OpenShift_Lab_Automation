class Instance < ActiveRecord::Base
  # attr_accessible :title, :body

  belongs_to :project
end
