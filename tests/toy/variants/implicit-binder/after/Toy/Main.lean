import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- The approved statement with `n` implicit (`{n : Nat}`) instead of explicit.
theorem main (h : AddZero) {n : Nat} : double n = 2 * n + 0 := by
  rw [h (2 * n)]
  exact Toy.Lemmas.Double.double_eq n

end Toy.Main
