# typed: true

# Constants defined by stub_const in fiber integration specs.
IN_FLIGHT = T.let(T.unsafe(nil), Concurrent::AtomicFixnum)
MAX_IN_FLIGHT = T.let(T.unsafe(nil), Concurrent::AtomicFixnum)
STARTED = T.let(T.unsafe(nil), Concurrent::Event)
class CliInterruptedJob < ActiveJob::Base; end
class InterruptedJob < ActiveJob::Base; end
class ThreadIsolationJob < ActiveJob::Base; end
