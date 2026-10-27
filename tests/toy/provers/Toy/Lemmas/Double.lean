import Toy.Defs.Basic

namespace Toy.Lemmas.Double
open Toy.Defs.Basic

theorem double_eq (n : Nat) : double n = 2 * n := by
  unfold double
  omega

end Toy.Lemmas.Double
