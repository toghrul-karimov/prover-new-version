import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- The approved statement written with `@Eq` and a full name instead of `=` and `open`:
-- different text, the same elaborated statement.
theorem main (h : AddZero) (n : Nat) : @Eq Nat (Toy.Defs.Basic.double n) (2 * n + 0) := by
  rw [h (2 * n)]
  exact Toy.Lemmas.Double.double_eq n

end Toy.Main
