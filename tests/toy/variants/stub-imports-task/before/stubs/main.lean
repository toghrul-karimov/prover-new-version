import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

/-- The toy campaign's top-level statement, conditional on `AddZero`. -/
theorem main (h : AddZero) (n : Nat) : double n = 2 * n + 0 := by
  sorry

end Toy.Main
