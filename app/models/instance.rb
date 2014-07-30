class Instance < ActiveRecord::Base
  # attr_accessible :title, :body

  belongs_to :project

  serialize :types

  def start
  end

  def stop
  end

  def restart
    stop
    start
  end

  private
 
  # Generate cloudinit details 
  def generate_cloudinit
  end  

  # Generate Installation script variables
  def generate_variables
  end

end
