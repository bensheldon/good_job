module SqlHelper
  def normalize_sql(sql)
    sql.gsub(/\s/, ' ').gsub(/([()])/, ' \1 ').squish
  end
end

RSpec.configure { |c| c.include SqlHelper }
