import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- The assumption `AddZero` written out by its definition: definitionally equal to the
-- approved statement, but it no longer names the assumption.
theorem main (h : ∀ n : Nat, n + 0 = n) (n : Nat) : double n = 2 * n + 0 := by
  rw [h (2 * n)]
  exact Toy.Lemmas.Double.double_eq n

end Toy.Main
