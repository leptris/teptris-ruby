target :lib do
  signature "sig"

  # The lib layer is unannotated Ruby; this first slice gates the
  # SIGNATURES (self-consistency + the contract they declare). Code
  # checking lands with per-file annotations.
  # check "lib"

  configure_code_diagnostics do |hash|
    # keep the lane green while signatures evolve
  end
end
