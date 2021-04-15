module GoodJob
  class BaseRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
