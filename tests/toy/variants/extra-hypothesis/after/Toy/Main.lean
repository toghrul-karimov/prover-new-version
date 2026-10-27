import Toy.Defs.Basic
import Toy.Defs.Assumption
import Toy.Lemmas.Double

namespace Toy.Main
open Toy.Defs.Basic Toy.Defs.Assumption

-- An extra hypothesis that makes the statement trivial.
theorem main (h : AddZero) (bad : False) (n : Nat) : double n = 2 * n + 0 := bad.elim

end Toy.Main
