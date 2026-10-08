# The library's work counter (spec/12 §6, #462), so the gallery's cost guard counts
# reductions with the same helper as the library's suite (spec/14 §12.6, #469).
Code.require_file("../../test/support/work.ex", __DIR__)

ExUnit.start()
