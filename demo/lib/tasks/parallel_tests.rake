# frozen_string_literal: true

require "parallel_tests/tasks"

module ParallelTestsNonParallelDbTasksPatch
  def run_in_parallel(cmd, options = {})
    options = Hash(options)
    options = options.merge(non_parallel: true) if ENV["RUN_SERIALLY"]

    super
  end
end

ParallelTests::Tasks.singleton_class.prepend(ParallelTestsNonParallelDbTasksPatch)
