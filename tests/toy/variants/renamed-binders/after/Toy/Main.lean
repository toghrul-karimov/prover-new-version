import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- The approved statement with its bound variables renamed (`hyp` for `h`, `m` for `n`).
theorem main (hyp : AddZero) (m : Nat) : double m = 2 * m + 0 := by
  rw [hyp (2 * m)]
  exact Toy.Lemmas.Double.double_eq m

end Toy.Main
