# frozen_string_literal: true

module RuboCop
  module Cop
    module GoodJob
      class ExplicitNamespaceCop < Base
        CONSTANTS_TO_CHECK = %w[DiscreteExecution].freeze
        MSG = 'Use GoodJob::%{constant} instead of %{constant}. See https://github.com/bensheldon/good_job/pull/962'

        CONSTANTS_PATTERN = CONSTANTS_TO_CHECK.map { |constant| ":#{constant}" }.join(' ')

        def_node_matcher :constant_access?, <<~PATTERN
          (const nil? { #{CONSTANTS_PATTERN} } )
        PATTERN

        def_node_matcher :class_definition?, <<~PATTERN
          (class
            (const nil? { #{CONSTANTS_PATTERN} })
            ...
          )
        PATTERN

        def constants_pattern
          CONSTANTS_TO_CHECK.map { |c| ":#{c}" }.join(' ')
        end

        def on_const(node)
          return if class_definition?(node.parent)
          return unless constant_access?(node)

          constant_name = node.const_name.to_s
          add_offense(node, message: format(MSG, constant: constant_name))
        end
      end
    end
  end
end
