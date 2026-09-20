# Round-trips a LOCAL, not-yet-published .gem (installed by the
# caller with gem install --local). Exit non-zero on any assertion
# failure - this is the pre-publish gate.
require_relative "roundtrip_assertions"
