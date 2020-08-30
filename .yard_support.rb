require 'kramdown'
require 'kramdown-parser-gfm'

# Custom markup provider class that always renders Kramdown using GFM (Github Flavored Markdown).
# GFM is needed to render markdown tables and fenced code blocks in the README.
class KramdownGfmDocument < Kramdown::Document
  def initialize(source, options = {})
    options[:input] = 'GFM' unless options.key?(:input)
    super(source, options)
  end
end

# Insert the new provider as the highest priority option for Markdown.
# See:
# - https://github.com/lsegal/yard/issues/1157
# - https://github.com/lsegal/yard/issues/1017
# - https://github.com/lsegal/yard/blob/main/lib/yard/templates/helpers/markup_helper.rb
YARD::Templates::Helpers::MarkupHelper::MARKUP_PROVIDERS[:markdown].insert(
  0,
  { const: 'KramdownGfmDocument' }
)
